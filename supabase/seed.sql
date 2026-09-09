-- Local/dev seed: app_config defaults only.
-- Production values are managed via the dashboard / service role; the same rows
-- are inserted idempotently by migration 20260909000007_app_config.sql.
INSERT INTO public.app_config (key, value) VALUES
  ('min_supported_version', '"1.0.0"'::jsonb),
  ('latest_version',        '"1.0.0"'::jsonb),
  ('maintenance_mode',      'false'::jsonb),
  ('store_urls',            '{}'::jsonb)
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
