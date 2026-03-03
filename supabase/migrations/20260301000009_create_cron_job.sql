-- Enable pg_cron and pg_net extensions for scheduled Edge Function calls
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- Create a helper function to generate the daily puzzle
CREATE OR REPLACE FUNCTION public.trigger_daily_puzzle_generation()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  _project_url text := 'https://uorwefbvqdmslqhmpnun.supabase.co';
  _service_key text;
BEGIN
  -- Read service role key from vault (must be stored there first)
  SELECT decrypted_secret INTO _service_key
  FROM vault.decrypted_secrets
  WHERE name = 'service_role_key'
  LIMIT 1;

  -- If no vault secret, skip silently
  IF _service_key IS NULL THEN
    RAISE NOTICE 'No service_role_key found in vault, skipping puzzle generation';
    RETURN;
  END IF;

  -- Call the daily-puzzle Edge Function
  PERFORM net.http_post(
    url := _project_url || '/functions/v1/daily-puzzle',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || _service_key
    ),
    body := '{}'::jsonb
  );
END;
$$;

-- Schedule daily puzzle generation at 23:00 UTC (generates next day's puzzle)
SELECT cron.schedule(
  'generate-daily-puzzle',
  '0 23 * * *',
  'SELECT public.trigger_daily_puzzle_generation()'
);
