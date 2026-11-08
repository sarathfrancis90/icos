// Behaviour of migrations/0002_functions.sql and 0003_seed.sql against the
// Neon `test` branch. Every test runs in one transaction that is rolled back,
// so the users (plain profiles rows), groups, puzzles and attempts it creates
// never persist. A client is simulated with SET LOCAL ROLE authenticated plus
// request.jwt.claims (app.uid() falls back to its `sub`).
// Skips (does not fail) when NEON_TEST_DATABASE_URL is not set.
import { after, before, describe, test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import pg from "pg";
import { TEST_DATABASE_URL } from "./helpers/env.js";
import { applyMigrations, clientConfig } from "../scripts/migrate.js";

// Callable by signed-in clients through the Data API.
const CLIENT_FUNCTIONS = [
  "public.create_group(text, text)",
  "public.leave_group(uuid)",
  "public.remove_group_member(uuid, uuid)",
  "public.transfer_group_admin(uuid, uuid)",
  "public.delete_group(uuid)",
  "public.regenerate_invite_code(uuid)",
  "public.get_group_daily_leaderboard(uuid, date)",
  "public.get_group_weekly_leaderboard(uuid, date)",
  "public.list_blocked_users()",
  "public.request_account_deletion()",
  "public.cancel_account_deletion()",
  "public.sanitize_text(text)",
  "public.validate_name(text, text)",
  "public.contains_profanity(text)",
];
// Owner / Function only.
const SERVICE_FUNCTIONS = [
  "public.generate_invite_code()",
  "public.assert_active_user(uuid)",
  "public.assert_group_member(uuid)",
  "public.recompute_streak(uuid)",
  "public.record_solve(uuid, date)",
  "public.apply_streak_freezes()",
  "public.reset_weekly_freezes()",
  "public.expire_stale_streaks()",
  "public.prune_submission_log()",
  "public.detach_user_from_groups(uuid)",
  "public.purge_deleted_accounts()",
  "public.purge_inactive_anonymous()",
  "public.validate_profile_display_name()",
  "public.group_members_before_insert()",
  "public.group_members_after_change()",
];
// Supabase-era functions that must not exist on Neon.
const REMOVED_FUNCTIONS = [
  "handle_new_user",
  "handle_user_updated",
  "notify_report_filed",
  "trigger_daily_puzzle_generation",
  "decrement_group_member_count",
  "update_group",
  "block_user",
  "unblock_user",
  "provider_display_name",
  "is_placeholder_display_name",
];

type PgError = { code?: string; hint?: string };

describe("0002_functions / 0003_seed", { skip: TEST_DATABASE_URL ? false : "NEON_TEST_DATABASE_URL not set" }, () => {
  const url = TEST_DATABASE_URL ?? "";
  let db: pg.Client;

  before(async () => {
    await applyMigrations(url);
    db = new pg.Client(clientConfig(url));
    await db.connect();
    // Load pg_session_jwt in this backend before any test sets claims: when the
    // library is first loaded inside app.uid() (a function with its own
    // search_path), a transaction-local request.jwt.claims set earlier is lost
    // and app.uid() returns NULL for that transaction. The Data API always
    // calls auth.jwt_session_init first, so real clients are unaffected.
    await db.query(`SELECT auth.user_id()`);
  });

  after(async () => {
    await db?.end();
  });

  // --- helpers --------------------------------------------------------------

  /** Runs fn in a transaction that is always rolled back. */
  async function inTx(fn: () => Promise<void>): Promise<void> {
    await db.query("BEGIN");
    try {
      await fn();
    } finally {
      await db.query("ROLLBACK");
    }
  }

  /** Asserts that `sql` fails with `pred`, keeping the transaction usable. */
  async function rejectsWith(
    sql: string,
    params: unknown[],
    pred: (e: PgError) => boolean,
  ): Promise<void> {
    await db.query("SAVEPOINT expect_error");
    await assert.rejects(db.query(sql, params), pred);
    await db.query("ROLLBACK TO SAVEPOINT expect_error");
  }

  /** Acts as the signed-in client `uid` for the rest of the transaction (until asOwner). */
  async function asUser(uid: string): Promise<void> {
    await db.query("RESET ROLE");
    await db.query(`SELECT set_config('request.jwt.claims', $1, true)`, [
      JSON.stringify({ sub: uid, role: "authenticated" }),
    ]);
    await db.query("SET LOCAL ROLE authenticated");
  }

  async function asOwner(): Promise<void> {
    await db.query("RESET ROLE");
    await db.query(`SELECT set_config('request.jwt.claims', '', true)`);
  }

  /** Creates profiles as the owner; returns their ids in order. */
  async function makeUsers(
    count: number,
    opts: { anonymous?: boolean; names?: string[] } = {},
  ): Promise<string[]> {
    const ids: string[] = [];
    for (let i = 0; i < count; i++) {
      const id = randomUUID();
      await db.query(`INSERT INTO public.profiles (id, display_name, is_anonymous) VALUES ($1, $2, $3)`, [
        id,
        opts.names?.[i] ?? `Player ${1000 + i}`,
        opts.anonymous ?? false,
      ]);
      ids.push(id);
    }
    return ids;
  }

  /** UTC date `offset` days from today, as YYYY-MM-DD (computed by the database). */
  async function utcDate(offset: number): Promise<string> {
    const { rows } = await db.query<{ d: string }>(
      `SELECT to_char((now() AT TIME ZONE 'utc')::date + $1::int, 'YYYY-MM-DD') AS d`,
      [offset],
    );
    return rows[0].d;
  }

  /** Puzzle id for a date, creating the puzzle if the branch has none. */
  async function puzzleFor(date: string): Promise<string> {
    await db.query(
      `INSERT INTO public.puzzles (puzzle_date, grid_size, waypoints, difficulty, par_time_seconds)
       VALUES ($1, 5, '[]'::jsonb, 'easy', 60)
       ON CONFLICT (puzzle_date) DO NOTHING`,
      [date],
    );
    const { rows } = await db.query<{ id: string }>(`SELECT id FROM public.puzzles WHERE puzzle_date = $1`, [date]);
    return rows[0].id;
  }

  async function addAttempt(
    userId: string,
    date: string,
    a: { time?: number; hints?: number; undos?: number } = {},
  ): Promise<void> {
    const puzzleId = await puzzleFor(date);
    await db.query(
      `INSERT INTO public.puzzle_attempts
         (user_id, puzzle_id, puzzle_date, time_seconds, hints_used, undos_used, completed, completed_at, verified)
       VALUES ($1, $2, $3, $4, $5, $6, true, now(), true)`,
      [userId, puzzleId, date, a.time ?? 60, a.hints ?? 0, a.undos ?? 0],
    );
  }

  /** As `adminId`: create a group; then (as the owner) add `members`. Returns the group id. */
  async function makeGroup(adminId: string, members: string[] = []): Promise<string> {
    await asUser(adminId);
    const { rows } = await db.query<{ id: string }>(`SELECT id FROM public.create_group('Puzzle Pals', 'Daily')`);
    await asOwner();
    for (const m of members) {
      await db.query(`INSERT INTO public.group_members (group_id, user_id) VALUES ($1, $2)`, [rows[0].id, m]);
    }
    return rows[0].id;
  }

  async function streakOf(uid: string): Promise<number> {
    const { rows } = await db.query<{ current_streak: number }>(
      `SELECT current_streak FROM public.streaks WHERE user_id = $1`,
      [uid],
    );
    return rows[0]?.current_streak ?? -1;
  }

  // --- groups and leaderboards ----------------------------------------------

  test("create_group, then the daily leaderboard ranks the admin's completed attempt 1", async () => {
    await inTx(async () => {
      const [admin] = await makeUsers(1);
      const today = await utcDate(0);
      const groupId = await makeGroup(admin);
      await addAttempt(admin, today, { time: 42 });

      const group = await db.query<{ admin_id: string; member_count: number; invite_code: string }>(
        `SELECT admin_id, member_count, invite_code FROM public.groups WHERE id = $1`,
        [groupId],
      );
      assert.equal(group.rows[0].admin_id, admin);
      assert.equal(group.rows[0].member_count, 1, "member_count maintained by trigger");
      assert.match(group.rows[0].invite_code, /^[A-Z2-9]{6}$/);

      await asUser(admin);
      const { rows } = await db.query(
        `SELECT rank, user_id, display_name, time_seconds, completed, verified
           FROM public.get_group_daily_leaderboard($1, $2)`,
        [groupId, today],
      );
      assert.deepEqual(rows, [
        { rank: 1, user_id: admin, display_name: "Player 1000", time_seconds: 42, completed: true, verified: true },
      ]);
    });
  });

  test("create_group refuses guests and profane names", async () => {
    await inTx(async () => {
      const [guest] = await makeUsers(1, { anonymous: true });
      const [member] = await makeUsers(1);
      await asUser(guest);
      await rejectsWith(`SELECT public.create_group('Guests Club')`, [], (e: PgError) => e.code === "42501" && e.hint === "ANONYMOUS_USER");
      await asUser(member);
      await rejectsWith(`SELECT public.create_group('sh1t club')`, [], (e: PgError) => e.code === "22023" && e.hint === "PROFANITY");
    });
  });

  test("regenerate_invite_code: new code for the admin, 42501 for a member", async () => {
    await inTx(async () => {
      const [admin, member] = await makeUsers(2);
      const groupId = await makeGroup(admin, [member]);
      const before = await db.query<{ invite_code: string }>(`SELECT invite_code FROM public.groups WHERE id = $1`, [
        groupId,
      ]);

      await asUser(admin);
      const { rows } = await db.query<{ invite_code: string }>(
        `SELECT invite_code FROM public.regenerate_invite_code($1)`,
        [groupId],
      );
      assert.notEqual(rows[0].invite_code, before.rows[0].invite_code);
      assert.match(rows[0].invite_code, /^[A-Z2-9]{6}$/);

      await asUser(member);
      await rejectsWith(`SELECT public.regenerate_invite_code($1)`, [groupId], (e: PgError) => e.code === "42501" && e.hint === "NOT_ADMIN");
    });
  });

  test("group_members triggers: GROUP_FULL, GROUP_INACTIVE and member_count", async () => {
    await inTx(async () => {
      const [admin, a, b] = await makeUsers(3);
      const groupId = await makeGroup(admin, [a]);
      const count = async () =>
        (await db.query<{ n: number }>(`SELECT member_count AS n FROM public.groups WHERE id = $1`, [groupId])).rows[0]
          .n;
      assert.equal(await count(), 2);

      await db.query(`UPDATE public.groups SET max_members = 2 WHERE id = $1`, [groupId]);
      await rejectsWith(`INSERT INTO public.group_members (group_id, user_id) VALUES ($1, $2)`, [groupId, b], (e: PgError) => e.hint === "GROUP_FULL");

      await asUser(a);
      await db.query(`SELECT public.leave_group($1)`, [groupId]);
      await asOwner();
      assert.equal(await count(), 1);

      await db.query(`UPDATE public.groups SET is_active = false WHERE id = $1`, [groupId]);
      await rejectsWith(`INSERT INTO public.group_members (group_id, user_id) VALUES ($1, $2)`, [groupId, b], (e: PgError) => e.hint === "GROUP_INACTIVE");
      await rejectsWith(`INSERT INTO public.group_members (group_id, user_id) VALUES ($1, $2)`, [randomUUID(), b], (e: PgError) => e.hint === "GROUP_NOT_FOUND");
    });
  });

  test("leaderboards: non-members are refused", async () => {
    await inTx(async () => {
      const [admin, outsider] = await makeUsers(2);
      const groupId = await makeGroup(admin);
      await asUser(outsider);
      await rejectsWith(`SELECT * FROM public.get_group_daily_leaderboard($1, $2)`, [groupId, await utcDate(0)], (e: PgError) => e.code === "42501" && e.hint === "NOT_A_MEMBER");
    });
  });

  test("is_blocked_by_me hides a blocked member from both leaderboards", async () => {
    await inTx(async () => {
      const [me, blocked, other] = await makeUsers(3);
      const today = await utcDate(0);
      const groupId = await makeGroup(me, [blocked, other]);
      await addAttempt(me, today, { time: 90 });
      await addAttempt(blocked, today, { time: 10 });
      await addAttempt(other, today, { time: 50 });

      await asUser(me);
      const daily = async () =>
        (
          await db.query<{ rank: number; user_id: string }>(
            `SELECT rank, user_id FROM public.get_group_daily_leaderboard($1, $2)`,
            [groupId, today],
          )
        ).rows;
      const weekly = async () =>
        (
          await db.query<{ user_id: string }>(
            `SELECT user_id FROM public.get_group_weekly_leaderboard($1, date_trunc('week', $2::date)::date)`,
            [groupId, today],
          )
        ).rows.map((r) => r.user_id);

      assert.deepEqual(await daily(), [
        { rank: 1, user_id: blocked },
        { rank: 2, user_id: other },
        { rank: 3, user_id: me },
      ]);
      assert.deepEqual((await weekly()).sort(), [me, blocked, other].sort());

      await asOwner();
      await db.query(`INSERT INTO public.user_blocks (blocker_id, blocked_id) VALUES ($1, $2)`, [me, blocked]);
      await asUser(me);

      assert.deepEqual(await daily(), [
        { rank: 1, user_id: other },
        { rank: 2, user_id: me },
      ]);
      assert.deepEqual((await weekly()).sort(), [me, other].sort());

      const listed = await db.query<{ user_id: string; display_name: string }>(
        `SELECT user_id, display_name FROM public.list_blocked_users()`,
      );
      assert.deepEqual(listed.rows, [{ user_id: blocked, display_name: "Player 1001" }]);

      // The blocked user still sees the blocker.
      await asUser(blocked);
      const theirs = await db.query<{ user_id: string }>(
        `SELECT user_id FROM public.get_group_daily_leaderboard($1, $2)`,
        [groupId, today],
      );
      assert.equal(theirs.rows.length, 3);
    });
  });

  test("RLS: co-members see each other's profiles, outsiders do not", async () => {
    await inTx(async () => {
      const [me, mate, stranger] = await makeUsers(3);
      await makeGroup(me, [mate]);
      await asUser(me);
      const { rows } = await db.query<{ id: string }>(`SELECT id FROM public.profiles`);
      assert.deepEqual(rows.map((r) => r.id).sort(), [me, mate].sort());
      assert.equal(rows.some((r) => r.id === stranger), false);
    });
  });

  test("RLS: group_feed rows of a blocked user are hidden", async () => {
    await inTx(async () => {
      const [me, blocked, other] = await makeUsers(3);
      const today = await utcDate(0);
      const groupId = await makeGroup(me, [blocked, other]);
      for (const u of [me, blocked, other]) {
        await db.query(`INSERT INTO public.group_feed (group_id, user_id, puzzle_date, event) VALUES ($1, $2, $3, 'solved')`, [
          groupId,
          u,
          today,
        ]);
      }
      await db.query(`INSERT INTO public.user_blocks (blocker_id, blocked_id) VALUES ($1, $2)`, [me, blocked]);

      await asUser(me);
      const mine = await db.query<{ user_id: string }>(`SELECT user_id FROM public.group_feed WHERE group_id = $1`, [
        groupId,
      ]);
      assert.deepEqual(mine.rows.map((r) => r.user_id).sort(), [me, other].sort());

      await asUser(other);
      const theirs = await db.query(`SELECT 1 FROM public.group_feed WHERE group_id = $1`, [groupId]);
      assert.equal(theirs.rowCount, 3);
    });
  });

  test("validate_profile_display_name rejects bad names on a client update", async () => {
    await inTx(async () => {
      const [me] = await makeUsers(1);
      await asUser(me);
      await rejectsWith(`UPDATE public.profiles SET display_name = 'x' WHERE id = $1`, [me], (e: PgError) => e.hint === "INVALID_LENGTH");
      const { rows } = await db.query<{ display_name: string }>(
        `UPDATE public.profiles SET display_name = E'  Ada\\u200B  Lovelace ' WHERE id = $1 RETURNING display_name`,
        [me],
      );
      assert.deepEqual(rows, [{ display_name: "Ada Lovelace" }]);
    });
  });

  // --- streaks --------------------------------------------------------------

  test("record_solve on two consecutive dates gives current_streak 2", async () => {
    await inTx(async () => {
      const [me] = await makeUsers(1);
      const yesterday = await utcDate(-1);
      const today = await utcDate(0);

      await addAttempt(me, yesterday);
      const first = await db.query<{ current_streak: number }>(
        `SELECT current_streak FROM public.record_solve($1, $2)`,
        [me, yesterday],
      );
      assert.equal(first.rows[0].current_streak, 1);

      await addAttempt(me, today);
      const second = await db.query<{ current_streak: number; longest_streak: number; last_solve_date: string }>(
        `SELECT current_streak, longest_streak, to_char(last_solve_date, 'YYYY-MM-DD') AS last_solve_date
           FROM public.record_solve($1, $2)`,
        [me, today],
      );
      assert.deepEqual(second.rows, [{ current_streak: 2, longest_streak: 2, last_solve_date: today }]);
    });
  });

  test("recompute_streak counts a freeze as a covered day", async () => {
    await inTx(async () => {
      const [me] = await makeUsers(1);
      await addAttempt(me, await utcDate(-2));
      await db.query(`INSERT INTO public.streak_freezes (user_id, frozen_date) VALUES ($1, $2)`, [
        me,
        await utcDate(-1),
      ]);
      await addAttempt(me, await utcDate(0));
      const { rows } = await db.query<{ current_streak: number }>(
        `SELECT current_streak FROM public.recompute_streak($1)`,
        [me],
      );
      assert.equal(rows[0].current_streak, 3);
    });
  });

  test("apply_streak_freezes spends a freeze for a missed yesterday", async () => {
    await inTx(async () => {
      const [me] = await makeUsers(1);
      await addAttempt(me, await utcDate(-2));
      await db.query(`SELECT public.record_solve($1, $2)`, [me, await utcDate(-2)]);
      await db.query(`SELECT public.apply_streak_freezes()`);
      const { rows } = await db.query<{ current_streak: number; freeze_count: number }>(
        `SELECT current_streak, freeze_count FROM public.streaks WHERE user_id = $1`,
        [me],
      );
      assert.deepEqual(rows, [{ current_streak: 2, freeze_count: 0 }]);
    });
  });

  test("expire_stale_streaks zeroes a stale streak", async () => {
    await inTx(async () => {
      const [me] = await makeUsers(1);
      await db.query(
        `INSERT INTO public.streaks (user_id, current_streak, longest_streak, last_solve_date)
         VALUES ($1, 5, 5, (now() AT TIME ZONE 'utc')::date - 5)`,
        [me],
      );
      const { rows } = await db.query<{ n: number }>(`SELECT public.expire_stale_streaks() AS n`);
      assert.ok(rows[0].n >= 1);
      assert.equal(await streakOf(me), 0);
      const longest = await db.query<{ longest_streak: number }>(
        `SELECT longest_streak FROM public.streaks WHERE user_id = $1`,
        [me],
      );
      assert.equal(longest.rows[0].longest_streak, 5, "longest is kept");
    });
  });

  // --- account lifecycle ----------------------------------------------------

  test("request_account_deletion sets deleted_at; cancel clears it", async () => {
    await inTx(async () => {
      const [me] = await makeUsers(1);
      await asUser(me);
      const req = await db.query<{ id: string; deleted: boolean }>(
        `SELECT id, deleted_at IS NOT NULL AS deleted FROM public.request_account_deletion()`,
      );
      assert.deepEqual(req.rows, [{ id: me, deleted: true }]);
      const cancel = await db.query<{ deleted: boolean }>(
        `SELECT deleted_at IS NOT NULL AS deleted FROM public.cancel_account_deletion()`,
      );
      assert.deepEqual(cancel.rows, [{ deleted: false }]);
    });
  });

  test("purge_deleted_accounts anonymizes past the grace period, returns the id and keeps attempts", async () => {
    await inTx(async () => {
      const [gone, mate, recent] = await makeUsers(3);
      const today = await utcDate(0);
      const groupId = await makeGroup(mate, [gone]);
      await addAttempt(gone, today, { time: 30 });
      await db.query(
        `UPDATE public.profiles
            SET deleted_at = now() - interval '31 days', email = 'gone@example.com',
                email_verified = true, providers = '{google}', notification_enabled = true,
                avatar_url = 'https://example.com/a.png'
          WHERE id = $1`,
        [gone],
      );
      await db.query(`UPDATE public.profiles SET deleted_at = now() - interval '5 days' WHERE id = $1`, [recent]);
      await db.query(`INSERT INTO public.puzzle_sessions (user_id, puzzle_date, nonce) VALUES ($1, $2, 'n')`, [
        gone,
        today,
      ]);

      const purged = await db.query<{ id: string }>(`SELECT id FROM public.purge_deleted_accounts() AS id`);
      const ids = purged.rows.map((r) => r.id);
      assert.ok(ids.includes(gone), "returns the purged id");
      assert.equal(ids.includes(recent), false, "still in its grace period");

      const profile = await db.query(
        `SELECT display_name, avatar_url, email, email_verified, providers, notification_enabled,
                purged_at IS NOT NULL AS purged
           FROM public.profiles WHERE id = $1`,
        [gone],
      );
      assert.deepEqual(profile.rows, [
        {
          display_name: "Deleted User",
          avatar_url: null,
          email: null,
          email_verified: false,
          providers: [],
          notification_enabled: false,
          purged: true,
        },
      ]);
      const attempts = await db.query(`SELECT 1 FROM public.puzzle_attempts WHERE user_id = $1`, [gone]);
      assert.equal(attempts.rowCount, 1, "attempt rows are kept");
      const sessions = await db.query(`SELECT 1 FROM public.puzzle_sessions WHERE user_id = $1`, [gone]);
      assert.equal(sessions.rowCount, 0);
      const membership = await db.query(`SELECT 1 FROM public.group_members WHERE user_id = $1`, [gone]);
      assert.equal(membership.rowCount, 0);
      const remembered = await db.query(`SELECT 1 FROM public.group_purged_members WHERE user_id = $1`, [gone]);
      assert.equal(remembered.rowCount, 1);

      // Former co-members still see the row, as "Deleted User".
      await asUser(mate);
      const board = await db.query<{ user_id: string; display_name: string; avatar_url: string | null }>(
        `SELECT user_id, display_name, avatar_url FROM public.get_group_daily_leaderboard($1, $2)`,
        [groupId, today],
      );
      assert.deepEqual(board.rows, [{ user_id: gone, display_name: "Deleted User", avatar_url: null }]);

      await asOwner();
      const again = await db.query<{ id: string }>(`SELECT id FROM public.purge_deleted_accounts() AS id`);
      assert.equal(
        again.rows.some((r) => r.id === gone),
        false,
        "an already purged profile is not returned again",
      );
    });
  });

  test("purge_inactive_anonymous deletes idle guests and cascades their attempts", async () => {
    await inTx(async () => {
      const [idle, active] = await makeUsers(2, { anonymous: true });
      const [account] = await makeUsers(1);
      await addAttempt(idle, await utcDate(-100));
      await db.query(
        `UPDATE public.profiles SET last_active_at = now() - interval '91 days' WHERE id = ANY($1::uuid[])`,
        [[idle, account]],
      );

      const { rows } = await db.query<{ id: string }>(`SELECT id FROM public.purge_inactive_anonymous() AS id`);
      const ids = rows.map((r) => r.id);
      assert.ok(ids.includes(idle));
      assert.equal(ids.includes(active), false);
      assert.equal(ids.includes(account), false, "accounts are never purged as guests");

      const left = await db.query<{ id: string }>(`SELECT id FROM public.profiles WHERE id = ANY($1::uuid[])`, [
        [idle, active, account],
      ]);
      assert.deepEqual(left.rows.map((r) => r.id).sort(), [active, account].sort());
      const attempts = await db.query(`SELECT 1 FROM public.puzzle_attempts WHERE user_id = $1`, [idle]);
      assert.equal(attempts.rowCount, 0, "attempts cascade with the profile");
    });
  });

  // --- text helpers ---------------------------------------------------------

  test("sanitize_text, contains_profanity and validate_name", async () => {
    await inTx(async () => {
      const [me] = await makeUsers(1);
      await asUser(me);
      const { rows } = await db.query(
        `SELECT public.sanitize_text(E'  a\\u200Bb \\t c  ') AS clean,
                public.contains_profanity('what the fUck') AS rude,
                public.contains_profanity('Scunthorpe United') AS place,
                public.validate_name('  Grid Gang ', 'Group name') AS name`,
      );
      assert.deepEqual(rows, [{ clean: "ab c", rude: true, place: false, name: "Grid Gang" }]);
    });
  });

  // --- privileges, removed functions, seed ----------------------------------

  test("function privileges: client list for authenticated only; service list for nobody", async () => {
    const all = [...CLIENT_FUNCTIONS, ...SERVICE_FUNCTIONS];
    const { rows } = await db.query<{ fn: string; authed: boolean; anon: boolean; pub: boolean }>(
      `SELECT fn,
              has_function_privilege('authenticated', fn, 'EXECUTE') AS authed,
              has_function_privilege('anonymous', fn, 'EXECUTE') AS anon,
              EXISTS (
                SELECT 1 FROM aclexplode(COALESCE((SELECT proacl FROM pg_proc WHERE oid = fn::regprocedure),
                                                  acldefault('f', (SELECT proowner FROM pg_proc WHERE oid = fn::regprocedure)))) a
                 WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE'
              ) AS pub
         FROM unnest($1::text[]) fn`,
      [all],
    );
    const byFn = new Map(rows.map((r) => [r.fn, r]));
    for (const fn of CLIENT_FUNCTIONS) {
      assert.equal(byFn.get(fn)?.authed, true, `authenticated must execute ${fn}`);
    }
    for (const fn of SERVICE_FUNCTIONS) {
      assert.equal(byFn.get(fn)?.authed, false, `authenticated must not execute ${fn}`);
    }
    for (const fn of all) {
      assert.equal(byFn.get(fn)?.anon, false, `anonymous must not execute ${fn}`);
      assert.equal(byFn.get(fn)?.pub, false, `PUBLIC must not execute ${fn}`);
    }
  });

  test("SECURITY DEFINER functions pin an empty search_path", async () => {
    const { rows } = await db.query<{ proname: string }>(
      `SELECT proname FROM pg_proc
        WHERE pronamespace = 'public'::regnamespace AND prosecdef
          AND (proconfig IS NULL OR NOT ('search_path=""' = ANY (proconfig)))`,
    );
    assert.deepEqual(rows, []);
  });

  test("Supabase-only functions are not ported", async () => {
    const { rows } = await db.query<{ proname: string }>(
      `SELECT proname FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = ANY($1::text[])`,
      [REMOVED_FUNCTIONS],
    );
    assert.deepEqual(rows, []);
    const authRefs = await db.query<{ proname: string }>(
      `SELECT proname FROM pg_proc
        WHERE pronamespace IN ('public'::regnamespace, 'app'::regnamespace)
          AND prosrc ~ '(auth\\.(uid|role|users|identities|sessions|refresh_tokens|mfa_factors)|vault\\.|net\\.http|cron\\.)'
          AND proname <> 'uid'`,
    );
    assert.deepEqual(authRefs.rows, []);
  });

  test("triggers from 0002 are installed", async () => {
    const { rows } = await db.query<{ tgname: string; tbl: string }>(
      `SELECT tgname, tgrelid::regclass::text AS tbl FROM pg_trigger
        WHERE NOT tgisinternal AND tgname IN
          ('validate_profile_display_name', 'group_members_before_insert', 'group_members_after_change')
        ORDER BY tgname`,
    );
    assert.deepEqual(rows, [
      { tgname: "group_members_after_change", tbl: "group_members" },
      { tgname: "group_members_before_insert", tbl: "group_members" },
      { tgname: "validate_profile_display_name", tbl: "profiles" },
    ]);
  });

  test("seed: app_config defaults and banned_words", async () => {
    const { rows } = await db.query<{ key: string; value: unknown }>(
      `SELECT key, value FROM public.app_config
        WHERE key IN ('min_supported_version', 'latest_version', 'maintenance_mode', 'store_urls')
        ORDER BY key`,
    );
    assert.deepEqual(rows, [
      { key: "latest_version", value: "1.1.0" },
      { key: "maintenance_mode", value: false },
      { key: "min_supported_version", value: "1.1.0" },
      {
        key: "store_urls",
        value: {
          ios: "https://apps.apple.com/app/id6810895361",
          android: "https://play.google.com/store/apps/details?id=com.icos.game",
        },
      },
    ]);
    const words = await db.query<{ n: number }>(`SELECT count(*)::int AS n FROM public.banned_words`);
    assert.equal(words.rows[0].n, 66);
  });
});
