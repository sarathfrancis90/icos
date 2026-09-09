-- Production hardening (3/9): streaks are derived state, never client-written.
--
-- * Drop the client INSERT policy on streaks (only record_solve/recompute write).
-- * New streak_freezes(user_id, frozen_date): one row per day covered by a freeze.
-- * recompute_streak(uid): covered dates = completed non-archive attempts ∪ freezes;
--   current streak is alive iff the latest covered date >= today - 1 (UTC);
--   longest streak = longest run of consecutive covered dates.
-- * record_solve(uid, date): called by submit-score; returns the streak row.
-- * apply_streak_freezes(): daily 00:05 UTC cron — spends a freeze for users who
--   missed yesterday but had an alive streak the day before.
-- * reset_weekly_freezes(): Monday 00:00 UTC cron — everyone gets 1 freeze.

DROP POLICY IF EXISTS "Users can insert their own streak" ON public.streaks;
DROP POLICY IF EXISTS "Service role can manage streaks" ON public.streaks;
DROP POLICY IF EXISTS "Users can view their own streak" ON public.streaks;
CREATE POLICY "Users can view their own streak"
  ON public.streaks FOR SELECT
  TO authenticated
  USING ((select auth.uid()) = user_id);

CREATE TABLE public.streak_freezes (
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  frozen_date DATE NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, frozen_date)
);
CREATE INDEX idx_streak_freezes_frozen_date ON public.streak_freezes (frozen_date);

ALTER TABLE public.streak_freezes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view their own freezes"
  ON public.streak_freezes FOR SELECT
  TO authenticated
  USING ((select auth.uid()) = user_id);

-- ---------------------------------------------------------------------------
-- recompute_streak(uid) -> streaks
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.recompute_streak(p_user_id UUID)
RETURNS public.streaks
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_today          DATE := (now() AT TIME ZONE 'utc')::date;
  v_current        INTEGER := 0;
  v_longest        INTEGER := 0;
  v_last_covered   DATE;
  v_last_solve     DATE;
  v_row            public.streaks;
BEGIN
  WITH covered AS (
    SELECT DISTINCT pa.puzzle_date AS d
    FROM public.puzzle_attempts pa
    WHERE pa.user_id = p_user_id AND pa.completed AND NOT pa.is_archive
    UNION
    SELECT sf.frozen_date
    FROM public.streak_freezes sf
    WHERE sf.user_id = p_user_id
  ),
  numbered AS (
    SELECT d, d - (row_number() OVER (ORDER BY d))::int AS grp
    FROM covered
  ),
  islands AS (
    SELECT max(d) AS end_d, count(*)::int AS len
    FROM numbered
    GROUP BY grp
  )
  SELECT
    COALESCE(max(len), 0),
    COALESCE((SELECT len FROM islands i WHERE i.end_d = (SELECT max(end_d) FROM islands)), 0),
    (SELECT max(end_d) FROM islands)
  INTO v_longest, v_current, v_last_covered
  FROM islands;

  -- A streak is only "current" if it reaches yesterday or today (UTC).
  IF v_last_covered IS NULL OR v_last_covered < v_today - 1 THEN
    v_current := 0;
  END IF;

  SELECT max(pa.puzzle_date) INTO v_last_solve
  FROM public.puzzle_attempts pa
  WHERE pa.user_id = p_user_id AND pa.completed AND NOT pa.is_archive;

  INSERT INTO public.streaks (user_id, current_streak, longest_streak, last_solve_date)
  VALUES (p_user_id, v_current, v_longest, v_last_solve)
  ON CONFLICT (user_id) DO UPDATE
    SET current_streak  = EXCLUDED.current_streak,
        longest_streak  = GREATEST(public.streaks.longest_streak, EXCLUDED.longest_streak),
        last_solve_date = EXCLUDED.last_solve_date
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.recompute_streak(UUID) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- record_solve(uid, date) -> streaks   (service role only; called by submit-score)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.record_solve(p_user_id UUID, p_puzzle_date DATE)
RETURNS public.streaks
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_row public.streaks;
BEGIN
  UPDATE public.profiles
     SET last_active_at = now()
   WHERE id = p_user_id;

  v_row := public.recompute_streak(p_user_id);
  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.record_solve(UUID, DATE) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- apply_streak_freezes()  — cron, 00:05 UTC daily
-- For yesterday (UTC): users who had a covered date the day before yesterday,
-- did NOT solve yesterday, have no freeze for yesterday, and have freeze_count > 0
-- get a freeze row for yesterday and their streak recomputed.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.apply_streak_freezes()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_yesterday DATE := (now() AT TIME ZONE 'utc')::date - 1;
  v_applied   INTEGER := 0;
  r           RECORD;
BEGIN
  FOR r IN
    SELECT s.user_id
    FROM public.streaks s
    WHERE s.freeze_count > 0
      AND EXISTS (                         -- streak alive through the day before yesterday
        SELECT 1 FROM public.puzzle_attempts pa
        WHERE pa.user_id = s.user_id AND pa.puzzle_date = v_yesterday - 1
          AND pa.completed AND NOT pa.is_archive
        UNION ALL
        SELECT 1 FROM public.streak_freezes sf
        WHERE sf.user_id = s.user_id AND sf.frozen_date = v_yesterday - 1
      )
      AND NOT EXISTS (                     -- missed yesterday
        SELECT 1 FROM public.puzzle_attempts pa
        WHERE pa.user_id = s.user_id AND pa.puzzle_date = v_yesterday
          AND pa.completed AND NOT pa.is_archive
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.streak_freezes sf
        WHERE sf.user_id = s.user_id AND sf.frozen_date = v_yesterday
      )
  LOOP
    INSERT INTO public.streak_freezes (user_id, frozen_date)
    VALUES (r.user_id, v_yesterday)
    ON CONFLICT DO NOTHING;

    UPDATE public.streaks
       SET freeze_count = freeze_count - 1,
           last_freeze_used_at = v_yesterday
     WHERE user_id = r.user_id;

    PERFORM public.recompute_streak(r.user_id);
    v_applied := v_applied + 1;
  END LOOP;

  RETURN v_applied;
END;
$$;

REVOKE ALL ON FUNCTION public.apply_streak_freezes() FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- reset_weekly_freezes() — cron, Monday 00:00 UTC
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reset_weekly_freezes()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_count INTEGER;
BEGIN
  UPDATE public.streaks
     SET freeze_count = 1,
         freeze_reset_week_start = (now() AT TIME ZONE 'utc')::date
   WHERE freeze_count < 1
      OR freeze_reset_week_start IS DISTINCT FROM (now() AT TIME ZONE 'utc')::date;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.reset_weekly_freezes() FROM PUBLIC, anon, authenticated;
