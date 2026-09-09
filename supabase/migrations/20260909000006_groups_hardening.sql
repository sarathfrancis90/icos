-- Production hardening (6/9): groups.
--
-- * banned_words + contains_profanity(text) + sanitize_text(text) (server-side
--   Unicode sanitizer: NFKC, strip zero-width/control/combining abuse, collapse
--   whitespace, trim).
-- * member_count maintained by trigger on group_members (race-free), with the
--   50-member cap enforced in a BEFORE INSERT trigger under a row lock.
-- * All writes go through RPCs: create_group, update_group, remove_group_member,
--   transfer_group_admin, delete_group (soft), leave_group,
--   decrement_group_member_count (kept for old clients; now a resync no-op).
-- * Drop "Anyone can read group by invite code" (join goes through join-group).
-- * Fix the self-referential group_members SELECT policy (infinite recursion).
-- * group_feed table, members SELECT, realtime enabled.

-- ---------------------------------------------------------------------------
-- Profanity / sanitization
-- ---------------------------------------------------------------------------
CREATE TABLE public.banned_words (
  word TEXT PRIMARY KEY
);
ALTER TABLE public.banned_words ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.banned_words FROM anon, authenticated;

INSERT INTO public.banned_words (word) VALUES
  ('anal'), ('anus'), ('arse'), ('ass'), ('asshole'), ('bastard'), ('bitch'),
  ('blowjob'), ('bollocks'), ('boner'), ('boob'), ('boobs'), ('bugger'), ('bullshit'),
  ('chink'), ('clit'), ('cock'), ('coon'), ('cum'), ('cunt'), ('dick'), ('dildo'),
  ('dyke'), ('fag'), ('faggot'), ('fuck'), ('fucker'), ('fucking'), ('gook'),
  ('handjob'), ('hitler'), ('jerkoff'), ('jizz'), ('kike'), ('kkk'), ('motherfucker'),
  ('nazi'), ('nigga'), ('nigger'), ('paki'), ('penis'), ('piss'), ('porn'), ('prick'),
  ('pussy'), ('queef'), ('rape'), ('rapist'), ('retard'), ('scrotum'), ('sex'),
  ('shit'), ('shite'), ('slut'), ('smegma'), ('spic'), ('tit'), ('tits'), ('titties'),
  ('tranny'), ('twat'), ('vagina'), ('wank'), ('wanker'), ('whore'), ('wetback')
ON CONFLICT DO NOTHING;

-- sanitize_text: NFKC-normalize, strip zero-width / bidi / control characters and
-- stray combining marks (zalgo), collapse whitespace, trim. Case is preserved.
CREATE OR REPLACE FUNCTION public.sanitize_text(p_input TEXT)
RETURNS TEXT
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

