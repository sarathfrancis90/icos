-- Production hardening (11): PostgREST resource embedding needs a foreign key
-- between the joined tables. group_members / group_feed / puzzle_attempts /
-- groups referenced auth.users only, so `select('*, profiles(display_name)')`
-- failed with PGRST200. profiles.id mirrors auth.users.id, so a second FK is safe.
ALTER TABLE public.group_members
  ADD CONSTRAINT group_members_user_id_profiles_fkey
  FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

ALTER TABLE public.group_feed
  ADD CONSTRAINT group_feed_user_id_profiles_fkey
  FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

ALTER TABLE public.puzzle_attempts
  ADD CONSTRAINT puzzle_attempts_user_id_profiles_fkey
  FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

ALTER TABLE public.groups
  ADD CONSTRAINT groups_admin_id_profiles_fkey
  FOREIGN KEY (admin_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

NOTIFY pgrst, 'reload schema';
