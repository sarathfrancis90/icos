-- Production hardening (4/9): per-play sessions (HMAC nonce + server start time)
-- and a lightweight submission log used for rate limiting.
-- Both tables are service-role only (RLS enabled, no client policies).

CREATE TABLE public.puzzle_sessions (
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  puzzle_date DATE NOT NULL,
  started_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  nonce       TEXT NOT NULL,
  PRIMARY KEY (user_id, puzzle_date)
);
CREATE INDEX idx_puzzle_sessions_started_at ON public.puzzle_sessions (started_at);
ALTER TABLE public.puzzle_sessions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.puzzle_sessions FROM anon, authenticated;

CREATE TABLE public.submission_log (
  id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_submission_log_user_created ON public.submission_log (user_id, created_at);
ALTER TABLE public.submission_log ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.submission_log FROM anon, authenticated;

-- Housekeeping: drop log rows older than 1 day (keeps the table tiny).
CREATE OR REPLACE FUNCTION public.prune_submission_log()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_count INTEGER;
BEGIN
  DELETE FROM public.submission_log WHERE created_at < now() - interval '1 day';
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;
REVOKE ALL ON FUNCTION public.prune_submission_log() FROM PUBLIC, anon, authenticated;
