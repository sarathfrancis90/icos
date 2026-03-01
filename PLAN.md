# Icos - Production-Ready Mobile Puzzle Game
## Comprehensive Implementation Plan

---

## Table of Contents
1. [Executive Summary](#1-executive-summary)
2. [Technology Stack](#2-technology-stack)
3. [Feature Classification](#3-feature-classification)
4. [Architecture Overview](#4-architecture-overview)
5. [Database Design](#5-database-design)
6. [Puzzle Engine](#6-puzzle-engine)
7. [UI/UX Design System](#7-uiux-design-system)
8. [Social & Group System](#8-social--group-system)
9. [User Management & Authentication](#9-user-management--authentication)
10. [Scaling Strategy](#10-scaling-strategy)
11. [Development Phases](#11-development-phases)
12. [Project Structure](#12-project-structure)

---

## 1. Executive Summary

**Icos** is a premium mobile puzzle game for Android and iOS where players draw a continuous path through a grid, connecting numbered waypoints in order while filling every cell. It differentiates from LinkedIn's Zip through superior UI/UX, group-based social features, and a richer game experience.

**Core differentiators:**
- Beautiful, polished UI with fluid animations and haptic feedback
- Group system with daily leaderboards (friends, coworkers, custom groups)
- Practice mode with unlimited puzzles alongside the daily puzzle
- Spoiler-free result sharing (Wordle-style)
- Accessibility-first design (colorblind modes, screen reader support)
- Offline-first architecture (play without internet)

---

## 2. Technology Stack

### Frontend (Mobile App)
| Component | Technology | Rationale |
|-----------|-----------|-----------|
| **Framework** | **Flutter 3.x (Dart)** | Custom rendering via Impeller engine, 60-120 FPS, pixel-perfect UI, single codebase for iOS/Android, 95%+ code reuse |
| **Game Canvas** | **Flutter CustomPainter + Canvas API** | Direct control over path drawing, grid rendering, animations. Lighter than Flame engine for a puzzle game |
| **State Management** | **Riverpod 2.x** | Compile-safe, testable, supports async/stream states for real-time leaderboard updates |
| **Navigation** | **GoRouter** | Declarative routing with deep link support (for group invites) |
| **Local Storage** | **Hive / SharedPreferences** | Offline puzzle cache, user preferences, streak data |
| **Animations** | **Flutter Animations + Rive** | Rive for complex celebration animations; Flutter implicit/explicit animations for UI transitions |

### Backend
| Component | Technology | Rationale |
|-----------|-----------|-----------|
| **Primary Backend** | **Supabase** | PostgreSQL-native, SQL for leaderboards (RANK(), window functions), Row-Level Security, real-time subscriptions, Edge Functions, open-source |
| **Database** | **PostgreSQL (via Supabase)** | Relational model ideal for users/groups/scores/puzzles; JSONB for puzzle data; materialized views for leaderboards |
| **Auth** | **Supabase Auth (GoTrue)** | Email, Google, Apple Sign-In, anonymous auth; integrated with RLS |
| **Real-time** | **Supabase Realtime** | PostgreSQL WAL-based change streams for live leaderboard updates |
| **Edge Functions** | **Supabase Edge Functions (Deno)** | Puzzle validation, anti-cheat, daily puzzle scheduling, group invite processing |
| **Leaderboard Cache** | **Redis (Upstash)** | Sorted Sets for O(log N) ranking; add when scale demands it (not at launch) |
| **Push Notifications** | **Firebase Cloud Messaging (FCM)** | Industry standard, handles both platforms, topic-based subscriptions for daily puzzle alerts |
| **File Storage** | **Supabase Storage** | User avatars, group images |

### Analytics & Monitoring
| Component | Technology | Rationale |
|-----------|-----------|-----------|
| **Analytics** | **Firebase Analytics (GA4)** | Free, unlimited events, Flutter-native, BigQuery export |
| **Crash Reporting** | **Firebase Crashlytics** | Free, correlates crashes with app versions |
| **Performance** | **Firebase Performance Monitoring** | App startup, screen render, network latency |
| **Remote Config** | **Firebase Remote Config** | Feature flags, puzzle parameters, A/B tests without app updates |

### DevOps & CI/CD
| Component | Technology | Rationale |
|-----------|-----------|-----------|
| **CI/CD** | **GitHub Actions + Fastlane** | Automated builds, testing, store deployment |
| **Code Quality** | **Flutter Analyze + Custom Lint Rules** | Enforce code standards |
| **Testing** | **Flutter Test + Integration Tests** | Unit, widget, integration, golden tests |

---

## 3. Feature Classification

### Must-Have Features (MVP)

#### Core Gameplay
- [ ] **Grid rendering** with numbered waypoints and wall barriers
- [ ] **Touch-based path drawing** with drag gesture (smooth, responsive)
- [ ] **Path validation** engine (continuous, visits all cells, hits waypoints in order, respects walls)
- [ ] **Undo/redo** — backtrack by dragging backward or tap undo button
- [ ] **Reset puzzle** button
- [ ] **Timer** — tracks solve time (displayed after completion, not during to reduce anxiety)
- [ ] **Completion detection** with celebration animation
- [ ] **Daily puzzle** — one new puzzle each day, same for all users
- [ ] **Difficulty progression** — easier on Monday, hardest on Sunday
- [ ] **Grid sizes**: 5x5 (Mon), 5x6 (Tue), 6x6 (Wed), 6x7 (Thu), 7x7 (Fri), 7x8 (Sat), 8x8 (Sun)

#### Hint System
- [ ] **Reveal next segment** — shows the correct path for the next 2-3 cells
- [ ] **Dead-end highlighter** — subtly highlights cells that can only be entered/exited one way
- [ ] **3 free hints per day**, additional hints via watching optional ad or earned through streaks

#### User Management
- [ ] **Anonymous play** — start playing immediately without sign-up
- [ ] **Account creation** — email, Google Sign-In, Apple Sign-In
- [ ] **Profile** — display name, avatar (selection from preset avatars), statistics
- [ ] **Account linking** — convert anonymous account to full account without losing progress
- [ ] **Settings** — haptics toggle, sound toggle, theme selection, notification preferences

#### Streaks & Statistics
- [ ] **Current streak** count (consecutive days with completed puzzle)
- [ ] **Longest streak** record
- [ ] **Total puzzles solved**
- [ ] **Average solve time**
- [ ] **Solve time distribution** chart
- [ ] **Streak freeze** — 1 free freeze per week (miss a day without breaking streak)

#### Social — Groups & Leaderboards
- [ ] **Create group** — name, optional description, optional avatar
- [ ] **Join group** — via invite code (6-character alphanumeric) or deep link
- [ ] **Group daily leaderboard** — ranked by today's solve time
- [ ] **Group weekly leaderboard** — ranked by total weekly solve time or puzzles completed
- [ ] **Leave group / delete group** (admin)
- [ ] **Group member list** with roles (admin, member)
- [ ] **Max group size**: 50 members (prevents abuse, keeps leaderboard manageable)

#### Sharing
- [ ] **Spoiler-free result sharing** — generate a shareable image/text showing:
  - Grid size, day, solve time
  - Abstract path visualization (colored blocks showing general path shape, no solution revealed)
  - "I solved today's Icos in 0:42! Can you beat my time?"
- [ ] **Share to social media** — Instagram Stories, WhatsApp, Twitter/X, clipboard
- [ ] **Group invite sharing** — deep link + invite code

#### Offline Support
- [ ] **Offline-first architecture** — daily puzzle cached 24h in advance via silent push
- [ ] **Play without internet** — solve the puzzle offline, sync result when online
- [ ] **Queue sync** — offline completions sync automatically when connectivity returns

### Nice-to-Have Features (Post-MVP)

#### Enhanced Gameplay
- [ ] **Practice mode** — unlimited randomly generated puzzles (choose grid size + difficulty)
- [ ] **Archive** — replay past daily puzzles you missed
- [ ] **Speed run mode** — solve 5 puzzles in a row, total time tracked
- [ ] **Weekly challenge** — special large puzzle (9x9 or 10x10) released every Saturday
- [ ] **Tutorial** — interactive onboarding for first-time players (progressive, learn by playing)

#### Advanced Social
- [ ] **Global leaderboard** — top 100 fastest solvers per day
- [ ] **Group chat** — lightweight chat within groups (text only)
- [ ] **Group challenges** — admin can create custom challenges (e.g., "solve in under 30 seconds")
- [ ] **Friend system** — add friends without creating a group, see their daily results
- [ ] **Spectator replay** — watch a replay of a group member's solve path (after both have solved)
- [ ] **Head-to-head mode** — real-time race against a group member on the same puzzle

#### Gamification
- [ ] **Achievement badges** — "First Solve", "7-Day Streak", "30-Day Streak", "Speed Demon (under 15s)", "Perfectionist (no undo used)", "Social Butterfly (5 groups)", etc.
- [ ] **Seasonal themes** — holiday-themed grid colors and celebration animations
- [ ] **Weekly recap** — Sunday night summary of your week (puzzles solved, rank in groups, streak status)
- [ ] **Milestone celebrations** — special animations for 10th, 50th, 100th, 365th puzzle

#### Customization
- [ ] **Theme selection** — Light, Dark, AMOLED Black, Pastel, High Contrast
- [ ] **Path color customization** — choose your path color (10+ options)
- [ ] **Grid style options** — rounded cells, sharp cells, minimal lines
- [ ] **Celebration animation style** — confetti, fireworks, subtle glow, none

#### Accessibility
- [ ] **Colorblind mode** — patterns/textures on path instead of color-only
- [ ] **Screen reader support** — VoiceOver/TalkBack with cell-by-cell navigation
- [ ] **Large text mode** — enlarged numbers and UI elements
- [ ] **Reduced motion mode** — respects system accessibility settings
- [ ] **One-handed mode** — compact layout for smaller screens

### Unique/Differentiating Features

- [ ] **"Ghost Race"** — after solving, see an animated replay of a group member's path overlaid on yours (like racing game ghosts). No spoilers since both have already solved.
- [ ] **"Path Heatmap"** — after solving, see an aggregate heatmap of which cells were filled first/last by all players globally. Reveals the "hard spots" of the puzzle.
- [ ] **"Puzzle DNA"** — a unique visual fingerprint generated from your solve path. Every solve produces a different abstract art piece based on path order and timing. Shareable as a profile badge.
- [ ] **"Group Streak"** — in addition to personal streaks, groups have a collective streak (% of members who solved today). Groups compete for the longest collective streak.
- [ ] **"Daily Trivia Tie-In"** — each daily puzzle has a fun trivia fact shown after completion (e.g., "Today's 7x7 grid has 49 cells — the same as the number of states that border an ocean"). Light, non-intrusive.
- [ ] **"Solve Path Replay"** — watch your own solve path animated in fast-forward. See where you hesitated, backtracked, or breezed through. Available in your statistics.

---

## 4. Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    MOBILE APP (Flutter)                   │
│                                                           │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐ │
│  │   Game    │  │  Social  │  │  Profile  │  │ Settings │ │
│  │  Screen   │  │  Screen  │  │  Screen   │  │  Screen  │ │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘ │
│       │              │              │              │       │
│  ┌────┴──────────────┴──────────────┴──────────────┴────┐ │
│  │              State Management (Riverpod)              │ │
│  └────┬──────────────┬──────────────┬───────────────────┘ │
│       │              │              │                      │
│  ┌────┴────┐   ┌─────┴────┐  ┌─────┴─────┐               │
│  │  Puzzle  │   │  Social  │  │   Auth     │               │
│  │  Engine  │   │  Service │  │  Service   │               │
│  │ (Local)  │   │          │  │            │               │
│  └────┬────┘   └─────┬────┘  └─────┬─────┘               │
│       │              │              │                      │
│  ┌────┴────┐         │              │                      │
│  │  Hive   │         │              │                      │
│  │ (Cache) │         │              │                      │
│  └─────────┘         │              │                      │
└──────────────────────┼──────────────┼──────────────────────┘
                       │              │
                       ▼              ▼
┌──────────────────────────────────────────────────────────┐
│                      SUPABASE                             │
│                                                           │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐ │
│  │   Auth   │  │ Database │  │ Realtime  │  │  Edge    │ │
│  │ (GoTrue) │  │ (PgSQL)  │  │  (WAL)   │  │Functions │ │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘ │
│                                                           │
│  ┌──────────┐  ┌──────────┐                              │
│  │ Storage  │  │   RLS    │                              │
│  │ (Avatars)│  │(Security)│                              │
│  └──────────┘  └──────────┘                              │
└──────────────────────────────────────────────────────────┘
                       │
            ┌──────────┼──────────┐
            ▼          ▼          ▼
       ┌─────────┐ ┌───────┐ ┌────────┐
       │Firebase  │ │Redis  │ │Firebase│
       │  FCM     │ │(Cache)│ │Analytics│
       │(Push)    │ │       │ │Crash   │
       └─────────┘ └───────┘ └────────┘
```

### Key Architecture Decisions

1. **Offline-first**: The puzzle engine runs entirely on-device. The app caches tomorrow's puzzle via silent push. Results sync when online.

2. **Client-side puzzle validation + server-side verification**: The app validates the solution instantly for UX. The server re-validates before recording the score (anti-cheat).

3. **Real-time leaderboards**: Supabase Realtime subscriptions push leaderboard updates to connected clients. No polling needed.

4. **Edge Functions for sensitive logic**: Puzzle delivery, score submission, invite processing, and anti-cheat all run server-side.

---

## 5. Database Design

### Core Tables

```sql
-- ============================================
-- USERS & AUTH
-- ============================================

-- Managed by Supabase Auth (auth.users)
-- Extended with a public profiles table:

CREATE TABLE public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    display_name TEXT NOT NULL DEFAULT 'Player',
    avatar_id TEXT NOT NULL DEFAULT 'default',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_anonymous BOOLEAN NOT NULL DEFAULT TRUE,
    timezone TEXT DEFAULT 'UTC'
);

-- ============================================
-- PUZZLES
-- ============================================

CREATE TABLE public.puzzles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    puzzle_date DATE NOT NULL UNIQUE,          -- one puzzle per day
    grid_width SMALLINT NOT NULL,
    grid_height SMALLINT NOT NULL,
    day_of_week SMALLINT NOT NULL,             -- 1=Mon, 7=Sun
    difficulty TEXT NOT NULL,                   -- 'easy', 'medium', 'hard', 'expert'
    waypoints JSONB NOT NULL,                  -- [{x, y, number}]
    walls JSONB NOT NULL,                      -- [{x1, y1, x2, y2}] (edges between cells)
    solution_path JSONB NOT NULL,              -- [{x, y}] ordered — server-only, never sent to client
    metadata JSONB DEFAULT '{}',               -- trivia, theme, etc.
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_puzzles_date ON public.puzzles(puzzle_date);

-- ============================================
-- PUZZLE ATTEMPTS (SCORES)
-- ============================================

CREATE TABLE public.puzzle_attempts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    puzzle_id UUID NOT NULL REFERENCES public.puzzles(id) ON DELETE CASCADE,
    puzzle_date DATE NOT NULL,
    solve_time_ms INTEGER NOT NULL,            -- milliseconds
    hints_used SMALLINT NOT NULL DEFAULT 0,
    undos_used INTEGER NOT NULL DEFAULT 0,
    completed BOOLEAN NOT NULL DEFAULT TRUE,
    path_data JSONB,                           -- optional: the user's path for replay
    submitted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    verified BOOLEAN NOT NULL DEFAULT FALSE,   -- server-side verification flag
    UNIQUE(user_id, puzzle_date)               -- one attempt per user per day
);

CREATE INDEX idx_attempts_date ON public.puzzle_attempts(puzzle_date);
CREATE INDEX idx_attempts_user ON public.puzzle_attempts(user_id);
CREATE INDEX idx_attempts_date_time ON public.puzzle_attempts(puzzle_date, solve_time_ms);

-- ============================================
-- STREAKS
-- ============================================

CREATE TABLE public.streaks (
    user_id UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
    current_streak INTEGER NOT NULL DEFAULT 0,
    longest_streak INTEGER NOT NULL DEFAULT 0,
    last_solve_date DATE,
    streak_freezes_remaining SMALLINT NOT NULL DEFAULT 1,
    streak_freeze_used_date DATE,              -- when the last freeze was used
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================
-- GROUPS
-- ============================================

CREATE TABLE public.groups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    description TEXT DEFAULT '',
    avatar_id TEXT DEFAULT 'group_default',
    invite_code TEXT NOT NULL UNIQUE,          -- 6-char alphanumeric
    created_by UUID NOT NULL REFERENCES public.profiles(id),
    max_members SMALLINT NOT NULL DEFAULT 50,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_groups_invite ON public.groups(invite_code);

CREATE TABLE public.group_members (
    group_id UUID NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    role TEXT NOT NULL DEFAULT 'member',       -- 'admin', 'member'
    joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (group_id, user_id)
);

CREATE INDEX idx_group_members_user ON public.group_members(user_id);

-- ============================================
-- ACHIEVEMENTS (Post-MVP)
-- ============================================

CREATE TABLE public.achievements (
    id TEXT PRIMARY KEY,                       -- 'first_solve', 'streak_7', etc.
    name TEXT NOT NULL,
    description TEXT NOT NULL,
    icon_id TEXT NOT NULL
);

CREATE TABLE public.user_achievements (
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    achievement_id TEXT NOT NULL REFERENCES public.achievements(id),
    unlocked_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, achievement_id)
);
```

### Key Database Functions (RPCs)

```sql
-- Daily leaderboard for a group
CREATE OR REPLACE FUNCTION get_group_daily_leaderboard(
    p_group_id UUID,
    p_date DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (
    user_id UUID,
    display_name TEXT,
    avatar_id TEXT,
    solve_time_ms INTEGER,
    hints_used SMALLINT,
    rank BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        pa.user_id,
        pr.display_name,
        pr.avatar_id,
        pa.solve_time_ms,
        pa.hints_used,
        DENSE_RANK() OVER (ORDER BY pa.hints_used ASC, pa.solve_time_ms ASC)::BIGINT AS rank
    FROM public.puzzle_attempts pa
    JOIN public.profiles pr ON pr.id = pa.user_id
    JOIN public.group_members gm ON gm.user_id = pa.user_id AND gm.group_id = p_group_id
    WHERE pa.puzzle_date = p_date
      AND pa.completed = TRUE
    ORDER BY rank ASC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Weekly leaderboard for a group
CREATE OR REPLACE FUNCTION get_group_weekly_leaderboard(
    p_group_id UUID,
    p_week_start DATE DEFAULT date_trunc('week', CURRENT_DATE)::DATE
)
RETURNS TABLE (
    user_id UUID,
    display_name TEXT,
    avatar_id TEXT,
    puzzles_completed BIGINT,
    total_time_ms BIGINT,
    avg_time_ms BIGINT,
    rank BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        pa.user_id,
        pr.display_name,
        pr.avatar_id,
        COUNT(*)::BIGINT AS puzzles_completed,
        SUM(pa.solve_time_ms)::BIGINT AS total_time_ms,
        AVG(pa.solve_time_ms)::BIGINT AS avg_time_ms,
        DENSE_RANK() OVER (ORDER BY COUNT(*) DESC, AVG(pa.solve_time_ms) ASC)::BIGINT AS rank
    FROM public.puzzle_attempts pa
    JOIN public.profiles pr ON pr.id = pa.user_id
    JOIN public.group_members gm ON gm.user_id = pa.user_id AND gm.group_id = p_group_id
    WHERE pa.puzzle_date >= p_week_start
      AND pa.puzzle_date < p_week_start + INTERVAL '7 days'
      AND pa.completed = TRUE
    GROUP BY pa.user_id, pr.display_name, pr.avatar_id
    ORDER BY rank ASC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

### Row-Level Security Policies

```sql
-- Profiles: users can read any profile, update only their own
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Public profiles are viewable by everyone"
    ON public.profiles FOR SELECT USING (true);
CREATE POLICY "Users can update own profile"
    ON public.profiles FOR UPDATE USING (auth.uid() = id);

-- Puzzle attempts: users can insert their own, read group members'
ALTER TABLE public.puzzle_attempts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can insert own attempts"
    ON public.puzzle_attempts FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can read own attempts"
    ON public.puzzle_attempts FOR SELECT USING (auth.uid() = user_id);

-- Groups: members can read their groups
ALTER TABLE public.groups ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Group members can read group"
    ON public.groups FOR SELECT USING (
        EXISTS (SELECT 1 FROM public.group_members WHERE group_id = id AND user_id = auth.uid())
    );

-- Group members: members can see other members
ALTER TABLE public.group_members ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Group members can read members"
    ON public.group_members FOR SELECT USING (
        EXISTS (SELECT 1 FROM public.group_members gm WHERE gm.group_id = group_id AND gm.user_id = auth.uid())
    );
```

---

## 6. Puzzle Engine

### Generation Algorithm

The puzzle generator uses the **Backbite algorithm** to create random Hamiltonian paths on grids, then places waypoints and walls to create unique puzzles.

```
Algorithm: Generate Icos Puzzle
─────────────────────────────────
Input:  width, height, difficulty_level
Output: puzzle (waypoints, walls, solution_path)

1. GENERATE a random Hamiltonian path on the grid using Backbite:
   a. Start with a trivial serpentine (zig-zag) path covering all cells
   b. Repeat N times (N = quality_factor * 20 * width * height * log²(width*height)):
      i.   Pick a random endpoint of the current path
      ii.  Pick a random neighbor of that endpoint (not its predecessor)
      iii. This creates a cycle — remove the appropriate edge to restore a path
   c. The resulting path is approximately uniformly random

2. PLACE WAYPOINTS along the path:
   a. Waypoint 1 = path start, Waypoint_max = path end
   b. Place intermediate waypoints at roughly equal intervals along the path
   c. Number of waypoints scales inversely with difficulty:
      - Easy:   grid_cells / 5  waypoints
      - Medium: grid_cells / 7  waypoints
      - Hard:   grid_cells / 10 waypoints
      - Expert: grid_cells / 14 waypoints

3. PLACE WALLS (optional, based on difficulty):
   a. Identify cell edges that are NOT part of the solution path
   b. Randomly select a subset as walls
   c. More walls on easier puzzles (more constraints = easier)
   d. Fewer walls on harder puzzles

4. VERIFY UNIQUENESS:
   a. Run backtracking solver from waypoint 1
   b. If solver finds more than 1 solution:
      - Add more waypoints or walls
      - Re-verify
   c. Repeat until exactly 1 solution exists

5. RATE DIFFICULTY:
   a. Measure solver backtrack count (more backtracks = harder)
   b. Count dead-end cells (fewer = harder)
   c. Count forced moves (fewer = harder)
   d. Assign difficulty score and verify it matches target
```

### Solver (for verification & hints)

```
Algorithm: Solve Icos Puzzle (DFS with pruning)
──────────────────────────────────────────────────
Input:  grid, waypoints, walls
Output: solution_path or NONE

1. Start DFS from waypoint 1
2. At each step, try all valid neighbors (up/down/left/right, no walls, not visited)
3. PRUNING rules (critical for performance):
   a. If current cell should be next waypoint but isn't → backtrack
   b. If skipped a waypoint → backtrack
   c. If remaining unvisited cells form disconnected regions → backtrack
   d. If an unvisited cell has 0 unvisited neighbors (isolated) → backtrack
4. On reaching final waypoint with all cells visited → SOLUTION FOUND
5. Continue search after first solution to verify uniqueness
```

### Pre-generation Strategy

- **Generate puzzles 30 days in advance** via a scheduled Edge Function (cron job)
- **Store in database** with puzzle_date
- **Pre-cache on device**: Silent push delivers tomorrow's puzzle the night before
- **Fallback**: App includes 7 bundled offline puzzles in case of connectivity issues on first launch

---

## 7. UI/UX Design System

### Visual Design Language

```
COLOR PALETTE
─────────────
Background (Dark):    #0A0E1A (deep navy)
Background (Light):   #F5F6FA (soft off-white)
Grid Lines:           #2A3050 (dark) / #D0D4E0 (light)
Grid Cells:           #141830 (dark) / #FFFFFF (light)
Path Color (default): #4F8CFF (vibrant blue)
Path Glow:            #4F8CFF at 30% opacity
Waypoint Numbers:     #FFFFFF (dark) / #1A1E30 (light)
Waypoint Circles:     #FF6B4A (coral-orange accent)
Walls:                #FF4444 at 80% or thick white
Timer Text:           #8B92A8 (muted gray)
Success Green:        #4ADE80
Streak Fire:          #FF9F43

TYPOGRAPHY
──────────
Primary Font:    Inter (or system default for performance)
Numbers on Grid: SF Mono / JetBrains Mono (monospace, clear at small sizes)
Headings:        Inter Bold, 20-28sp
Body:            Inter Regular, 14-16sp
Timer:           JetBrains Mono, 32sp

SPACING & SIZING
────────────────
Grid cell size:      adaptive (screen_width - 48px padding) / grid_columns
Min touch target:    44x44dp (Apple HIG / Material guidelines)
Grid padding:        24px on each side
Corner radius:       8dp (cells), 16dp (cards), 24dp (modals)
```

### Screen Flow

```
┌─────────┐     ┌─────────────┐     ┌──────────┐
│  Splash  │────▶│  Home / Hub  │────▶│  Daily   │
│  Screen  │     │             │     │  Puzzle  │
└─────────┘     │  - Daily    │     │  Screen  │
                │  - Groups   │     └──────────┘
                │  - Stats    │          │
                │  - Profile  │          ▼
                └──────┬──────┘     ┌──────────┐
                       │            │  Result   │
                       │            │  Screen   │
                       │            │  (Share)  │
                       │            └──────────┘
                       │
                ┌──────┴──────┐
                │             │
          ┌─────┴───┐  ┌─────┴────┐
          │ Groups  │  │  Stats   │
          │  List   │  │  Screen  │
          └────┬────┘  └──────────┘
               │
          ┌────┴─────┐
          │  Group   │
          │  Detail  │
          │(Leaderbd)│
          └──────────┘
```

### Key Screen Designs

#### Home Screen
- Clean, card-based layout
- **Daily puzzle card** — prominent, shows today's grid size, difficulty indicator (colored dots), and "Play" button
- **Group activity card** — "3 of 8 members solved today" with mini avatars
- **Streak display** — flame icon with current streak number
- **Stats summary** — total solved, average time
- Bottom navigation: Home | Groups | Stats | Profile

#### Game Screen
- **Full-screen grid** centered on screen
- **Minimal chrome** — only a back arrow and hint button visible during play
- **Path drawing**: finger drag creates smooth, animated path with subtle glow trail
- **Waypoint numbers**: large, clear, in coral-orange circles
- **Walls**: thick lines between cells, distinct from grid lines
- **Haptic feedback**: light tap on each cell entered, medium impact on waypoint reached, error buzz on wall collision
- **Timer**: hidden during play (reduces anxiety), shown on completion

#### Result Screen
- **Celebration animation**: confetti burst (Rive animation), grid lights up
- **Time displayed prominently**: "1:23" in large monospace font
- **Comparison stats**: "Faster than 73% of players today"
- **Group rankings preview**: "You're #2 in 'Engineering Team'"
- **Share button**: generates spoiler-free shareable card
- **"See Leaderboard" button**: navigate to group leaderboard

#### Group Leaderboard Screen
- **Tab bar**: Daily | Weekly | All-Time
- **Ranked list**: avatar, name, solve time, rank badge (gold/silver/bronze for top 3)
- **Your position highlighted** if not in visible range
- **Empty states**: "Waiting for [Name] to solve..." for members who haven't solved yet
- **Group streak indicator**: "8/10 members solved today — keep the group streak alive!"

### Animation Specifications

| Trigger | Animation | Duration | Haptic |
|---------|-----------|----------|--------|
| Cell entered | Cell fills with path color, subtle scale pulse | 50ms | Light tap |
| Waypoint reached | Number circle pulses, brief glow ring | 200ms | Medium impact |
| Wall collision | Path bounces back, cell flashes red briefly | 150ms | Error buzz |
| Undo | Path segment fades out in reverse | 100ms | Light tap |
| Puzzle complete | Grid cells ripple outward, confetti burst | 800ms | Success pattern |
| Streak milestone | Fire emoji animation, streak counter increments | 600ms | Heavy impact |

### Gesture Handling

- **Drag to draw**: Primary interaction. Finger down on cell → drag through adjacent cells → finger up
- **Drag backward to undo**: Retrace path to remove segments
- **Tap cell on path**: Remove path from that cell to the end (alternative undo)
- **Double-tap**: Reset puzzle (with confirmation)
- **Edge gestures**: Avoid conflict with system gestures (back swipe on iOS/Android)

---

## 8. Social & Group System

### Group Lifecycle

```
CREATE GROUP                JOIN GROUP                  MANAGE GROUP
───────────                 ──────────                  ────────────
1. Tap "Create Group"       1. Receive invite link      1. View members
2. Enter name               2. Open link / enter code   2. Remove member (admin)
3. (Optional) description   3. Preview group            3. Promote to admin
4. Get invite code          4. Tap "Join"               4. Edit name/desc
5. Share invite             5. Added to group           5. Delete group (admin)
                                                        6. Leave group
```

### Invite System
- **Invite code**: 6-character alphanumeric (e.g., "ZP3K9M"), case-insensitive
- **Deep link**: `https://icos.app/join/ZP3K9M` → opens app or app store
- **QR code**: generated in-app for in-person sharing
- **Expiry**: codes don't expire (simplicity), but groups have max 50 members
- **Regenerate code**: admin can invalidate old code and create new one

### Leaderboard Scoring

**Daily Leaderboard Ranking:**
1. Primary sort: **Hints used** (ascending — fewer hints = better)
2. Secondary sort: **Solve time** (ascending — faster = better)
3. Tie-breaker: **Undos used** (ascending)

This incentivizes clean, fast solves without penalizing thinking time excessively.

**Weekly Leaderboard Ranking:**
1. **Puzzles completed** (descending — more = better)
2. **Average solve time** (ascending)
3. **Total hints used** (ascending)

### Privacy Controls
- **Profile visibility**: display name + avatar only (no email, no real name required)
- **Group membership**: only visible to other group members
- **Solve data**: only shared within groups you've joined
- **Block user**: prevents them from seeing your data and joining your groups

### Notification Strategy for Groups
- **"[Name] just solved today's puzzle in 0:42!"** — when a group member solves
- **"You're the last one! 9/10 members have solved today"** — gentle nudge
- **"New member joined [Group Name]"** — group activity
- **All notifications are opt-in per group** with granular controls

---

## 9. User Management & Authentication

### Auth Flow

```
FIRST LAUNCH
─────────────
1. App creates anonymous Supabase session
2. User can play immediately (no sign-up wall)
3. Progress saved locally + synced to anonymous account

ACCOUNT CREATION (prompted after 3rd solve or group join)
──────────────────
1. "Create account to save progress & join groups"
2. Options: Email + Password | Google Sign-In | Apple Sign-In
3. Anonymous account linked to new identity (no data loss)
4. Profile setup: choose display name + avatar

RETURNING USER
──────────────
1. Auto-login via stored refresh token
2. If token expired: re-authenticate
3. If new device: sign in → all data synced from server

ACCOUNT DELETION (GDPR/CCPA)
─────────────────
1. Settings → Delete Account
2. Confirmation dialog with clear explanation
3. Supabase cascading delete removes all user data
4. 30-day grace period before permanent deletion
```

### Security Measures
- **Rate limiting**: Max 10 score submissions per hour per user (Edge Function)
- **Anti-cheat**: Server re-validates submitted paths against puzzle solution
- **Timing validation**: Reject solve times under physical minimum (e.g., < 3 seconds for a 5x5)
- **JWT tokens**: Supabase handles token rotation, RLS enforces access control
- **No sensitive data on client**: Solution paths never sent to the app

---

## 10. Scaling Strategy

### Phase 1: Launch (0 - 10K users)
- **Supabase Free/Pro tier** handles all traffic
- **Single PostgreSQL instance** with proper indexes
- **No Redis needed** — PostgreSQL handles leaderboard queries directly
- **CDN**: Supabase Storage + Cloudflare for static assets
- **Cost**: ~$25-50/month

### Phase 2: Growth (10K - 100K users)
- **Supabase Pro tier** with connection pooling (PgBouncer)
- **Add read replicas** for leaderboard queries (separate read/write traffic)
- **Introduce Redis (Upstash)** for hot leaderboard caching
- **Materialized views** for weekly/all-time leaderboards (refresh on schedule)
- **Cost**: ~$100-300/month

### Phase 3: Scale (100K - 1M+ users)
- **Supabase Team/Enterprise tier**
- **Multiple read replicas** across regions
- **Redis cluster** for all leaderboard operations
- **Edge caching** for daily puzzle delivery
- **Database partitioning** on puzzle_attempts by date
- **Consider moving puzzle generation** to a dedicated worker service
- **Cost**: ~$500-2000/month

### Performance Targets
| Metric | Target |
|--------|--------|
| App cold start | < 2 seconds |
| Puzzle load time | < 200ms (cached), < 500ms (network) |
| Path drawing latency | < 16ms per frame (60 FPS) |
| Score submission | < 300ms |
| Leaderboard load | < 500ms |
| Push notification delivery | < 30 seconds |

---

## 11. Development Phases

### Phase 1: Foundation (Weeks 1-3)
**Goal**: Playable game with core mechanics

- [ ] Flutter project setup with folder structure, linting, CI
- [ ] Supabase project setup: database schema, auth, RLS policies
- [ ] Grid rendering engine (CustomPainter)
- [ ] Path drawing with gesture handling
- [ ] Puzzle data model and validation engine
- [ ] Basic puzzle solver (for verification)
- [ ] Hardcoded sample puzzles for testing
- [ ] Basic game screen: grid, path drawing, completion detection
- [ ] Unit tests for puzzle engine

### Phase 2: Core Experience (Weeks 4-6)
**Goal**: Complete single-player experience

- [ ] Puzzle generation algorithm (Backbite + waypoint placement)
- [ ] Daily puzzle system (Supabase Edge Function cron)
- [ ] Timer and scoring
- [ ] Hint system (3/day)
- [ ] Undo/redo
- [ ] Streak tracking
- [ ] Home screen with daily puzzle card
- [ ] Result screen with solve time
- [ ] Statistics screen
- [ ] Settings screen (haptics, sound, theme)
- [ ] Anonymous auth flow
- [ ] Offline puzzle caching

### Phase 3: Social (Weeks 7-9)
**Goal**: Groups and leaderboards

- [ ] Account creation flow (email, Google, Apple)
- [ ] Profile screen (display name, avatar)
- [ ] Group CRUD (create, join, leave, delete)
- [ ] Invite system (code, deep link, QR)
- [ ] Group daily leaderboard
- [ ] Group weekly leaderboard
- [ ] Real-time leaderboard updates (Supabase Realtime)
- [ ] Spoiler-free sharing (image generation)
- [ ] Push notifications (FCM) for daily puzzle + group activity
- [ ] Group member management

### Phase 4: Polish & Launch Prep (Weeks 10-12)
**Goal**: Production-ready, store-ready

- [ ] UI polish: animations, haptics, transitions
- [ ] Celebration animations (Rive)
- [ ] Dark mode + Light mode + AMOLED theme
- [ ] Colorblind mode
- [ ] Onboarding tutorial (interactive)
- [ ] Performance optimization (profiling, jank elimination)
- [ ] Firebase Analytics + Crashlytics integration
- [ ] App store assets (screenshots, description, metadata)
- [ ] Privacy policy and terms of service
- [ ] GDPR/CCPA compliance (account deletion, data export)
- [ ] Beta testing (TestFlight + Google Play Internal Testing)
- [ ] Load testing backend
- [ ] Bug fixes from beta feedback

### Phase 5: Post-Launch (Weeks 13+)
**Goal**: Engagement and growth features

- [ ] Practice mode (unlimited puzzles)
- [ ] Archive (replay past puzzles)
- [ ] Achievement/badge system
- [ ] Ghost Race feature
- [ ] Path Heatmap
- [ ] Global leaderboard
- [ ] Speed run mode
- [ ] Weekly challenges
- [ ] Seasonal themes
- [ ] A/B testing via Remote Config
- [ ] App Store Optimization (ASO)

---

## 12. Project Structure

```
lib/
├── main.dart
├── app.dart                          # MaterialApp, theme, routing
│
├── core/
│   ├── constants/
│   │   ├── app_colors.dart
│   │   ├── app_sizes.dart
│   │   └── app_strings.dart
│   ├── theme/
│   │   ├── app_theme.dart
│   │   ├── dark_theme.dart
│   │   └── light_theme.dart
│   ├── router/
│   │   └── app_router.dart           # GoRouter configuration
│   ├── utils/
│   │   ├── haptics.dart
│   │   ├── date_utils.dart
│   │   └── share_utils.dart
│   └── services/
│       ├── supabase_service.dart
│       ├── analytics_service.dart
│       ├── notification_service.dart
│       └── storage_service.dart
│
├── features/
│   ├── auth/
│   │   ├── data/
│   │   │   └── auth_repository.dart
│   │   ├── domain/
│   │   │   └── auth_state.dart
│   │   ├── providers/
│   │   │   └── auth_provider.dart
│   │   └── presentation/
│   │       ├── login_screen.dart
│   │       └── widgets/
│   │
│   ├── puzzle/
│   │   ├── data/
│   │   │   ├── puzzle_repository.dart
│   │   │   └── puzzle_cache.dart
│   │   ├── domain/
│   │   │   ├── models/
│   │   │   │   ├── puzzle.dart
│   │   │   │   ├── cell.dart
│   │   │   │   ├── wall.dart
│   │   │   │   ├── waypoint.dart
│   │   │   │   └── path_segment.dart
│   │   │   ├── puzzle_engine.dart     # Validation, completion detection
│   │   │   ├── puzzle_generator.dart  # Backbite + waypoint placement
│   │   │   └── puzzle_solver.dart     # DFS solver for hints & verification
│   │   ├── providers/
│   │   │   ├── puzzle_provider.dart
│   │   │   ├── game_state_provider.dart
│   │   │   └── timer_provider.dart
│   │   └── presentation/
│   │       ├── game_screen.dart
│   │       ├── result_screen.dart
│   │       └── widgets/
│   │           ├── grid_painter.dart  # CustomPainter for grid + path
│   │           ├── grid_widget.dart   # GestureDetector wrapper
│   │           ├── waypoint_widget.dart
│   │           ├── timer_widget.dart
│   │           ├── hint_button.dart
│   │           └── celebration_overlay.dart
│   │
│   ├── home/
│   │   ├── providers/
│   │   │   └── home_provider.dart
│   │   └── presentation/
│   │       ├── home_screen.dart
│   │       └── widgets/
│   │           ├── daily_puzzle_card.dart
│   │           ├── streak_badge.dart
│   │           └── group_activity_card.dart
│   │
│   ├── groups/
│   │   ├── data/
│   │   │   └── group_repository.dart
│   │   ├── domain/
│   │   │   ├── models/
│   │   │   │   ├── group.dart
│   │   │   │   └── group_member.dart
│   │   │   └── group_service.dart
│   │   ├── providers/
│   │   │   ├── groups_provider.dart
│   │   │   └── leaderboard_provider.dart
│   │   └── presentation/
│   │       ├── groups_list_screen.dart
│   │       ├── group_detail_screen.dart
│   │       ├── create_group_screen.dart
│   │       ├── join_group_screen.dart
│   │       └── widgets/
│   │           ├── leaderboard_list.dart
│   │           ├── leaderboard_entry.dart
│   │           ├── invite_card.dart
│   │           └── member_list.dart
│   │
│   ├── stats/
│   │   ├── providers/
│   │   │   └── stats_provider.dart
│   │   └── presentation/
│   │       ├── stats_screen.dart
│   │       └── widgets/
│   │           ├── solve_time_chart.dart
│   │           ├── streak_calendar.dart
│   │           └── stat_card.dart
│   │
│   ├── profile/
│   │   ├── data/
│   │   │   └── profile_repository.dart
│   │   ├── providers/
│   │   │   └── profile_provider.dart
│   │   └── presentation/
│   │       ├── profile_screen.dart
│   │       └── widgets/
│   │           ├── avatar_selector.dart
│   │           └── settings_section.dart
│   │
│   └── sharing/
│       ├── domain/
│       │   └── share_card_generator.dart
│       └── presentation/
│           └── share_preview_screen.dart
│
├── shared/
│   ├── widgets/
│   │   ├── app_button.dart
│   │   ├── app_card.dart
│   │   ├── loading_indicator.dart
│   │   └── error_widget.dart
│   └── extensions/
│       ├── context_extensions.dart
│       └── datetime_extensions.dart
│
supabase/
├── migrations/
│   ├── 001_initial_schema.sql
│   ├── 002_rls_policies.sql
│   └── 003_functions.sql
├── functions/
│   ├── daily-puzzle/
│   │   └── index.ts                  # Cron: generate & schedule daily puzzle
│   ├── submit-score/
│   │   └── index.ts                  # Validate & record puzzle completion
│   ├── join-group/
│   │   └── index.ts                  # Process group invite
│   └── generate-share-card/
│       └── index.ts                  # Generate shareable result image
└── seed.sql                          # Sample data for development

test/
├── unit/
│   ├── puzzle_engine_test.dart
│   ├── puzzle_generator_test.dart
│   ├── puzzle_solver_test.dart
│   └── streak_calculator_test.dart
├── widget/
│   ├── grid_painter_test.dart
│   ├── game_screen_test.dart
│   └── leaderboard_test.dart
└── integration/
    ├── game_flow_test.dart
    └── group_flow_test.dart
```

---

## Summary

**Icos** is a beautifully crafted, socially engaging Hamiltonian path puzzle game. The key architectural decisions are:

1. **Flutter** for pixel-perfect, performant cross-platform UI
2. **Supabase (PostgreSQL)** for relational data that naturally fits users, groups, scores, and leaderboards
3. **Offline-first** design so the core game works without internet
4. **Group-based social** that makes daily puzzles a shared experience
5. **Phased development** that delivers a playable game in 3 weeks and a launch-ready product in 12 weeks

The feature set balances familiar daily-puzzle mechanics (proven by Wordle, NYT Games, LinkedIn) with unique differentiators (Ghost Race, Path Heatmap, Puzzle DNA) that give Icos its own identity.
