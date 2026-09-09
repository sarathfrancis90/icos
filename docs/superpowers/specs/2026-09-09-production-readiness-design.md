# Icos Production Readiness — Design Spec

Date: 2026-09-09
Status: approved for autonomous execution (user requested a fully autonomous end-to-end pass)

## 1. Goal

Take the existing Icos Flutter + Supabase daily Hamiltonian-path puzzle game from
"works in a demo" to "submittable to Google Play and the App Store", with a
best-in-class puzzle engine (unique solutions, measured difficulty, deterministic
generation), hardened backend, complete social features (groups, leaderboards,
activity feed), and the release plumbing needed for both stores.

## 2. Audit summary (what was wrong)

Four independent audits (client, backend, release config, algorithm) found:

- Generator never verifies solution uniqueness; backbite variant can deadlock;
  5 of 7 bundled offline puzzles are unsolvable (bipartite parity violation).
- `solution_hash` publicly readable; clients can INSERT `puzzle_attempts` and
  `streaks` directly; no HMAC / clock check; `daily-puzzle` function has no auth;
  unique constraint blocks retries after a failed submission.
- Contract mismatches: daily leaderboard RPC param name, `join-group` response
  shape, missing `decrement_group_member_count` RPC, `profiles.deleted_at`
  missing. Guest → account conversion creates a new user and orphans history.
- Dead code: colorblind palettes never applied, AudioService never initialised,
  share card never captured, notification prompt never shown, pre-cache never
  scheduled, `/puzzle/:date` ignores the date.
- Release: no INTERNET permission in release manifest, iOS pipeline cannot sign
  (no Matchfile / team id), no PrivacyInfo.xcprivacy, no entitlements, AAB
  committed to git, no codegen step in CI.

## 3. Architecture decisions

### 3.1 Puzzle core (shared algorithm, two implementations)

One algorithm, implemented twice (TypeScript for Deno edge functions / CLI,
Dart for on-device hints, practice mode and offline fallback). Both must agree
on validation semantics; a shared JSON fixture set verifies parity.

API (same names in both languages):

```
seedFor(date: string, salt: string): number            // FNV-1a 32-bit over `${salt}:${date}`
Rng(seed)                                               // mulberry32; nextInt(n), nextDouble()
class Grid { size, walls:Set<index> ; isOpen(r,c); neighbors(idx) }
isHamiltonianFeasible(size, walls) -> bool              // connected AND bipartite parity ok
findHamiltonianPath(size, walls, rng, budget) -> idx[]? // Warnsdorff DFS + connectivity pruning, then K backbite moves
countSolutions(size, walls, waypoints, {limit:2, nodeBudget}) -> {count, nodes, solutions:idx[][], exhausted}
chooseWaypoints(path, size, walls, rng, {minWaypoints, maxWaypoints, nodeBudget}) -> waypoints[]
generatePuzzle({size, difficulty, seed, nodeBudget}) -> {gridSize, walls, waypoints, referencePath, difficultyScore, parTimeSeconds}
validatePath(size, walls, waypoints, path:[r,c][]) -> {ok, reason}
```

Rules:
- Waypoints are ordered points on the reference path; order 1 = path start, order N = path end.
- Uniqueness loop: start with endpoints; while `countSolutions(limit 2) == 2`, add the
  reference-path cell at the first index where the second solution diverges; stop at
  maxWaypoints (regenerate if not unique). Then minimality pass for hard/expert
  (remove interior waypoints while still unique); for easy/medium, add helper waypoints
  up to a target count (evenly spaced) so easy days have more clues.
- Pruning in solver: flood-fill reachability of unvisited cells from current cell;
  all remaining waypoints must be reachable; dead-end check (an unvisited cell with
  zero unvisited neighbours that is not the final cell); waypoint-order constraint;
  Warnsdorff ordering; node budget with `exhausted` flag.
- `validatePath` (server and client must agree): length == open cells; all cells in
  bounds, not walls, no duplicates, 4-adjacent; path[0] == waypoint 1;
  path[last] == waypoint N; waypoints appear in ascending order.
