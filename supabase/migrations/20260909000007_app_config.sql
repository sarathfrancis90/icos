-- Production hardening (7/9): app_config — public key/value used by the client
-- for force-update and maintenance gates. Written only by the service role.

CREATE TABLE public.app_config (
  key        TEXT PRIMARY KEY,
  value      JSONB NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.app_config ENABLE ROW LEVEL SECURITY;

CREATE POLICY "App config is publicly readable"
  ON public.app_config FOR SELECT
  TO anon, authenticated
  USING (true);

DROP TRIGGER IF EXISTS update_app_config_updated_at ON public.app_config;
CREATE TRIGGER update_app_config_updated_at
  BEFORE UPDATE ON public.app_config
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

-- Defaults (idempotent so prod gets them too; supabase/seed.sql re-asserts locally).
INSERT INTO public.app_config (key, value) VALUES
  ('min_supported_version', '"1.0.0"'::jsonb),
  ('latest_version',        '"1.0.0"'::jsonb),
  ('maintenance_mode',      'false'::jsonb),
  ('store_urls',            '{}'::jsonb)
ON CONFLICT (key) DO NOTHING;
