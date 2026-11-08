// pool / q / tx against the Neon `test` branch. Skips (does not fail) when
// NEON_TEST_DATABASE_URL is not set.
import { after, before, describe, test } from "node:test";
import assert from "node:assert/strict";
import { TEST_DATABASE_URL } from "./helpers/env.js";

const url = TEST_DATABASE_URL;

// Runs first: the module is cached afterwards, and the pool reads
// DATABASE_URL lazily, so the suite below can still point it at the test branch.
test("importing db.ts without DATABASE_URL does not throw; first use does", async () => {
  const saved = process.env.DATABASE_URL;
  delete process.env.DATABASE_URL;
  try {
    const mod = await import("../src/db.js");
    assert.throws(() => mod.getPool(), /DATABASE_URL is not set/);
  } finally {
    if (saved !== undefined) process.env.DATABASE_URL = saved;
  }
});

describe("db", { skip: url ? false : "NEON_TEST_DATABASE_URL not set" }, () => {
  let db: typeof import("../src/db.js");

  before(async () => {
    // Point the lazily-built pool at the test branch before its first use.
    process.env.DATABASE_URL = url;
    db = await import("../src/db.js");
  });

  after(async () => {
    await db?.closePool();
  });

  test("q returns rows", async () => {
    const rows = await db.q<{ one: number }>("select 1 as one");
    assert.deepEqual(rows, [{ one: 1 }]);
  });

  test("q binds parameters", async () => {
    const rows = await db.q<{ v: string }>("select $1::text as v", ["icos"]);
    assert.equal(rows[0].v, "icos");
  });

  test("tx commits and returns the callback's value", async () => {
    const value = await db.tx(async (c) => {
      await c.query("create temp table tx_ok (n int) on commit drop");
      const { rows } = await c.query<{ n: number }>("insert into tx_ok values (7) returning n");
      return rows[0].n;
    });
    assert.equal(value, 7);
  });

  test("tx rolls back on throw and rethrows the original error", async () => {
    const table = `tx_rollback_${process.pid}_${Date.now()}`;
    const boom = new Error("boom");
    await assert.rejects(
      db.tx(async (c) => {
        await c.query(`create table ${table} (n int)`);
        throw boom;
      }),
      (err) => err === boom,
    );
    const rows = await db.q<{ t: string | null }>("select to_regclass($1)::text as t", [table]);
    assert.equal(rows[0].t, null, "table creation rolled back");
  });

  test("the pool is reused across calls", async () => {
    assert.equal(db.getPool(), db.getPool());
  });
});
