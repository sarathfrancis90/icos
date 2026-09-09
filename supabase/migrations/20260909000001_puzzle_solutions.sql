-- Production hardening (1/9): move puzzle solutions out of the public puzzles row.
--
-- Before: puzzles.solution_hash was readable by everyone (SELECT USING (true)).
-- After:  solutions live in puzzle_solutions, which has RLS enabled and NO client
--         policies at all — only the service role (edge functions) can touch it.

CREATE TABLE public.puzzle_solutions (
  puzzle_id  UUID PRIMARY KEY REFERENCES public.puzzles(id) ON DELETE CASCADE,
  path       JSONB NOT NULL,            -- [[row, col], ...] reference solution
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.puzzle_solutions ENABLE ROW LEVEL SECURITY;
-- Intentionally no policies: anon/authenticated get zero rows. Service role bypasses RLS.
REVOKE ALL ON public.puzzle_solutions FROM anon, authenticated;

-- Puzzle metadata for the v2 generator (deterministic seed + measured difficulty).
ALTER TABLE public.puzzles
  DROP COLUMN IF EXISTS solution_hash,
  ADD COLUMN IF NOT EXISTS difficulty_score INTEGER,
  ADD COLUMN IF NOT EXISTS seed_version INTEGER NOT NULL DEFAULT 2;

COMMENT ON COLUMN public.puzzles.difficulty_score IS
  'Solver nodes expanded to find the first solution (analytics only).';
COMMENT ON COLUMN public.puzzles.seed_version IS
  'Generator version that produced this puzzle. 2 = deterministic seedFor(date, salt).';

-- The old "Service role can manage puzzles" policy used auth.role() which is
-- evaluated per row; service role bypasses RLS anyway, so the policy is redundant.
DROP POLICY IF EXISTS "Service role can manage puzzles" ON public.puzzles;
