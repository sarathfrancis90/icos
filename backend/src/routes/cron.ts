// POST /cron/:job — the Neon schedule triggers (design §8, purges §7.3).
//
// Only Neon can call these: its Functions proxy strips client-set X-Neon-*
// headers, so X-Neon-Trigger-Invocation-Id being present proves the request is
// a trigger delivery (else 401 UNAUTHORIZED). Unknown job -> 404 UNKNOWN_JOB.
//
// Body (Neon's trigger payload): {version, invocation_id, trigger{type,id,name},
// data{scheduled_at}, previous_attempts}. (job, data.scheduled_at) is claimed in
// cron_runs first, so a duplicate delivery answers 200 {job, ran:false}. A run
// answers 200 {job, ran:true, result}. A failed run frees its cron_runs row and
// answers 503 + Retry-After: 300 {error, code:"JOB_FAILED"} so Neon retries.
import { Hono } from "hono";
import { q, tx } from "../db.js";
import { addDays, errorFields, Logger, readJson, utcToday } from "../shared/http.js";
import { type ApiDeps, requestCtx } from "./common.js";
import { generateForDate as realGenerateForDate } from "./puzzle.js";

export const INVOCATION_HEADER = "x-neon-trigger-invocation-id";

/** How many days after today daily-puzzle keeps generated (today … today+14). */
export const PUZZLE_BUFFER_DAYS = 14;

export const JOB_NAMES = [
  "reset-weekly-freezes",
  "apply-streak-freezes",
  "expire-stale-streaks",
  "daily-puzzle",
  "purge-deleted-accounts",
  "purge-inactive-anonymous",
  "prune-submission-log",
] as const;

export type JobName = (typeof JOB_NAMES)[number];

/** A job's summary (counts) for the response and the log. */
export type JobResult = Record<string, unknown>;
export type Job = (log: Logger) => Promise<JobResult>;

/** A job that did part of its work: the run still fails (Neon retries). */
export class PartialJobFailure extends Error {
  constructor(
    message: string,
    readonly result: JobResult,
  ) {
    super(message);
    this.name = "PartialJobFailure";
  }
}

/** Test seams: replace a job, the generator, today's date or the window. */
export interface CronOptions {
  jobs?: Partial<Record<JobName, Job>>;
  generateForDate?: (date: string, log: Logger) => Promise<"exists" | "created">;
  today?: () => string;
  /** Days after today daily-puzzle covers (default PUZZLE_BUFFER_DAYS). */
  windowDays?: number;
}

/** Runs `SELECT public.<fn>()` (an integer-returning SQL job). */
function sqlCountJob(fn: string): Job {
  return async () => {
    const [row] = await q<{ count: number }>(`SELECT public.${fn}() AS count`);
    return { count: Number(row?.count ?? 0) };
  };
}

// Anonymous auth users with no profile, older than an hour. The age guard keeps
// away from a guest whose profile the user.create.after hook (or requireSession's
// repair, or a sign-up re-key) is about to create or move.
const HEAL_ORPHAN_GUESTS = `
  DELETE FROM ba."user" u
   WHERE u."isAnonymous"
     AND u."createdAt" < now() - interval '1 hour'
     AND NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = u.id)`;

async function purgeDeletedAccounts(): Promise<JobResult> {
  // One transaction: a profile is never anonymized while its sign-in survives.
  const purged = await tx(async (c) => {
    const ids = (await c.query<{ id: string }>("SELECT id FROM public.purge_deleted_accounts() AS id")).rows.map(
      (r) => r.id,
    );
    if (ids.length > 0) await c.query(`DELETE FROM ba."user" WHERE id = ANY($1::uuid[])`, [ids]);
    return ids.length;
  });
  // Self-heal: sign-ins left by a purge that ran before this code (or by hand).
  const healed = await q(
    `DELETE FROM ba."user" u
      WHERE EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = u.id AND p.purged_at IS NOT NULL)
      RETURNING 1`,
  );
  return { purged, healed: healed.length };
}

async function purgeInactiveAnonymous(): Promise<JobResult> {
  const purged = await tx(async (c) => {
    // Auth rows first (same predicate as purge_inactive_anonymous): requireSession
    // recreates a missing profile, so a guest must never keep a sign-in without one.
    await c.query(
      `DELETE FROM ba."user" u
        WHERE u."isAnonymous"
          AND EXISTS (SELECT 1 FROM public.profiles p
                       WHERE p.id = u.id AND p.is_anonymous
                         AND p.last_active_at < now() - interval '90 days')`,
    );
    return (await c.query("SELECT id FROM public.purge_inactive_anonymous() AS id")).rowCount ?? 0;
  });
  const healed = await q(`${HEAL_ORPHAN_GUESTS} RETURNING 1`);
  return { purged, healed: healed.length };
}

