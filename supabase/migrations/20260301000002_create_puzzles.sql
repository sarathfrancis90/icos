-- Create puzzles table
CREATE TABLE public.puzzles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  puzzle_date DATE NOT NULL UNIQUE,
  grid_size INTEGER NOT NULL CHECK (grid_size BETWEEN 5 AND 8),
  waypoints JSONB NOT NULL,
  walls JSONB NOT NULL DEFAULT '[]'::jsonb,
  solution_hash TEXT NOT NULL,
  difficulty TEXT NOT NULL CHECK (difficulty IN ('easy', 'medium', 'hard', 'expert')),
  par_time_seconds INTEGER NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.puzzles ENABLE ROW LEVEL SECURITY;

-- Everyone can read puzzles (they are public)
CREATE POLICY "Puzzles are publicly readable"
  ON public.puzzles FOR SELECT
  USING (true);

-- Only service role can insert/update puzzles (Edge Functions)
CREATE POLICY "Service role can manage puzzles"
  ON public.puzzles FOR ALL
  USING (auth.role() = 'service_role');

-- Index for date-based lookups
CREATE INDEX idx_puzzles_puzzle_date ON public.puzzles(puzzle_date);
