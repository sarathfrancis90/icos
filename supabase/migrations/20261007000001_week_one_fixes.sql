-- Week-one fixes after the 2026-10-05 launch.
--
-- * expire_stale_streaks(): streaks.current_streak was only recomputed by
--   record_solve / apply_streak_freezes, so a player who missed a day without a
--   freeze kept a stale non-zero streak. This job recomputes every row whose
--   last covered date (last solve or freeze) is before yesterday UTC.
--   pg_cron 'expire-stale-streaks' at 00:10 UTC, after apply-streak-freezes
--   (00:05) so a freeze spent for yesterday is seen first.
-- * regenerate_invite_code(p_group_id) (FR41): admin-only, returns the groups
--   row with a fresh 6-char code; the old code stops working immediately.
-- * Deleted users on leaderboards (FR105): purge_deleted_accounts() detached the
--   user from every group (DELETE FROM group_members) and both leaderboard RPCs
--   inner-join group_members, so a purged player's past results vanished from
--   every group leaderboard instead of showing as "Deleted User". The co-member
--   profile policy depended on group_members too, so their feed entries lost
--   their name. Now:
--     - public.group_purged_members remembers (group_id, user_id) for purged
--       accounts; it is written by purge_deleted_accounts() and backfilled from
--       group_feed for accounts purged before this migration.
--     - the leaderboard RPCs count those rows as members and always render a
--       purged profile as 'Deleted User' with no avatar.
--     - members may read a purged profile that was in one of their groups, so
--       group_feed's profiles(display_name) embed resolves to 'Deleted User'.
--   Purged users are not added back to group_members: member lists and
--   member_count stay as they were.
-- The leaderboard functions keep the signature, return type, ordering and
-- block filter of 20261005000001_user_blocks.sql.

-- ---------------------------------------------------------------------------
-- 1. Stale streaks
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.expire_stale_streaks()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_yesterday DATE := (now() AT TIME ZONE 'utc')::date - 1;
  v_count     INTEGER := 0;
  r           RECORD;
BEGIN
  FOR r IN
    SELECT s.user_id
    FROM public.streaks s
    WHERE s.current_streak > 0
      AND COALESCE(
            GREATEST(
              s.last_solve_date,
              (SELECT max(sf.frozen_date) FROM public.streak_freezes sf WHERE sf.user_id = s.user_id)
            ),
            '-infinity'::date
          ) < v_yesterday
  LOOP
    PERFORM public.recompute_streak(r.user_id);
    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.expire_stale_streaks() FROM PUBLIC, anon, authenticated;

DO $$
DECLARE
  j RECORD;
BEGIN
  FOR j IN SELECT jobid FROM cron.job WHERE jobname = 'expire-stale-streaks' LOOP
    PERFORM cron.unschedule(j.jobid);
  END LOOP;
END;
$$;

SELECT cron.schedule('expire-stale-streaks', '10 0 * * *', 'SELECT public.expire_stale_streaks()');

-- Fix the rows that are already stale instead of waiting for the first run.
SELECT public.expire_stale_streaks();

-- ---------------------------------------------------------------------------
-- 2. Invite code regeneration (FR41)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.regenerate_invite_code(p_group_id UUID)
RETURNS public.groups
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid   UUID := (select auth.uid());
  v_group public.groups;
BEGIN
  PERFORM public.assert_active_user(v_uid);
  SELECT * INTO v_group FROM public.groups WHERE id = p_group_id FOR UPDATE;
  IF v_group.id IS NULL OR v_group.admin_id <> v_uid THEN
    RAISE EXCEPTION 'Only the group admin can change the invite code'
      USING ERRCODE = '42501', HINT = 'NOT_ADMIN';
  END IF;

  UPDATE public.groups
     SET invite_code = public.generate_invite_code(),
         updated_at  = now()
   WHERE id = p_group_id
  RETURNING * INTO v_group;
  RETURN v_group;
END;
$$;

