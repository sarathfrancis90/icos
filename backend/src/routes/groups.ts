// POST /api/join-group (port of the join-group edge function), POST /api/report
// (replaces the client's direct insert into reports + the notify_report_filed
// trigger) and POST /api/block, /api/unblock (replace the block_user /
// unblock_user RPCs).
//
// join-group { invite_code } -> 200 { group, already_member }
//   400 INVALID_JSON / INVALID_INVITE_CODE  403 BANNED / DELETED / ANONYMOUS_USER
//   404 GROUP_NOT_FOUND  409 GROUP_FULL / GROUP_INACTIVE / TOO_MANY_GROUPS
// report { reported_user_id | reported_group_id, reason, details? } -> 201 { id }
// block { user_id } -> 200 { blocked: true }   unblock { user_id } -> 200 { blocked: false }
import { Hono } from "hono";
import { q, tx } from "../db.js";
import { readJson, utcToday } from "../shared/http.js";
import {
  activeUser,
  type ApiDeps,
  methodNotAllowed,
  notifyReportFiled,
  pgError,
  type ReportRow,
  requestCtx,
  touchLastActive,
  UUID_RE,
} from "./common.js";

const MAX_GROUPS_PER_USER = 20;
const INVITE_RE = /^[A-Z0-9]{6}$/;
const MAX_DETAILS = 1000;
/** Reports one reporter may file in a rolling 24 h window (block notices included). */
export const MAX_REPORTS_PER_DAY = 10;

/** Reasons the app offers (ReportReason in report_dialog.dart). */
export const REPORT_REASONS = ["inappropriate_name", "harassment", "cheating", "spam", "other"] as const;

const BLOCK_NOTICE = "Automatic notice: the reporter blocked this user.";
const REPORT_COLUMNS = "id, reporter_id, reported_user_id, reported_group_id, reason, details, created_at";

