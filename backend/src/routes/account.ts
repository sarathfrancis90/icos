// GET/POST /api/export-data (port of the export-data edge function) and
// POST /api/account/upgrade-email (replaces supabase updateUser(email,
// password) for a guest: the same id becomes an email account, design §7.2).
//
// export-data -> 200 { exported_at, user, profile, attempts, streak, streak_freezes,
//   groups, reports_filed, blocked_users }   403 PROFILE_NOT_FOUND / BANNED
//   (accounts pending deletion may still export: that is the grace period's point)
// upgrade-email { email, password } -> 200 { user: { id, email, is_anonymous:false, email_verified:false } }
//   400 NOT_ANONYMOUS / INVALID_FIELD   409 EMAIL_EXISTS
import { Hono } from "hono";
import { q, tx } from "../db.js";
import { activeUser, type ApiDeps, methodNotAllowed, pgError, requestCtx } from "./common.js";
import { markProfileLinked, providerDisplayName, realEmailOf, requireSession } from "../identity.js";
import { errorFields, readJson } from "../shared/http.js";

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const MIN_PASSWORD = 6;
const MAX_PASSWORD = 128; // Better Auth's default maximum

/** ba."user" and profile fields captured before an upgrade (restored on failure). */
interface BeforeUpgrade {
  email: string;
  name: string;
  emailVerified: boolean;
  isAnonymous: boolean | null;
  updatedAt: Date;
  is_anonymous: boolean;
  profile_email: string | null;
  email_verified: boolean;
  display_name: string;
  providers: string[];
}

interface ExportProfile {
  email: string | null;
  is_anonymous: boolean;
  is_banned: boolean;
  providers: string[];
  [key: string]: unknown;
}

