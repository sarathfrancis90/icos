# Icos - Project Context for AI Agents

_Critical rules and patterns that AI agents must follow when implementing code. Focus on unobvious details that agents might otherwise miss._

## Project Overview

Icos (Dart package `icos`, bundle id `com.icos.game`) is a cross-platform mobile puzzle game (iOS + Android) built with Flutter. Players draw a continuous path through a grid, connecting numbered waypoints in order while filling every cell. One puzzle per day, same for all users worldwide. Difficulty scales Monday (5x5 easy) to Sunday (8x8 hard).

## Technology Stack & Versions

| Component | Technology | Version/Notes |
|-----------|-----------|---------------|
| Framework | Flutter | 3.x with Impeller engine |
| Language | Dart | Latest stable |
| State Management | Riverpod | 2.x (flutter_riverpod ^2.6, riverpod_annotation ^2.6, codegen) |
| Navigation | GoRouter | Latest stable, declarative routes |
| Backend | Neon Lakebase Postgres + Data API | Project `icos` (aws-us-east-1, Free plan); Data API = PostgREST with RLS, Bearer JWT from `/auth/token`; source in `backend/` |
| Auth | Better Auth, self-hosted on a Neon Function | Anonymous + Email + Google + Apple; `bearer`, `jwt` (ES256, 15 min) and `expo` plugins; tables in schema `ba` |
| Server logic | Neon Function `api` (Node 24, Hono) | `/auth/*`, `/api/*` (start-puzzle, submit-score, join-group, export-data, daily-puzzle, report, block, …), `/cron/*` (schedule triggers); shared code in `backend/src/shared/` |
| Email | Resend (HTTPS API from the Function) | Verification, password reset, report alerts; from `noreply@icos.sarathfrancis.work` |
| Local Storage | Hive | Puzzle cache, offline sync queue |
| Settings | SharedPreferences | User preferences, flags |
| Analytics | Firebase Analytics (GA4) | Optional: enabled only when FIREBASE_* env values are set (`lib/firebase_options.dart`); no-op otherwise |
| Crash Reporting | Firebase Crashlytics | Error monitoring |
| Performance | Firebase Performance Monitoring | App metrics |
| Feature Flags / kill switch | `app_config` table | `min_supported_version`, `latest_version`, `maintenance_mode`, `store_urls` (router gates in `app_router.dart`) |
| Notifications | flutter_local_notifications (+ FCM topic `daily_puzzle` when Firebase configured) | Daily reminder + streak-at-risk reminder |
| Animations | Flutter AnimationController + Rive | Celebration animations |
| CI/CD | GitHub Actions + Fastlane | Automated builds and store deployment |

## Project Structure

```
lib/
├── main.dart
├── app.dart                           # MaterialApp, theme, routing
├── core/
│   ├── constants/                     # app_colors, app_sizes, app_strings
│   ├── theme/                         # app_theme, dark_theme, light_theme
│   ├── router/                        # GoRouter configuration
│   ├── utils/                         # haptics, date_utils, share_utils
│   ├── backend/                       # BackendConfig, AuthClient, DataApi, ApiClient, TokenStore
│   └── services/                      # analytics, notification, storage, app config
├── features/
│   ├── auth/                          # data/ domain/ providers/ presentation/
│   ├── puzzle/                        # data/ domain/ providers/ presentation/
│   ├── home/                          # providers/ presentation/
│   ├── groups/                        # data/ domain/ providers/ presentation/
│   ├── stats/                         # providers/ presentation/
│   ├── profile/                       # data/ providers/ presentation/
│   └── sharing/                       # domain/ presentation/
├── shared/
│   ├── widgets/                       # Reusable UI components
│   └── extensions/                    # Dart extension methods
backend/                               # Neon project (run every `neon` command from here)
├── neon.ts                            # compute pins, Function `api`, schedule triggers
├── src/                               # Hono app: auth.ts, routes/, shared/ (puzzle_core, http)
├── migrations/                        # 0001_schema … 0005_leave_feed_events (additive)
├── scripts/                           # migrate, seed_puzzles, smoke, generate
├── test/                              # node --test (DB suites need NEON_TEST_DATABASE_URL)
├── README.md                          # project ids, URLs, CLI commands
└── CONTRACTS.md                       # RPC, route and cron contracts
test/
├── unit/                              # Business logic tests
├── widget/                            # Widget rendering tests
├── integration/                       # End-to-end flow tests
└── goldens/                           # Visual golden tests
```