function dailyPuzzleJob(opts: CronOptions): Job {
  const generate = opts.generateForDate ?? realGenerateForDate;
  const today = opts.today ?? utcToday;
  const windowDays = opts.windowDays ?? PUZZLE_BUFFER_DAYS;
  return async (log) => {
    const from = today();
    const to = addDays(from, windowDays);
    const existingRows = await q<{ puzzle_date: string }>(
      "SELECT puzzle_date FROM public.puzzles WHERE puzzle_date BETWEEN $1 AND $2",
      [from, to],
    );
    const existing = new Set(existingRows.map((r) => r.puzzle_date));
    const created: string[] = [];
    const failed: string[] = [];
    for (let i = 0; i <= windowDays; i += 1) {
      const date = addDays(from, i);
      if (existing.has(date)) continue;
      try {
        await generate(date, log.child({ date }));
        created.push(date);
      } catch (err) {
        failed.push(date);
        log.error("puzzle generation failed", { date, ...errorFields(err) });
      }
    }
    const result: JobResult = { created, existing: existing.size };
    if (failed.length > 0) {
      throw new PartialJobFailure(`generation failed for ${failed.length} date(s)`, { ...result, failed });
    }
    return result;
  };
}

function buildJobs(opts: CronOptions): Record<JobName, Job> {
  return {
    "reset-weekly-freezes": sqlCountJob("reset_weekly_freezes"),
    "apply-streak-freezes": sqlCountJob("apply_streak_freezes"),
    "expire-stale-streaks": sqlCountJob("expire_stale_streaks"),
    "daily-puzzle": dailyPuzzleJob(opts),
    "purge-deleted-accounts": purgeDeletedAccounts,
    "purge-inactive-anonymous": purgeInactiveAnonymous,
    "prune-submission-log": sqlCountJob("prune_submission_log"),
    ...opts.jobs,
  };
}

function isJobName(name: string): name is JobName {
  return (JOB_NAMES as readonly string[]).includes(name);
}

/** data.scheduled_at as an ISO timestamp, or null when absent or unparseable. */
function scheduledAtOf(body: Record<string, unknown> | null): string | null {
  const data = body?.data;
  if (data === null || typeof data !== "object") return null;
  const at = (data as Record<string, unknown>).scheduled_at;
  if (typeof at !== "string" || Number.isNaN(Date.parse(at))) return null;
  return at;
}

export function cronRoutes(deps: ApiDeps, opts: CronOptions = {}): Hono {
  const app = new Hono();
  const jobs = buildJobs(opts);

  app.post("/:job", async (c) => {
    const r = requestCtx(c, deps, "cron");
    const invocationId = c.req.header(INVOCATION_HEADER)?.trim();
    if (!invocationId) return r.fail(401, "Unauthorized", "UNAUTHORIZED");

    const job = c.req.param("job");
    if (!isJobName(job)) return r.fail(404, `Unknown job: ${job}`, "UNKNOWN_JOB");

    const body = await readJson(c.req.raw);
    const log = r.log.child({ job, invocation_id: invocationId });
    // The idempotency key. A delivery without a usable scheduled_at (not sent
    // by Neon's schedule triggers) is keyed to its minute; every job is safe to
    // re-run, so this only narrows duplicate suppression.
    const scheduledAt = scheduledAtOf(body);
    if (scheduledAt === null) log.warn("trigger payload without data.scheduled_at");

    await q("DELETE FROM public.cron_runs WHERE ran_at < now() - interval '30 days'");
    const claimed = await q<{ scheduled_at: Date }>(
      `INSERT INTO public.cron_runs (job, scheduled_at)
       VALUES ($1, COALESCE($2::timestamptz, date_trunc('minute', now())))
       ON CONFLICT DO NOTHING
       RETURNING scheduled_at`,
      [job, scheduledAt],
    );
    if (claimed.length === 0) {
      log.info("duplicate delivery ignored", { scheduled_at: scheduledAt });
      return r.ok({ job, ran: false });
    }
    const slot = claimed[0].scheduled_at;

    const started = Date.now();
    try {
      const result = await jobs[job](log);
      log.info("job done", { result, ms: Date.now() - started });
      return r.ok({ job, ran: true, result });
    } catch (err) {
      log.error("job failed", { ms: Date.now() - started, ...errorFields(err) });
      try {
        await q("DELETE FROM public.cron_runs WHERE job = $1 AND scheduled_at = $2", [job, slot]);
      } catch (releaseErr) {
        log.error("could not release the cron_runs slot", errorFields(releaseErr));
      }
      const extra = err instanceof PartialJobFailure ? { result: err.result } : {};
      const res = r.fail(503, `Job ${job} failed`, "JOB_FAILED", extra);
      res.headers.set("Retry-After", "300");
      return res;
    }
  });

  return app;
}
