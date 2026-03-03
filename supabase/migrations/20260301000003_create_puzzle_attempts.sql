-- Create puzzle_attempts table
CREATE TABLE public.puzzle_attempts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  puzzle_id UUID NOT NULL REFERENCES public.puzzles(id) ON DELETE CASCADE,
  puzzle_date DATE NOT NULL,
  time_seconds INTEGER NOT NULL,
  hints_used INTEGER NOT NULL DEFAULT 0,
  undos_used INTEGER NOT NULL DEFAULT 0,
  completed BOOLEAN NOT NULL DEFAULT false,
  path JSONB NOT NULL DEFAULT '[]'::jsonb,
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- Enforce one completed attempt per user per day
  CONSTRAINT unique_completed_attempt UNIQUE (user_id, puzzle_date)
);

-- Enable RLS
ALTER TABLE public.puzzle_attempts ENABLE ROW LEVEL SECURITY;

-- Users can view their own attempts
CREATE POLICY "Users can view their own attempts"
  ON public.puzzle_attempts FOR SELECT
  USING (auth.uid() = user_id);

-- Users can insert their own attempts
CREATE POLICY "Users can insert their own attempts"
  ON public.puzzle_attempts FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Service role can manage all attempts (for Edge Functions)
CREATE POLICY "Service role can manage attempts"
  ON public.puzzle_attempts FOR ALL
  USING (auth.role() = 'service_role');

-- Indexes
CREATE INDEX idx_puzzle_attempts_user_id ON public.puzzle_attempts(user_id);
CREATE INDEX idx_puzzle_attempts_puzzle_date ON public.puzzle_attempts(puzzle_date);
CREATE INDEX idx_puzzle_attempts_user_date ON public.puzzle_attempts(user_id, puzzle_date);
