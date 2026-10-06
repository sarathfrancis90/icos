-- RLS smoke test for the Icos schema. LOCAL STACKS ONLY (inserts into auth.users).
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/rls_smoke.sql
--   (or: docker exec -i supabase_db_icos psql -U postgres -d postgres -v ON_ERROR_STOP=1 < supabase/tests/rls_smoke.sql)
--
-- Every assertion is a DO block that RAISEs on failure; the whole script runs in
-- one transaction and is rolled back at the end, so it leaves no data behind.

\set ON_ERROR_STOP on
\set QUIET on
\o /dev/null
BEGIN;

-- ---------------------------------------------------------------------------
-- Fixtures: two non-anonymous users (alice, bob), one anonymous (carol),
-- a puzzle for today with a solution, and attempts for alice.
-- ---------------------------------------------------------------------------
INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
                        raw_app_meta_data, raw_user_meta_data, is_anonymous, created_at, updated_at)
VALUES
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'alice@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{}', false, now(), now()),
  ('22222222-2222-2222-2222-222222222222', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'bob@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{}', false, now(), now()),
  ('33333333-3333-3333-3333-333333333333', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   NULL, '', NULL, '{}', '{}', true, now(), now());

UPDATE public.profiles SET display_name = 'Alice' WHERE id = '11111111-1111-1111-1111-111111111111';
UPDATE public.profiles SET display_name = 'Bob'   WHERE id = '22222222-2222-2222-2222-222222222222';

INSERT INTO public.puzzles (id, puzzle_date, grid_size, waypoints, walls, difficulty, par_time_seconds)
VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', current_date, 5,
        '[{"order":1,"row":0,"col":0},{"order":2,"row":4,"col":4}]', '[]', 'easy', 50);
INSERT INTO public.puzzle_solutions (puzzle_id, path)
VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '[[0,0],[4,4]]');

INSERT INTO public.puzzle_attempts (user_id, puzzle_id, puzzle_date, time_seconds, hints_used, undos_used, completed, path, completed_at)
VALUES ('11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', current_date, 42, 0, 1, true, '[[0,0]]', now());

