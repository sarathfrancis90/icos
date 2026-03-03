-- Cross-table RLS policies that depend on group_members existing
-- These reference public.group_members, so must run after migration 5

-- Users in same groups can see each other's puzzle attempts (for leaderboard)
CREATE POLICY "Group members can view each other's attempts"
  ON public.puzzle_attempts FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.group_members gm1
      JOIN public.group_members gm2 ON gm1.group_id = gm2.group_id
      WHERE gm1.user_id = auth.uid()
      AND gm2.user_id = puzzle_attempts.user_id
    )
  );

-- Users in groups can see each other's streaks
CREATE POLICY "Group members can view streaks"
  ON public.streaks FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.group_members gm1
      JOIN public.group_members gm2 ON gm1.group_id = gm2.group_id
      WHERE gm1.user_id = auth.uid()
      AND gm2.user_id = streaks.user_id
    )
  );
