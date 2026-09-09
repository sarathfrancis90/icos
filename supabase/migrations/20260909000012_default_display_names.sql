-- Polish: every profile gets a default display name ("Player 1234") so
-- leaderboards, member lists and feeds never show an empty name.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.profiles (id, is_anonymous, display_name)
  VALUES (
    NEW.id,
    NEW.is_anonymous,
    'Player ' || lpad((floor(random() * 10000))::int::text, 4, '0')
  );
  RETURN NEW;
END;
$$;

UPDATE public.profiles
   SET display_name = 'Player ' || lpad((floor(random() * 10000))::int::text, 4, '0')
 WHERE display_name = '' AND purged_at IS NULL;