### Feature Architecture (4-Layer Pattern)

Every feature under `lib/features/{feature}/` follows this structure:
- **data/** — Repository implementations, API clients, cache layers
- **domain/** — Models, business logic, service interfaces
- **providers/** — Riverpod providers (AsyncNotifierProvider, StreamProvider, NotifierProvider)
- **presentation/** — Screens and widgets

## Critical Implementation Rules

### Dart/Flutter Rules

- Use **strict analysis** — `analysis_options.yaml` with strict lint rules, all warnings are errors
- **Never** use `print()` — use structured logging via analytics service
- All async operations must handle errors — repositories return `Result<T, AppError>`, never throw
- Providers use `AsyncValue` pattern — presentation uses `.when(data:, loading:, error:)`
- All user-facing strings go through `intl` package with ARB files for localization
- Use `EdgeInsetsDirectional` (not `EdgeInsets`) for RTL support
- Pin Flutter SDK version via `.fvmrc` file; pin all dependency versions in `pubspec.lock`

### Riverpod State Management

- Use `riverpod_annotation` with code generation (`@riverpod` annotations)
- `AsyncNotifierProvider` for server-synced state (puzzles, groups, leaderboards)
- `StreamProvider` for live data: the group feed polls the Data API every 15 s while the group screen is visible (no websocket)
- `NotifierProvider` for local-only state (game state, UI state)
- Global `connectivityProvider` tracks network state for offline fallback
- Stop feed polling on group leave, screen disposal and app background

### Navigation (GoRouter)

- Declarative routes with deep link support
- Routes: `/join/{invite_code}`, `/puzzle/{date}`, `/reset?token=…` (password-reset universal link → new-password screen)
- `ShellRoute` for bottom tab navigation (Home, Groups, Stats, Profile)
- State restoration: persist navigation state for OS process death recovery

### Database Schema (Neon Postgres, `backend/migrations/`)

All tables are created by `backend/migrations/0001_schema.sql` (SQL functions in `0002_functions.sql`, seed in `0003_seed.sql`, Better Auth tables in `0004_better_auth.sql`). Migrations are additive: never edit a shipped file under `backend/migrations/`; add the next numbered file, run `npm run migrate -- --url <unpooled url>` from `backend/`, then `neon data-api refresh-schema --database neondb`.

| Table | Purpose |
|-------|---------|
| profiles | Root identity (`id` = Better Auth user id; every app FK points here, `ON UPDATE CASCADE`). Settings, `email`, `email_verified`, `providers`, `is_banned`, `deleted_at`, `last_active_at` |
| puzzles | Public puzzle data (NO solution column); readable by `anonymous` |
| puzzle_solutions | Reference path per puzzle; owner (Function) only |
| puzzle_attempts | Solve records; written ONLY by `/api/submit-score`; partial unique on completed |
| puzzle_sessions / submission_log | HMAC nonce per user/date; rate limiting |
| streaks / streak_freezes | Recomputed by `recompute_streak(uid)` from attempts + freezes |
| groups / group_members / group_feed / group_purged_members | Groups, membership (count via trigger), polled activity feed, purged members kept for leaderboards |
| user_blocks | Who blocked whom (writes only via `/api/block` / `/api/unblock`; read via the `list_blocked_users` RPC); hides the blocked user from the blocker's leaderboards and feed |
| app_config | Force-update / maintenance / store URLs; readable by `anonymous` |
| reports / banned_words | Moderation reports (filed via `/api/report`), profanity list used by `contains_profanity()` |
| cron_runs | Idempotency ledger for `/cron/*` deliveries |

Schemas: `public` (app), `ba` (Better Auth: `user`, `session`, `account`, `verification`, `jwks`, `ratelimit`; not exposed through the Data API), `app` (our helpers `app.uid()`, `app.is_service()`), `auth` (Neon's pg_session_jwt; we never define objects there).

**Row-Level Security (RLS):** Every public table MUST have RLS policies, expressed with `app.uid()` (the JWT `sub`). The Data API roles are `authenticated` and `anonymous`; `anonymous` may only read `puzzles` and `app_config`. The Function connects as the owner role, which bypasses RLS. Users can only read their own attempts and data within groups they belong to.

**Database RPC Functions (Data API `rpc/…`; clients never write groups/attempts/streaks directly):**
- `get_group_daily_leaderboard(p_group_id, p_puzzle_date)` — rank, hints ASC, time ASC, undos ASC (+ `verified`)
- `get_group_weekly_leaderboard(p_group_id, p_week_start)` — completed DESC, avg_time ASC
- `create_group`, `leave_group`, `remove_group_member`, `transfer_group_admin`, `delete_group`, `regenerate_invite_code`, `list_blocked_users`
- `request_account_deletion`, `cancel_account_deletion`; owner-only jobs run by `/cron/*`: `purge_deleted_accounts`, `purge_inactive_anonymous`, `apply_streak_freezes`, `reset_weekly_freezes`, `expire_stale_streaks`, `prune_submission_log`
- Blocking is not an RPC: use `/api/block` and `/api/unblock` on the Function
- Full contracts: `backend/CONTRACTS.md`

**Indexes:** puzzles(puzzle_date), puzzle_attempts(puzzle_date), puzzle_attempts(user_id), groups(invite_code), group_members(user_id)

### Backend Function routes (Neon Function `api`, `backend/src/`)

| Route | Purpose |
|-------|---------|
| `ALL /auth/*` | Better Auth (anonymous, email, social, link-social, token, jwks, reset/verify, OAuth callbacks) |
| `GET /api/config` | Public `app_config` (the force-update / maintenance gate needs no JWT) |
| `GET /api/puzzle/:date` | Public puzzle row for a date (before the guest session exists) |
| `POST /api/start-puzzle` | Issue the HMAC nonce for (user, date) |
| `POST /api/submit-score` | Validate path server-side, record attempt, update streaks, feed insert |
| `POST /api/join-group` | Validate invite code, enforce 50-member limit |
| `GET/POST /api/export-data` | Full data export (JSON attachment) |
| `POST /api/daily-puzzle` | Generate a puzzle; users may ask for today/tomorrow only |
| `POST /api/report` | File a moderation report and send the alert email |
| `POST /api/block`, `POST /api/unblock` | Block / unblock a user (a new block also files a `blocked_by_user` report) |
| `POST /api/account/upgrade-email` | Same-id guest → email account |
| `POST /cron/<job>` | Neon schedule triggers (`neon.ts`), idempotent per `scheduled_at` |
| `GET /health` | `{status, fn, ts}` |

**All `/api/*` routes must** (helpers in `backend/src/shared/http.ts`, `backend/src/identity.ts`, `backend/src/routes/common.ts`):
- Use the structured `Logger` (correlation id from `x-correlation-id`) and the `{error, code}` error contract
- Check `is_banned` / `deleted_at` via `banCheck` (`identity.ts`)
- `/api/submit-score` verifies HMAC-SHA256(nonce from `/api/start-puzzle`) over `date|time|hints|undos|sha256(path)`, clock plausibility (5 min), date window, and re-validates the path with `puzzle_core.validatePath`
- Puzzle generation requires `PUZZLE_SEED_SALT` in the Function env; generation is deterministic per date (`/cron/daily-puzzle` keeps a 14-day buffer)
- `/cron/*` accepts only Neon trigger deliveries (`X-Neon-Trigger-Invocation-Id`; Neon strips client-set copies)

### Authentication Flow

1. First launch → anonymous session via Better Auth (`/auth/sign-in/anonymous`; no sign-up wall)
2. Prompt account creation after 3rd puzzle solve or group join attempt
3. Upgrades keep the user id (all progress stays): Google/Apple via `/auth/link-social` with the guest bearer, email via `POST /api/account/upgrade-email`. Signing in to a different existing account discards the guest (Better Auth `anonymous.onLinkAccount`)
4. Providers: Google (native id token), Apple (native id token on iOS; on Android the browser flow through Better Auth's authorization proxy, callback `io.icos://oauth-callback`), Email/Password (reset link `https://icos.sarathfrancis.work/reset?token=…`; a reset does not sign the player in)
5. Sessions last 30 days (refreshed daily on use); the Data API JWT lasts 15 minutes and is re-minted from `/auth/token`

### Offline-First Architecture

- Pre-cache tomorrow's puzzle 12+ hours before release via background fetch
- 7 bundled fallback puzzles in `assets/puzzles/fallback_puzzles.json` for first-launch offline
- Offline sync queue in Hive — queue results when offline, sync with exponential backoff on reconnect
- Suppress offline banner during active puzzle play (preserve flow state)
- All core gameplay features work identically offline
- Hive cache limited to 50MB with LRU eviction

### Performance Targets

- Path drawing: 60 FPS minimum on 2022+ devices
- Cold start: < 2 seconds
- Cached puzzle load: < 200ms
- Score submission: < 300ms
- Auto-save per move: < 5ms (non-blocking I/O)
- Memory during puzzle rendering: < 100MB

### Design System

- **Dark Immersive** theme: deep navy background (#0A1628), electric blue path (#3B82F6), coral-orange waypoints (#FF6B35)
- Three themes: light, dark, system (follows OS)
- Theme transition: 300ms cross-fade
- Touch targets: minimum 44x44dp (Apple HIG + Material Design)
- WCAG 2.1 AA contrast ratios (4.5:1 body, 3:1 large text)
- Reduced motion: respect system setting, replace animations with static alternatives
- Grid sizing formula: `(screen_width - 48px) / grid_columns`
- Portrait-locked on all devices in v1 (`main.dart` sets portrait only); tablet landscape is a follow-up
- Tablet: grid capped at 500dp width, content max 600dp width

### Accessibility (Non-Negotiable)

- All non-game UI: complete VoiceOver/TalkBack semantic labels
- Puzzle grid cells: "Row N, Column M, [empty/filled/waypoint N/wall]"
- Colorblind mode: 3 palettes (deuteranopia, protanopia, tritanopia) with pattern overlays
- Dynamic type: support up to 200% scaling without layout breakage
- Focus indicators: 2dp high-contrast ring on all interactive elements for keyboard/switch nav
- Tap-to-select: alternative to drag input for motor-impaired users
- Visual alternatives for haptic/audio feedback on devices without haptic motors

### Testing Strategy

- **Unit tests** (`test/unit/`): Business logic, puzzle engine, streak calculator
- **Widget tests** (`test/widget/`): Component rendering, interactions
- **Integration tests** (`test/integration/`): End-to-end flows
- **Golden tests** (`test/goldens/`): Visual regression for all custom components
  - Theme matrix: light, dark, colorblind variants
  - 4 device sizes: iPhone SE, iPhone 15, Pixel 7, iPad Mini
  - Dynamic type: 100%, 150%, 200% scale factors
- **Claude Code hooks:** Visual validation runs on every Dart file edit; golden gate on response completion

### Security Rules

- All network: HTTPS/TLS 1.2+
- Tokens: session token and cached JWT in `flutter_secure_storage` (`lib/core/backend/token_store.dart`), never SharedPreferences
- The Data API requires a JWT on every request (RLS by `app.uid()`); clients never hold a privileged key. Secrets live only in the Neon Function env (`backend/.env.neon`, git-ignored) and GitHub Actions secrets
- Puzzle solutions: NEVER transmitted to client; server re-validates submitted paths
- Score submissions: rate-limited (40/hour/user), HMAC-signed, clock manipulation detection (5-min tolerance)
- User input: sanitize against XSS, SQL injection, Unicode abuse (zalgo, invisible chars)
- No certificate pinning (Neon certificates rotate; TLS 1.2+ via the platform trust store)
- Profanity filter on display names and group names (client + server)

### Error Handling Pattern

```dart
// Repository layer
Future<Result<T, AppError>> fetchData() async {
  try {
    final response = await dataApi.from('table').select();
    return Result.success(Model.fromJson(response));
  } on PostgrestException catch (e) {
    return Result.failure(AppError.database(e.message));
  } on SocketException {
    return Result.failure(AppError.network('No connection'));
  }
}

// Provider layer — uses AsyncValue
@riverpod
Future<T> myProvider(Ref ref) async {
  final result = await ref.read(repositoryProvider).fetchData();
  return result.when(
    success: (data) => data,
    failure: (error) => throw error,
  );
}

// Presentation layer
myProvider.when(
  data: (data) => DataWidget(data),
  loading: () => ShimmerSkeleton(),
  error: (e, st) => ErrorWidget(e, onRetry: () => ref.invalidate(myProvider)),
);
```

### Critical Don't-Miss Rules

- **One puzzle per day per user** — enforced server-side. First server-verified solve wins across all devices.
- **Daily rollover at midnight UTC** — not local time. Weekly boundaries: Monday 00:00 UTC to Sunday 23:59:59 UTC.
- **Never transmit puzzle solution paths to the client** — server re-validates on submission.
- **Share cards are client-side** (RepaintBoundary.toImage), NOT server-side.
- **Tables created just-in-time** — only in the story that first needs them, not all upfront.
- **No MVP phasing** — all 126 FRs ship in v1. Production-ready from day one.
- **Puzzle core** (`backend/src/shared/puzzle_core.ts` and its Dart mirror `lib/features/puzzle/domain/solver/`): Warnsdorff DFS + canonical backbite for the reference path, pruned solver proving exactly ONE solution, waypoints chosen to enforce uniqueness (fewer clues = harder). Keep both implementations in sync; `backend/src/shared/fixtures/puzzle_parity.json` is the parity test.
- **Weekday difficulty:** Mon/Tue 5x5 easy, Wed/Thu 6x6 medium, Fri/Sat 7x7 hard, Sun 8x8 expert (UTC).
- **Celebration animation:** 800ms total (200ms grid ripple + 600ms confetti burst). Reduced motion: green glow on grid border.
- **Pre-permission screen** before OS notification dialog — shown after first puzzle completion.
- **Group max 50 members.** Invite codes are 6-char alphanumeric.
- **Streak freeze:** 1 per week, auto-applied at midnight UTC if player has one available and missed that day.
- **Account deletion:** 30-day grace period. Leaderboard entries anonymized to "Deleted User", not removed.
- **Anonymous data purge:** 90 days of inactivity.

## Planning Artifacts

All planning documents are in `_bmad-output/planning-artifacts/`:
- `prd.md` — Product Requirements Document (126 FRs, 50 NFRs)
- `architecture.md` — Technical Architecture
- `ux-design-specification.md` — UX Design Specification
- `epics.md` — 11 Epics, 57 Stories with full acceptance criteria
- `visual-testing-strategy.md` — Golden test specifications
- `implementation-readiness-report-2026-03-02.md` — Readiness assessment

## Sprint Tracking

Sprint status tracked in `_bmad-output/implementation-artifacts/sprint-status.yaml`.
Story files created in `_bmad-output/implementation-artifacts/` as `{story-key}.md`.

To create a story for implementation, use: `/bmad-bmm-create-story`
To implement a story, use: `/bmad-bmm-dev-story`

## Environment Setup

```bash
# Flutter project creation
flutter create --org com.icos --project-name icos --platforms ios,android .

# App environment files (copy .env.example):
# .env.development / .env.staging / .env.production with
#   API_BASE_URL       Neon Function origin, trailing slash (Better Auth at /auth/, routes at /api/)
#   DATA_API_URL       Neon Data API root (…/neondb/rest/v1)
#   GOOGLE_WEB_CLIENT_ID, GOOGLE_IOS_CLIENT_ID
#   APPLE_SERVICE_ID   com.icos.game.signin
# At runtime https://icos.sarathfrancis.work/config.json (docs/config.json) overrides both hosts.

# Backend (Neon CLI; run from backend/, linked via the git-ignored .neon file)
cd backend
npm ci && npm run typecheck && npm test        # DB suites need NEON_TEST_DATABASE_URL
neon deploy --env .env.neon -y                 # Function + triggers + compute pins (neon.ts)
npm run migrate -- --url <unpooled url>        # apply backend/migrations/*
neon data-api refresh-schema --database neondb # after every migration
```

---

Last Updated: 2026-11-08 (Neon migration: see `docs/superpowers/specs/2026-11-08-neon-migration-design.md`, `backend/README.md` and `docs/RELEASE_RUNBOOK.md`)
