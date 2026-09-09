// join-group: join a group by invite code.
//
// POST { invite_code: "ABC123" }
// Auth: user JWT (non-anonymous).
//
// 200 { group: { ...full groups row }, already_member: false }
// 200 { group: { ...full groups row }, already_member: true }
// 400 INVALID_JSON / INVALID_INVITE_CODE   401   403 BANNED / DELETED / ANONYMOUS_USER
// 404 GROUP_NOT_FOUND   409 GROUP_FULL / GROUP_INACTIVE / TOO_MANY_GROUPS   500
//
// The member_count is maintained atomically by a trigger on group_members; the
// 50-member cap is enforced by the same trigger under a row lock.

import {
  adminClient,
  banCheck,
  correlationIdFrom,
  CORRELATION_HEADER,
  errorFields,
  errorResponse,
  getUser,
  handleCommon,
  json,
  Logger,
  readJson,
} from "../_shared/http.ts";

const FN = "join-group";
const MAX_GROUPS_PER_USER = 20;
const INVITE_RE = /^[A-Z0-9]{6}$/;

Deno.serve(async (req: Request): Promise<Response> => {
  const common = handleCommon(req, FN);
  if (common) return common;

  const correlationId = correlationIdFrom(req);
  const log = new Logger(FN, correlationId);
  const ok = (body: unknown, status = 200) =>
    json(body, status, { [CORRELATION_HEADER]: correlationId });

  if (req.method !== "POST") {
    return errorResponse(405, "Method not allowed", "METHOD_NOT_ALLOWED", correlationId);
  }

  try {
    const user = await getUser(req);
    if (!user) return errorResponse(401, "Unauthorized", "UNAUTHORIZED", correlationId);
    const admin = adminClient();
    const gate = await banCheck(admin, user.id);
    if (!gate.ok) {
      log.warn("caller rejected", { user_id: user.id, code: gate.code });
      return errorResponse(gate.status, gate.message, gate.code, correlationId);
    }
    if (gate.profile.is_anonymous || user.isAnonymous) {
      return errorResponse(403, "Create an account to join groups", "ANONYMOUS_USER", correlationId);
    }

    const body = await readJson(req);
    if (body === null) {
      return errorResponse(400, "Body must be a JSON object", "INVALID_JSON", correlationId);
    }
    const rawCode = body.invite_code;
    const inviteCode = typeof rawCode === "string" ? rawCode.trim().toUpperCase() : "";
    if (!INVITE_RE.test(inviteCode)) {
      return errorResponse(400, "Invite code must be 6 letters/digits", "INVALID_INVITE_CODE", correlationId);
    }

    const lg = log.child({ user_id: user.id, invite_code: inviteCode });

    const { data: group, error: groupError } = await admin
      .from("groups")
      .select("*")
      .eq("invite_code", inviteCode)
      .eq("is_active", true)
      .maybeSingle();
    if (groupError) throw new Error(`group lookup failed: ${groupError.message}`);
    if (!group) {
      lg.info("invite code not found");
      return errorResponse(404, "Invalid invite code", "GROUP_NOT_FOUND", correlationId);
    }
    const groupId = group.id as string;

    const { data: existing } = await admin
      .from("group_members")
      .select("id")
      .eq("group_id", groupId)
      .eq("user_id", user.id)
      .maybeSingle();
    if (existing) {
      lg.info("already a member");
      return ok({ group, already_member: true });
    }

    const { count: membershipCount } = await admin
      .from("group_members")
      .select("id", { count: "exact", head: true })
      .eq("user_id", user.id);
    if ((membershipCount ?? 0) >= MAX_GROUPS_PER_USER) {
      return errorResponse(409, `You can be in at most ${MAX_GROUPS_PER_USER} groups`, "TOO_MANY_GROUPS", correlationId);
    }

    const { error: insertError } = await admin
      .from("group_members")
      .insert({ group_id: groupId, user_id: user.id, role: "member" });
    if (insertError) {
      const hint = (insertError as { hint?: string }).hint ?? "";
      if (insertError.code === "23505") {
        const { data: again } = await admin.from("groups").select("*").eq("id", groupId).single();
        return ok({ group: again ?? group, already_member: true });
      }
      if (hint === "GROUP_FULL" || insertError.code === "23514") {
        lg.info("group full");
        return errorResponse(409, "Group is full (max 50 members)", "GROUP_FULL", correlationId);
      }
      if (hint === "GROUP_INACTIVE") {
        return errorResponse(409, "Group is no longer active", "GROUP_INACTIVE", correlationId);
      }
      throw new Error(`member insert failed: ${insertError.message} (${insertError.code})`);
    }

    await admin.from("group_feed").insert({
      group_id: groupId,
      user_id: user.id,
      puzzle_date: new Date().toISOString().slice(0, 10),
      event: "joined",
    });
    await admin.from("profiles").update({ last_active_at: new Date().toISOString() }).eq("id", user.id);

    const { data: fresh, error: freshError } = await admin.from("groups").select("*").eq("id", groupId).single();
    if (freshError || !fresh) throw new Error(`group re-read failed: ${freshError?.message}`);

    lg.info("joined group", { group_id: groupId, member_count: fresh.member_count });
    return ok({ group: fresh, already_member: false });
  } catch (err) {
    log.error("unhandled error", errorFields(err));
    return errorResponse(500, "Internal server error", "INTERNAL", correlationId);
  }
});
