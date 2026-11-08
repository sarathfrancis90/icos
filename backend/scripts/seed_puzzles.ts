// Generate puzzles for a date range directly against a branch database.
//
//   npm run seed:puzzles -- --url <unpooled connection string> --from 2026-11-01 --days 46
//
// Uses the same generateForDate() the /cron/daily-puzzle job uses, so the
// seeded rows are byte-identical to what the nightly job would produce for the
// configured PUZZLE_SEED_SALT. Existing dates are skipped. Never prints the URL.
import { addDays, isIsoDate, utcToday } from "../src/shared/http.js";

function arg(name: string): string | undefined {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 ? process.argv[i + 1] : undefined;
}

async function main(): Promise<number> {
  const url = arg("url") ?? process.env.DATABASE_URL_UNPOOLED ?? process.env.DATABASE_URL;
  if (!url) {
    console.error("usage: seed_puzzles --url <connection string> [--from YYYY-MM-DD] [--days N]");
    return 2;
  }
  if (!process.env.PUZZLE_SEED_SALT) {
    console.error("PUZZLE_SEED_SALT must be set");
    return 2;
  }
  process.env.DATABASE_URL = url;
  const from = arg("from") ?? utcToday();
  const days = Number(arg("days") ?? "1");
  if (!isIsoDate(from) || !Number.isInteger(days) || days < 1 || days > 120) {
    console.error("invalid --from or --days");
    return 2;
  }
  const { generateForDate } = await import("../src/routes/puzzle.js");
  const { closePool } = await import("../src/db.js");
  let created = 0;
  let existing = 0;
  for (let i = 0; i < days; i++) {
    const date = addDays(from, i);
    const started = Date.now();
    const result = await generateForDate(date);
    if (result === "created") created++;
    else existing++;
    console.log(`${date} ${result} (${Date.now() - started} ms)`);
  }
  console.log(`done: created ${created}, existing ${existing}`);
  await closePool();
  return 0;
}

main().then(
  (code) => process.exit(code),
  (err) => {
    console.error(err instanceof Error ? err.message : String(err));
    process.exit(1);
  },
);
