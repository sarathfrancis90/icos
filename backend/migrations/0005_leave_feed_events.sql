-- Leaving or being removed from a group now writes a `left` feed event, so
-- the polled group feed (and the member count derived from it on clients)
-- reflects departures. Bodies are those of 0002_functions.sql plus one insert.

CREATE OR REPLACE FUNCTION public.remove_group_member(p_group_id uuid, p_user_id uuid)
RETURNS public.groups
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid   uuid := (select app.uid());
  v_group public.groups;
BEGIN
  PERFORM public.assert_active_user(v_uid);
  SELECT * INTO v_group FROM public.groups WHERE id = p_group_id FOR UPDATE;
  IF v_group.id IS NULL OR v_group.admin_id <> v_uid THEN
    RAISE EXCEPTION 'Only the group admin can remove members'
      USING ERRCODE = '42501', HINT = 'NOT_ADMIN';
  END IF;
  IF p_user_id = v_uid THEN
    RAISE EXCEPTION 'Admins must use leave_group or transfer_group_admin'
      USING ERRCODE = '22023', HINT = 'CANNOT_REMOVE_SELF';
  END IF;

  DELETE FROM public.group_members
   WHERE group_id = p_group_id AND user_id = p_user_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'User is not a member of this group'
      USING ERRCODE = 'P0002', HINT = 'NOT_A_MEMBER';
  END IF;

  INSERT INTO public.group_feed (group_id, user_id, puzzle_date, event, payload)
  VALUES (p_group_id, p_user_id, (now() AT TIME ZONE 'utc')::date, 'left', '{"removed": true}'::jsonb);

  SELECT * INTO v_group FROM public.groups WHERE id = p_group_id;
  RETURN v_group;
END;
$$;

CREATE OR REPLACE FUNCTION public.leave_group(p_group_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid       uuid := (select app.uid());
  v_group     public.groups;
  v_new_admin uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501', HINT = 'UNAUTHENTICATED';
  END IF;
  SELECT * INTO v_group FROM public.groups WHERE id = p_group_id FOR UPDATE;
  IF v_group.id IS NULL THEN
    RAISE EXCEPTION 'Group not found' USING ERRCODE = 'P0002', HINT = 'GROUP_NOT_FOUND';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.group_members WHERE group_id = p_group_id AND user_id = v_uid
  ) THEN
    RAISE EXCEPTION 'You are not a member of this group'
      USING ERRCODE = 'P0002', HINT = 'NOT_A_MEMBER';
  END IF;

  IF v_group.admin_id = v_uid THEN
    SELECT gm.user_id INTO v_new_admin
    FROM public.group_members gm
    WHERE gm.group_id = p_group_id AND gm.user_id <> v_uid
    ORDER BY gm.joined_at ASC, gm.id ASC
    LIMIT 1;

    IF v_new_admin IS NULL THEN
      UPDATE public.groups SET is_active = false WHERE id = p_group_id;
    ELSE
      UPDATE public.groups SET admin_id = v_new_admin WHERE id = p_group_id;
      UPDATE public.group_members SET role = 'admin'
       WHERE group_id = p_group_id AND user_id = v_new_admin;
    END IF;
  END IF;

  DELETE FROM public.group_members WHERE group_id = p_group_id AND user_id = v_uid;

  INSERT INTO public.group_feed (group_id, user_id, puzzle_date, event, payload)
  VALUES (p_group_id, v_uid, (now() AT TIME ZONE 'utc')::date, 'left', '{}'::jsonb);
END;
$$;

REVOKE ALL ON FUNCTION
  public.remove_group_member(uuid, uuid),
  public.leave_group(uuid)
FROM PUBLIC, authenticated, anonymous;

GRANT EXECUTE ON FUNCTION
  public.remove_group_member(uuid, uuid),
  public.leave_group(uuid)
TO authenticated;
