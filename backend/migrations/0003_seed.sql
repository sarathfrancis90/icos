-- 0003_seed: reference data. Idempotent.

-- Force-update / maintenance gates and store links read by the client.
INSERT INTO public.app_config (key, value) VALUES
  ('min_supported_version', '"1.1.0"'::jsonb),
  ('latest_version',        '"1.1.0"'::jsonb),
  ('maintenance_mode',      'false'::jsonb),
  ('store_urls',            '{"ios":"https://apps.apple.com/app/id6810895361","android":"https://play.google.com/store/apps/details?id=com.icos.game"}'::jsonb)
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

-- Profanity list used by contains_profanity() (copied from
-- supabase/migrations/20260909000006_groups_hardening.sql).
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
