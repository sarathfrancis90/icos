# Icos - Project Context for AI Agents

_Critical rules and patterns that AI agents must follow when implementing code. Focus on unobvious details that agents might otherwise miss._

## Project Overview

Icos is a cross-platform mobile puzzle game (iOS + Android) built with Flutter. Players draw a continuous path through a grid, connecting numbered waypoints in order while filling every cell. One puzzle per day, same for all users worldwide. Difficulty scales Monday (5x5 easy) to Sunday (8x8 hard).

## Technology Stack & Versions

| Component | Technology | Version/Notes |
|-----------|-----------|---------------|
| Framework | Flutter | 3.x with Impeller engine |
| Language | Dart | Latest stable |
| State Management | Riverpod | 3.x (riverpod ^3.2.x, riverpod_annotation ^4.0.x) |
| Navigation | GoRouter | Latest stable, declarative routes |
| Backend | Supabase | PostgreSQL + Auth + Realtime + Edge Functions + Storage |
| Auth | Supabase Auth (GoTrue) | Anonymous + Email + Google + Apple |
| Edge Functions | Deno runtime | 4 functions: daily-puzzle, submit-score, join-group |
| Local Storage | Hive | Puzzle cache, offline sync queue |
| Settings | SharedPreferences | User preferences, flags |
| Analytics | Firebase Analytics (GA4) | Event tracking |
| Crash Reporting | Firebase Crashlytics | Error monitoring |
| Performance | Firebase Performance Monitoring | App metrics |
| Feature Flags | Firebase Remote Config | A/B testing, kill switches |
| Push Notifications | Firebase Cloud Messaging | Topic-based (daily_puzzle, group_{id}) |
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
│   └── services/                      # supabase, analytics, notification, storage
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
supabase/
├── migrations/                        # SQL migration files
├── functions/                         # Edge Functions (Deno/TypeScript)
└── seed.sql
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
- `StreamProvider` for real-time data (Supabase Realtime subscriptions)
- `NotifierProvider` for local-only state (game state, UI state)
- Global `connectivityProvider` tracks network state for offline fallback
- Clean up Realtime WebSocket subscriptions on group leave, screen disposal, app background
- Maximum 5 concurrent Realtime subscriptions

### Navigation (GoRouter)

- Declarative routes with deep link support
- Routes: `/join/{invite_code}`, `/puzzle/{date}`
- `ShellRoute` for bottom tab navigation (Home, Groups, Stats, Profile)
- State restoration: persist navigation state for OS process death recovery

### Database Schema (7 PostgreSQL Tables)

| Table | Created In | Purpose |
|-------|-----------|---------|
| profiles | Story 1.1 | User identity, display name, avatar, settings |
| puzzles | Story 3.1 | Daily puzzle data (grid, waypoints, walls, metadata) |
| puzzle_attempts | Story 3.4 | Solve records (time, hints, undos, path) |
| streaks | Story 3.5 | Current streak, longest streak, freeze count |
| groups | Story 4.1 | Group name, description, invite code, admin |
| group_members | Story 4.1 | User-group membership with role and join date |
| reports | Story 8.2 | Content moderation reports |

**Critical:** Create tables just-in-time in the story that first needs them. Do NOT create all tables upfront.

**Row-Level Security (RLS):** Every public table MUST have RLS policies. Users can only read their own attempts and data within groups they belong to.

**Database RPC Functions:**
- `get_group_daily_leaderboard(group_id, puzzle_date)` — ranked by hints ASC, time ASC, undos ASC
- `get_group_weekly_leaderboard(group_id, week_start)` — ranked by completed DESC, avg_time ASC

**Indexes:** puzzles(puzzle_date), puzzle_attempts(puzzle_date), puzzle_attempts(user_id), groups(invite_code), group_members(user_id)

### Edge Functions (Deno Runtime)

| Function | Trigger | Purpose |
|----------|---------|---------|
| daily-puzzle | Cron (daily) | Generate tomorrow's puzzle via Backbite algorithm |
| submit-score | HTTP POST | Validate path server-side, record attempt, update streaks |
| join-group | HTTP POST | Validate invite code, enforce 50-member limit |

**All Edge Functions must:**
- Expose `/health` endpoint returning 200 OK
- Use structured JSON logging with correlation IDs
- Check `is_banned` on profiles table before processing
- Validate HMAC signature on score submissions

### Authentication Flow

1. First launch → anonymous auth via Supabase (no sign-up wall)
2. Prompt account creation after 3rd puzzle solve or group join attempt
3. Link anonymous session via `linkIdentity`/`updateUser` (preserve all data)
4. OAuth providers: Google, Apple, Email/Password
5. Session tokens expire after 30 days of inactivity; refresh tokens after 90 days

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
- Portrait-locked on phones (< 768dp); landscape supported on tablets
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
- Tokens: platform-secure credential storage
- Puzzle solutions: NEVER transmitted to client; server re-validates submitted paths
- Score submissions: rate-limited (10/hour/user), HMAC-signed, clock manipulation detection (5-min tolerance)
- User input: sanitize against XSS, SQL injection, Unicode abuse (zalgo, invisible chars)
- Certificate pinning for Supabase API
- Profanity filter on display names and group names (client + server)

### Error Handling Pattern

```dart
// Repository layer
Future<Result<T, AppError>> fetchData() async {
  try {
    final response = await supabase.from('table').select();
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
- **Share cards are client-side** (RepaintBoundary.toImage), NOT server-side Edge Function.
- **Tables created just-in-time** — only in the story that first needs them, not all upfront.
- **No MVP phasing** — all 126 FRs ship in v1. Production-ready from day one.
- **Backbite algorithm** for Hamiltonian path generation — server-side only.
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

# Environment files
# .env.development — Supabase URL + anon key (dev)
# .env.staging — Supabase URL + anon key (staging)
# .env.production — Supabase URL + anon key (prod)

# Supabase CLI
supabase init
supabase start  # Local development
```

---

Last Updated: 2026-03-02
