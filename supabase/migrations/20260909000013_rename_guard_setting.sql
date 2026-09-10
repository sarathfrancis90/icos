-- Rebrand: the transaction-local guard setting is now icos.profile_guard_bypass.
CREATE OR REPLACE FUNCTION public.protect_profile_columns()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF current_setting('icos.profile_guard_bypass', true) = 'on' THEN
    RETURN NEW;
  END IF;
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
