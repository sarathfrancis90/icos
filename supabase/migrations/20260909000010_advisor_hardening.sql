-- Production hardening (10): Supabase security-advisor follow-ups.
-- * Trigger functions must not be callable through PostgREST RPC.
-- * update_updated_at gets a pinned search_path.

REVOKE ALL ON FUNCTION public.group_members_after_change() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.group_members_before_insert() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.handle_user_updated() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.protect_profile_columns() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.validate_profile_display_name() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.update_updated_at() FROM PUBLIC, anon, authenticated;

ALTER FUNCTION public.update_updated_at() SET search_path = '';
