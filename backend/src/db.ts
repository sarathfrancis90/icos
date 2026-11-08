// Postgres access for the Icos API: one small pool per Function instance.
//
// The pool is built on first use so importing this module (e.g. from unit
// tests) does not need DATABASE_URL.
import { attachDatabasePool } from "@neon/functions";
import pg, { type PoolClient, type QueryResultRow } from "pg";
import { pgConfig } from "./shared/pg_url.js";

// DATE columns come back as "YYYY-MM-DD" strings (as PostgREST returned
// them), not as JS Dates at local midnight.
pg.types.setTypeParser(pg.types.builtins.DATE, (value: string) => value);

let instance: pg.Pool | undefined;

export function getPool(): pg.Pool {
  if (instance === undefined) {
    const url = process.env.DATABASE_URL;
    if (!url) throw new Error("DATABASE_URL is not set");
    const created = new pg.Pool({ ...pgConfig(url), max: 5 });
    // Swallows idle-connection drops (Neon scale-to-zero) instead of crashing.
    attachDatabasePool(created);
    instance = created;
  }
  return instance;
}

/** The shared pool, created on first property access. */
export const pool: pg.Pool = new Proxy({} as pg.Pool, {
  get(_target, prop) {
    const real = getPool();
    const value = Reflect.get(real, prop, real) as unknown;
    return typeof value === "function" ? value.bind(real) : value;
  },
});

/** Ends the pool (tests, graceful shutdown). The next use builds a new one. */
export async function closePool(): Promise<void> {
  const current = instance;
  instance = undefined;
  await current?.end();
}

/** Runs one statement on the pool and returns its rows. */
export async function q<T = Record<string, unknown>>(text: string, params?: unknown[]): Promise<T[]> {
  const result = await getPool().query<QueryResultRow>(text, params);
  return result.rows as T[];
}

/**
 * Runs `fn` inside BEGIN/COMMIT on one pooled connection. On any error it rolls
 * back and rethrows the original error (a failing ROLLBACK does not mask it).
 */
export async function tx<T>(fn: (c: PoolClient) => Promise<T>): Promise<T> {
  const client = await getPool().connect();
  let broken: Error | undefined;
  try {
    await client.query("BEGIN");
    const value = await fn(client);
    await client.query("COMMIT");
    return value;
  } catch (err) {
    try {
      await client.query("ROLLBACK");
    } catch (rollbackErr) {
      // The connection is unusable; drop it from the pool below.
      broken = rollbackErr as Error;
    }
    throw err;
  } finally {
    client.release(broken);
  }
}
