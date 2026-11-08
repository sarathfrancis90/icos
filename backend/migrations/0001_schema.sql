-- 0001_schema: the Icos application schema on Neon.
--
-- Consolidated from supabase/migrations/* (last definition of each object wins),
-- with the identity change of the Neon migration design (spec §5.2):
--   * public.profiles(id) is the root identity. Every former reference to
--     auth.users(id) points at profiles(id) ON DELETE CASCADE ON UPDATE CASCADE
--     (a guest's profile id is re-keyed to the account it upgrades to).
--   * profiles gains email, email_verified, providers; puzzles.seed_version = 3.
--   * No Supabase-only objects: no auth.users, vault, pg_net, pg_cron,
--     realtime publication, service_role or auth.role() policies.
--
-- Roles: `authenticated` and `anonymous` are the Neon Data API roles. The
-- Function connects as the database owner, which bypasses RLS (it replaces
-- Supabase's service role). Objects in schema `auth` belong to Neon
-- (pg_session_jwt); nothing here creates objects there.
--
-- SQL functions and the remaining triggers (validate_profile_display_name,
-- group_members_before_insert / _after_change) are in 0002_functions.sql.

-- ---------------------------------------------------------------------------
-- Schema app: request identity helpers
-- ---------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS app;
REVOKE ALL ON SCHEMA app FROM PUBLIC;
GRANT USAGE ON SCHEMA app TO authenticated, anonymous;

-- The caller's user id, or NULL.
--   1. pg_session_jwt's auth.user_id(), when installed and the current role may
--      use schema auth (Neon does not grant USAGE on it to the Data API roles).
--   2. Otherwise the `sub` claim of request.jwt.claims (set per request by the
--      Data API; also what auth.user_id() falls back to without a JWT session).
-- Any error (malformed claims, non-uuid sub) yields NULL.
CREATE OR REPLACE FUNCTION app.uid()
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_text text;
BEGIN
  -- Nested on purpose: to_regprocedure() raises without USAGE on the schema,
  -- and has_schema_privilege() raises when the schema does not exist.
  IF to_regnamespace('auth') IS NOT NULL THEN
    IF has_schema_privilege('auth', 'USAGE') THEN
      IF to_regprocedure('auth.user_id()') IS NOT NULL THEN
        EXECUTE 'SELECT auth.user_id()' INTO v_text;
      END IF;
    END IF;
  END IF;
  IF nullif(v_text, '') IS NULL THEN
    v_text := nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub';
  END IF;
  RETURN nullif(v_text, '')::uuid;
EXCEPTION WHEN OTHERS THEN
  RETURN NULL;
END;
$$;

-- true for the owner / Function connection, false for Data API clients.
CREATE OR REPLACE FUNCTION app.is_service()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT current_user NOT IN ('authenticated', 'anonymous');
$$;

REVOKE ALL ON FUNCTION app.uid() FROM PUBLIC;
REVOKE ALL ON FUNCTION app.is_service() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app.uid() TO authenticated, anonymous;
GRANT EXECUTE ON FUNCTION app.is_service() TO authenticated, anonymous;

-- ---------------------------------------------------------------------------
-- Trigger functions with no dependencies
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- Clients may not change moderation, lifecycle or identity columns; every
-- client update bumps last_active_at. SECURITY DEFINER RPCs that must write the
-- guarded columns on the caller's behalf set icos.profile_guard_bypass = 'on'
-- (transaction-local).
CREATE OR REPLACE FUNCTION public.protect_profile_columns()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF current_setting('icos.profile_guard_bypass', true) = 'on' THEN
    RETURN NEW;
  END IF;
  IF current_user IN ('authenticated', 'anonymous') THEN
    NEW.is_banned      := OLD.is_banned;
    NEW.deleted_at     := OLD.deleted_at;
    NEW.purged_at      := OLD.purged_at;
    NEW.is_anonymous   := OLD.is_anonymous;
    NEW.email          := OLD.email;
    NEW.email_verified := OLD.email_verified;
    NEW.providers      := OLD.providers;
    NEW.last_active_at := now();
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.update_updated_at() FROM PUBLIC, authenticated, anonymous;
REVOKE ALL ON FUNCTION public.protect_profile_columns() FROM PUBLIC, authenticated, anonymous;

-- ---------------------------------------------------------------------------
-- Tables (dependency order)
-- ---------------------------------------------------------------------------
CREATE TABLE public.profiles (
  id                   uuid PRIMARY KEY,
  display_name         text NOT NULL DEFAULT '',
  avatar_url           text,
  is_anonymous         boolean NOT NULL DEFAULT true,
  is_banned            boolean NOT NULL DEFAULT false,
  colorblind_mode      text NOT NULL DEFAULT 'none',
  theme_mode           text NOT NULL DEFAULT 'system',
  haptic_enabled       boolean NOT NULL DEFAULT true,
  sound_enabled        boolean NOT NULL DEFAULT true,
  notification_enabled boolean NOT NULL DEFAULT false,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now(),
  deleted_at           timestamptz,
  last_active_at       timestamptz NOT NULL DEFAULT now(),
  purged_at            timestamptz,
  email                text,
  email_verified       boolean NOT NULL DEFAULT false,
  providers            text[] NOT NULL DEFAULT '{}'
);
COMMENT ON COLUMN public.profiles.id IS
  'Root identity; equals ba."user".id (kept equal by the Function''s auth hooks, no FK).';
COMMENT ON COLUMN public.profiles.providers IS
  'Linked sign-in providers (e.g. google, apple, credential), mirrored by the auth hooks.';

CREATE TABLE public.puzzles (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  puzzle_date      date NOT NULL UNIQUE,
  grid_size        integer NOT NULL CHECK (grid_size BETWEEN 5 AND 8),
  waypoints        jsonb NOT NULL,
  walls            jsonb NOT NULL DEFAULT '[]'::jsonb,
  difficulty       text NOT NULL CHECK (difficulty IN ('easy', 'medium', 'hard', 'expert')),
  par_time_seconds integer NOT NULL,
  created_at       timestamptz NOT NULL DEFAULT now(),
  difficulty_score integer,
  seed_version     integer NOT NULL DEFAULT 3
);
COMMENT ON COLUMN public.puzzles.difficulty_score IS
  'Solver nodes expanded to find the first solution (analytics only).';
COMMENT ON COLUMN public.puzzles.seed_version IS
  'Generator version that produced this puzzle. 3 = deterministic seedFor(date, salt) with the Neon-era salt.';

-- Reference solutions: never readable by clients.
CREATE TABLE public.puzzle_solutions (
  puzzle_id  uuid PRIMARY KEY REFERENCES public.puzzles(id) ON DELETE CASCADE,
  path       jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Written only by the Function's submit-score.
CREATE TABLE public.puzzle_attempts (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE ON UPDATE CASCADE,
  puzzle_id     uuid NOT NULL REFERENCES public.puzzles(id) ON DELETE CASCADE,
  puzzle_date   date NOT NULL,
  time_seconds  integer NOT NULL,
  hints_used    integer NOT NULL DEFAULT 0,
  undos_used    integer NOT NULL DEFAULT 0,
  completed     boolean NOT NULL DEFAULT false,
  path          jsonb NOT NULL DEFAULT '[]'::jsonb,
  completed_at  timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now(),
  verified      boolean NOT NULL DEFAULT false,
  is_archive    boolean NOT NULL DEFAULT false,
  attempt_count integer NOT NULL DEFAULT 1,
  updated_at    timestamptz NOT NULL DEFAULT now()
);
COMMENT ON COLUMN public.puzzle_attempts.verified IS
  'true when the submission carried a valid HMAC signature bound to a puzzle_sessions nonce.';
COMMENT ON COLUMN public.puzzle_attempts.is_archive IS
  'true when the puzzle was solved after its UTC day ended; never affects streaks or leaderboards.';

CREATE TABLE public.streaks (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                 uuid NOT NULL UNIQUE REFERENCES public.profiles(id) ON DELETE CASCADE ON UPDATE CASCADE,
  current_streak          integer NOT NULL DEFAULT 0,
  longest_streak          integer NOT NULL DEFAULT 0,
  freeze_count            integer NOT NULL DEFAULT 1,
  last_solve_date         date,
  last_freeze_used_at     date,
  freeze_reset_week_start date,
  updated_at              timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.streak_freezes (
  user_id     uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE ON UPDATE CASCADE,
  frozen_date date NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, frozen_date)
);

-- Per-play HMAC nonce and server start time (Function only).
CREATE TABLE public.puzzle_sessions (
  user_id     uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE ON UPDATE CASCADE,
  puzzle_date date NOT NULL,
  started_at  timestamptz NOT NULL DEFAULT now(),
  nonce       text NOT NULL,
  PRIMARY KEY (user_id, puzzle_date)
);

-- Rate limiting for score submissions (Function only).
CREATE TABLE public.submission_log (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id    uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE ON UPDATE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.groups (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name         text NOT NULL,
  description  text NOT NULL DEFAULT '',
  invite_code  text NOT NULL UNIQUE,
  admin_id     uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE ON UPDATE CASCADE,
  member_count integer NOT NULL DEFAULT 1,
  max_members  integer NOT NULL DEFAULT 50,
  is_active    boolean NOT NULL DEFAULT true,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.group_members (
  id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id  uuid NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  user_id   uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE ON UPDATE CASCADE,
  role      text NOT NULL DEFAULT 'member' CHECK (role IN ('admin', 'member')),
  joined_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT unique_group_member UNIQUE (group_id, user_id)
);

-- Activity feed (written by the Function; clients poll it).
CREATE TABLE public.group_feed (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  group_id    uuid NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  user_id     uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE ON UPDATE CASCADE,
  puzzle_date date NOT NULL,
  event       text NOT NULL CHECK (event IN ('solved', 'solved_archive', 'joined', 'left')),
  payload     jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- Purged accounts keep their leaderboard rows as "Deleted User" in the groups
-- they belonged to (read only through SECURITY DEFINER functions).
CREATE TABLE public.group_purged_members (
  group_id  uuid NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  user_id   uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE ON UPDATE CASCADE,
  purged_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (group_id, user_id)
);

CREATE TABLE public.reports (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id       uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE ON UPDATE CASCADE,
  reported_user_id  uuid REFERENCES public.profiles(id) ON DELETE SET NULL ON UPDATE CASCADE,
  reported_group_id uuid REFERENCES public.groups(id) ON DELETE SET NULL,
  reason            text NOT NULL,
  details           text NOT NULL DEFAULT '',
  status            text NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending', 'reviewed', 'resolved', 'dismissed')),
  created_at        timestamptz NOT NULL DEFAULT now(),
  reviewed_at       timestamptz
);

-- Profanity list used by contains_profanity() (seeded in 0003_seed.sql).
CREATE TABLE public.banned_words (
  word text PRIMARY KEY
);

-- Force-update / maintenance / store URLs (seeded in 0003_seed.sql).
CREATE TABLE public.app_config (
  key        text PRIMARY KEY,
  value      jsonb NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.user_blocks (
  blocker_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE ON UPDATE CASCADE,
  blocked_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE ON UPDATE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (blocker_id, blocked_id),
  CONSTRAINT user_blocks_no_self_block CHECK (blocker_id <> blocked_id)
);

-- Idempotency ledger for the Function's /cron/* routes (at-least-once triggers).
CREATE TABLE public.cron_runs (
  job          text NOT NULL,
  scheduled_at timestamptz NOT NULL,
  ran_at       timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (job, scheduled_at)
);

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------
CREATE INDEX idx_profiles_deleted_at
  ON public.profiles (deleted_at) WHERE deleted_at IS NOT NULL AND purged_at IS NULL;
CREATE INDEX idx_profiles_anonymous_inactive
  ON public.profiles (last_active_at) WHERE is_anonymous;

CREATE INDEX idx_puzzles_puzzle_date ON public.puzzles (puzzle_date);

CREATE INDEX idx_puzzle_attempts_user_id ON public.puzzle_attempts (user_id);
CREATE INDEX idx_puzzle_attempts_puzzle_date ON public.puzzle_attempts (puzzle_date);
CREATE INDEX idx_puzzle_attempts_user_date ON public.puzzle_attempts (user_id, puzzle_date);
CREATE INDEX idx_puzzle_attempts_puzzle_id ON public.puzzle_attempts (puzzle_id);
-- One COMPLETED attempt per user per day; incomplete attempts may be retried.
CREATE UNIQUE INDEX puzzle_attempts_one_completed_per_day
  ON public.puzzle_attempts (user_id, puzzle_date) WHERE completed;
-- Leaderboard lookups: by date, completed, live only.
CREATE INDEX idx_puzzle_attempts_date_live
  ON public.puzzle_attempts (puzzle_date, hints_used, time_seconds, undos_used)
  WHERE completed AND NOT is_archive;

CREATE INDEX idx_streaks_user_id ON public.streaks (user_id);
CREATE INDEX idx_streak_freezes_frozen_date ON public.streak_freezes (frozen_date);
CREATE INDEX idx_puzzle_sessions_started_at ON public.puzzle_sessions (started_at);
CREATE INDEX idx_submission_log_user_created ON public.submission_log (user_id, created_at);

CREATE INDEX idx_groups_invite_code ON public.groups (invite_code);
CREATE INDEX idx_group_members_user_id ON public.group_members (user_id);
CREATE INDEX idx_group_members_group_id ON public.group_members (group_id);
CREATE INDEX idx_group_feed_group_created ON public.group_feed (group_id, created_at DESC);
CREATE INDEX idx_group_feed_user_id ON public.group_feed (user_id);
CREATE INDEX idx_group_purged_members_user_id ON public.group_purged_members (user_id);

CREATE INDEX idx_reports_reporter_id ON public.reports (reporter_id);
CREATE INDEX idx_reports_reported_user_id ON public.reports (reported_user_id);
CREATE INDEX idx_reports_reported_group_id ON public.reports (reported_group_id);

CREATE INDEX idx_user_blocks_blocked_id ON public.user_blocks (blocked_id);

-- ---------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------
CREATE TRIGGER update_profiles_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
CREATE TRIGGER protect_profile_columns
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.protect_profile_columns();
CREATE TRIGGER update_puzzle_attempts_updated_at
  BEFORE UPDATE ON public.puzzle_attempts
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
CREATE TRIGGER update_streaks_updated_at
  BEFORE UPDATE ON public.streaks
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
CREATE TRIGGER update_groups_updated_at
  BEFORE UPDATE ON public.groups
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();
CREATE TRIGGER update_app_config_updated_at
  BEFORE UPDATE ON public.app_config
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

-- ---------------------------------------------------------------------------
-- RLS helpers (SECURITY DEFINER so policies can consult group_members and
-- user_blocks without recursing through their own policies). They live here,
-- not in 0002, because the policies below need them.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_group_member(p_group_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.group_members gm
    WHERE gm.group_id = p_group_id
      AND gm.user_id = (select app.uid())
  );
$$;

CREATE OR REPLACE FUNCTION public.shares_group_with(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.group_members mine
    JOIN public.group_members theirs ON theirs.group_id = mine.group_id
    WHERE mine.user_id = (select app.uid())
      AND theirs.user_id = p_user_id
  );
$$;

-- Caller is a current member of a group the purged user p_user_id was in.
CREATE OR REPLACE FUNCTION public.shares_former_group_with(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.group_purged_members gp
    JOIN public.group_members mine ON mine.group_id = gp.group_id
    WHERE gp.user_id = p_user_id
      AND mine.user_id = (select app.uid())
  );
$$;

CREATE OR REPLACE FUNCTION public.is_blocked_by_me(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_blocks b
    WHERE b.blocker_id = (select app.uid())
      AND b.blocked_id = p_user_id
  );
$$;

REVOKE ALL ON FUNCTION public.is_group_member(uuid) FROM PUBLIC, anonymous;
REVOKE ALL ON FUNCTION public.shares_group_with(uuid) FROM PUBLIC, anonymous;
REVOKE ALL ON FUNCTION public.shares_former_group_with(uuid) FROM PUBLIC, anonymous;
REVOKE ALL ON FUNCTION public.is_blocked_by_me(uuid) FROM PUBLIC, anonymous;
GRANT EXECUTE ON FUNCTION public.is_group_member(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.shares_group_with(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.shares_former_group_with(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_blocked_by_me(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- Row-level security: on for every table. The owner bypasses it; tables with
-- no policy are invisible to clients.
-- ---------------------------------------------------------------------------
ALTER TABLE public.profiles             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.puzzles              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.puzzle_solutions     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.puzzle_attempts      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.streaks              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.streak_freezes       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.puzzle_sessions      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.submission_log       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.groups               ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.group_members        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.group_feed           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.group_purged_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reports              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.banned_words         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_config           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_blocks          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cron_runs            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.schema_migrations    ENABLE ROW LEVEL SECURITY;

-- profiles
CREATE POLICY "Users can view their own profile"
  ON public.profiles FOR SELECT
  TO authenticated
  USING ((select app.uid()) = id);
CREATE POLICY "Users can update their own profile"
  ON public.profiles FOR UPDATE
  TO authenticated
  USING ((select app.uid()) = id)
  WITH CHECK ((select app.uid()) = id);
CREATE POLICY "Users can insert their own profile"
  ON public.profiles FOR INSERT
  TO authenticated
  WITH CHECK ((select app.uid()) = id);
CREATE POLICY "Co-members can view profiles"
  ON public.profiles FOR SELECT
  TO authenticated
  USING (public.shares_group_with(id));
CREATE POLICY "Members can view purged former co-members"
  ON public.profiles FOR SELECT
  TO authenticated
  USING (purged_at IS NOT NULL AND public.shares_former_group_with(id));

-- puzzles (public)
CREATE POLICY "Puzzles are publicly readable"
  ON public.puzzles FOR SELECT
  TO anonymous, authenticated
  USING (true);

-- puzzle_attempts (writes: Function only; leaderboards via SECURITY DEFINER RPCs)
CREATE POLICY "Users can view their own attempts"
  ON public.puzzle_attempts FOR SELECT
  TO authenticated
  USING ((select app.uid()) = user_id);

-- streaks / streak_freezes (writes: record_solve / recompute_streak only)
CREATE POLICY "Users can view their own streak"
  ON public.streaks FOR SELECT
  TO authenticated
  USING ((select app.uid()) = user_id);
CREATE POLICY "Group members can view streaks"
  ON public.streaks FOR SELECT
  TO authenticated
  USING (public.shares_group_with(user_id));
CREATE POLICY "Users can view their own freezes"
  ON public.streak_freezes FOR SELECT
  TO authenticated
  USING ((select app.uid()) = user_id);

-- groups / group_members / group_feed (writes: RPCs and the Function)
CREATE POLICY "Members can view their groups"
  ON public.groups FOR SELECT
  TO authenticated
  USING (public.is_group_member(id));
CREATE POLICY "Members can view group members"
  ON public.group_members FOR SELECT
  TO authenticated
  USING (public.is_group_member(group_id));
CREATE POLICY "Members can view group feed"
  ON public.group_feed FOR SELECT
  TO authenticated
  USING (
    public.is_group_member(group_id)
    AND NOT public.is_blocked_by_me(user_id)
  );

-- reports: file your own, see your own
CREATE POLICY "Users can create reports"
  ON public.reports FOR INSERT
  TO authenticated
  WITH CHECK ((select app.uid()) = reporter_id);
CREATE POLICY "Users can view their own reports"
  ON public.reports FOR SELECT
  TO authenticated
  USING ((select app.uid()) = reporter_id);

-- app_config (public)
CREATE POLICY "App config is publicly readable"
  ON public.app_config FOR SELECT
  TO anonymous, authenticated
  USING (true);

-- user_blocks: read-only for the blocker (writes: the Function's /api/block)
CREATE POLICY "Users can view their own blocks"
  ON public.user_blocks FOR SELECT
  TO authenticated
  USING (blocker_id = (select app.uid()));

-- ---------------------------------------------------------------------------
-- Privileges. Neon's default privileges grant `authenticated` INSERT, SELECT,
-- UPDATE, DELETE on every new table in public (and USAGE on sequences), so
-- start from nothing and grant exactly what the policies above can use.
-- puzzle_solutions, puzzle_sessions, submission_log, banned_words,
-- group_purged_members, cron_runs and schema_migrations stay owner-only.
-- ---------------------------------------------------------------------------
GRANT USAGE ON SCHEMA public TO authenticated, anonymous;

REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC, authenticated, anonymous;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC, authenticated, anonymous;

GRANT SELECT ON public.puzzles, public.app_config TO anonymous;

GRANT SELECT ON
  public.profiles,
  public.puzzles,
  public.puzzle_attempts,
  public.streaks,
  public.streak_freezes,
  public.groups,
  public.group_members,
  public.group_feed,
  public.reports,
  public.app_config,
  public.user_blocks
TO authenticated;
GRANT INSERT, UPDATE ON public.profiles TO authenticated;
GRANT INSERT ON public.reports TO authenticated;