REVOKE ALL ON FUNCTION public.regenerate_invite_code(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.regenerate_invite_code(UUID) TO authenticated;

-- ---------------------------------------------------------------------------
-- 3. Deleted users on leaderboards (FR105)
-- ---------------------------------------------------------------------------
CREATE TABLE public.group_purged_members (
  group_id  UUID NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  user_id   UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  purged_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (group_id, user_id)
);
CREATE INDEX idx_group_purged_members_user_id ON public.group_purged_members (user_id);

-- Read only through the SECURITY DEFINER functions below; no client policies.
ALTER TABLE public.group_purged_members ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.group_purged_members FROM anon, authenticated;

-- Backfill accounts purged before this migration: their group_members rows are
-- gone, but group_feed ('joined', 'solved', ...) still records which groups
-- they were in.
INSERT INTO public.group_purged_members (group_id, user_id, purged_at)
SELECT DISTINCT gf.group_id, gf.user_id, p.purged_at
FROM public.group_feed gf
JOIN public.profiles p ON p.id = gf.user_id
WHERE p.purged_at IS NOT NULL
ON CONFLICT DO NOTHING;

-- Older purges already set display_name/avatar; make sure none slipped through.
UPDATE public.profiles
   SET display_name = 'Deleted User',
       avatar_url   = NULL
 WHERE purged_at IS NOT NULL
   AND (display_name IS DISTINCT FROM 'Deleted User' OR avatar_url IS NOT NULL);

-- Caller is a current member of a group the purged user p_user_id was in.
CREATE OR REPLACE FUNCTION public.shares_former_group_with(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.group_purged_members gp
    JOIN public.group_members mine ON mine.group_id = gp.group_id
    WHERE gp.user_id = p_user_id
      AND mine.user_id = (select auth.uid())
  );
$$;

REVOKE ALL ON FUNCTION public.shares_former_group_with(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.shares_former_group_with(UUID) TO authenticated;

DROP POLICY IF EXISTS "Members can view purged former co-members" ON public.profiles;
CREATE POLICY "Members can view purged former co-members"
  ON public.profiles FOR SELECT
  TO authenticated
  USING (purged_at IS NOT NULL AND public.shares_former_group_with(id));

-- Same body as 20260909000005_profiles_deletion_and_privacy.sql, plus the
-- group_purged_members insert before the user is detached from their groups.
CREATE OR REPLACE FUNCTION public.purge_deleted_accounts()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  r       RECORD;
  v_count INTEGER := 0;
BEGIN
  FOR r IN
    SELECT id FROM public.profiles
    WHERE deleted_at IS NOT NULL
      AND deleted_at < now() - interval '30 days'
      AND purged_at IS NULL
  LOOP
    -- Remember group membership so leaderboards keep the rows as "Deleted User".
    INSERT INTO public.group_purged_members (group_id, user_id)
    SELECT gm.group_id, gm.user_id
    FROM public.group_members gm
    WHERE gm.user_id = r.id
    ON CONFLICT DO NOTHING;

    PERFORM public.detach_user_from_groups(r.id);

    DELETE FROM public.puzzle_sessions WHERE user_id = r.id;
    DELETE FROM public.submission_log  WHERE user_id = r.id;

    UPDATE public.profiles
       SET display_name = 'Deleted User',
           avatar_url   = NULL,
           notification_enabled = false,
           purged_at    = now()
     WHERE id = r.id;

    -- Scrub auth: no email/phone/password/metadata, no identities, no sessions.
    DELETE FROM auth.identities     WHERE user_id = r.id;
    DELETE FROM auth.sessions       WHERE user_id = r.id;
    DELETE FROM auth.refresh_tokens WHERE user_id = r.id::text;
    DELETE FROM auth.mfa_factors    WHERE user_id = r.id;

    UPDATE auth.users
       SET email = NULL,
           phone = NULL,
           encrypted_password = NULL,
           email_change = '',
           email_change_token_new = '',
           email_change_token_current = '',
           phone_change = '',
           phone_change_token = '',
           recovery_token = '',
           confirmation_token = '',
           raw_user_meta_data = '{}'::jsonb,
           raw_app_meta_data  = '{}'::jsonb,
           banned_until = 'infinity'::timestamptz,
           updated_at = now()
     WHERE id = r.id;

    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$;
REVOKE ALL ON FUNCTION public.purge_deleted_accounts() FROM PUBLIC, anon, authenticated;

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
  WITH members AS (
    SELECT gm.user_id FROM public.group_members gm WHERE gm.group_id = p_group_id
    UNION
    SELECT gp.user_id FROM public.group_purged_members gp WHERE gp.group_id = p_group_id
  )
  SELECT
    (row_number() OVER (ORDER BY pa.hints_used ASC, pa.time_seconds ASC, pa.undos_used ASC, pa.completed_at ASC))::int AS rank,
    pa.user_id,
    CASE
      WHEN p.purged_at IS NOT NULL THEN 'Deleted User'
      WHEN p.display_name = '' THEN 'Anonymous'
      ELSE p.display_name
    END AS display_name,
    CASE WHEN p.purged_at IS NOT NULL THEN NULL ELSE p.avatar_url END AS avatar_url,
    pa.time_seconds,
    pa.hints_used,
    pa.undos_used,
    pa.completed,
    pa.verified
  FROM public.puzzle_attempts pa
  JOIN members m ON m.user_id = pa.user_id
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
  WITH members AS (
    SELECT gm.user_id FROM public.group_members gm WHERE gm.group_id = p_group_id
    UNION
    SELECT gp.user_id FROM public.group_purged_members gp WHERE gp.group_id = p_group_id
  ),
  agg AS (
    SELECT
      pa.user_id,
      count(*) FILTER (WHERE pa.completed)::bigint          AS completed_count,
      avg(pa.time_seconds) FILTER (WHERE pa.completed)      AS avg_time_seconds,
      COALESCE(sum(pa.hints_used) FILTER (WHERE pa.completed), 0)::bigint AS total_hints
    FROM public.puzzle_attempts pa
    JOIN members m ON m.user_id = pa.user_id
    WHERE pa.puzzle_date BETWEEN p_week_start AND v_week_end
      AND NOT pa.is_archive
    GROUP BY pa.user_id
  )
  SELECT
    (row_number() OVER (ORDER BY a.completed_count DESC, a.avg_time_seconds ASC NULLS LAST, a.total_hints ASC))::int AS rank,
    a.user_id,
    CASE
      WHEN p.purged_at IS NOT NULL THEN 'Deleted User'
      WHEN p.display_name = '' THEN 'Anonymous'
      ELSE p.display_name
    END AS display_name,
    CASE WHEN p.purged_at IS NOT NULL THEN NULL ELSE p.avatar_url END AS avatar_url,
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

REVOKE ALL ON FUNCTION public.get_group_daily_leaderboard(UUID, DATE) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_group_weekly_leaderboard(UUID, DATE) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_group_daily_leaderboard(UUID, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_group_weekly_leaderboard(UUID, DATE) TO authenticated;