-- ---------------------------------------------------------------------------
-- Helper: impersonate a user the way PostgREST does.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pg_temp.impersonate(p_uid text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated', 'aud', 'authenticated')::text, true);
  PERFORM set_config('request.jwt.claim.sub', p_uid, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.reset_role()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('role', 'postgres', true);
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', '', true);
END;
$$;

-- ===========================================================================
-- 1. Authenticated user cannot read puzzle_solutions (no policy + no grant).
-- ===========================================================================
SELECT pg_temp.impersonate('11111111-1111-1111-1111-111111111111');
DO $$
DECLARE n int;
BEGIN
  BEGIN
    SELECT count(*) INTO n FROM public.puzzle_solutions;
    IF n <> 0 THEN RAISE EXCEPTION 'FAIL 1: user can read % puzzle_solutions rows', n; END IF;
  EXCEPTION WHEN insufficient_privilege THEN
    NULL; -- also acceptable: table-level privilege revoked
  END;
  RAISE NOTICE 'PASS 1: puzzle_solutions hidden from users';
END $$;

-- ===========================================================================
-- 2. User cannot INSERT puzzle_attempts.
-- ===========================================================================
DO $$
BEGIN
  BEGIN
    INSERT INTO public.puzzle_attempts (user_id, puzzle_id, puzzle_date, time_seconds, completed, path)
    VALUES ('11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', current_date - 1, 10, true, '[]');
    RAISE EXCEPTION 'FAIL 2: user inserted into puzzle_attempts';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'PASS 2: puzzle_attempts INSERT denied';
  END;
END $$;

-- ===========================================================================
-- 3. User cannot INSERT streaks.
-- ===========================================================================
DO $$
BEGIN
  BEGIN
    INSERT INTO public.streaks (user_id, current_streak) VALUES ('11111111-1111-1111-1111-111111111111', 99);
    RAISE EXCEPTION 'FAIL 3: user inserted into streaks';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'PASS 3: streaks INSERT denied';
  END;
END $$;

-- ===========================================================================
-- 4. User can SELECT puzzles (public) and does not see a solution column.
-- ===========================================================================
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.puzzles WHERE puzzle_date = current_date;
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL 4: expected 1 puzzle, got %', n; END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema = 'public' AND table_name = 'puzzles' AND column_name = 'solution_hash') THEN
    RAISE EXCEPTION 'FAIL 4: puzzles.solution_hash still exists';
  END IF;
  RAISE NOTICE 'PASS 4: puzzles readable, no solution column';
END $$;

-- ===========================================================================
-- 5. Alice can only see her own attempts (Bob sees none of hers).
-- ===========================================================================
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.puzzle_attempts;
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL 5a: alice expected 1 own attempt, got %', n; END IF;
END $$;
SELECT pg_temp.impersonate('22222222-2222-2222-2222-222222222222');
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.puzzle_attempts;
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL 5b: bob can see % attempts of others', n; END IF;
  RAISE NOTICE 'PASS 5: attempts are private';
END $$;

-- ===========================================================================
-- 6. Before any shared group: Bob cannot read Alice's profile.
-- ===========================================================================
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.profiles WHERE id = '11111111-1111-1111-1111-111111111111';
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL 6: non-co-member can read profile'; END IF;
  RAISE NOTICE 'PASS 6: profile hidden from strangers';
END $$;

-- ===========================================================================
-- 7. create_group works, member_count == 1, creator is admin member.
--    Anonymous user is rejected; profanity is rejected; direct INSERT is denied.
-- ===========================================================================
SELECT pg_temp.impersonate('11111111-1111-1111-1111-111111111111');
DO $$
DECLARE g public.groups; n int;
BEGIN
  g := public.create_group('  Alice''s   Crew ', 'test group');
  IF g.member_count <> 1 THEN RAISE EXCEPTION 'FAIL 7a: member_count = %', g.member_count; END IF;
  IF g.name <> 'Alice''s Crew' THEN RAISE EXCEPTION 'FAIL 7b: name not sanitized: %', g.name; END IF;
  IF length(g.invite_code) <> 6 THEN RAISE EXCEPTION 'FAIL 7c: invite code %', g.invite_code; END IF;
  SELECT count(*) INTO n FROM public.group_members WHERE group_id = g.id AND user_id = auth.uid() AND role = 'admin';
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL 7d: creator not admin member'; END IF;
  PERFORM set_config('test.group_id', g.id::text, true);
  PERFORM set_config('test.invite_code', g.invite_code, true);

  BEGIN
    PERFORM public.create_group('total shit', '');
    RAISE EXCEPTION 'FAIL 7e: profanity accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;

  BEGIN
    INSERT INTO public.groups (name, invite_code, admin_id) VALUES ('direct', 'ZZZZZZ', auth.uid());
    RAISE EXCEPTION 'FAIL 7f: direct INSERT into groups allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  RAISE NOTICE 'PASS 7: create_group OK (member_count=1, sanitized, profanity/direct insert blocked)';
END $$;

SELECT pg_temp.impersonate('33333333-3333-3333-3333-333333333333');
DO $$
BEGIN
  BEGIN
    PERFORM public.create_group('Guest Group', '');
    RAISE EXCEPTION 'FAIL 7g: anonymous user created a group';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  RAISE NOTICE 'PASS 7g: anonymous create_group rejected';
END $$;

-- ===========================================================================
-- 8. Non-member cannot read the group (even by invite code), leaderboard RPC rejects.
-- ===========================================================================
SELECT pg_temp.impersonate('22222222-2222-2222-2222-222222222222');
DO $$
DECLARE n int; gid uuid := current_setting('test.group_id')::uuid;
BEGIN
  SELECT count(*) INTO n FROM public.groups WHERE invite_code = current_setting('test.invite_code');
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL 8a: non-member can read group by invite code'; END IF;
  SELECT count(*) INTO n FROM public.group_members WHERE group_id = gid;
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL 8b: non-member can read group_members'; END IF;

  BEGIN
    PERFORM * FROM public.get_group_daily_leaderboard(gid, current_date);
    RAISE EXCEPTION 'FAIL 8c: leaderboard served to non-member';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM * FROM public.get_group_weekly_leaderboard(gid, current_date - 3);
    RAISE EXCEPTION 'FAIL 8d: weekly leaderboard served to non-member';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;

  BEGIN
    INSERT INTO public.group_members (group_id, user_id) VALUES (gid, auth.uid());
    RAISE EXCEPTION 'FAIL 8e: direct self-join into group_members allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  RAISE NOTICE 'PASS 8: non-member blocked from group, members, leaderboards, direct join';
END $$;

-- ===========================================================================
-- 9. Service-role join (what join-group does) -> member_count == 2 via trigger;
--    co-member can now read Alice's profile and the leaderboard; streak visible.
-- ===========================================================================
SELECT pg_temp.reset_role();
INSERT INTO public.group_members (group_id, user_id, role)
VALUES (current_setting('test.group_id')::uuid, '22222222-2222-2222-2222-222222222222', 'member');
DO $$
DECLARE n int;
BEGIN
  SELECT member_count INTO n FROM public.groups WHERE id = current_setting('test.group_id')::uuid;
  IF n <> 2 THEN RAISE EXCEPTION 'FAIL 9a: member_count after join = %', n; END IF;
END $$;

SELECT pg_temp.impersonate('22222222-2222-2222-2222-222222222222');
DO $$
DECLARE n int; r record; gid uuid := current_setting('test.group_id')::uuid;
BEGIN
  SELECT count(*) INTO n FROM public.profiles WHERE id = '11111111-1111-1111-1111-111111111111';
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL 9b: co-member cannot read profile'; END IF;

  SELECT count(*) INTO n FROM public.groups WHERE id = gid;
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL 9c: member cannot read group'; END IF;

  SELECT count(*) INTO n FROM public.group_members WHERE group_id = gid;
  IF n <> 2 THEN RAISE EXCEPTION 'FAIL 9d: member sees % member rows', n; END IF;

  SELECT * INTO r FROM public.get_group_daily_leaderboard(gid, current_date) LIMIT 1;
  IF r.user_id IS DISTINCT FROM '11111111-1111-1111-1111-111111111111' OR r.rank <> 1 THEN
    RAISE EXCEPTION 'FAIL 9e: leaderboard row %', r;
  END IF;
  IF r.display_name <> 'Alice' THEN RAISE EXCEPTION 'FAIL 9f: display_name %', r.display_name; END IF;

  SELECT count(*) INTO n FROM public.get_group_weekly_leaderboard(gid, date_trunc('week', current_date)::date);
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL 9g: weekly leaderboard rows = %', n; END IF;

  -- attempts remain private even for co-members
  SELECT count(*) INTO n FROM public.puzzle_attempts;
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL 9h: co-member can read raw attempts'; END IF;

  RAISE NOTICE 'PASS 9: co-member visibility + leaderboards OK';
END $$;

-- ===========================================================================
-- 9B. User blocking: hides the blocked user's leaderboard rows and feed
--     entries from the blocker only; self-block rejected; repeat block is a
--     no-op (one report); unblock restores; user_blocks is private.
--     Fixtures added here are removed at the end of the section.
-- ===========================================================================
SELECT pg_temp.reset_role();
INSERT INTO public.puzzle_attempts (user_id, puzzle_id, puzzle_date, time_seconds, hints_used, undos_used, completed, path, completed_at)
VALUES ('22222222-2222-2222-2222-222222222222', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', current_date, 30, 0, 0, true, '[[0,0]]', now());
INSERT INTO public.group_feed (group_id, user_id, puzzle_date, event)
VALUES (current_setting('test.group_id')::uuid, '11111111-1111-1111-1111-111111111111', current_date, 'solved'),
       (current_setting('test.group_id')::uuid, '22222222-2222-2222-2222-222222222222', current_date, 'solved');

SELECT pg_temp.impersonate('11111111-1111-1111-1111-111111111111');
DO $$
DECLARE n int; r record; gid uuid := current_setting('test.group_id')::uuid;
BEGIN
  -- Before blocking: bob (30s) outranks alice (42s) and both feed rows are visible.
  SELECT rank INTO n FROM public.get_group_daily_leaderboard(gid, current_date)
   WHERE user_id = '11111111-1111-1111-1111-111111111111';
  IF n <> 2 THEN RAISE EXCEPTION 'FAIL 9B-a: alice rank before block = %', n; END IF;
  SELECT count(*) INTO n FROM public.group_feed WHERE group_id = gid;
  IF n <> 2 THEN RAISE EXCEPTION 'FAIL 9B-b: alice sees % feed rows before block', n; END IF;

  BEGIN
    PERFORM public.block_user(auth.uid());
    RAISE EXCEPTION 'FAIL 9B-c: self-block accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
  BEGIN
    PERFORM public.block_user(NULL);
    RAISE EXCEPTION 'FAIL 9B-d: NULL block accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
  BEGIN
    PERFORM public.block_user('99999999-9999-9999-9999-999999999999');
    RAISE EXCEPTION 'FAIL 9B-e: block of unknown user accepted';
  EXCEPTION WHEN no_data_found THEN NULL;
  END;

  PERFORM public.block_user('22222222-2222-2222-2222-222222222222');
  PERFORM public.block_user('22222222-2222-2222-2222-222222222222');   -- idempotent

  SELECT count(*) INTO n FROM public.user_blocks;
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL 9B-f: % block rows after double block', n; END IF;
  SELECT count(*) INTO n FROM public.reports
   WHERE reporter_id = auth.uid() AND reported_user_id = '22222222-2222-2222-2222-222222222222'
     AND reason = 'blocked_by_user';
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL 9B-g: % block reports (expected exactly 1)', n; END IF;

  -- Bob is gone from alice's leaderboards and feed; ranks are recomputed.
  SELECT count(*) INTO n FROM public.get_group_daily_leaderboard(gid, current_date)
   WHERE user_id = '22222222-2222-2222-2222-222222222222';
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL 9B-h: blocked user still on daily leaderboard'; END IF;
  SELECT rank INTO n FROM public.get_group_daily_leaderboard(gid, current_date)
   WHERE user_id = '11111111-1111-1111-1111-111111111111';
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL 9B-i: alice rank after block = %', n; END IF;
  SELECT count(*) INTO n FROM public.get_group_weekly_leaderboard(gid, date_trunc('week', current_date)::date)
   WHERE user_id = '22222222-2222-2222-2222-222222222222';
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL 9B-j: blocked user still on weekly leaderboard'; END IF;
  SELECT count(*) INTO n FROM public.group_feed WHERE group_id = gid AND user_id = '22222222-2222-2222-2222-222222222222';
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL 9B-k: blocked user still in feed'; END IF;
  SELECT count(*) INTO n FROM public.group_feed WHERE group_id = gid AND user_id = auth.uid();
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL 9B-l: own feed row hidden'; END IF;

  -- The member row stays so an admin can still remove the user.
  SELECT count(*) INTO n FROM public.group_members WHERE group_id = gid;
  IF n <> 2 THEN RAISE EXCEPTION 'FAIL 9B-m: member list shows % rows', n; END IF;

  SELECT * INTO r FROM public.list_blocked_users();
  IF r.user_id IS DISTINCT FROM '22222222-2222-2222-2222-222222222222' OR r.display_name <> 'Bob' THEN
    RAISE EXCEPTION 'FAIL 9B-n: list_blocked_users row %', r;
  END IF;

  -- Direct writes are denied (RPC only).
  BEGIN
    INSERT INTO public.user_blocks (blocker_id, blocked_id)
    VALUES (auth.uid(), '33333333-3333-3333-3333-333333333333');
    RAISE EXCEPTION 'FAIL 9B-o: direct INSERT into user_blocks allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  RAISE NOTICE 'PASS 9B-1: block hides bob from alice; self/null/unknown rejected; repeat block is a no-op';
END $$;

-- The blocked user is not affected: bob still sees alice (and himself).
SELECT pg_temp.impersonate('22222222-2222-2222-2222-222222222222');
DO $$
DECLARE n int; gid uuid := current_setting('test.group_id')::uuid;
BEGIN
  SELECT count(*) INTO n FROM public.get_group_daily_leaderboard(gid, current_date);
  IF n <> 2 THEN RAISE EXCEPTION 'FAIL 9B-p: bob sees % leaderboard rows', n; END IF;
  SELECT count(*) INTO n FROM public.group_feed WHERE group_id = gid;
  IF n <> 2 THEN RAISE EXCEPTION 'FAIL 9B-q: bob sees % feed rows', n; END IF;
  SELECT count(*) INTO n FROM public.user_blocks;
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL 9B-r: bob can read alice''s blocks'; END IF;
  RAISE NOTICE 'PASS 9B-2: blocked user still sees the blocker; blocks are private from bob';
END $$;

-- Carol (unrelated) cannot read alice's blocks.
SELECT pg_temp.impersonate('33333333-3333-3333-3333-333333333333');
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.user_blocks;
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL 9B-s: carol sees % user_blocks rows', n; END IF;
  RAISE NOTICE 'PASS 9B-3: user_blocks private to the blocker';
END $$;

-- Unblock restores visibility; unblocking again is a no-op.
SELECT pg_temp.impersonate('11111111-1111-1111-1111-111111111111');
DO $$
DECLARE n int; gid uuid := current_setting('test.group_id')::uuid;
BEGIN
  PERFORM public.unblock_user('22222222-2222-2222-2222-222222222222');
  PERFORM public.unblock_user('22222222-2222-2222-2222-222222222222');
  SELECT count(*) INTO n FROM public.get_group_daily_leaderboard(gid, current_date);
  IF n <> 2 THEN RAISE EXCEPTION 'FAIL 9B-t: % leaderboard rows after unblock', n; END IF;
  SELECT count(*) INTO n FROM public.group_feed WHERE group_id = gid;
  IF n <> 2 THEN RAISE EXCEPTION 'FAIL 9B-u: % feed rows after unblock', n; END IF;
  SELECT count(*) INTO n FROM public.list_blocked_users();
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL 9B-v: blocked list not empty after unblock'; END IF;
  RAISE NOTICE 'PASS 9B-4: unblock restores visibility';
END $$;

-- block -> unblock -> block again still leaves exactly one notice report.
DO $$
DECLARE n int;
BEGIN
  PERFORM public.block_user('22222222-2222-2222-2222-222222222222');
  PERFORM public.unblock_user('22222222-2222-2222-2222-222222222222');
  PERFORM public.block_user('22222222-2222-2222-2222-222222222222');
  SELECT count(*) INTO n FROM public.reports
   WHERE reporter_id = auth.uid() AND reported_user_id = '22222222-2222-2222-2222-222222222222'
     AND reason = 'blocked_by_user';
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL 9B-w: % block reports after block/unblock/block', n; END IF;
  PERFORM public.unblock_user('22222222-2222-2222-2222-222222222222');
  RAISE NOTICE 'PASS 9B-5: repeat block/unblock cannot file extra reports';
END $$;

-- Remove the section's fixtures so later sections see the original state.
SELECT pg_temp.reset_role();
DELETE FROM public.group_feed WHERE group_id = current_setting('test.group_id')::uuid;
DELETE FROM public.reports WHERE reason = 'blocked_by_user';
DELETE FROM public.puzzle_attempts
 WHERE user_id = '22222222-2222-2222-2222-222222222222' AND puzzle_date = current_date;

-- ===========================================================================
-- 10. Streak machinery: record_solve, recompute, freezes.
-- ===========================================================================
SELECT pg_temp.reset_role();
DO $$
DECLARE s public.streaks; n int;
BEGIN
  -- Alice solved today (fixture). Add yesterday + day-before as live solves.
  INSERT INTO public.puzzle_attempts (user_id, puzzle_id, puzzle_date, time_seconds, completed, path, completed_at)
  VALUES ('11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', current_date - 1, 30, true, '[]', now() - interval '1 day'),
         ('11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', current_date - 2, 30, true, '[]', now() - interval '2 days');
  s := public.record_solve('11111111-1111-1111-1111-111111111111', current_date);
  IF s.current_streak <> 3 OR s.longest_streak <> 3 THEN
    RAISE EXCEPTION 'FAIL 10a: streak = %/%', s.current_streak, s.longest_streak;
  END IF;

  -- Archive solve must not count.
  INSERT INTO public.puzzle_attempts (user_id, puzzle_id, puzzle_date, time_seconds, completed, is_archive, path, completed_at)
  VALUES ('11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', current_date - 3, 30, true, true, '[]', now());
  s := public.recompute_streak('11111111-1111-1111-1111-111111111111');
  IF s.current_streak <> 3 THEN RAISE EXCEPTION 'FAIL 10b: archive counted (streak=%)', s.current_streak; END IF;

  -- Gap at day-4 bridged by a freeze -> 5-day streak with day-5 solve.
  INSERT INTO public.puzzle_attempts (user_id, puzzle_id, puzzle_date, time_seconds, completed, path, completed_at)
  VALUES ('11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', current_date - 5, 30, true, '[]', now());
  s := public.recompute_streak('11111111-1111-1111-1111-111111111111');
  IF s.current_streak <> 3 OR s.longest_streak <> 3 THEN RAISE EXCEPTION 'FAIL 10c: gap not respected (%/%)', s.current_streak, s.longest_streak; END IF;
  INSERT INTO public.streak_freezes (user_id, frozen_date) VALUES ('11111111-1111-1111-1111-111111111111', current_date - 4);
  INSERT INTO public.streak_freezes (user_id, frozen_date) VALUES ('11111111-1111-1111-1111-111111111111', current_date - 3);
  s := public.recompute_streak('11111111-1111-1111-1111-111111111111');
  IF s.current_streak <> 6 OR s.longest_streak <> 6 THEN RAISE EXCEPTION 'FAIL 10d: freeze not bridging (%/%)', s.current_streak, s.longest_streak; END IF;

  -- Bob: solved day-before-yesterday only, has 1 freeze -> apply_streak_freezes covers yesterday.
  INSERT INTO public.puzzle_attempts (user_id, puzzle_id, puzzle_date, time_seconds, completed, path, completed_at)
  VALUES ('22222222-2222-2222-2222-222222222222', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', current_date - 2, 30, true, '[]', now());
  PERFORM public.record_solve('22222222-2222-2222-2222-222222222222', current_date - 2);
  n := public.apply_streak_freezes();
  IF n < 1 THEN RAISE EXCEPTION 'FAIL 10e: apply_streak_freezes applied %', n; END IF;
  SELECT * INTO s FROM public.streaks WHERE user_id = '22222222-2222-2222-2222-222222222222';
  IF s.current_streak <> 2 OR s.freeze_count <> 0 THEN
    RAISE EXCEPTION 'FAIL 10f: bob streak=% freeze_count=%', s.current_streak, s.freeze_count;
  END IF;
  n := public.apply_streak_freezes();   -- idempotent: nothing left to apply
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL 10g: second apply did %', n; END IF;

  n := public.reset_weekly_freezes();
  SELECT * INTO s FROM public.streaks WHERE user_id = '22222222-2222-2222-2222-222222222222';
  IF s.freeze_count <> 1 THEN RAISE EXCEPTION 'FAIL 10h: reset_weekly_freezes'; END IF;
  RAISE NOTICE 'PASS 10: streak recompute / freezes / weekly reset OK';
END $$;

-- ===========================================================================
-- 11. leave_group decrements; admin leaving transfers; last member deactivates.
-- ===========================================================================
SELECT pg_temp.impersonate('11111111-1111-1111-1111-111111111111');
DO $$
DECLARE g public.groups; gid uuid := current_setting('test.group_id')::uuid;
BEGIN
  PERFORM public.leave_group(gid);   -- admin leaves -> bob becomes admin
  PERFORM pg_temp.reset_role();
  SELECT * INTO g FROM public.groups WHERE id = gid;
  IF g.member_count <> 1 THEN RAISE EXCEPTION 'FAIL 11a: member_count after leave = %', g.member_count; END IF;
  IF g.admin_id <> '22222222-2222-2222-2222-222222222222' THEN RAISE EXCEPTION 'FAIL 11b: admin not transferred'; END IF;
  IF NOT g.is_active THEN RAISE EXCEPTION 'FAIL 11c: group deactivated too early'; END IF;
  RAISE NOTICE 'PASS 11a: leave_group decremented + transferred admin';
END $$;

SELECT pg_temp.impersonate('22222222-2222-2222-2222-222222222222');
DO $$
DECLARE g public.groups; gid uuid := current_setting('test.group_id')::uuid;
BEGIN
  PERFORM public.leave_group(gid);   -- last member leaves -> deactivated
  PERFORM pg_temp.reset_role();
  SELECT * INTO g FROM public.groups WHERE id = gid;
  IF g.member_count <> 0 OR g.is_active THEN
    RAISE EXCEPTION 'FAIL 11d: after last leave member_count=% active=%', g.member_count, g.is_active;
  END IF;
  RAISE NOTICE 'PASS 11b: last member leaving deactivates group';
END $$;

-- ===========================================================================
-- 12. Capacity cap enforced by trigger (max_members shrunk to 1 for the test).
-- ===========================================================================
SELECT pg_temp.reset_role();
DO $$
DECLARE gid uuid;
BEGIN
  INSERT INTO public.groups (name, invite_code, admin_id, member_count, max_members)
  VALUES ('Cap', 'CAPCAP', '11111111-1111-1111-1111-111111111111', 0, 1) RETURNING id INTO gid;
  INSERT INTO public.group_members (group_id, user_id, role) VALUES (gid, '11111111-1111-1111-1111-111111111111', 'admin');
  BEGIN
    INSERT INTO public.group_members (group_id, user_id) VALUES (gid, '22222222-2222-2222-2222-222222222222');
    RAISE EXCEPTION 'FAIL 12: cap not enforced';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  RAISE NOTICE 'PASS 12: member cap enforced by trigger';
END $$;

-- ===========================================================================
-- 13. Account deletion RPCs + protected columns + purge anonymization.
-- ===========================================================================
SELECT pg_temp.impersonate('11111111-1111-1111-1111-111111111111');
DO $$
DECLARE p public.profiles;
BEGIN
  UPDATE public.profiles SET is_banned = true, deleted_at = now() WHERE id = auth.uid();
  SELECT * INTO p FROM public.profiles WHERE id = auth.uid();
  IF p.is_banned OR p.deleted_at IS NOT NULL THEN RAISE EXCEPTION 'FAIL 13a: protected columns writable'; END IF;

  p := public.request_account_deletion();
  IF p.deleted_at IS NULL THEN RAISE EXCEPTION 'FAIL 13b: request_account_deletion'; END IF;
  p := public.cancel_account_deletion();
  IF p.deleted_at IS NOT NULL THEN RAISE EXCEPTION 'FAIL 13c: cancel_account_deletion'; END IF;
  p := public.request_account_deletion();
  RAISE NOTICE 'PASS 13a: deletion request/cancel + protected columns OK';
END $$;

SELECT pg_temp.reset_role();
DO $$
DECLARE n int; p public.profiles; u auth.users;
BEGIN
  UPDATE public.profiles SET deleted_at = now() - interval '31 days' WHERE id = '11111111-1111-1111-1111-111111111111';
  n := public.purge_deleted_accounts();
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL 13d: purged %', n; END IF;
  SELECT * INTO p FROM public.profiles WHERE id = '11111111-1111-1111-1111-111111111111';
  IF p.display_name <> 'Deleted User' OR p.purged_at IS NULL THEN RAISE EXCEPTION 'FAIL 13e: not anonymized'; END IF;
  SELECT * INTO u FROM auth.users WHERE id = '11111111-1111-1111-1111-111111111111';
  IF u.email IS NOT NULL OR u.encrypted_password IS NOT NULL THEN RAISE EXCEPTION 'FAIL 13f: auth not scrubbed'; END IF;
  SELECT count(*) INTO n FROM public.puzzle_attempts WHERE user_id = '11111111-1111-1111-1111-111111111111';
  IF n = 0 THEN RAISE EXCEPTION 'FAIL 13g: attempts removed instead of anonymized'; END IF;
  SELECT count(*) INTO n FROM public.group_members WHERE user_id = '11111111-1111-1111-1111-111111111111';
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL 13h: memberships remain'; END IF;
  RAISE NOTICE 'PASS 13b: purge_deleted_accounts anonymized user';
END $$;

-- ===========================================================================
-- 14. Anonymous purge deletes idle guests only.
-- ===========================================================================
DO $$
DECLARE n int;
BEGIN
  n := public.purge_inactive_anonymous();
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL 14a: active guest purged'; END IF;
  UPDATE public.profiles SET last_active_at = now() - interval '91 days' WHERE id = '33333333-3333-3333-3333-333333333333';
  n := public.purge_inactive_anonymous();
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL 14b: idle guest not purged (%)', n; END IF;
  SELECT count(*) INTO n FROM auth.users WHERE id = '33333333-3333-3333-3333-333333333333';
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL 14c: auth.users row remains'; END IF;
  RAISE NOTICE 'PASS 14: purge_inactive_anonymous OK';
END $$;

-- ===========================================================================
-- 16. provider_display_name: Apple relay addresses never become a name.
-- ===========================================================================
DO $$
DECLARE v text;
BEGIN
  v := public.provider_display_name('{}'::jsonb, 'k3x9q2@privaterelay.appleid.com');
  IF v IS NOT NULL THEN RAISE EXCEPTION 'FAIL 16a: relay email gave name %', v; END IF;
  v := public.provider_display_name('{}'::jsonb, 'k3x9q2@PrivateRelay.AppleID.com');
  IF v IS NOT NULL THEN RAISE EXCEPTION 'FAIL 16b: relay email (mixed case) gave name %', v; END IF;
  v := public.provider_display_name('{"full_name":"Ada Lovelace"}'::jsonb, 'k3x9q2@privaterelay.appleid.com');
  IF v IS DISTINCT FROM 'Ada Lovelace' THEN RAISE EXCEPTION 'FAIL 16c: relay + full_name gave %', v; END IF;
  v := public.provider_display_name('{}'::jsonb, 'ada.lovelace@example.com');
  IF v IS DISTINCT FROM 'Ada Lovelace' THEN RAISE EXCEPTION 'FAIL 16d: normal email gave %', v; END IF;
  RAISE NOTICE 'PASS 16: provider_display_name relay handling OK';
END $$;

-- ===========================================================================
-- 15. app_config is readable by anon; service-only tables are not.
-- ===========================================================================
SELECT set_config('role', 'anon', true);
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.app_config;
  IF n < 4 THEN RAISE EXCEPTION 'FAIL 15a: app_config rows visible to anon = %', n; END IF;
  BEGIN
    SELECT count(*) INTO n FROM public.puzzle_sessions;
    IF n <> 0 THEN RAISE EXCEPTION 'FAIL 15b: anon reads puzzle_sessions'; END IF;
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    SELECT count(*) INTO n FROM public.submission_log;
    IF n <> 0 THEN RAISE EXCEPTION 'FAIL 15c: anon reads submission_log'; END IF;
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    SELECT count(*) INTO n FROM public.banned_words;
    IF n <> 0 THEN RAISE EXCEPTION 'FAIL 15d: anon reads banned_words'; END IF;
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  RAISE NOTICE 'PASS 15: app_config public; internal tables hidden';
END $$;

SELECT pg_temp.reset_role();
ROLLBACK;
\o
\echo RLS smoke test finished: all assertions passed.
