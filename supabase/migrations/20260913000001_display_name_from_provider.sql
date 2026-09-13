-- Use the name the identity provider gave us, instead of "Player 1234".
--
-- Two paths reach a profile and both were ignoring provider metadata:
--   * a brand new user signing up with Google/Apple/email (INSERT on auth.users)
--   * a guest linking an identity, which is how almost every real account is
--     created in this app (UPDATE on auth.users, raw_user_meta_data fills in)
--
-- Apple only returns a name on the very first authorisation, and not always, so
-- every branch still falls back rather than leaving a profile nameless.

-- Best display name we can derive from a user row, or NULL if there is none.
CREATE OR REPLACE FUNCTION public.provider_display_name(
  p_meta JSONB,
  p_email TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
DECLARE
  v_name TEXT;
BEGIN
  -- Google sends full_name and name; Apple sends full_name when it sends
  -- anything; some providers only send given/family separately.
  v_name := COALESCE(
    NULLIF(TRIM(p_meta->>'full_name'), ''),
    NULLIF(TRIM(p_meta->>'name'), ''),
    NULLIF(TRIM(CONCAT_WS(' ', p_meta->>'given_name', p_meta->>'family_name')), ''),
    NULLIF(TRIM(p_meta->>'preferred_username'), '')
  );

  -- Fall back to the local part of the email, tidied up: "ada.lovelace" reads
  -- better as "Ada Lovelace" on a leaderboard.
  IF v_name IS NULL AND p_email IS NOT NULL AND POSITION('@' IN p_email) > 1 THEN
    v_name := INITCAP(
      REGEXP_REPLACE(SPLIT_PART(p_email, '@', 1), '[._\-+]+', ' ', 'g')
    );
    v_name := NULLIF(TRIM(REGEXP_REPLACE(v_name, '\s+', ' ', 'g')), '');
  END IF;

  IF v_name IS NULL THEN
    RETURN NULL;
  END IF;

  -- display_name is capped at 30 elsewhere; keep this in step.
  RETURN LEFT(v_name, 30);
END;
$$;

-- A name this app assigned because it had nothing better, so it is safe to
-- replace later. A name the player chose is never overwritten.
CREATE OR REPLACE FUNCTION public.is_placeholder_display_name(p_name TEXT)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT p_name IS NULL
      OR TRIM(p_name) = ''
      OR p_name ~ '^Player [0-9]{4}$';
$$;

-- ---------------------------------------------------------------------------
-- New user: take the provider's name when there is one.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_name TEXT;
BEGIN
  v_name := public.provider_display_name(NEW.raw_user_meta_data, NEW.email);

  INSERT INTO public.profiles (id, is_anonymous, display_name)
  VALUES (
    NEW.id,
    NEW.is_anonymous,
    COALESCE(
      v_name,
      'Player ' || lpad((floor(random() * 10000))::int::text, 4, '0')
    )
  );
  RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- Guest links an identity: fill the name in, but only over a placeholder.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_user_updated()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_name TEXT;
BEGIN
  IF NEW.is_anonymous IS DISTINCT FROM OLD.is_anonymous THEN
    UPDATE public.profiles
       SET is_anonymous = NEW.is_anonymous
     WHERE id = NEW.id;
  END IF;

  IF NEW.raw_user_meta_data IS DISTINCT FROM OLD.raw_user_meta_data
     OR NEW.email IS DISTINCT FROM OLD.email THEN
    v_name := public.provider_display_name(NEW.raw_user_meta_data, NEW.email);
    IF v_name IS NOT NULL THEN
      UPDATE public.profiles
         SET display_name = v_name
       WHERE id = NEW.id
         AND public.is_placeholder_display_name(display_name);
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- The old trigger only fired on is_anonymous, so a link that carried a name but
-- left is_anonymous alone never reached the function. Listing the columns
-- rather than plain AFTER UPDATE keeps it off the hot path: auth.users is
-- written on every sign-in to bump last_sign_in_at.
DROP TRIGGER IF EXISTS on_auth_user_updated ON auth.users;
CREATE TRIGGER on_auth_user_updated
  AFTER UPDATE OF is_anonymous, raw_user_meta_data, email ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_user_updated();

-- ---------------------------------------------------------------------------
-- Backfill: anyone already signed in with a provider but still showing a
-- placeholder.
-- ---------------------------------------------------------------------------
UPDATE public.profiles p
   SET display_name = public.provider_display_name(u.raw_user_meta_data, u.email)
  FROM auth.users u
 WHERE u.id = p.id
   AND p.purged_at IS NULL
   AND public.is_placeholder_display_name(p.display_name)
   AND public.provider_display_name(u.raw_user_meta_data, u.email) IS NOT NULL;
