-- 0002_functions: SQL functions and the remaining triggers of the Icos schema.
--
-- Ported from the current definitions in supabase/migrations/* (last
-- CREATE OR REPLACE wins), with the Neon migration changes (spec §5.3):
--   * auth.uid() -> (select app.uid()); names, arguments and return types are
--     unchanged (the client calls them by name with named parameters).
--   * No auth.users / auth.identities / vault / pg_net / pg_cron. The purge
--     jobs return the affected ids so the Function can delete the auth users.
--   * Not ported: handle_new_user, handle_user_updated, provider_display_name,
--     is_placeholder_display_name (now the Function's auth hooks),
--     notify_report_filed, trigger_daily_puzzle_generation (Function cron),
--     decrement_group_member_count, update_group (unused), block_user and
--     unblock_user (the Function's /api/block routes).
--   * icos.profile_guard_bypass is gone: SECURITY DEFINER functions run as the
--     owner, which protect_profile_columns (0001) never pins.
--
-- Defined in 0001 and not repeated here: app.uid(), app.is_service(),
-- update_updated_at, protect_profile_columns (+ their triggers),
-- is_group_member, shares_group_with, shares_former_group_with,
-- is_blocked_by_me.
--
-- Privileges: 0001 revoked the default EXECUTE grants, and each function below
-- also revokes explicitly. Client-callable functions are granted to
-- `authenticated` at the end of this file; everything else is owner-only.

-- ---------------------------------------------------------------------------
-- Text: sanitization, profanity, name validation
-- ---------------------------------------------------------------------------

-- NFKC-normalize, strip zero-width / bidi / control characters and stray
-- combining marks (zalgo), collapse whitespace, trim. Case is preserved.
CREATE OR REPLACE FUNCTION public.sanitize_text(p_input text)
RETURNS text
LANGUAGE sql
IMMUTABLE
STRICT
SET search_path = ''
AS $$
  SELECT btrim(
    regexp_replace(
      regexp_replace(
        regexp_replace(
          normalize(p_input, NFKC),
          -- zero-width, bidi controls, soft hyphen, BOM, word joiner, hangul fillers, variation selectors
          '[\u00AD\u034F\u061C\u115F\u1160\u17B4\u17B5\u180E\u200B-\u200F\u202A-\u202E\u2060-\u206F\u3164\uFE00-\uFE0F\uFEFF\uFFA0\uFFF0-\uFFFF]',
          '', 'g'),
        -- C0/C1 control characters + combining marks (zalgo)
        '[\x01-\x1F\x7F-\x9F\u0300-\u036F\u1AB0-\u1AFF\u1DC0-\u1DFF\u20D0-\u20FF\uFE20-\uFE2F]',
        '', 'g'),
      '\s+', ' ', 'g')
  );
$$;

-- Case-insensitive whole-word match after leetspeak folding. SECURITY DEFINER
-- because clients cannot read banned_words.
CREATE OR REPLACE FUNCTION public.contains_profanity(p_input text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
STRICT
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_folded text;
BEGIN
  v_folded := lower(public.sanitize_text(p_input));
  v_folded := translate(v_folded, '01345$@!|', 'oieaesail');
  v_folded := regexp_replace(v_folded, '[^a-z0-9 ]', '', 'g');

  RETURN EXISTS (
    SELECT 1 FROM public.banned_words bw
    WHERE v_folded ~ ('(^|[^a-z])' || bw.word || '([^a-z]|$)')
       OR regexp_replace(v_folded, '[^a-z]', '', 'g') = bw.word
  );
END;
$$;

-- Validate a display/group name: returns the sanitized value or raises.
CREATE OR REPLACE FUNCTION public.validate_name(p_input text, p_field text DEFAULT 'name')
RETURNS text
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $$
DECLARE
  v_clean text;
BEGIN
  v_clean := public.sanitize_text(COALESCE(p_input, ''));
  IF length(v_clean) < 2 OR length(v_clean) > 30 THEN
    RAISE EXCEPTION '% must be between 2 and 30 characters', p_field
      USING ERRCODE = '22023', HINT = 'INVALID_LENGTH';
  END IF;
  IF public.contains_profanity(v_clean) THEN
    RAISE EXCEPTION '% contains inappropriate language', p_field
      USING ERRCODE = '22023', HINT = 'PROFANITY';
  END IF;
  RETURN v_clean;
END;
$$;

-- Display names are validated server-side too (the client filter is advisory).
-- Runs as the invoker: a client update calls validate_name as `authenticated`.
CREATE OR REPLACE FUNCTION public.validate_profile_display_name()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF NEW.display_name IS DISTINCT FROM OLD.display_name AND NEW.display_name <> '' THEN
    NEW.display_name := public.validate_name(NEW.display_name, 'Display name');
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER validate_profile_display_name
  BEFORE UPDATE OF display_name ON public.profiles
  FOR EACH ROW
  WHEN (pg_trigger_depth() = 0)
  EXECUTE FUNCTION public.validate_profile_display_name();

-- ---------------------------------------------------------------------------
-- group_members: capacity enforcement and member_count maintenance
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.group_members_before_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_group public.groups;
BEGIN
  SELECT * INTO v_group FROM public.groups WHERE id = NEW.group_id FOR UPDATE;
  IF v_group.id IS NULL THEN
    RAISE EXCEPTION 'Group not found' USING ERRCODE = 'P0002', HINT = 'GROUP_NOT_FOUND';
  END IF;
  IF NOT v_group.is_active THEN
    RAISE EXCEPTION 'Group is no longer active' USING ERRCODE = '22023', HINT = 'GROUP_INACTIVE';
  END IF;
  IF v_group.member_count >= v_group.max_members THEN
    RAISE EXCEPTION 'Group is full (max % members)', v_group.max_members
      USING ERRCODE = '23514', HINT = 'GROUP_FULL';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.group_members_after_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.groups SET member_count = member_count + 1 WHERE id = NEW.group_id;
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.groups SET member_count = GREATEST(member_count - 1, 0) WHERE id = OLD.group_id;
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$;

CREATE TRIGGER group_members_before_insert
  BEFORE INSERT ON public.group_members
  FOR EACH ROW EXECUTE FUNCTION public.group_members_before_insert();

CREATE TRIGGER group_members_after_change
  AFTER INSERT OR DELETE ON public.group_members
  FOR EACH ROW EXECUTE FUNCTION public.group_members_after_change();

-- ---------------------------------------------------------------------------
-- Internal helpers (owner-only; called from the SECURITY DEFINER RPCs)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.generate_invite_code()
RETURNS text
LANGUAGE plpgsql
VOLATILE
SET search_path = ''
AS $$
DECLARE
  v_chars text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; -- no 0/O/1/I ambiguity
  v_code  text;
  v_i     integer;
BEGIN
  LOOP
    v_code := '';
    FOR v_i IN 1..6 LOOP
      v_code := v_code || substr(v_chars, 1 + floor(random() * length(v_chars))::int, 1);
    END LOOP;
    EXIT WHEN NOT EXISTS (SELECT 1 FROM public.groups WHERE invite_code = v_code);
  END LOOP;
  RETURN v_code;
END;
$$;

CREATE OR REPLACE FUNCTION public.assert_active_user(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $$
DECLARE
  v_profile public.profiles;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501', HINT = 'UNAUTHENTICATED';
  END IF;
  SELECT * INTO v_profile FROM public.profiles WHERE id = p_user_id;
  IF v_profile.id IS NULL THEN
    RAISE EXCEPTION 'Profile not found' USING ERRCODE = 'P0002', HINT = 'PROFILE_NOT_FOUND';
  END IF;
  IF v_profile.is_banned THEN
    RAISE EXCEPTION 'Account suspended' USING ERRCODE = '42501', HINT = 'BANNED';
  END IF;
  IF v_profile.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'Account scheduled for deletion' USING ERRCODE = '42501', HINT = 'DELETED';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.assert_group_member(p_group_id uuid)
RETURNS void
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $$
DECLARE
  v_uid uuid := (select app.uid());
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

-- ---------------------------------------------------------------------------
-- Group RPCs (SECURITY DEFINER, search_path pinned, bound to app.uid())
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_group(p_name text, p_description text DEFAULT '')
RETURNS public.groups
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid   uuid := (select app.uid());
  v_name  text;
  v_desc  text;
  v_group public.groups;
BEGIN
  PERFORM public.assert_active_user(v_uid);

  IF (SELECT is_anonymous FROM public.profiles WHERE id = v_uid) THEN
    RAISE EXCEPTION 'Create an account to create groups'
      USING ERRCODE = '42501', HINT = 'ANONYMOUS_USER';
  END IF;

  IF (SELECT count(*) FROM public.group_members WHERE user_id = v_uid) >= 20 THEN
    RAISE EXCEPTION 'You are already in the maximum number of groups (20)'
      USING ERRCODE = '22023', HINT = 'TOO_MANY_GROUPS';
  END IF;

  v_name := public.validate_name(p_name, 'Group name');
  v_desc := left(public.sanitize_text(COALESCE(p_description, '')), 200);
  IF v_desc <> '' AND public.contains_profanity(v_desc) THEN
    RAISE EXCEPTION 'Description contains inappropriate language'
      USING ERRCODE = '22023', HINT = 'PROFANITY';
  END IF;

  INSERT INTO public.groups (name, description, invite_code, admin_id, member_count, max_members, is_active)
  VALUES (v_name, v_desc, public.generate_invite_code(), v_uid, 0, 50, true)
  RETURNING * INTO v_group;

  INSERT INTO public.group_members (group_id, user_id, role)
  VALUES (v_group.id, v_uid, 'admin');

  SELECT * INTO v_group FROM public.groups WHERE id = v_group.id;
  RETURN v_group;
END;
$$;

CREATE OR REPLACE FUNCTION public.remove_group_member(p_group_id uuid, p_user_id uuid)
RETURNS public.groups
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid   uuid := (select app.uid());
  v_group public.groups;
BEGIN
  PERFORM public.assert_active_user(v_uid);
  SELECT * INTO v_group FROM public.groups WHERE id = p_group_id FOR UPDATE;
  IF v_group.id IS NULL OR v_group.admin_id <> v_uid THEN
    RAISE EXCEPTION 'Only the group admin can remove members'
      USING ERRCODE = '42501', HINT = 'NOT_ADMIN';
  END IF;
  IF p_user_id = v_uid THEN
    RAISE EXCEPTION 'Admins must use leave_group or transfer_group_admin'
      USING ERRCODE = '22023', HINT = 'CANNOT_REMOVE_SELF';
  END IF;

  DELETE FROM public.group_members
   WHERE group_id = p_group_id AND user_id = p_user_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'User is not a member of this group'
      USING ERRCODE = 'P0002', HINT = 'NOT_A_MEMBER';
  END IF;

  SELECT * INTO v_group FROM public.groups WHERE id = p_group_id;
  RETURN v_group;
END;
$$;

CREATE OR REPLACE FUNCTION public.transfer_group_admin(p_group_id uuid, p_new_admin_id uuid)
RETURNS public.groups
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid   uuid := (select app.uid());
  v_group public.groups;
BEGIN
  PERFORM public.assert_active_user(v_uid);
  SELECT * INTO v_group FROM public.groups WHERE id = p_group_id FOR UPDATE;
  IF v_group.id IS NULL OR v_group.admin_id <> v_uid THEN
    RAISE EXCEPTION 'Only the group admin can transfer ownership'
      USING ERRCODE = '42501', HINT = 'NOT_ADMIN';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.group_members WHERE group_id = p_group_id AND user_id = p_new_admin_id
  ) THEN
    RAISE EXCEPTION 'New admin must be a member of the group'
      USING ERRCODE = 'P0002', HINT = 'NOT_A_MEMBER';
  END IF;

  UPDATE public.group_members SET role = 'member' WHERE group_id = p_group_id AND user_id = v_uid;
  UPDATE public.group_members SET role = 'admin'  WHERE group_id = p_group_id AND user_id = p_new_admin_id;
  UPDATE public.groups SET admin_id = p_new_admin_id WHERE id = p_group_id
  RETURNING * INTO v_group;
  RETURN v_group;
END;
$$;

-- Soft delete: the group is deactivated, rows are kept.
CREATE OR REPLACE FUNCTION public.delete_group(p_group_id uuid)
RETURNS public.groups
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid   uuid := (select app.uid());
  v_group public.groups;
BEGIN
  PERFORM public.assert_active_user(v_uid);
  SELECT * INTO v_group FROM public.groups WHERE id = p_group_id FOR UPDATE;
  IF v_group.id IS NULL OR v_group.admin_id <> v_uid THEN
    RAISE EXCEPTION 'Only the group admin can delete the group'
      USING ERRCODE = '42501', HINT = 'NOT_ADMIN';
  END IF;

  UPDATE public.groups SET is_active = false WHERE id = p_group_id
  RETURNING * INTO v_group;
  RETURN v_group;
END;
$$;

-- An admin who leaves hands the group to the oldest other member, or
-- deactivates it when nobody is left.
CREATE OR REPLACE FUNCTION public.leave_group(p_group_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid       uuid := (select app.uid());
  v_group     public.groups;
  v_new_admin uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501', HINT = 'UNAUTHENTICATED';
  END IF;
  SELECT * INTO v_group FROM public.groups WHERE id = p_group_id FOR UPDATE;
  IF v_group.id IS NULL THEN
    RAISE EXCEPTION 'Group not found' USING ERRCODE = 'P0002', HINT = 'GROUP_NOT_FOUND';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.group_members WHERE group_id = p_group_id AND user_id = v_uid
  ) THEN
    RAISE EXCEPTION 'You are not a member of this group'
      USING ERRCODE = 'P0002', HINT = 'NOT_A_MEMBER';
  END IF;

  IF v_group.admin_id = v_uid THEN
    SELECT gm.user_id INTO v_new_admin
    FROM public.group_members gm
    WHERE gm.group_id = p_group_id AND gm.user_id <> v_uid
    ORDER BY gm.joined_at ASC, gm.id ASC
    LIMIT 1;

    IF v_new_admin IS NULL THEN
      UPDATE public.groups SET is_active = false WHERE id = p_group_id;
    ELSE
      UPDATE public.groups SET admin_id = v_new_admin WHERE id = p_group_id;
      UPDATE public.group_members SET role = 'admin'
       WHERE group_id = p_group_id AND user_id = v_new_admin;
    END IF;
  END IF;

  DELETE FROM public.group_members WHERE group_id = p_group_id AND user_id = v_uid;
END;
$$;

-- Admin-only (FR41): a fresh 6-char code; the old code stops working at once.
CREATE OR REPLACE FUNCTION public.regenerate_invite_code(p_group_id uuid)
RETURNS public.groups
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid   uuid := (select app.uid());
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

-- ---------------------------------------------------------------------------
-- Leaderboards. Members = current members plus purged former members (shown
-- as "Deleted User"); banned users and users the caller blocked are left out.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_group_daily_leaderboard(
  p_group_id    uuid,
  p_puzzle_date date
)
RETURNS TABLE (
  rank         integer,
  user_id      uuid,
  display_name text,
  avatar_url   text,
  time_seconds integer,
  hints_used   integer,
  undos_used   integer,
  completed    boolean,
  verified     boolean
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
  p_group_id   uuid,
  p_week_start date
)
RETURNS TABLE (
  rank             integer,
  user_id          uuid,
  display_name     text,
  avatar_url       text,
  completed_count  bigint,
  avg_time_seconds numeric,
  total_hints      bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_week_end date := p_week_start + 6;
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

-- ---------------------------------------------------------------------------
-- Blocking (writes are the Function's /api/block routes)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.list_blocked_users()
RETURNS TABLE (user_id uuid, display_name text, blocked_at timestamptz)
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
  WHERE b.blocker_id = (select app.uid())
  ORDER BY b.created_at DESC;
$$;

-- ---------------------------------------------------------------------------
-- Account deletion (30-day grace period)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.request_account_deletion()
RETURNS public.profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid uuid := (select app.uid());
  v_row public.profiles;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;
  UPDATE public.profiles
     SET deleted_at = COALESCE(deleted_at, now())
   WHERE id = v_uid AND purged_at IS NULL
  RETURNING * INTO v_row;
  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'Profile not found' USING ERRCODE = 'P0002';
  END IF;
  RETURN v_row;
END;
$$;

CREATE OR REPLACE FUNCTION public.cancel_account_deletion()
RETURNS public.profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid uuid := (select app.uid());
  v_row public.profiles;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;
  UPDATE public.profiles
     SET deleted_at = NULL
   WHERE id = v_uid AND purged_at IS NULL
  RETURNING * INTO v_row;
  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'Profile not found or already purged' USING ERRCODE = 'P0002';
  END IF;
  RETURN v_row;
END;
$$;

-- ---------------------------------------------------------------------------
-- Streaks (derived state; written only here)
-- ---------------------------------------------------------------------------

-- Covered dates = completed live attempts ∪ freezes. The current streak is
-- alive iff the latest covered date is today or yesterday (UTC); longest =
-- longest run of consecutive covered dates (never decreases).
CREATE OR REPLACE FUNCTION public.recompute_streak(p_user_id uuid)
RETURNS public.streaks
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_today        date := (now() AT TIME ZONE 'utc')::date;
  v_current      integer := 0;
  v_longest      integer := 0;
  v_last_covered date;
  v_last_solve   date;
  v_row          public.streaks;
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

-- Called by the Function's submit-score after recording a solve.
CREATE OR REPLACE FUNCTION public.record_solve(p_user_id uuid, p_puzzle_date date)
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

-- Daily 00:05 UTC: users who were covered the day before yesterday, missed
-- yesterday and have a freeze left get yesterday frozen.
CREATE OR REPLACE FUNCTION public.apply_streak_freezes()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_yesterday date := (now() AT TIME ZONE 'utc')::date - 1;
  v_applied   integer := 0;
  r           record;
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

-- Monday 00:00 UTC: everyone gets one freeze for the week.
CREATE OR REPLACE FUNCTION public.reset_weekly_freezes()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_count integer;
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

-- Daily 00:10 UTC (after apply_streak_freezes): recompute every non-zero
-- streak whose last covered date (solve or freeze) is before yesterday.
CREATE OR REPLACE FUNCTION public.expire_stale_streaks()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_yesterday date := (now() AT TIME ZONE 'utc')::date - 1;
  v_count     integer := 0;
  r           record;
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

-- ---------------------------------------------------------------------------
-- Housekeeping and account purges (the Function's /cron/* routes)
-- ---------------------------------------------------------------------------

-- Drop rate-limit log rows older than a day.
CREATE OR REPLACE FUNCTION public.prune_submission_log()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_count integer;
BEGIN
  DELETE FROM public.submission_log WHERE created_at < now() - interval '1 day';
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

-- Transfer admin to the oldest other member (or deactivate the group), then
-- remove all of the user's memberships. Used by both purge jobs.
CREATE OR REPLACE FUNCTION public.detach_user_from_groups(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  g           record;
  v_new_admin uuid;
BEGIN
  FOR g IN SELECT id FROM public.groups WHERE admin_id = p_user_id LOOP
    SELECT gm.user_id INTO v_new_admin
    FROM public.group_members gm
    WHERE gm.group_id = g.id AND gm.user_id <> p_user_id
    ORDER BY gm.joined_at ASC, gm.id ASC
    LIMIT 1;

    IF v_new_admin IS NULL THEN
      UPDATE public.groups SET is_active = false WHERE id = g.id;
    ELSE
      UPDATE public.groups SET admin_id = v_new_admin WHERE id = g.id;
      UPDATE public.group_members SET role = 'admin'
       WHERE group_id = g.id AND user_id = v_new_admin;
    END IF;
  END LOOP;

  DELETE FROM public.group_members WHERE user_id = p_user_id;
END;
$$;

-- Daily: anonymize accounts whose 30-day grace period has elapsed and return
-- their ids (the Function then deletes the auth users). Attempts are kept and
-- group_purged_members remembers the groups, so leaderboards show the rows as
-- "Deleted User".
CREATE OR REPLACE FUNCTION public.purge_deleted_accounts()
RETURNS SETOF uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT id FROM public.profiles
    WHERE deleted_at < now() - interval '30 days'
      AND purged_at IS NULL
    FOR UPDATE
  LOOP
    INSERT INTO public.group_purged_members (group_id, user_id)
    SELECT gm.group_id, gm.user_id
    FROM public.group_members gm
    WHERE gm.user_id = r.id
    ON CONFLICT DO NOTHING;

    PERFORM public.detach_user_from_groups(r.id);

    DELETE FROM public.puzzle_sessions WHERE user_id = r.id;
    DELETE FROM public.submission_log  WHERE user_id = r.id;

    UPDATE public.profiles
       SET display_name         = 'Deleted User',
           avatar_url           = NULL,
           email                = NULL,
           email_verified       = false,
           providers            = '{}',
           notification_enabled = false,
           purged_at            = now()
     WHERE id = r.id;

    RETURN NEXT r.id;
  END LOOP;
  RETURN;
END;
$$;

-- Daily: hard-delete guests idle for 90+ days (up to 1000 per run) and return
-- their ids (the Function then deletes the auth users). Deleting the profile
-- cascades to attempts, streaks, sessions and the rest.
CREATE OR REPLACE FUNCTION public.purge_inactive_anonymous()
RETURNS SETOF uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT p.id
    FROM public.profiles p
    WHERE p.is_anonymous
      AND p.last_active_at < now() - interval '90 days'
    LIMIT 1000
    FOR UPDATE
  LOOP
    -- Hand off any admin role first: groups.admin_id cascades on delete.
    PERFORM public.detach_user_from_groups(r.id);
    DELETE FROM public.profiles WHERE id = r.id;
    RETURN NEXT r.id;
  END LOOP;
  RETURN;
END;
$$;

-- ---------------------------------------------------------------------------
-- Privileges: nothing for PUBLIC / anonymous; client RPCs for authenticated.
-- ---------------------------------------------------------------------------
REVOKE ALL ON FUNCTION
  public.sanitize_text(text),
  public.contains_profanity(text),
  public.validate_name(text, text),
  public.validate_profile_display_name(),
  public.group_members_before_insert(),
  public.group_members_after_change(),
  public.generate_invite_code(),
  public.assert_active_user(uuid),
  public.assert_group_member(uuid),
  public.create_group(text, text),
  public.remove_group_member(uuid, uuid),
  public.transfer_group_admin(uuid, uuid),
  public.delete_group(uuid),
  public.leave_group(uuid),
  public.regenerate_invite_code(uuid),
  public.get_group_daily_leaderboard(uuid, date),
  public.get_group_weekly_leaderboard(uuid, date),
  public.list_blocked_users(),
  public.request_account_deletion(),
  public.cancel_account_deletion(),
  public.recompute_streak(uuid),
  public.record_solve(uuid, date),
  public.apply_streak_freezes(),
  public.reset_weekly_freezes(),
  public.expire_stale_streaks(),
  public.prune_submission_log(),
  public.detach_user_from_groups(uuid),
  public.purge_deleted_accounts(),
  public.purge_inactive_anonymous()
FROM PUBLIC, authenticated, anonymous;

GRANT EXECUTE ON FUNCTION
  public.sanitize_text(text),
  public.contains_profanity(text),
  public.validate_name(text, text),
  public.create_group(text, text),
  public.remove_group_member(uuid, uuid),
  public.transfer_group_admin(uuid, uuid),
  public.delete_group(uuid),
  public.leave_group(uuid),
  public.regenerate_invite_code(uuid),
  public.get_group_daily_leaderboard(uuid, date),
  public.get_group_weekly_leaderboard(uuid, date),
  public.list_blocked_users(),
  public.request_account_deletion(),
  public.cancel_account_deletion()
TO authenticated;
