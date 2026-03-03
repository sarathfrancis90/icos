-- Daily leaderboard for a group
CREATE OR REPLACE FUNCTION public.get_group_daily_leaderboard(
  p_group_id UUID,
  p_puzzle_date DATE
)
RETURNS TABLE (
  user_id UUID,
  display_name TEXT,
  avatar_url TEXT,
  time_seconds INTEGER,
  hints_used INTEGER,
  undos_used INTEGER,
  completed BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Verify caller is a member of the group
  IF NOT EXISTS (
    SELECT 1 FROM public.group_members gm
    WHERE gm.group_id = p_group_id
    AND gm.user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Not a member of this group';
  END IF;

  RETURN QUERY
  SELECT
    pa.user_id,
    COALESCE(p.display_name, 'Anonymous') as display_name,
    p.avatar_url,
    pa.time_seconds,
    pa.hints_used,
    pa.undos_used,
    pa.completed
  FROM public.puzzle_attempts pa
  JOIN public.group_members gm ON gm.user_id = pa.user_id AND gm.group_id = p_group_id
  JOIN public.profiles p ON p.id = pa.user_id
  WHERE pa.puzzle_date = p_puzzle_date
  AND pa.completed = true
  ORDER BY pa.hints_used ASC, pa.time_seconds ASC, pa.undos_used ASC;
END;
$$;

-- Weekly leaderboard for a group
CREATE OR REPLACE FUNCTION public.get_group_weekly_leaderboard(
  p_group_id UUID,
  p_week_start DATE
)
RETURNS TABLE (
  user_id UUID,
  display_name TEXT,
  avatar_url TEXT,
  completed_count BIGINT,
  avg_time_seconds NUMERIC,
  total_hints BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_week_end DATE;
BEGIN
  -- Verify caller is a member of the group
  IF NOT EXISTS (
    SELECT 1 FROM public.group_members gm
    WHERE gm.group_id = p_group_id
    AND gm.user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Not a member of this group';
  END IF;

  v_week_end := p_week_start + INTERVAL '6 days';

  RETURN QUERY
  SELECT
    pa.user_id,
    COALESCE(p.display_name, 'Anonymous') as display_name,
    p.avatar_url,
    COUNT(*) FILTER (WHERE pa.completed = true) as completed_count,
    AVG(pa.time_seconds) FILTER (WHERE pa.completed = true) as avg_time_seconds,
    SUM(pa.hints_used) as total_hints
  FROM public.puzzle_attempts pa
  JOIN public.group_members gm ON gm.user_id = pa.user_id AND gm.group_id = p_group_id
  JOIN public.profiles p ON p.id = pa.user_id
  WHERE pa.puzzle_date BETWEEN p_week_start AND v_week_end
  GROUP BY pa.user_id, p.display_name, p.avatar_url
  ORDER BY completed_count DESC, avg_time_seconds ASC;
END;
$$;

-- Enable anonymous auth
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
