-- Create streaks table
CREATE TABLE public.streaks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  current_streak INTEGER NOT NULL DEFAULT 0,
  longest_streak INTEGER NOT NULL DEFAULT 0,
  freeze_count INTEGER NOT NULL DEFAULT 1,
  last_solve_date DATE,
  last_freeze_used_at DATE,
  freeze_reset_week_start DATE,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.streaks ENABLE ROW LEVEL SECURITY;

-- Users can view their own streak
CREATE POLICY "Users can view their own streak"
  ON public.streaks FOR SELECT
  USING (auth.uid() = user_id);

-- Service role manages streaks (Edge Functions)
CREATE POLICY "Service role can manage streaks"
  ON public.streaks FOR ALL
  USING (auth.role() = 'service_role');

-- Users can insert their own streak (initial creation)
CREATE POLICY "Users can insert their own streak"
  ON public.streaks FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Index
CREATE INDEX idx_streaks_user_id ON public.streaks(user_id);

-- Auto-update updated_at
CREATE TRIGGER update_streaks_updated_at
  BEFORE UPDATE ON public.streaks
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at();
