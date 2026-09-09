-- Production hardening (2/9): puzzle_attempts is written ONLY by submit-score.
--
-- * Clients can no longer INSERT attempts directly (score must be server-verified).
-- * The blanket UNIQUE(user_id, puzzle_date) blocked retries after a failed
--   submission; replace it with a partial unique index on completed rows only.
-- * Cross-member SELECT policy dropped: leaderboards go through SECURITY DEFINER RPCs.
-- * New columns: verified, is_archive, attempt_count, updated_at.

ALTER TABLE public.puzzle_attempts
  DROP CONSTRAINT IF EXISTS unique_completed_attempt;

ALTER TABLE public.puzzle_attempts
  ADD COLUMN IF NOT EXISTS verified      BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS is_archive    BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS attempt_count INTEGER NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS updated_at    TIMESTAMPTZ NOT NULL DEFAULT now();

COMMENT ON COLUMN public.puzzle_attempts.verified IS
  'true when the submission carried a valid HMAC signature bound to a puzzle_sessions nonce.';
COMMENT ON COLUMN public.puzzle_attempts.is_archive IS
  'true when the puzzle was solved after its UTC day ended; never affects streaks or leaderboards.';

-- One COMPLETED attempt per user per day; incomplete attempts may be retried/updated.
CREATE UNIQUE INDEX IF NOT EXISTS puzzle_attempts_one_completed_per_day
  ON public.puzzle_attempts (user_id, puzzle_date)
  WHERE completed;

-- Leaderboard lookups: by date, completed, live only.
CREATE INDEX IF NOT EXISTS idx_puzzle_attempts_date_live
  ON public.puzzle_attempts (puzzle_date, hints_used, time_seconds, undos_used)
  WHERE completed AND NOT is_archive;

CREATE INDEX IF NOT EXISTS idx_puzzle_attempts_puzzle_id
  ON public.puzzle_attempts (puzzle_id);

DROP TRIGGER IF EXISTS update_puzzle_attempts_updated_at ON public.puzzle_attempts;
CREATE TRIGGER update_puzzle_attempts_updated_at
  BEFORE UPDATE ON public.puzzle_attempts
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at();

-- Policies -----------------------------------------------------------------
DROP POLICY IF EXISTS "Users can insert their own attempts" ON public.puzzle_attempts;
DROP POLICY IF EXISTS "Group members can view each other's attempts" ON public.puzzle_attempts;
DROP POLICY IF EXISTS "Service role can manage attempts" ON public.puzzle_attempts;

-- Recreate the own-rows SELECT policy with (select auth.uid()) so the planner
-- evaluates it once per query instead of once per row.
DROP POLICY IF EXISTS "Users can view their own attempts" ON public.puzzle_attempts;
CREATE POLICY "Users can view their own attempts"
  ON public.puzzle_attempts FOR SELECT
  TO authenticated
  USING ((select auth.uid()) = user_id);
