// Applies backend/migrations/*.sql in order, one transaction per file, and
// records each applied version (the file name's leading digits) in
// public.schema_migrations.
//
//   npm run migrate -- --url <unpooled connection string>
//
// Logs file names only: never the connection string.
// Migration files must not contain their own BEGIN/COMMIT: the runner wraps each one.
import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import pg from "pg";

const DEFAULT_DIR = fileURLToPath(new URL("../migrations", import.meta.url));
// Arbitrary constant so two concurrent runs serialise instead of racing.
const LOCK_KEY = 4_276_601;

/**
 * pg warns that `sslmode=require` will change meaning; ask for full
 * certificate and host verification explicitly instead.
 */
export function clientConfig(url: string): pg.ClientConfig {
  return {
    connectionString: url.replace(/([?&])sslmode=require\b/, "$1sslmode=verify-full"),
    enableChannelBinding: /[?&]channel_binding=require\b/.test(url),
  };
}

export function versionOf(file: string): string {
  const match = /^(\d+)_.*\.sql$/.exec(file);
  if (!match) throw new Error(`migration file name must start with digits and an underscore: ${file}`);
  return match[1];
}

/** Applies pending migrations; returns the file names applied, in order. */
export async function applyMigrations(url: string, dir: string = DEFAULT_DIR): Promise<string[]> {
  const files = (await readdir(dir)).filter((f) => f.endsWith(".sql")).sort();
  const versions = files.map(versionOf);
  if (new Set(versions).size !== versions.length) throw new Error("duplicate migration versions");

  const client = new pg.Client(clientConfig(url));
  await client.connect();
  const applied: string[] = [];
  try {
    await client.query("SELECT pg_advisory_lock($1)", [LOCK_KEY]);
    await client.query(
      `CREATE TABLE IF NOT EXISTS public.schema_migrations (
         version    text PRIMARY KEY,
         applied_at timestamptz NOT NULL DEFAULT now()
       )`,
    );
    const { rows } = await client.query<{ version: string }>("SELECT version FROM public.schema_migrations");
    const done = new Set(rows.map((r) => r.version));

    for (const file of files) {
      const version = versionOf(file);
      if (done.has(version)) continue;
      const sql = await readFile(join(dir, file), "utf8");
      await client.query("BEGIN");
      try {
        await client.query(sql);
        await client.query("INSERT INTO public.schema_migrations (version) VALUES ($1)", [version]);
        await client.query("COMMIT");
      } catch (err) {
        try {
          await client.query("ROLLBACK");
        } catch {
          // Connection already broken; the original error is what matters.
        }
        throw new Error(`${file}: ${(err as Error).message}`);
      }
      applied.push(file);
    }
  } finally {
    await client.end();
  }
  return applied;
}

function urlFromArgs(argv: string[]): string | undefined {
  const i = argv.indexOf("--url");
  if (i >= 0) return argv[i + 1];
  return argv.find((a) => a.startsWith("--url="))?.slice("--url=".length);
}

async function main(): Promise<void> {
  const url = urlFromArgs(process.argv.slice(2));
  if (!url) {
    console.error("usage: npm run migrate -- --url <connection string>");
    process.exit(2);
  }
  try {
    const applied = await applyMigrations(url);
    for (const file of applied) console.log(`applied ${file}`);
    if (applied.length === 0) console.log("up to date");
  } catch (err) {
    console.error(`migration failed: ${(err as Error).message}`);
    process.exit(1);
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  await main();
}
