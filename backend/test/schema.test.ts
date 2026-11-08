// Schema checks for migrations/0001_schema.sql against the Neon `test` branch.
// Skips (does not fail) when NEON_TEST_DATABASE_URL is not set.
import { after, before, describe, test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import pg from "pg";
import { TEST_DATABASE_URL } from "./helpers/env.js";
import { applyMigrations, clientConfig } from "../scripts/migrate.js";

const APP_TABLES = [
  "profiles",
  "puzzles",
  "puzzle_solutions",
  "puzzle_attempts",
  "streaks",
  "streak_freezes",
  "puzzle_sessions",
  "submission_log",
  "groups",
  "group_members",
  "group_feed",
  "group_purged_members",
  "reports",
  "banned_words",
  "app_config",
  "user_blocks",
  "schema_migrations",
];
const ALL_TABLES = [...APP_TABLES, "cron_runs"];

// Every column that used to reference auth.users(id) (or already referenced
// profiles) and now hangs off the root identity profiles(id).
const PROFILE_FKS: Array<[table: string, column: string, onDelete: "c" | "n"]> = [
  ["puzzle_attempts", "user_id", "c"],
  ["streaks", "user_id", "c"],
  ["streak_freezes", "user_id", "c"],
  ["puzzle_sessions", "user_id", "c"],
  ["submission_log", "user_id", "c"],
  ["groups", "admin_id", "c"],
  ["group_members", "user_id", "c"],
  ["group_feed", "user_id", "c"],
  ["group_purged_members", "user_id", "c"],
  ["reports", "reporter_id", "c"],
  ["reports", "reported_user_id", "n"],
  ["user_blocks", "blocker_id", "c"],
  ["user_blocks", "blocked_id", "c"],
];

const PRIVILEGES = ["SELECT", "INSERT", "UPDATE", "DELETE", "TRUNCATE", "REFERENCES", "TRIGGER"];

// What the client role may do; RLS narrows the rows further.
const AUTHENTICATED_GRANTS: Record<string, string[]> = {
  profiles: ["SELECT", "INSERT", "UPDATE"],
  puzzles: ["SELECT"],
  puzzle_attempts: ["SELECT"],
  streaks: ["SELECT"],
  streak_freezes: ["SELECT"],
  groups: ["SELECT"],
  group_members: ["SELECT"],
  group_feed: ["SELECT"],
  reports: ["SELECT", "INSERT"],
  app_config: ["SELECT"],
  user_blocks: ["SELECT"],
};
const ANONYMOUS_GRANTS: Record<string, string[]> = {
  puzzles: ["SELECT"],
  app_config: ["SELECT"],
};

describe("0001_schema", { skip: TEST_DATABASE_URL ? false : "NEON_TEST_DATABASE_URL not set" }, () => {
  const url = TEST_DATABASE_URL ?? "";
  let db: pg.Client;

  before(async () => {
    await applyMigrations(url);
    db = new pg.Client(clientConfig(url));
    await db.connect();
  });

  after(async () => {
    await db?.end();
  });

  test("re-running the migrations applies nothing", async () => {
    assert.deepEqual(await applyMigrations(url), []);
  });

  test("every table exists in public with row-level security on", async () => {
    const { rows } = await db.query<{ relname: string; relrowsecurity: boolean }>(
      `SELECT c.relname, c.relrowsecurity
         FROM pg_class c
        WHERE c.relnamespace = 'public'::regnamespace AND c.relkind = 'r'`,
    );
    const byName = new Map(rows.map((r) => [r.relname, r.relrowsecurity]));
    for (const table of ALL_TABLES) {
      assert.equal(byName.has(table), true, `missing table ${table}`);
      assert.equal(byName.get(table), true, `RLS off on ${table}`);
    }
  });

  test("user references point at profiles(id) with ON UPDATE CASCADE", async () => {
    const { rows } = await db.query<{
      tbl: string;
      col: string;
      ref: string;
      refcol: string;
      upd: string;
      del: string;
    }>(
      `SELECT c.conrelid::regclass::text AS tbl,
              a.attname AS col,
              c.confrelid::regclass::text AS ref,
              ra.attname AS refcol,
              c.confupdtype AS upd,
              c.confdeltype AS del
         FROM pg_constraint c
         JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
         JOIN pg_attribute ra ON ra.attrelid = c.confrelid AND ra.attnum = c.confkey[1]
        WHERE c.contype = 'f' AND c.connamespace = 'public'::regnamespace`,
    );
    for (const [table, column, onDelete] of PROFILE_FKS) {
      const fks = rows.filter((r) => r.tbl === table && r.col === column);
      assert.equal(fks.length, 1, `${table}.${column}: expected exactly one FK`);
      const [fk] = fks;
      assert.equal(fk.ref, "profiles", `${table}.${column} references ${fk.ref}`);
      assert.equal(fk.refcol, "id");
      assert.equal(fk.upd, "c", `${table}.${column} must be ON UPDATE CASCADE`);
      assert.equal(fk.del, onDelete, `${table}.${column} ON DELETE`);
    }
    const outside = await db.query(
      `SELECT conname FROM pg_constraint
        WHERE contype = 'f' AND connamespace = 'public'::regnamespace
          AND confrelid::regclass::text NOT IN (${ALL_TABLES.map((_, i) => `$${i + 1}`).join(",")})`,
      ALL_TABLES,
    );
    assert.deepEqual(outside.rows, [], "no FK may leave the public tables");
  });

  test("profiles carries the identity columns", async () => {
    const { rows } = await db.query<{
      column_name: string;
      data_type: string;
      is_nullable: string;
      column_default: string | null;
    }>(
      `SELECT column_name, data_type, is_nullable, column_default
         FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'profiles'
          AND column_name IN ('email', 'email_verified', 'providers')
        ORDER BY column_name`,
    );
    assert.deepEqual(
      rows.map((r) => [r.column_name, r.data_type, r.is_nullable]),
      [
        ["email", "text", "YES"],
        ["email_verified", "boolean", "NO"],
        ["providers", "ARRAY", "NO"],
      ],
    );
    assert.equal(rows[1].column_default, "false");
    assert.match(rows[2].column_default ?? "", /^'\{\}'::text\[\]$/);
  });

  test("puzzles.seed_version defaults to 3", async () => {
    const { rows } = await db.query<{ column_default: string; is_nullable: string }>(
      `SELECT column_default, is_nullable FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'puzzles' AND column_name = 'seed_version'`,
    );
    assert.deepEqual(rows, [{ column_default: "3", is_nullable: "NO" }]);
  });

  test("one completed attempt per user per day (partial unique index)", async () => {
    const { rows } = await db.query<{ def: string }>(
      `SELECT pg_get_indexdef(indexrelid) AS def FROM pg_index
        WHERE indexrelid = 'public.puzzle_attempts_one_completed_per_day'::regclass`,
    );
    assert.equal(rows.length, 1);
    assert.match(rows[0].def, /UNIQUE INDEX .* \(user_id, puzzle_date\) WHERE completed/);
  });

  test("table privileges: anonymous reads puzzles and app_config only", async () => {
    for (const [role, expected] of [
      ["anonymous", ANONYMOUS_GRANTS],
      ["authenticated", AUTHENTICATED_GRANTS],
    ] as const) {
      for (const table of ALL_TABLES) {
        const { rows } = await db.query<{ priv: string; ok: boolean }>(
          `SELECT p AS priv, has_table_privilege($1, $2, p) AS ok FROM unnest($3::text[]) p`,
          [role, `public.${table}`, PRIVILEGES],
        );
        const granted = rows.filter((r) => r.ok).map((r) => r.priv);
        assert.deepEqual(granted, expected[table] ?? [], `${role} on ${table}`);
      }
    }
  });

  test("app.uid() and app.is_service() by role", async () => {
    const sub = randomUUID();
    const claims = JSON.stringify({ sub, role: "authenticated" });
    await db.query("BEGIN");
    try {
      const owner = await db.query(`SELECT app.uid() AS uid, app.is_service() AS svc`);
      assert.deepEqual(owner.rows, [{ uid: null, svc: true }], "owner without a JWT");

      await db.query(`SELECT set_config('request.jwt.claims', $1, true)`, [claims]);
      const ownerWithClaims = await db.query(`SELECT app.uid() AS uid`);
      assert.deepEqual(ownerWithClaims.rows, [{ uid: sub }], "owner with request.jwt.claims");

      await db.query("SET LOCAL ROLE authenticated");
      const authed = await db.query(`SELECT app.uid() AS uid, app.is_service() AS svc`);
      assert.deepEqual(authed.rows, [{ uid: sub, svc: false }], "authenticated with claims");

      await db.query("RESET ROLE");
      await db.query(`SELECT set_config('request.jwt.claims', '', true)`);
      await db.query("SET LOCAL ROLE anonymous");
      const anon = await db.query(`SELECT app.uid() AS uid, app.is_service() AS svc`);
      assert.deepEqual(anon.rows, [{ uid: null, svc: false }], "anonymous without claims");
    } finally {
      await db.query("ROLLBACK");
    }
  });

  test("RLS and protect_profile_columns for an authenticated client", async () => {
    const me = randomUUID();
    const other = randomUUID();
    await db.query("BEGIN");
    try {
      await db.query(
        `INSERT INTO public.profiles (id, display_name) VALUES ($1, 'Player 0001'), ($2, 'Player 0002')`,
        [me, other],
      );
      await db.query(`SELECT set_config('request.jwt.claims', $1, true)`, [
        JSON.stringify({ sub: me, role: "authenticated" }),
      ]);
      await db.query("SET LOCAL ROLE authenticated");

      const visible = await db.query<{ id: string }>(`SELECT id FROM public.profiles`);
      assert.deepEqual(visible.rows, [{ id: me }], "a client sees only its own profile");

      const updated = await db.query<{ theme_mode: string; is_banned: boolean; is_anonymous: boolean }>(
        `UPDATE public.profiles
            SET theme_mode = 'dark', is_banned = true, is_anonymous = false
          RETURNING theme_mode, is_banned, is_anonymous`,
      );
      assert.deepEqual(updated.rows, [{ theme_mode: "dark", is_banned: false, is_anonymous: true }]);

      const blocked = await db.query(`UPDATE public.profiles SET theme_mode = 'light' WHERE id = $1`, [other]);
      assert.equal(blocked.rowCount, 0, "a client cannot update someone else's profile");
    } finally {
      await db.query("ROLLBACK");
    }
  });
});