export function accountRoutes(deps: ApiDeps): Hono {
  const app = new Hono();

  app.all("/export-data", async (c) => {
    const r = requestCtx(c, deps, "export-data");
    if (c.req.method !== "GET" && c.req.method !== "POST") return methodNotAllowed(r);

    const user = await requireSession(c, deps.auth());
    const lg = r.log.child({ user_id: user.id });

    const [profile] = await q<ExportProfile>("SELECT * FROM public.profiles WHERE id = $1 LIMIT 1", [user.id]);
    if (!profile) return r.fail(403, "Profile not found", "PROFILE_NOT_FOUND");
    if (profile.is_banned) return r.fail(403, "Account suspended", "BANNED");

    const [attempts, streaks, freezes, groups, reports, blocks, authUsers] = await Promise.all([
      q(
        `SELECT puzzle_date, time_seconds, hints_used, undos_used, completed, verified, is_archive,
                attempt_count, path, completed_at, created_at, updated_at
           FROM public.puzzle_attempts WHERE user_id = $1 ORDER BY puzzle_date DESC`,
        [user.id],
      ),
      q(
        `SELECT current_streak, longest_streak, freeze_count, last_solve_date, last_freeze_used_at,
                freeze_reset_week_start, updated_at
           FROM public.streaks WHERE user_id = $1 LIMIT 1`,
        [user.id],
      ),
      q("SELECT frozen_date, created_at FROM public.streak_freezes WHERE user_id = $1 ORDER BY frozen_date", [user.id]),
      q<{ g: Record<string, unknown> }>(
        `SELECT to_jsonb(g) || jsonb_build_object('role', gm.role, 'joined_at', gm.joined_at) AS g
           FROM public.group_members gm JOIN public.groups g ON g.id = gm.group_id
          WHERE gm.user_id = $1 ORDER BY gm.joined_at`,
        [user.id],
      ),
      q(
        `SELECT id, reported_user_id, reported_group_id, reason, details, status, created_at
           FROM public.reports WHERE reporter_id = $1`,
        [user.id],
      ),
      q(
        `SELECT blocked_id AS blocked_user_id, created_at AS blocked_at
           FROM public.user_blocks WHERE blocker_id = $1 ORDER BY created_at`,
        [user.id],
      ),
      q<{ createdAt: Date }>(`SELECT "createdAt" FROM ba."user" WHERE id = $1`, [user.id]),
    ]);

    const payload = {
      exported_at: new Date().toISOString(),
      user: {
        id: user.id,
        // A real address only, never a guest's placeholder.
        email: realEmailOf(profile.email) ?? realEmailOf(user.email),
        is_anonymous: profile.is_anonymous,
        created_at: authUsers[0]?.createdAt ?? null,
        providers: profile.providers ?? [],
      },
      profile,
      attempts,
      streak: streaks[0] ?? null,
      streak_freezes: freezes,
      groups: groups.map((row) => row.g),
      reports_filed: reports,
      blocked_users: blocks,
    };

    lg.info("export produced", { attempts: attempts.length, groups: groups.length });
    return r.ok(payload, 200, { "Content-Disposition": `attachment; filename="icos-export-${user.id}.json"` });
  });

  app.all("/account/upgrade-email", async (c) => {
    const r = requestCtx(c, deps, "upgrade-email");
    if (c.req.method !== "POST") return methodNotAllowed(r);

    const gate = await activeUser(c, deps, r);
    if (gate instanceof Response) return gate;
    const { user } = gate;
    if (!user.isAnonymous) return r.fail(400, "This account already has a sign-in method", "NOT_ANONYMOUS");

    const body = await readJson(c.req.raw);
    if (body === null) return r.fail(400, "Body must be a JSON object", "INVALID_JSON");
    const { bad } = r;
    const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
    if (email.length > 254 || !EMAIL_RE.test(email)) return bad("email");
    const password = body.password;
    if (typeof password !== "string" || password.length < MIN_PASSWORD || password.length > MAX_PASSWORD) {
      return bad("password");
    }
    const lg = r.log.child({ user_id: user.id });

    const taken = await q(`SELECT 1 FROM ba."user" WHERE lower(email) = $1 AND id <> $2 LIMIT 1`, [email, user.id]);
    if (taken.length > 0) return r.fail(409, "An account with this email already exists", "EMAIL_EXISTS");

    // 1. Flip the guest to an email account (ba."user" + profile) in one
    //    transaction, re-checking under the row lock that it is still a guest
    //    (a double submit or concurrent request finds it already upgraded).
    //    setPassword and sendVerificationEmail act on the session user, and
    //    sendVerificationEmail requires the session's email to match.
    const name = providerDisplayName(null, email);
    let before: BeforeUpgrade | "not-anonymous";
    try {
      before = await tx(async (db) => {
        const { rows } = await db.query<BeforeUpgrade>(
          `SELECT u.email, u.name, u."emailVerified", u."isAnonymous", u."updatedAt",
                  p.is_anonymous, p.email AS profile_email, p.email_verified, p.display_name, p.providers
             FROM ba."user" u LEFT JOIN public.profiles p ON p.id = u.id
            WHERE u.id = $1 FOR UPDATE OF u`,
          [user.id],
        );
        const row = rows[0];
        if (!row) throw new Error("auth user not found");
        if (!row.isAnonymous) return "not-anonymous" as const;
        await db.query(
          `UPDATE ba."user"
              SET email = $2, "emailVerified" = false, "isAnonymous" = false,
                  name = coalesce($3, name), "updatedAt" = now()
            WHERE id = $1`,
          [user.id, email, name],
        );
        await markProfileLinked(db, user.id, email, false, name);
        return row;
      });
    } catch (err) {
      if (pgError(err).code === "23505") return r.fail(409, "An account with this email already exists", "EMAIL_EXISTS");
      throw err;
    }
    if (before === "not-anonymous") return r.fail(400, "This account already has a sign-in method", "NOT_ANONYMOUS");
    const saved = before;

    // 2. The credential account (its account.create.after hook records the
    //    provider). On failure, put the user and profile back exactly as they
    //    were (profiles.updated_at is set by its trigger and cannot be restored).
    const auth = deps.auth();
    const headers = c.req.raw.headers;
    try {
      await auth.api.setPassword({ body: { newPassword: password }, headers });
    } catch (err) {
      lg.error("setPassword failed; reverting the upgrade", errorFields(err));
      await tx(async (db) => {
        await db.query(`DELETE FROM ba.account WHERE "userId" = $1 AND "providerId" = 'credential'`, [user.id]);
        await db.query(
          `UPDATE ba."user"
              SET email = $2, name = $3, "emailVerified" = $4, "isAnonymous" = $5, "updatedAt" = $6
            WHERE id = $1`,
          [user.id, saved.email, saved.name, saved.emailVerified, saved.isAnonymous, saved.updatedAt],
        );
        await db.query(
          `UPDATE public.profiles
              SET is_anonymous = $2, email = $3, email_verified = $4, display_name = $5, providers = $6
            WHERE id = $1`,
          [user.id, saved.is_anonymous, saved.profile_email, saved.email_verified, saved.display_name, saved.providers],
        );
      });
      throw err;
    }

    // 3. The verification email (best effort: the app can resend it).
    try {
      await auth.api.sendVerificationEmail({ body: { email }, headers });
    } catch (err) {
      lg.warn("verification email not sent", errorFields(err));
    }

    lg.info("guest upgraded to email account");
    return r.ok({ user: { id: user.id, email, is_anonymous: false, email_verified: false } });
  });

  return app;
}
