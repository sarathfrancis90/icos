// start-puzzle: open (or resume) a play session for a puzzle date.
//
// POST { puzzle_date: "YYYY-MM-DD" }
// Auth: user JWT (verify_jwt = true at the gateway; re-checked here).
//
// 200 { puzzle_date, nonce, started_at, already_completed }
// 400 { error, code }  401/403  404 { error, code: "PUZZLE_NOT_FOUND" }
//
// The session is idempotent: calling again for the same date returns the SAME
// nonce and the ORIGINAL started_at (so resuming after an app restart does not
// shrink the server-side elapsed time used by submit-score's clock check).
// The nonce is the HMAC key the client uses to sign its score submission.

import {
  addDays,
  adminClient,
  banCheck,
  compareDates,
  correlationIdFrom,
  CORRELATION_HEADER,
  errorFields,
  errorResponse,
  getUser,
  handleCommon,
  isIsoDate,
  json,
  Logger,
  randomNonce,
  readJson,
  utcToday,
} from "../_shared/http.ts";

const FN = "start-puzzle";
const ARCHIVE_WINDOW_DAYS = 30;

Deno.serve(async (req: Request): Promise<Response> => {
  const common = handleCommon(req, FN);
  if (common) return common;

  const correlationId = correlationIdFrom(req);
  const log = new Logger(FN, correlationId);

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

    const body = await readJson(req);
    if (body === null) {
      return errorResponse(400, "Body must be a JSON object", "INVALID_JSON", correlationId);
    }
    const puzzleDate = body.puzzle_date;
    if (!isIsoDate(puzzleDate)) {
      return errorResponse(400, "puzzle_date must be YYYY-MM-DD", "INVALID_DATE", correlationId);
    }
    const today = utcToday();
    if (compareDates(puzzleDate, today) > 0 || compareDates(puzzleDate, addDays(today, -ARCHIVE_WINDOW_DAYS)) < 0) {
      return errorResponse(400, "puzzle_date is outside the playable window", "DATE_OUT_OF_RANGE", correlationId);
    }

    const lg = log.child({ user_id: user.id, puzzle_date: puzzleDate });

    const { data: puzzle, error: puzzleError } = await admin
      .from("puzzles")
      .select("id")
      .eq("puzzle_date", puzzleDate)
      .maybeSingle();
    if (puzzleError) throw new Error(`puzzle lookup failed: ${puzzleError.message}`);
    if (!puzzle) {
      return errorResponse(404, "No puzzle for that date", "PUZZLE_NOT_FOUND", correlationId);
    }

    // Insert-if-absent, then read back whichever row exists.
    const { error: insertError } = await admin
      .from("puzzle_sessions")
      .upsert(
        { user_id: user.id, puzzle_date: puzzleDate, nonce: randomNonce(32) },
        { onConflict: "user_id,puzzle_date", ignoreDuplicates: true },
      );
    if (insertError) throw new Error(`session upsert failed: ${insertError.message}`);

    const { data: session, error: sessionError } = await admin
      .from("puzzle_sessions")
      .select("nonce, started_at")
      .eq("user_id", user.id)
      .eq("puzzle_date", puzzleDate)
      .single();
    if (sessionError || !session) throw new Error(`session read failed: ${sessionError?.message}`);

    const { data: attempt } = await admin
      .from("puzzle_attempts")
      .select("completed")
      .eq("user_id", user.id)
      .eq("puzzle_date", puzzleDate)
      .eq("completed", true)
      .maybeSingle();

    await admin.from("profiles").update({ last_active_at: new Date().toISOString() }).eq("id", user.id);

    lg.info("session ready", { already_completed: Boolean(attempt) });
    return json(
      {
        puzzle_date: puzzleDate,
        nonce: session.nonce as string,
        started_at: session.started_at as string,
        already_completed: Boolean(attempt),
      },
      200,
      { [CORRELATION_HEADER]: correlationId },
    );
  } catch (err) {
    log.error("unhandled error", errorFields(err));
    return errorResponse(500, "Internal server error", "INTERNAL", correlationId);
  }
});
