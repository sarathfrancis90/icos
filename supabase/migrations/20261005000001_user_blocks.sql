-- User blocking (App Store guideline 1.2 / Google Play UGC policy).
--
-- * public.user_blocks: who blocked whom. Clients never write it directly;
--   they call block_user / unblock_user / list_blocked_users.
-- * Blocking hides the blocked user's scores and activity from the blocker
--   (daily + weekly group leaderboards, group_feed). The blocked user is not
--   told and still sees the blocker. Member lists are left alone so a group
--   admin can still remove the member; the client renders the row as blocked.
-- * A new block also files a row in public.reports so the developer is
--   notified and can review the account (reason = 'blocked_by_user').
-- The two leaderboard functions are redefined with the same signature, return
-- type and ordering as 20260909000008_leaderboard_rpcs.sql, plus one filter.

-- ---------------------------------------------------------------------------
-- Table
-- ---------------------------------------------------------------------------
CREATE TABLE public.user_blocks (
  blocker_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  blocked_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (blocker_id, blocked_id),
  CONSTRAINT user_blocks_no_self_block CHECK (blocker_id <> blocked_id)
);
CREATE INDEX idx_user_blocks_blocked_id ON public.user_blocks (blocked_id);

ALTER TABLE public.user_blocks ENABLE ROW LEVEL SECURITY;
-- Read-only for the blocker. No INSERT/UPDATE/DELETE policies: RPC only.
CREATE POLICY "Users can view their own blocks"
  ON public.user_blocks FOR SELECT
  TO authenticated
  USING (blocker_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- Helper used by the policy and RPCs below
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_blocked_by_me(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_blocks b
    WHERE b.blocker_id = (select auth.uid())
      AND b.blocked_id = p_user_id
  );
$$;

-- ---------------------------------------------------------------------------
-- block_user / unblock_user / list_blocked_users
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.block_user(p_user_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid UUID := (select auth.uid());
BEGIN
  PERFORM public.assert_active_user(v_uid);

  IF p_user_id IS NULL OR p_user_id = v_uid THEN
    RAISE EXCEPTION 'You cannot block yourself'
      USING ERRCODE = '22023', HINT = 'INVALID_TARGET';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'User not found'
      USING ERRCODE = 'P0002', HINT = 'PROFILE_NOT_FOUND';
  END IF;

  INSERT INTO public.user_blocks (blocker_id, blocked_id)
  VALUES (v_uid, p_user_id)
  ON CONFLICT DO NOTHING;

  -- Only a new block notifies the developer, and at most one notice per
  -- (reporter, target) pair ever, so block/unblock/block cannot flood the
  -- review queue.
  IF FOUND AND NOT EXISTS (
    SELECT 1 FROM public.reports r
    WHERE r.reporter_id = v_uid
      AND r.reported_user_id = p_user_id
      AND r.reason = 'blocked_by_user'
  ) THEN
    INSERT INTO public.reports (reporter_id, reported_user_id, reason, details)
    VALUES (v_uid, p_user_id, 'blocked_by_user', 'Automatic notice: the reporter blocked this user.');
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.unblock_user(p_user_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid UUID := (select auth.uid());
BEGIN
  PERFORM public.assert_active_user(v_uid);
  DELETE FROM public.user_blocks
  WHERE blocker_id = v_uid AND blocked_id = p_user_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.list_blocked_users()
RETURNS TABLE (user_id UUID, display_name TEXT, blocked_at TIMESTAMPTZ)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    b.blocked_id AS user_id,
    CASE WHEN p.display_name = '' THEN 'Anonymous' ELSE p.display_name END AS display_name,
    b.created_at AS blocked_at
  FROM public.user_blocks b
  JOIN public.profiles p ON p.id = b.blocked_id
  WHERE b.blocker_id = (select auth.uid())
  ORDER BY b.created_at DESC;
$$;

REVOKE ALL ON FUNCTION public.is_blocked_by_me(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.block_user(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.unblock_user(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.list_blocked_users() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_blocked_by_me(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.block_user(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.unblock_user(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_blocked_users() TO authenticated;

-- ---------------------------------------------------------------------------
-- Leaderboards: drop rows whose user the caller has blocked (ranks follow).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_group_daily_leaderboard(
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
    AND NOT public.is_blocked_by_me(pa.user_id)
  ORDER BY pa.hints_used ASC, pa.time_seconds ASC, pa.undos_used ASC, pa.completed_at ASC;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_group_weekly_leaderboard(
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
    AND NOT public.is_blocked_by_me(a.user_id)
  ORDER BY a.completed_count DESC, a.avg_time_seconds ASC NULLS LAST, a.total_hints ASC;
END;
$$;

-- CREATE OR REPLACE keeps the existing grants; restate them so this file is
-- self-describing.
REVOKE ALL ON FUNCTION public.get_group_daily_leaderboard(UUID, DATE) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_group_weekly_leaderboard(UUID, DATE) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_group_daily_leaderboard(UUID, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_group_weekly_leaderboard(UUID, DATE) TO authenticated;

-- ---------------------------------------------------------------------------
-- group_feed: members see the feed minus rows authored by users they blocked.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "Members can view group feed" ON public.group_feed;
CREATE POLICY "Members can view group feed"
  ON public.group_feed FOR SELECT
  TO authenticated
  USING (
    public.is_group_member(group_id)
    AND NOT public.is_blocked_by_me(user_id)
  );