- Difficulty by weekday (product rule, UTC): Mon/Tue 5x5 easy, Wed/Thu 6x6 medium,
  Fri/Sat 7x7 hard, Sun 8x8 expert. Parameters:

  | difficulty | walls        | waypoint target        |
  |------------|--------------|------------------------|
  | easy       | 0–1          | unique + pad to 6–7    |
  | medium     | 2–3          | unique + pad to 5–6    |
  | hard       | 3–5          | minimal unique set     |
  | expert     | 5–7          | minimal unique set     |

  Walls are placed with a corridor bias (adjacent to border or existing wall with
  p=0.6) and rejected if `isHamiltonianFeasible` fails.
- `difficultyScore` = solver nodes expanded to find the first solution from the
  start with waypoints given (Warnsdorff), stored for analytics.
- `parTimeSeconds` = round(openCells * k) with k = 2.0/2.4/2.8/3.2 by difficulty.
- Determinism: daily puzzle seed = `seedFor(date, PUZZLE_SEED_SALT)`; the salt is a
  server secret so clients cannot pre-generate future puzzles. Fallback puzzles use
  salt `fallback`. Practice mode uses random seeds.

### 3.2 Data model changes (new migrations only, never edit old ones)

- `puzzles`: drop `solution_hash`; add `difficulty_score int`, `seed_version int default 2`.
- new `puzzle_solutions(puzzle_id pk fk, path jsonb)` — no client policies at all.
- `puzzle_attempts`: drop client INSERT policy; drop unnamed unique constraint,
  add partial unique index `(user_id, puzzle_date) WHERE completed`; add columns
  `verified boolean default false`, `is_archive boolean default false`,
  `attempt_count int default 1`, `updated_at`. Drop cross-member SELECT policy
  (leaderboards go through SECURITY DEFINER RPCs).
- `streaks`: drop client INSERT policy. New `streak_freezes(user_id, frozen_date, pk both)`.
  Streaks are recomputed from attempts + freezes by `recompute_streak(uid)`.
- new `puzzle_sessions(user_id, puzzle_date, started_at, nonce text, pk(user_id,puzzle_date))`.
- `profiles`: add `deleted_at timestamptz`, `last_active_at timestamptz default now()`.
  Add SELECT policy for co-members of a group (display_name/avatar for member lists).
- `groups`/`group_members`: trigger maintains `member_count`; RPCs
  `create_group(name, description) returns groups`, `remove_group_member(group_id, user_id)`,
  `transfer_group_admin(group_id, new_admin_id)`, `delete_group(group_id)` (soft, is_active=false),
  `leave_group(group_id)` (admin leaving auto-transfers to oldest member or deactivates).
  Remove "Anyone can read group by invite code" policy (join goes through edge function).
- new `group_feed(id, group_id, user_id, puzzle_date, event text, created_at)`; RLS
  members SELECT; realtime enabled; written by `submit-score` on verified solve.
- new `app_config(key text pk, value jsonb)` public SELECT; keys:
  `min_supported_version`, `latest_version`, `maintenance_mode`, `store_urls`.
- `reports`: unchanged; client UI added.
- `get_group_daily_leaderboard(p_group_id, p_puzzle_date)` now returns `rank`; both
  leaderboard RPCs get `SET search_path = ''` and an `is_banned` check.
- Cron (pg_cron): `00:05 UTC apply_streak_freezes()`, `Mon 00:00 reset_weekly_freezes()`,
  `01:00 purge_deleted_accounts()` (30-day grace → anonymize), `01:30 purge_inactive_anonymous()`
  (90 days), `00:15 trigger_daily_puzzle_generation()` (generates D+1 and D+2).
- `supabase/config.toml` committed with `verify_jwt` per function.

### 3.3 Edge functions (Deno)

- `_shared/puzzle_core.ts`, `_shared/http.ts` (json response, cors, structured logger with
  correlation id, auth helper, ban check).
