-- Column-level privileges for client roles.
--   * profiles: 0001 granted SELECT/UPDATE on the whole table, and the
--     "Co-members can view profiles" policy then let any co-member read
--     email, email_verified and providers through the Data API. Clients now
--     get exactly the columns the app reads and writes; the Function (owner)
--     is unaffected. protect_profile_columns stays as defence in depth.
--   * reports: filed only through POST /api/report (sanitised, capped,
--     rate-limited), never by a direct Data API insert.
--   * group_feed: feed polling filters group_id = X AND id > N.

REVOKE SELECT, UPDATE ON public.profiles FROM authenticated;
GRANT SELECT (id, display_name, avatar_url, is_anonymous, is_banned, colorblind_mode, theme_mode,
              haptic_enabled, sound_enabled, notification_enabled, deleted_at, purged_at, created_at, updated_at)
  ON public.profiles TO authenticated;
GRANT UPDATE (display_name, avatar_url, colorblind_mode, theme_mode, haptic_enabled, sound_enabled,
              notification_enabled, updated_at)
  ON public.profiles TO authenticated;
-- Reports are filed only through POST /api/report (sanitised, capped, rate-limited).
REVOKE INSERT ON public.reports FROM authenticated;
-- Feed polling filters group_id = X AND id > N.
CREATE INDEX IF NOT EXISTS group_feed_group_id_id_idx ON public.group_feed (group_id, id);
