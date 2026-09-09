-- Production hardening (5/9): profiles — deletion grace period, activity tracking,
-- co-member visibility, and the purge jobs.
--
-- * profiles.deleted_at / last_active_at / purged_at
-- * shares_group_with(uid) helper (SECURITY DEFINER, pinned search_path) used by
--   RLS policies so they don't recurse through group_members' own RLS.
-- * Co-members of a group can SELECT each other's profile (display_name/avatar
--   for member lists and leaderboards).
-- * request_account_deletion() / cancel_account_deletion() RPCs (auth.uid()).
-- * purge_deleted_accounts(): 30-day grace → anonymize (keep leaderboard rows).
-- * purge_inactive_anonymous(): delete anonymous users idle for 90 days.

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS deleted_at     TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS last_active_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS purged_at      TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_profiles_deleted_at
  ON public.profiles (deleted_at) WHERE deleted_at IS NOT NULL AND purged_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_profiles_anonymous_inactive
  ON public.profiles (last_active_at) WHERE is_anonymous;

-- Clients may not flip deleted_at/purged_at/is_banned directly; the profile
-- UPDATE policy still allows the row, so enforce with a trigger.
CREATE OR REPLACE FUNCTION public.protect_profile_columns()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  -- SECURITY DEFINER RPCs (request/cancel deletion) set this transaction-local
  -- flag so they can write the guarded columns on the caller's behalf.
  IF current_setting('icos.profile_guard_bypass', true) = 'on' THEN
    RETURN NEW;
  END IF;
  -- PostgREST exposes the JWT as request.jwt.claims (JSON). Treat anything that is
  -- not the service role / a superuser session as a client update.
  IF COALESCE(
       NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
       NULLIF(current_setting('request.jwt.claim.role', true), ''),
       current_user::text
     ) IN ('authenticated', 'anon') THEN
    NEW.is_banned    := OLD.is_banned;
    NEW.deleted_at   := OLD.deleted_at;
    NEW.purged_at    := OLD.purged_at;
    NEW.is_anonymous := OLD.is_anonymous;
    NEW.last_active_at := now();
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS protect_profile_columns ON public.profiles;
CREATE TRIGGER protect_profile_columns
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.protect_profile_columns();

-- Keep profiles.is_anonymous in sync when a guest links an identity
-- (auth.users.is_anonymous flips to false on updateUser/linkIdentity).
CREATE OR REPLACE FUNCTION public.handle_user_updated()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NEW.is_anonymous IS DISTINCT FROM OLD.is_anonymous THEN
    UPDATE public.profiles
       SET is_anonymous = NEW.is_anonymous
     WHERE id = NEW.id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_updated ON auth.users;
CREATE TRIGGER on_auth_user_updated
  AFTER UPDATE OF is_anonymous ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_user_updated();

-- ---------------------------------------------------------------------------
-- RLS helpers (SECURITY DEFINER so policies can consult group_members without
-- recursing through group_members' own policies).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_group_member(p_group_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.group_members gm
    WHERE gm.group_id = p_group_id
      AND gm.user_id = (select auth.uid())
  );
$$;

CREATE OR REPLACE FUNCTION public.shares_group_with(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.group_members mine
    JOIN public.group_members theirs ON theirs.group_id = mine.group_id
    WHERE mine.user_id = (select auth.uid())
      AND theirs.user_id = p_user_id
  );
$$;

REVOKE ALL ON FUNCTION public.is_group_member(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.shares_group_with(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_group_member(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.shares_group_with(UUID) TO authenticated;

-- ---------------------------------------------------------------------------
-- Profile policies
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "Users can view their own profile" ON public.profiles;
CREATE POLICY "Users can view their own profile"
  ON public.profiles FOR SELECT
  TO authenticated
  USING ((select auth.uid()) = id);

DROP POLICY IF EXISTS "Users can update their own profile" ON public.profiles;
CREATE POLICY "Users can update their own profile"
  ON public.profiles FOR UPDATE
  TO authenticated
  USING ((select auth.uid()) = id)
  WITH CHECK ((select auth.uid()) = id);

DROP POLICY IF EXISTS "Users can insert their own profile" ON public.profiles;
CREATE POLICY "Users can insert their own profile"
  ON public.profiles FOR INSERT
  TO authenticated
  WITH CHECK ((select auth.uid()) = id);

CREATE POLICY "Co-members can view profiles"
  ON public.profiles FOR SELECT
  TO authenticated
  USING (public.shares_group_with(id));

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
  v_uid UUID := (select auth.uid());
  v_row public.profiles;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  PERFORM set_config('icos.profile_guard_bypass', 'on', true);
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
  v_uid UUID := (select auth.uid());
  v_row public.profiles;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  PERFORM set_config('icos.profile_guard_bypass', 'on', true);
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

REVOKE ALL ON FUNCTION public.request_account_deletion() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.cancel_account_deletion() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_account_deletion() TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_account_deletion() TO authenticated;

-- Detach a user from all groups: transfer admin to the oldest other member or
-- deactivate the group, then remove memberships. Used by both purge jobs.
CREATE OR REPLACE FUNCTION public.detach_user_from_groups(p_user_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  g          RECORD;
  v_new_admin UUID;
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
REVOKE ALL ON FUNCTION public.detach_user_from_groups(UUID) FROM PUBLIC, anon, authenticated;

-- purge_deleted_accounts(): cron 01:00 UTC. Anonymize accounts whose grace
-- period has elapsed. Leaderboard rows are kept (shown as "Deleted User").
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

-- purge_inactive_anonymous(): cron 01:30 UTC. Hard-delete guests idle 90+ days.
CREATE OR REPLACE FUNCTION public.purge_inactive_anonymous()
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
    SELECT p.id
    FROM public.profiles p
    JOIN auth.users u ON u.id = p.id
    WHERE p.is_anonymous
      AND u.is_anonymous
      AND p.last_active_at < now() - interval '90 days'
    LIMIT 1000
  LOOP
    PERFORM public.detach_user_from_groups(r.id);
    DELETE FROM auth.users WHERE id = r.id;   -- cascades to profiles/attempts/etc.
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$;
REVOKE ALL ON FUNCTION public.purge_inactive_anonymous() FROM PUBLIC, anon, authenticated;
