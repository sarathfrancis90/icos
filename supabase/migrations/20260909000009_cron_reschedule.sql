-- Production hardening (9/9): scheduled jobs.
--
-- trigger_daily_puzzle_generation() now reads BOTH the project URL and the
-- service-role key from Vault (names: project_url, service_role_key) and asks
-- the daily-puzzle function for D+1 and D+2 so a missed run never leaves a day
-- without a puzzle (clients can also generate on demand).
--
-- Schedule (all UTC):
--   00:00 Mon  reset_weekly_freezes()
--   00:05      apply_streak_freezes()
--   00:15      trigger_daily_puzzle_generation()
--   01:00      purge_deleted_accounts()
--   01:30      purge_inactive_anonymous()
--   02:00      prune_submission_log()

CREATE OR REPLACE FUNCTION public.trigger_daily_puzzle_generation()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  _project_url text;
  _service_key text;
  _offset      integer;
  _date        text;
BEGIN
  SELECT decrypted_secret INTO _project_url
  FROM vault.decrypted_secrets WHERE name = 'project_url' LIMIT 1;

  SELECT decrypted_secret INTO _service_key
  FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;

  IF _project_url IS NULL OR _service_key IS NULL THEN
    RAISE WARNING 'trigger_daily_puzzle_generation: vault secrets project_url/service_role_key missing; skipping';
    RETURN;
  END IF;

  _project_url := rtrim(_project_url, '/');

  FOR _offset IN 1..2 LOOP
    _date := to_char((now() AT TIME ZONE 'utc')::date + _offset, 'YYYY-MM-DD');
    PERFORM net.http_post(
      url     := _project_url || '/functions/v1/daily-puzzle',
      headers := jsonb_build_object(
        'Content-Type',     'application/json',
        'Authorization',    'Bearer ' || _service_key,
        'x-correlation-id', 'cron-' || _date
      ),
      body    := jsonb_build_object('date', _date),
      timeout_milliseconds := 30000
    );
  END LOOP;
END;
$$;
REVOKE ALL ON FUNCTION public.trigger_daily_puzzle_generation() FROM PUBLIC, anon, authenticated;

-- Replace the old 23:00 job and register the full schedule (idempotent).
DO $$
DECLARE
  j RECORD;
BEGIN
  FOR j IN
    SELECT jobid FROM cron.job
    WHERE jobname IN (
      'generate-daily-puzzle', 'reset-weekly-freezes', 'apply-streak-freezes',
      'purge-deleted-accounts', 'purge-inactive-anonymous', 'prune-submission-log'
    )
  LOOP
    PERFORM cron.unschedule(j.jobid);
  END LOOP;
END;
$$;

SELECT cron.schedule('reset-weekly-freezes',      '0 0 * * 1',  'SELECT public.reset_weekly_freezes()');
SELECT cron.schedule('apply-streak-freezes',      '5 0 * * *',  'SELECT public.apply_streak_freezes()');
SELECT cron.schedule('generate-daily-puzzle',     '15 0 * * *', 'SELECT public.trigger_daily_puzzle_generation()');
SELECT cron.schedule('purge-deleted-accounts',    '0 1 * * *',  'SELECT public.purge_deleted_accounts()');
SELECT cron.schedule('purge-inactive-anonymous',  '30 1 * * *', 'SELECT public.purge_inactive_anonymous()');
SELECT cron.schedule('prune-submission-log',      '0 2 * * *',  'SELECT public.prune_submission_log()');
