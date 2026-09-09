-- Production hardening (8/9): leaderboard RPCs.
--
-- * SECURITY DEFINER with SET search_path = '' (previously unpinned).
-- * Caller must be an active (not banned, not deleted) member of the group.
-- * Daily: rank column, ordered hints ASC, time ASC, undos ASC; live solves only.
-- * Weekly: rank column, ordered completed DESC, avg_time ASC.
-- * Banned / purged members are excluded from results.
-- Parameter names are unchanged (p_group_id, p_puzzle_date / p_week_start).

DROP FUNCTION IF EXISTS public.get_group_daily_leaderboard(UUID, DATE);
DROP FUNCTION IF EXISTS public.get_group_weekly_leaderboard(UUID, DATE);

CREATE OR REPLACE FUNCTION public.assert_group_member(p_group_id UUID)
RETURNS void
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $$
DECLARE
  v_uid UUID := (select auth.uid());
BEGIN
  PERFORM public.assert_active_user(v_uid);
  IF NOT EXISTS (
    SELECT 1 FROM public.group_members gm
    WHERE gm.group_id = p_group_id AND gm.user_id = v_uid
  ) THEN
    RAISE EXCEPTION 'Not a member of this group'
      USING ERRCODE = '42501', HINT = 'NOT_A_MEMBER';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.assert_group_member(UUID) FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.get_group_daily_leaderboard(
  p_group_id    UUID,
  p_puzzle_date DATE
)
RETURNS TABLE (
  rank         INTEGER,
  user_id      UUID,
  display_name TEXT,
  avatar_url   TEXT,
  time_seconds INTEGER,
  hints_used   INTEGER,
  undos_used   INTEGER,
  completed    BOOLEAN,
  verified     BOOLEAN
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  PERFORM public.assert_group_member(p_group_id);

  RETURN QUERY
  SELECT
    (row_number() OVER (ORDER BY pa.hints_used ASC, pa.time_seconds ASC, pa.undos_used ASC, pa.completed_at ASC))::int AS rank,
    pa.user_id,
    CASE WHEN p.display_name = '' THEN 'Anonymous' ELSE p.display_name END AS display_name,
    p.avatar_url,
    pa.time_seconds,
    pa.hints_used,
    pa.undos_used,
    pa.completed,
    pa.verified
  FROM public.puzzle_attempts pa
  JOIN public.group_members gm ON gm.user_id = pa.user_id AND gm.group_id = p_group_id
  JOIN public.profiles p ON p.id = pa.user_id
  WHERE pa.puzzle_date = p_puzzle_date
    AND pa.completed
    AND NOT pa.is_archive
    AND NOT p.is_banned
  ORDER BY pa.hints_used ASC, pa.time_seconds ASC, pa.undos_used ASC, pa.completed_at ASC;
END;
$$;

CREATE FUNCTION public.get_group_weekly_leaderboard(
  p_group_id   UUID,
  p_week_start DATE
)
RETURNS TABLE (
  rank             INTEGER,
  user_id          UUID,
  display_name     TEXT,
  avatar_url       TEXT,
  completed_count  BIGINT,
  avg_time_seconds NUMERIC,
  total_hints      BIGINT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_week_end DATE := p_week_start + 6;
BEGIN
  PERFORM public.assert_group_member(p_group_id);

  RETURN QUERY
  WITH agg AS (
    SELECT
      pa.user_id,
      count(*) FILTER (WHERE pa.completed)::bigint          AS completed_count,
      avg(pa.time_seconds) FILTER (WHERE pa.completed)      AS avg_time_seconds,
      COALESCE(sum(pa.hints_used) FILTER (WHERE pa.completed), 0)::bigint AS total_hints
    FROM public.puzzle_attempts pa
    JOIN public.group_members gm ON gm.user_id = pa.user_id AND gm.group_id = p_group_id
    WHERE pa.puzzle_date BETWEEN p_week_start AND v_week_end
      AND NOT pa.is_archive
    GROUP BY pa.user_id
  )
  SELECT
    (row_number() OVER (ORDER BY a.completed_count DESC, a.avg_time_seconds ASC NULLS LAST, a.total_hints ASC))::int AS rank,
    a.user_id,
    CASE WHEN p.display_name = '' THEN 'Anonymous' ELSE p.display_name END AS display_name,
    p.avatar_url,
    a.completed_count,
    a.avg_time_seconds,
    a.total_hints
  FROM agg a
  JOIN public.profiles p ON p.id = a.user_id
  WHERE NOT p.is_banned
  ORDER BY a.completed_count DESC, a.avg_time_seconds ASC NULLS LAST, a.total_hints ASC;
END;
$$;

REVOKE ALL ON FUNCTION public.get_group_daily_leaderboard(UUID, DATE) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_group_weekly_leaderboard(UUID, DATE) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_group_daily_leaderboard(UUID, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_group_weekly_leaderboard(UUID, DATE) TO authenticated;

-- Streak visibility for co-members (recreated with the non-recursive helper).
DROP POLICY IF EXISTS "Group members can view streaks" ON public.streaks;
CREATE POLICY "Group members can view streaks"
  ON public.streaks FOR SELECT
  TO authenticated
  USING (public.shares_group_with(user_id));