- `daily-puzzle`: POST `{date?}`; auth = service role bearer OR user JWT. Generates the
  puzzle for `date` (default tomorrow) if missing, deterministic from seed; inserts
  puzzle + solution. Callable on demand by clients for today/tomorrow only.
- `start-puzzle`: POST `{puzzle_date}` → upsert session, returns `{nonce, started_at}`.
- `submit-score`: POST `{puzzle_date, time_seconds, hints_used, undos_used, path, signature?, queued_at?}`.
  Validates bounds, date window (≤ today, ≥ today-7), path via `validatePath`, HMAC-SHA256
  (key = session nonce) over `puzzle_date|time|hints|undos|sha256(JSON(path))` when a
  session exists, clock plausibility (`time_seconds ≤ server_elapsed + 300`). Upserts
  attempt (partial unique), sets `verified`, `is_archive` (completed_at − puzzle_date > 1 day),
  calls `record_solve(uid, date)` which recomputes streak, inserts `group_feed` rows.
  Returns `{completed, verified, streak, rank_hint?}`.
- `join-group`: returns `{group: {...full row}}`; atomic increment via trigger.

### 3.4 Client

- Auth: guest → account uses `updateUser(email,password)` (email) and
  `linkIdentity(provider)` (OAuth). Native Sign in with Apple (`sign_in_with_apple`)
  and Google (`google_sign_in`) with `signInWithIdToken`; fall back to web OAuth when
  client ids not configured (env `GOOGLE_WEB_CLIENT_ID`, `GOOGLE_IOS_CLIENT_ID`).
- Puzzle: `/puzzle/:date` loads that date (`puzzleForDateProvider(date)`); home shows
  "Solved" state with result when today's attempt exists (server or local record);
  hint solver runs in `Isolate.run`, uses the unique solution: if the player's path is
  a prefix of the solution → next cell, else highlight first wrong cell and suggest undo.
- Colorblind palettes applied in grid painter + snake renderer with pattern overlays.
- AudioService initialised in main; share card rendered via RepaintBoundary and shared
  as PNG; notification pre-permission dialog after first solve; local daily reminder via
  `flutter_local_notifications`; FCM topic `daily_puzzle` when Firebase configured.
- Firebase (Crashlytics + Analytics + Messaging) initialised only when
  `lib/firebase_options.dart` values are provided via env; otherwise a no-op
  `AnalyticsService` backend. Structured `AppLogger` replaces ad-hoc logging.
- Pre-cache tomorrow on app resume; Hive cache trimmed to last 60 puzzles.
- Offline banner outside gameplay; queued-score indicator.
- App config gate: force-update / maintenance screens.
- Groups: fixed contracts, admin actions (remove member, transfer admin, delete group),
  pull-to-refresh, realtime `group_feed` subscription on group detail (max 1 active),
  activity feed tab, report user/group, invite share with deep link + QR.
- Profile: real profanity filter + Unicode sanitizer (shared word list), privacy/terms
  links, dynamic version, account deletion (30-day grace, cancel on sign-in), data export.
- Practice mode (local generator 5x5–7x7, unlimited) and Archive (last 30 days, playable,
  scored but never affects streak).
- Rating prompt via `in_app_review` after 5th solve.

### 3.5 Release

- Android: INTERNET permission, `minSdk 23`, R8 minify + proguard rules, portrait on
  phones via code, remove committed AAB, `.fvmrc` pinned to 3.41.3.
- iOS: `Runner.entitlements` (associated domains, aps-environment, Sign in with Apple),
  `PrivacyInfo.xcprivacy`, portrait-only iPhone, Matchfile, Appfile team ids from env,
  `deploy-ios.yml` builds once via fastlane.
- CI: codegen step; debug APK build; Deno tests; Dart tests; fallback puzzle validity gate.
- `docs/.well-known/assetlinks.json` and `apple-app-site-association` templates.
- `docs/RELEASE_RUNBOOK.md`: every manual step the owner must perform.

## 4. Out of scope for this pass

- Full ARB localisation (English-only launch; strings remain centralised).
- Golden test matrix (visual tests exist via Maestro).
- Global leaderboard, head-to-head, ghost race.
