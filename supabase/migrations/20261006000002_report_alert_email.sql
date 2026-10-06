-- Email the owner when a report is filed, so the 24-hour review promise in the
-- Terms can be kept. Uses Resend over HTTPS via pg_net; the API key lives in
-- Vault under the name `resend_api_key`. If the secret is missing the trigger
-- logs a warning and the insert still succeeds.

CREATE OR REPLACE FUNCTION public.notify_report_filed()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  _key   text;
  _label text;
BEGIN
  SELECT decrypted_secret INTO _key
  FROM vault.decrypted_secrets WHERE name = 'resend_api_key' LIMIT 1;

  IF _key IS NULL THEN
    RAISE WARNING 'notify_report_filed: vault secret resend_api_key missing; report % not emailed', NEW.id;
    RETURN NEW;
  END IF;

  _label := CASE
    WHEN NEW.reported_group_id IS NOT NULL THEN 'group ' || NEW.reported_group_id::text
    WHEN NEW.reported_user_id IS NOT NULL THEN 'user ' || NEW.reported_user_id::text
    ELSE 'unknown target'
  END;

  PERFORM net.http_post(
    url     := 'https://api.resend.com/emails',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || _key
    ),
    body    := jsonb_build_object(
      'from',    'Icos <noreply@icos.sarathfrancis.work>',
      'to',      jsonb_build_array('sarathfrancis90@gmail.com'),
      'subject', 'Icos report: ' || NEW.reason || ' (' || _label || ')',
      'text',    'A report was filed in Icos.' || E'\n\n'
               || 'Report id: '   || NEW.id::text || E'\n'
               || 'Reason: '      || NEW.reason || E'\n'
               || 'Target: '      || _label || E'\n'
               || 'Reporter: '    || NEW.reporter_id::text || E'\n'
               || 'Details: '     || COALESCE(NULLIF(NEW.details, ''), '(none)') || E'\n'
               || 'Filed at: '    || to_char(NEW.created_at AT TIME ZONE 'utc', 'YYYY-MM-DD HH24:MI') || ' UTC' || E'\n\n'
               || 'Review within 24 hours: Supabase > Table Editor > reports, then set status.'
    ),
    timeout_milliseconds := 10000
  );
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.notify_report_filed() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS on_report_filed ON public.reports;
CREATE TRIGGER on_report_filed
  AFTER INSERT ON public.reports
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_report_filed();
