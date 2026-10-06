-- Never show the random half of an Apple "Hide My Email" address as a name.
--
-- Signing in with Apple and hiding the email gives an address such as
-- k3x9q2@privaterelay.appleid.com. Apple only sends the user's name on the very
-- first authorisation, so when it is missing provider_display_name fell back to
-- the local part and the profile showed random letters ("K3x9q2").
--
-- For a relay address there is no name to derive: return NULL so the caller's
-- "Player NNNN" placeholder applies, and the app asks the player to choose one.
-- Everything else is unchanged from 20260913000001_display_name_from_provider.

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
  v_name := COALESCE(
    NULLIF(TRIM(p_meta->>'full_name'), ''),
    NULLIF(TRIM(p_meta->>'name'), ''),
    NULLIF(TRIM(CONCAT_WS(' ', p_meta->>'given_name', p_meta->>'family_name')), ''),
    NULLIF(TRIM(p_meta->>'preferred_username'), '')
  );

  -- Fall back to the local part of the email, tidied up, unless the address is
  -- an Apple relay: its local part is random by construction (this covers the
  -- 6+ character lowercase/digit strings Apple generates).
  IF v_name IS NULL
     AND p_email IS NOT NULL
     AND POSITION('@' IN p_email) > 1
     AND LOWER(SPLIT_PART(p_email, '@', 2)) <> 'privaterelay.appleid.com' THEN
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

-- ---------------------------------------------------------------------------
-- Backfill: only profiles of signed-in (non-guest) Apple relay users whose
-- name is exactly what the previous function derived from the relay local
-- part. Nothing else is touched.
-- ---------------------------------------------------------------------------
UPDATE public.profiles p
   SET display_name = 'Player ' || lpad((floor(random() * 10000))::int::text, 4, '0')
  FROM auth.users u
 WHERE u.id = p.id
   AND p.purged_at IS NULL
   AND u.is_anonymous IS NOT TRUE
   AND u.email IS NOT NULL
   AND LOWER(SPLIT_PART(u.email, '@', 2)) = 'privaterelay.appleid.com'
   AND public.provider_display_name(u.raw_user_meta_data, u.email) IS NULL
   AND p.display_name = LEFT(
         NULLIF(TRIM(REGEXP_REPLACE(
           INITCAP(REGEXP_REPLACE(SPLIT_PART(u.email, '@', 1), '[._\-+]+', ' ', 'g')),
           '\s+', ' ', 'g')), ''),
         30);
