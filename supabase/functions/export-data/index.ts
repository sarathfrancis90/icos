// export-data: data-subject access request (DSAR) export for the caller.
//
// GET or POST (no body). Auth: user JWT.
//
// 200 {
//   exported_at, user: { id, email, is_anonymous, created_at },
//   profile: {...}, attempts: [...], streak: {...} | null, streak_freezes: [...],
//   groups: [{ ...group, role, joined_at }], reports_filed: [...]
// }
// 401 / 403 (BANNED)   500
//
// Deletion-pending accounts may still export (that is the point of the grace period).

import {
  adminClient,
  correlationIdFrom,
  CORRELATION_HEADER,
  errorFields,
  errorResponse,
  getUser,
  handleCommon,
  json,
  Logger,
} from "../_shared/http.ts";

const FN = "export-data";

Deno.serve(async (req: Request): Promise<Response> => {
  const common = handleCommon(req, FN);
  if (common) return common;

  const correlationId = correlationIdFrom(req);
  const log = new Logger(FN, correlationId);

  if (req.method !== "GET" && req.method !== "POST") {
    return errorResponse(405, "Method not allowed", "METHOD_NOT_ALLOWED", correlationId);
  }

  try {
    const user = await getUser(req);
    if (!user) return errorResponse(401, "Unauthorized", "UNAUTHORIZED", correlationId);
    const admin = adminClient();
    const lg = log.child({ user_id: user.id });

    const { data: profile, error: profileError } = await admin
      .from("profiles")
      .select("*")
      .eq("id", user.id)
      .maybeSingle();
    if (profileError) throw new Error(`profile lookup failed: ${profileError.message}`);
    if (!profile) return errorResponse(403, "Profile not found", "PROFILE_NOT_FOUND", correlationId);
    if (profile.is_banned) return errorResponse(403, "Account suspended", "BANNED", correlationId);

    const [attempts, streak, freezes, memberships, reports, authUser] = await Promise.all([
      admin
        .from("puzzle_attempts")
        .select("puzzle_date, time_seconds, hints_used, undos_used, completed, verified, is_archive, attempt_count, path, completed_at, created_at, updated_at")
        .eq("user_id", user.id)
        .order("puzzle_date", { ascending: false }),
      admin.from("streaks").select("current_streak, longest_streak, freeze_count, last_solve_date, last_freeze_used_at, freeze_reset_week_start, updated_at").eq("user_id", user.id).maybeSingle(),
      admin.from("streak_freezes").select("frozen_date, created_at").eq("user_id", user.id).order("frozen_date"),
      admin.from("group_members").select("role, joined_at, groups(*)").eq("user_id", user.id),
      admin.from("reports").select("id, reported_user_id, reported_group_id, reason, details, status, created_at").eq("reporter_id", user.id),
      admin.auth.admin.getUserById(user.id),
    ]);

    for (const r of [attempts, streak, freezes, memberships, reports]) {
      if (r.error) throw new Error(`export query failed: ${r.error.message}`);
    }

    const groups = (memberships.data ?? []).map((m) => {
      const row = m as unknown as {
        role: string;
        joined_at: string;
        groups: Record<string, unknown> | Record<string, unknown>[] | null;
      };
      const group = Array.isArray(row.groups) ? row.groups[0] ?? {} : row.groups ?? {};
      return { ...group, role: row.role, joined_at: row.joined_at };
    });

    const au = authUser.data?.user;
    const payload = {
      exported_at: new Date().toISOString(),
      user: {
        id: user.id,
        email: au?.email ?? user.email,
        is_anonymous: Boolean((au as { is_anonymous?: boolean } | undefined)?.is_anonymous),
        created_at: au?.created_at ?? null,
        providers: (au?.app_metadata?.providers as string[] | undefined) ?? [],
      },
      profile,
      attempts: attempts.data ?? [],
      streak: streak.data ?? null,
      streak_freezes: freezes.data ?? [],
      groups,
      reports_filed: reports.data ?? [],
    };

    lg.info("export produced", {
      attempts: payload.attempts.length,
      groups: groups.length,
    });

    return json(payload, 200, {
      [CORRELATION_HEADER]: correlationId,
      "Content-Disposition": `attachment; filename="icos-export-${user.id}.json"`,
    });
  } catch (err) {
    log.error("unhandled error", errorFields(err));
    return errorResponse(500, "Internal server error", "INTERNAL", correlationId);
  }
});