export function groupRoutes(deps: ApiDeps): Hono {
  const app = new Hono();

  app.all("/join-group", async (c) => {
    const r = requestCtx(c, deps, "join-group");
    if (c.req.method !== "POST") return methodNotAllowed(r);

    const gate = await activeUser(c, deps, r);
    if (gate instanceof Response) return gate;
    const { user, profile } = gate;
    if (profile.is_anonymous || user.isAnonymous) {
      return r.fail(403, "Create an account to join groups", "ANONYMOUS_USER");
    }

    const body = await readJson(c.req.raw);
    if (body === null) return r.fail(400, "Body must be a JSON object", "INVALID_JSON");
    const rawCode = body.invite_code;
    const inviteCode = typeof rawCode === "string" ? rawCode.trim().toUpperCase() : "";
    if (!INVITE_RE.test(inviteCode)) {
      return r.fail(400, "Invite code must be 6 letters/digits", "INVALID_INVITE_CODE");
    }
    const lg = r.log.child({ user_id: user.id, invite_code: inviteCode });

    const [group] = await q<Record<string, unknown> & { id: string }>(
      "SELECT * FROM public.groups WHERE invite_code = $1 AND is_active LIMIT 1",
      [inviteCode],
    );
    if (!group) {
      lg.info("invite code not found");
      return r.fail(404, "Invalid invite code", "GROUP_NOT_FOUND");
    }
    const groupId = group.id;

    const existing = await q("SELECT id FROM public.group_members WHERE group_id = $1 AND user_id = $2 LIMIT 1", [
      groupId,
      user.id,
    ]);
    if (existing.length > 0) {
      lg.info("already a member");
      return r.ok({ group, already_member: true });
    }

    const [{ n }] = await q<{ n: number }>("SELECT count(*)::int AS n FROM public.group_members WHERE user_id = $1", [
      user.id,
    ]);
    if (n >= MAX_GROUPS_PER_USER) {
      return r.fail(409, `You can be in at most ${MAX_GROUPS_PER_USER} groups`, "TOO_MANY_GROUPS");
    }

    try {
      await q("INSERT INTO public.group_members (group_id, user_id, role) VALUES ($1, $2, 'member')", [
        groupId,
        user.id,
      ]);
    } catch (err) {
      const { code, hint } = pgError(err);
      if (code === "23505") {
        const [again] = await q("SELECT * FROM public.groups WHERE id = $1", [groupId]);
        return r.ok({ group: again ?? group, already_member: true });
      }
      if (hint === "GROUP_FULL" || code === "23514") {
        lg.info("group full");
        return r.fail(409, "Group is full (max 50 members)", "GROUP_FULL");
      }
      if (hint === "GROUP_INACTIVE") return r.fail(409, "Group is no longer active", "GROUP_INACTIVE");
      throw err;
    }

    // Bookkeeping: neither failure undoes the join (the Deno original ignored both).
    try {
      await q(
        "INSERT INTO public.group_feed (group_id, user_id, puzzle_date, event) VALUES ($1, $2, $3, 'joined')",
        [groupId, user.id, utcToday()],
      );
    } catch (err) {
      lg.warn("group_feed insert failed", { db_error: err instanceof Error ? err.message : String(err) });
    }
    try {
      await touchLastActive(user.id);
    } catch (err) {
      lg.warn("last_active_at update failed", { db_error: err instanceof Error ? err.message : String(err) });
    }

    const [fresh] = await q<Record<string, unknown>>("SELECT * FROM public.groups WHERE id = $1", [groupId]);
    if (!fresh) throw new Error("group re-read failed: no row");
    lg.info("joined group", { group_id: groupId, member_count: fresh.member_count });
    return r.ok({ group: fresh, already_member: false });
  });

  app.all("/report", async (c) => {
    const r = requestCtx(c, deps, "report");
    if (c.req.method !== "POST") return methodNotAllowed(r);

    const gate = await activeUser(c, deps, r);
    if (gate instanceof Response) return gate;
    const { user } = gate;

    const body = await readJson(c.req.raw);
    if (body === null) return r.fail(400, "Body must be a JSON object", "INVALID_JSON");
    const { bad } = r;

    const userTarget = body.reported_user_id ?? null;
    const groupTarget = body.reported_group_id ?? null;
    if (userTarget !== null && !(typeof userTarget === "string" && UUID_RE.test(userTarget))) {
      return bad("reported_user_id");
    }
    if (groupTarget !== null && !(typeof groupTarget === "string" && UUID_RE.test(groupTarget))) {
      return bad("reported_group_id");
    }
    // Exactly one target.
    if ((userTarget === null) === (groupTarget === null)) return bad("reported_user_id");
    const reason = body.reason;
    if (typeof reason !== "string" || !(REPORT_REASONS as readonly string[]).includes(reason)) return bad("reason");
    const details = body.details ?? "";
    if (typeof details !== "string") return bad("details");

    const [{ n }] = await q<{ n: number }>(
      `SELECT count(*)::int AS n FROM public.reports
        WHERE reporter_id = $1 AND created_at > now() - interval '24 hours'`,
      [user.id],
    );
    if (n >= MAX_REPORTS_PER_DAY) {
      r.log.warn("report rate limited", { user_id: user.id, reports_24h: n });
      return r.fail(429, "Too many reports; try again later", "RATE_LIMITED");
    }

    let report: ReportRow;
    try {
      [report] = await q<ReportRow>(
        `INSERT INTO public.reports (reporter_id, reported_user_id, reported_group_id, reason, details)
         VALUES ($1, $2, $3, $4, left(coalesce(public.sanitize_text($5::text), ''), ${MAX_DETAILS}))
         RETURNING ${REPORT_COLUMNS}`,
        [user.id, userTarget, groupTarget, reason, details],
      );
    } catch (err) {
      if (pgError(err).code === "23503") {
        return userTarget !== null
          ? r.fail(404, "User not found", "PROFILE_NOT_FOUND")
          : r.fail(404, "Group not found", "GROUP_NOT_FOUND");
      }
      throw err;
    }

    r.log.info("report filed", { user_id: user.id, report_id: report.id, reason });
    await notifyReportFiled(deps, report, r.log);
    return r.ok({ id: report.id }, 201);
  });

  /** Reads and checks { user_id } for block/unblock. */
  function targetOf(body: Record<string, unknown>): string | null {
    const id = body.user_id;
    return typeof id === "string" && UUID_RE.test(id) ? id.toLowerCase() : null;
  }

  app.all("/block", async (c) => {
    const r = requestCtx(c, deps, "block");
    if (c.req.method !== "POST") return methodNotAllowed(r);

    const gate = await activeUser(c, deps, r);
    if (gate instanceof Response) return gate;
    const { user } = gate;

    const body = await readJson(c.req.raw);
    if (body === null) return r.fail(400, "Body must be a JSON object", "INVALID_JSON");
    const target = targetOf(body);
    if (target === null) return r.bad("user_id");
    if (target === user.id) {
      return r.fail(400, "You cannot block yourself", "INVALID_FIELD", { field: "user_id" });
    }

    const outcome = await tx(async (db) => {
      const found = await db.query("SELECT 1 FROM public.profiles WHERE id = $1", [target]);
      if (found.rowCount === 0) return "not-found" as const;
      const inserted = await db.query(
        "INSERT INTO public.user_blocks (blocker_id, blocked_id) VALUES ($1, $2) ON CONFLICT DO NOTHING",
        [user.id, target],
      );
      // Only a new block notifies the developer, and at most one notice per
      // (reporter, target) pair ever, so block/unblock/block cannot flood the
      // review queue.
      if (inserted.rowCount === 0) return null;
      const { rows } = await db.query<ReportRow>(
        `INSERT INTO public.reports (reporter_id, reported_user_id, reason, details)
         SELECT $1, $2, 'blocked_by_user', $3
          WHERE NOT EXISTS (
            SELECT 1 FROM public.reports r
             WHERE r.reporter_id = $1 AND r.reported_user_id = $2 AND r.reason = 'blocked_by_user')
         RETURNING ${REPORT_COLUMNS}`,
        [user.id, target, BLOCK_NOTICE],
      );
      return rows[0] ?? null;
    });
    if (outcome === "not-found") return r.fail(404, "User not found", "PROFILE_NOT_FOUND");

    r.log.info("user blocked", { user_id: user.id, blocked_id: target, notice_filed: outcome !== null });
    if (outcome) await notifyReportFiled(deps, outcome, r.log);
    return r.ok({ blocked: true });
  });

  app.all("/unblock", async (c) => {
    const r = requestCtx(c, deps, "unblock");
    if (c.req.method !== "POST") return methodNotAllowed(r);

    const gate = await activeUser(c, deps, r);
    if (gate instanceof Response) return gate;
    const { user } = gate;

    const body = await readJson(c.req.raw);
    if (body === null) return r.fail(400, "Body must be a JSON object", "INVALID_JSON");
    const target = targetOf(body);
    if (target === null) return r.bad("user_id");

    await q("DELETE FROM public.user_blocks WHERE blocker_id = $1 AND blocked_id = $2", [user.id, target]);
    r.log.info("user unblocked", { user_id: user.id, blocked_id: target });
    return r.ok({ blocked: false });
  });

  return app;
}