-- contains_profanity: case-insensitive whole-word match after leetspeak folding.
CREATE OR REPLACE FUNCTION public.contains_profanity(p_input TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
STRICT
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_folded TEXT;
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

GRANT EXECUTE ON FUNCTION public.sanitize_text(TEXT) TO authenticated, anon;
REVOKE ALL ON FUNCTION public.contains_profanity(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.contains_profanity(TEXT) TO authenticated;

-- Validate a display/group name: returns the sanitized value or raises.
CREATE OR REPLACE FUNCTION public.validate_name(p_input TEXT, p_field TEXT DEFAULT 'name')
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $$
DECLARE
  v_clean TEXT;
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
GRANT EXECUTE ON FUNCTION public.validate_name(TEXT, TEXT) TO authenticated;

-- Display names are validated server-side too (client filter is advisory).
CREATE OR REPLACE FUNCTION public.validate_profile_display_name()
RETURNS TRIGGER
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
DROP TRIGGER IF EXISTS validate_profile_display_name ON public.profiles;
CREATE TRIGGER validate_profile_display_name
  BEFORE UPDATE OF display_name ON public.profiles
  FOR EACH ROW
  WHEN (pg_trigger_depth() = 0)
  EXECUTE FUNCTION public.validate_profile_display_name();

-- ---------------------------------------------------------------------------
-- member_count trigger + capacity enforcement
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.group_members_before_insert()
RETURNS TRIGGER
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
RETURNS TRIGGER
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

DROP TRIGGER IF EXISTS group_members_before_insert ON public.group_members;
CREATE TRIGGER group_members_before_insert
  BEFORE INSERT ON public.group_members
  FOR EACH ROW EXECUTE FUNCTION public.group_members_before_insert();

DROP TRIGGER IF EXISTS group_members_after_change ON public.group_members;
CREATE TRIGGER group_members_after_change
  AFTER INSERT OR DELETE ON public.group_members
  FOR EACH ROW EXECUTE FUNCTION public.group_members_after_change();

-- Resync any drift from the pre-trigger era.
UPDATE public.groups g
   SET member_count = sub.cnt
  FROM (SELECT group_id, count(*)::int AS cnt FROM public.group_members GROUP BY group_id) sub
 WHERE sub.group_id = g.id AND g.member_count <> sub.cnt;

-- ---------------------------------------------------------------------------
-- Policies: reads via helpers, writes only via RPCs / edge functions
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "Anyone can read group by invite code for joining" ON public.groups;
DROP POLICY IF EXISTS "Members can view their groups" ON public.groups;
DROP POLICY IF EXISTS "Authenticated users can create groups" ON public.groups;
DROP POLICY IF EXISTS "Admin can update their group" ON public.groups;
DROP POLICY IF EXISTS "Admin can delete their group" ON public.groups;

CREATE POLICY "Members can view their groups"
  ON public.groups FOR SELECT
  TO authenticated
  USING (public.is_group_member(id));

DROP POLICY IF EXISTS "Members can view group members" ON public.group_members;
DROP POLICY IF EXISTS "Users can join groups" ON public.group_members;
DROP POLICY IF EXISTS "Users can leave groups" ON public.group_members;
DROP POLICY IF EXISTS "Admin can remove members" ON public.group_members;
DROP POLICY IF EXISTS "Service role can manage group members" ON public.group_members;

CREATE POLICY "Members can view group members"
  ON public.group_members FOR SELECT
  TO authenticated
  USING (public.is_group_member(group_id));

-- ---------------------------------------------------------------------------
-- Group RPCs (all SECURITY DEFINER, search_path pinned, auth.uid() bound)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.generate_invite_code()
RETURNS TEXT
LANGUAGE plpgsql
VOLATILE
SET search_path = ''
AS $$
DECLARE
  v_chars TEXT := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; -- no 0/O/1/I ambiguity
  v_code  TEXT;
  v_i     INTEGER;
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
REVOKE ALL ON FUNCTION public.generate_invite_code() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.assert_active_user(p_user_id UUID)
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
REVOKE ALL ON FUNCTION public.assert_active_user(UUID) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.create_group(p_name TEXT, p_description TEXT DEFAULT '')
RETURNS public.groups
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid   UUID := (select auth.uid());
  v_name  TEXT;
  v_desc  TEXT;
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

CREATE OR REPLACE FUNCTION public.update_group(p_group_id UUID, p_name TEXT DEFAULT NULL, p_description TEXT DEFAULT NULL)
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
    RAISE EXCEPTION 'Only the group admin can edit the group'
      USING ERRCODE = '42501', HINT = 'NOT_ADMIN';
  END IF;

  IF p_name IS NOT NULL THEN
    v_group.name := public.validate_name(p_name, 'Group name');
  END IF;
  IF p_description IS NOT NULL THEN
    v_group.description := left(public.sanitize_text(p_description), 200);
    IF v_group.description <> '' AND public.contains_profanity(v_group.description) THEN
      RAISE EXCEPTION 'Description contains inappropriate language'
        USING ERRCODE = '22023', HINT = 'PROFANITY';
    END IF;
  END IF;

  UPDATE public.groups
     SET name = v_group.name, description = v_group.description
   WHERE id = p_group_id
  RETURNING * INTO v_group;
  RETURN v_group;
END;
$$;

CREATE OR REPLACE FUNCTION public.remove_group_member(p_group_id UUID, p_user_id UUID)
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

CREATE OR REPLACE FUNCTION public.transfer_group_admin(p_group_id UUID, p_new_admin_id UUID)
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

CREATE OR REPLACE FUNCTION public.delete_group(p_group_id UUID)
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
    RAISE EXCEPTION 'Only the group admin can delete the group'
      USING ERRCODE = '42501', HINT = 'NOT_ADMIN';
  END IF;

  UPDATE public.groups SET is_active = false WHERE id = p_group_id
  RETURNING * INTO v_group;
  RETURN v_group;
END;
$$;

CREATE OR REPLACE FUNCTION public.leave_group(p_group_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid       UUID := (select auth.uid());
  v_group     public.groups;
  v_new_admin UUID;
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

-- Backwards-compat shim for clients that still call this after a direct delete.
-- member_count is trigger-maintained now, so this just resyncs from the source of truth.
CREATE OR REPLACE FUNCTION public.decrement_group_member_count(p_group_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF (select auth.uid()) IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;
  UPDATE public.groups g
     SET member_count = (SELECT count(*)::int FROM public.group_members gm WHERE gm.group_id = g.id)
   WHERE g.id = p_group_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_group(TEXT, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.update_group(UUID, TEXT, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.remove_group_member(UUID, UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.transfer_group_admin(UUID, UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.delete_group(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.leave_group(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.decrement_group_member_count(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_group(TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_group(UUID, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.remove_group_member(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.transfer_group_admin(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_group(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.leave_group(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.decrement_group_member_count(UUID) TO authenticated;

-- ---------------------------------------------------------------------------
-- group_feed (activity feed, written by submit-score, realtime for members)
-- ---------------------------------------------------------------------------
CREATE TABLE public.group_feed (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  group_id    UUID NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  puzzle_date DATE NOT NULL,
  event       TEXT NOT NULL CHECK (event IN ('solved', 'solved_archive', 'joined', 'left')),
  payload     JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_group_feed_group_created ON public.group_feed (group_id, created_at DESC);
CREATE INDEX idx_group_feed_user_id ON public.group_feed (user_id);

ALTER TABLE public.group_feed ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Members can view group feed"
  ON public.group_feed FOR SELECT
  TO authenticated
  USING (public.is_group_member(group_id));

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.group_feed;
  END IF;
END;
$$;

-- Reports: reporter/reported FKs were unindexed.
CREATE INDEX IF NOT EXISTS idx_reports_reporter_id ON public.reports (reporter_id);
CREATE INDEX IF NOT EXISTS idx_reports_reported_user_id ON public.reports (reported_user_id);
CREATE INDEX IF NOT EXISTS idx_reports_reported_group_id ON public.reports (reported_group_id);
