---
stepsCompleted: [1, 2, 3, 4, 5, 6, 7, 8]
inputDocuments:
  - product-brief-Zip-2026-03-02.md
  - prd.md
  - PLAN.md
workflowType: 'architecture'
project_name: 'Zip'
user_name: 'Sarathfrancis'
date: '2026-03-02'
lastStep: 8
status: 'complete'
completedAt: '2026-03-02'
classification:
  projectType: mobile_app
  domain: gaming_entertainment
  complexity: low
  projectContext: greenfield
---

# Architecture Decision Document - Icos

**Author:** Sarathfrancis
**Date:** 2026-03-02

_This document defines the comprehensive architectural decisions for Icos, a cross-platform mobile puzzle game built with Flutter and Supabase. All AI agents implementing this project must follow these decisions exactly to ensure consistent, conflict-free development._

---

## Project Context Analysis

### Requirements Overview

**Functional Requirements:**

Icos contains 61 functional requirements organized into 10 categories that collectively define a daily puzzle game with social group mechanics:

| FR Category | Count | Architectural Implications |
|-------------|-------|---------------------------|
| Puzzle Engine (FR1-FR11) | 11 | Custom rendering pipeline via CustomPainter, gesture recognition system, real-time path validation, haptic feedback integration |
| Daily Puzzle System (FR12-FR16) | 5 | Server-side scheduled puzzle generation, client-side caching with background fetch, date-based puzzle delivery |
| Hint System (FR17-FR19) | 3 | Partial solution computation, daily limit tracking with UTC reset, per-attempt hint counter |
| User Management (FR20-FR27) | 8 | Anonymous-to-authenticated account linking, multi-provider OAuth, profile management, GDPR deletion flow |
| Streaks & Statistics (FR28-FR33) | 6 | Persistent streak state with freeze mechanics, aggregated statistics computation, local+remote state sync |
| Groups & Leaderboards (FR34-FR44) | 11 | Group CRUD with invite system, real-time leaderboard subscriptions, admin role management, spoiler prevention logic |
| Sharing (FR45-FR48) | 4 | Dynamic image generation for share cards, native OS share sheet integration, deep link routing |
| Offline Support (FR49-FR53) | 5 | Offline-first data layer, background puzzle pre-caching, sync queue with conflict resolution, bundled fallback content |
| Settings & Preferences (FR54-FR58) | 5 | Local preference persistence, theme system, per-group notification configuration |
| Navigation & Structure (FR59-FR61) | 3 | Bottom tab navigation, deep link handling for group invites, home screen aggregation |

**Non-Functional Requirements:**

Icos defines 22 NFRs across 5 categories that constrain architectural choices:

| NFR Category | Count | Key Constraints |
|--------------|-------|-----------------|
| Performance (NFR1-NFR6) | 6 | 60 FPS path drawing, <2s cold start, <200ms cached puzzle load, <500ms network puzzle load, <300ms score submission, <500ms leaderboard load |
| Security (NFR7-NFR12) | 6 | HTTPS/TLS 1.2+, secure token storage, server-side solution validation, rate limiting, anti-cheat timing validation, RLS access control |
| Scalability (NFR13-NFR15) | 3 | 10K concurrent users, O(log n) database lookups, batch puzzle pre-generation |
| Accessibility (NFR16-NFR19) | 4 | 44x44dp touch targets, colorblind mode with patterns, WCAG 2.1 AA contrast, reduced motion support |
| Reliability (NFR20-NFR22) | 3 | Zero data loss on offline-to-online sync, <1% crash rate, 95% cache refresh success rate |

**Scale & Complexity:**

- Primary domain: Mobile App (Gaming / Entertainment)
- Complexity level: Low (no regulatory compliance, no payment processing, no sensitive data beyond email)
- Project context: Greenfield -- new product built from scratch
- Estimated architectural components: 6 feature modules + core services + backend functions
- User scale: 5K MAU at 3-month, 50K MAU at 12-month targets

### Technical Constraints & Dependencies

1. **Single codebase requirement** -- Flutter must deliver iOS 15.0+ and Android 8.0+ (API 26) from a single Dart codebase with 95%+ code reuse
2. **Rendering pipeline** -- Path drawing must use Impeller engine via CustomPainter/Canvas API for 60 FPS minimum on 2022+ mid-range devices
3. **Backend platform** -- Supabase provides PostgreSQL, Auth, Realtime, Edge Functions, and Storage as a unified platform; no custom backend server
4. **Offline-first constraint** -- Core puzzle gameplay must function without any network connectivity; all network-dependent features must degrade gracefully
5. **Anti-cheat integrity** -- Solution paths are never transmitted to the client; server re-validates all submitted paths
6. **App size budget** -- Initial download must remain under 50 MB (target: 35-40 MB)

### Cross-Cutting Concerns Identified

1. **Authentication state** -- Flows through every feature module; anonymous sessions must seamlessly upgrade to authenticated accounts without data loss
2. **Offline/online state** -- Affects puzzle loading, score submission, leaderboard display, group operations; requires sync queue and connectivity monitoring
3. **Error handling** -- Consistent error presentation across all features; distinguishes user-facing errors from technical logging
4. **Analytics tracking** -- Every significant user action must emit analytics events via Firebase Analytics
5. **Accessibility** -- Colorblind mode, reduced motion, and touch target sizing affect all visual components
6. **Theme system** -- Light/dark mode propagation across all screens and the game canvas
7. **Haptic feedback** -- Configurable tactile feedback across puzzle engine and UI interactions

---

## Starter Template Evaluation

### Primary Technology Domain

Mobile App (iOS + Android) using Flutter, identified from project requirements and the PRD's explicit technology stack specification.

### Starter Options Considered

| Option | Description | Verdict |
|--------|-------------|---------|
| `flutter create` (standard) | Default Flutter project scaffold with minimal structure | Too bare -- requires significant manual setup for feature-based architecture |
| `very_good_cli` (VGC) | Opinionated CLI from Very Good Ventures with built-in testing, linting, CI templates | Strong candidate but prescribes its own conventions that may conflict with project-specific patterns |
| Custom scaffold based on PLAN.md | Hand-crafted project structure following the detailed structure in PLAN.md Section 12 | Best fit -- the PLAN.md already defines a comprehensive, feature-based project structure |

### Selected Starter: Custom Flutter Project from PLAN.md Structure

**Rationale for Selection:**

The PLAN.md provides a detailed, project-specific directory structure (Section 12) that maps directly to the PRD's functional requirement categories. Using this as the base ensures zero friction between the architecture document and the implementation plan. The first implementation story initializes the Flutter project and scaffolds this structure.

**Initialization Command:**

```bash
flutter create --org com.icos --project-name icos --platforms ios,android icos
```

Post-creation, the project structure is reorganized to match the feature-based architecture defined in Section 12 of PLAN.md.

**Architectural Decisions Provided by Starter:**

**Language & Runtime:**
- Dart 3.8+ (ships with Flutter 3.41.x)
- Null safety enabled by default
- Strong typing with analysis_options.yaml configured for strict mode

**Styling Solution:**
- Flutter's built-in ThemeData with custom extensions
- Two theme variants: light and dark (AMOLED dark deferred to post-MVP)
- Design tokens defined in `core/constants/` (colors, sizes, strings)

**Build Tooling:**
- Flutter build system with Gradle (Android) and Xcode (iOS)
- Fastlane for automated store deployment
- GitHub Actions for CI/CD

**Testing Framework:**
- `flutter_test` for unit and widget tests
- `integration_test` for end-to-end flows
- Golden tests for visual regression on game grid rendering

**Code Organization:**
- Feature-based architecture: each feature in `lib/features/{feature}/` with `data/`, `domain/`, `providers/`, and `presentation/` subdirectories
- Core services and utilities in `lib/core/`
- Shared widgets and extensions in `lib/shared/`

**Development Experience:**
- Hot reload via Flutter's stateful hot reload
- Flutter DevTools for performance profiling and widget inspection
- `flutter analyze` with custom lint rules for code quality enforcement

---

## Core Architectural Decisions

### Decision Priority Analysis

**Critical Decisions (Block Implementation):**
1. State management approach (Riverpod 3.x)
2. Database schema and access patterns (Supabase PostgreSQL with RLS)
3. Authentication strategy (Supabase Auth with anonymous-to-authenticated linking)
4. Offline-first data architecture (Hive cache + sync queue)
5. Puzzle engine rendering approach (CustomPainter + Canvas API)

**Important Decisions (Shape Architecture):**
6. Navigation and deep linking (GoRouter)
7. Real-time communication (Supabase Realtime)
8. Push notification delivery (Firebase Cloud Messaging)
9. Analytics and monitoring (Firebase Analytics + Crashlytics + Performance)
10. API communication patterns (Supabase client SDK + Edge Functions)

**Deferred Decisions (Post-MVP):**
- Redis caching layer (add when leaderboard queries exceed PostgreSQL performance at scale)
- CDN for puzzle delivery (add when user base exceeds 100K)
- Database read replicas (add when concurrent users exceed 10K)
- Materialized views for weekly/all-time leaderboards

### Data Architecture

**Database: PostgreSQL via Supabase**
- Version: PostgreSQL 15+ (managed by Supabase)
- Rationale: Relational model naturally fits users, groups, scores, and leaderboards; JSONB for flexible puzzle data; window functions (RANK(), DENSE_RANK()) for leaderboard computation; Row-Level Security for access control

**Core Tables:**

| Table | Purpose | Key Fields |
|-------|---------|------------|
| `public.profiles` | User profile data extending auth.users | id (UUID, FK to auth.users), display_name, avatar_id, is_anonymous, timezone |
| `public.puzzles` | Daily puzzle definitions | id, puzzle_date (UNIQUE), grid_width, grid_height, day_of_week, difficulty, waypoints (JSONB), walls (JSONB), solution_path (JSONB, server-only) |
| `public.puzzle_attempts` | User solve records | id, user_id, puzzle_id, puzzle_date, solve_time_ms, hints_used, undos_used, completed, verified, UNIQUE(user_id, puzzle_date) |
| `public.streaks` | Streak tracking per user | user_id (PK), current_streak, longest_streak, last_solve_date, streak_freezes_remaining |
| `public.groups` | Group definitions | id, name, invite_code (UNIQUE, 6-char), created_by, max_members |
| `public.group_members` | Group membership junction | group_id + user_id (composite PK), role ('admin' or 'member'), joined_at |

**Database Functions (RPCs):**
- `get_group_daily_leaderboard(group_id, date)` -- Returns ranked members by hints_used ASC, solve_time_ms ASC
- `get_group_weekly_leaderboard(group_id, week_start)` -- Returns ranked members by puzzles_completed DESC, avg_time ASC

**Indexes:**
- `idx_puzzles_date` on puzzles(puzzle_date)
- `idx_attempts_date` on puzzle_attempts(puzzle_date)
- `idx_attempts_user` on puzzle_attempts(user_id)
- `idx_attempts_date_time` on puzzle_attempts(puzzle_date, solve_time_ms)
- `idx_groups_invite` on groups(invite_code)
- `idx_group_members_user` on group_members(user_id)

**Data Validation Strategy:**
- Client-side: Dart model classes with factory constructors validate data shape on deserialization
- Server-side: Edge Functions validate puzzle solution paths, timing constraints, and rate limits
- Database-level: PostgreSQL CHECK constraints and UNIQUE constraints enforce data integrity
- RLS policies enforce row-level access control at the database layer

**Migration Approach:**
- SQL migration files in `supabase/migrations/` directory, numbered sequentially (001_, 002_, etc.)
- Applied via Supabase CLI (`supabase db push`) during development
- Production migrations managed via Supabase Dashboard or CI/CD pipeline

**Caching Strategy:**
- Local (Hive): Puzzle data cached on-device 24 hours before release; offline sync queue for pending submissions
- Local (SharedPreferences): User settings, theme preference, haptic toggle
- Server-side (PostgreSQL): No additional caching layer at launch; Redis (Upstash) added post-MVP when leaderboard query performance degrades at scale

### Authentication & Security

**Authentication: Supabase Auth (GoTrue)**
- Anonymous auth on first app launch -- user plays immediately with no sign-up wall
- Account creation via email/password, Google Sign-In, or Apple Sign-In
- Account linking: anonymous session upgrades to authenticated account without data loss (Supabase `linkIdentity` / `updateUser` API)
- JWT tokens stored in platform-secure credential storage (iOS Keychain, Android Keystore)
- Token refresh handled automatically by Supabase Dart client

**Authorization Patterns:**
- Row-Level Security (RLS) policies on all public tables
- Users can only read/write their own puzzle attempts
- Users can only read group data for groups they belong to
- Group admins have additional write permissions (remove members, regenerate invite codes, delete group)
- Edge Functions use service role key for privileged operations (puzzle generation, score verification)

**Security Measures:**
- All network communication over HTTPS/TLS 1.2+
- Solution paths are never transmitted to the client
- Score submissions validated server-side: path re-verified against stored solution, timing checked (minimum 3 seconds for any grid)
- Rate limiting: max 10 score submissions per hour per user (enforced in Edge Function)
- Account deletion with 30-day grace period; cascading delete removes all user data

### API & Communication Patterns

**Primary API: Supabase Client SDK (supabase_flutter)**
- Direct database access via PostgREST API for CRUD operations (profiles, groups, group_members)
- RPC calls for complex queries (leaderboard functions)
- Real-time subscriptions via Supabase Realtime for live leaderboard updates
- Storage API for avatar uploads

**Edge Functions (Deno runtime):**

| Function | Trigger | Purpose |
|----------|---------|---------|
| `daily-puzzle` | Cron (scheduled) | Generate and schedule daily puzzles 30 days in advance |
| `submit-score` | HTTP POST | Validate submitted path against solution, record attempt, update streak |
| `join-group` | HTTP POST | Process group invite codes, validate membership limits, add member |
| `generate-share-card` | HTTP POST | Generate spoiler-free share card image |

**Error Handling Standard:**
- All API responses follow Supabase's built-in error format: `{ data, error }` tuple
- Edge Functions return standardized error responses: `{ error: { code: string, message: string } }`
- Client-side: errors mapped to user-friendly messages via error code lookup
- Network errors trigger offline fallback behavior

**Real-time Communication:**
- Supabase Realtime subscriptions on `puzzle_attempts` table for live leaderboard updates within groups
- Channel-based subscriptions scoped to group_id for efficient resource usage
- Subscriptions paused when app is backgrounded, resumed on foreground

### Frontend Architecture

**State Management: Riverpod 3.x**
- Version: riverpod ^3.2.x, riverpod_annotation ^4.0.x
- Rationale: Compile-safe providers, testable, supports async/stream states, automatic retry for transient failures, pause/resume for off-screen providers
- Provider organization: one provider file per feature concern (e.g., `puzzle_provider.dart`, `game_state_provider.dart`, `timer_provider.dart`)
- State classes use immutable data with `freezed` or manual `copyWith` patterns

**Component Architecture:**
- Feature-based organization: each feature module is self-contained with data, domain, providers, and presentation layers
- Presentation layer: screens (full pages) and widgets (reusable components)
- Domain layer: models (data classes), services (business logic), engines (computation)
- Data layer: repositories (data access abstraction over Supabase/Hive)

**Routing: GoRouter**
- Declarative route definitions in `core/router/app_router.dart`
- Deep link support for group invites: `https://icos.sarathfrancis.work/join/{invite_code}`
- Bottom navigation with ShellRoute for persistent tab bar across Home, Groups, Stats, Profile
- Route guards for authenticated-only routes (group creation, profile editing)

**Performance Optimization:**
- Puzzle rendering via CustomPainter with `shouldRepaint` optimization to avoid unnecessary redraws
- Canvas operations batched within single paint calls for minimal frame time
- Riverpod providers with `autoDispose` to release memory for off-screen features
- Image assets compressed and sized for target display densities (1x, 2x, 3x)
- Rive animations loaded lazily on first puzzle completion

### Infrastructure & Deployment

**Hosting: Supabase (managed)**
- Database, Auth, Realtime, Edge Functions, and Storage all hosted on Supabase
- Supabase project region selected for primary user base geography
- Connection pooling via PgBouncer (built into Supabase Pro tier)

**CI/CD Pipeline: GitHub Actions + Fastlane**
- On push to `main`: run `flutter analyze`, `flutter test`, build debug APK/IPA
- On tag/release: build release APK/AAB + IPA, deploy to TestFlight (iOS) and Google Play Internal Testing (Android) via Fastlane
- Supabase migrations applied via `supabase db push` in CI pipeline for staging environment
- Environment configuration via `.env` files (development, staging, production) with Supabase URL and anon key

**Monitoring & Logging:**
- Firebase Crashlytics: crash reporting with symbolicated stack traces
- Firebase Performance Monitoring: app startup time, screen render time, network request latency
- Firebase Analytics: custom events for puzzle completion, group activity, sharing, onboarding milestones
- Firebase Remote Config: feature flags for A/B testing and gradual rollouts

**Scaling Strategy (phased):**

| Phase | User Scale | Infrastructure Changes |
|-------|-----------|----------------------|
| Launch | 0-10K MAU | Supabase Free/Pro tier, single PostgreSQL instance, no Redis |
| Growth | 10K-100K MAU | Supabase Pro with connection pooling, read replicas, Redis (Upstash) for leaderboard caching, materialized views |
| Scale | 100K-1M+ MAU | Supabase Team/Enterprise, multiple read replicas, Redis cluster, database partitioning on puzzle_attempts by date, edge caching for puzzle delivery |

### Decision Impact Analysis

**Implementation Sequence:**
1. Flutter project initialization with Supabase and Firebase SDK integration
2. Database schema creation (migrations 001-003) with RLS policies
3. Authentication flow (anonymous + OAuth providers)
4. Puzzle engine (CustomPainter rendering + path validation)
5. Daily puzzle system (Edge Function + client caching)
6. Groups and leaderboards (CRUD + Realtime subscriptions)
7. Sharing system (share card generation + deep links)
8. Push notifications (FCM integration)
9. Polish (animations, haptics, accessibility, themes)

**Cross-Component Dependencies:**
- Auth state is consumed by every feature module; must be initialized before any other provider
- Puzzle engine depends on offline cache (Hive) and network layer (Supabase) for puzzle data
- Group leaderboards depend on auth (user identity), puzzle attempts (solve data), and Realtime (live updates)
- Sharing depends on puzzle completion state and group membership for context
- Analytics depends on auth (user ID) and all feature modules (event sources)

---

## Implementation Patterns & Consistency Rules

### Pattern Categories Defined

**Critical Conflict Points Identified:** 28 areas where AI agents could make different choices, organized into 5 categories below.

### Naming Patterns

**Database Naming Conventions:**
- Tables: `snake_case`, plural (e.g., `profiles`, `puzzles`, `puzzle_attempts`, `group_members`)
- Columns: `snake_case` (e.g., `user_id`, `solve_time_ms`, `display_name`, `created_at`)
- Foreign keys: `{referenced_table_singular}_id` (e.g., `user_id`, `puzzle_id`, `group_id`)
- Indexes: `idx_{table}_{column}` (e.g., `idx_puzzles_date`, `idx_attempts_user`)
- Functions: `snake_case` verb-noun (e.g., `get_group_daily_leaderboard`)
- Constraints: implied by column definition or explicit `UNIQUE({columns})`

**API Naming Conventions:**
- Edge Function names: `kebab-case` (e.g., `daily-puzzle`, `submit-score`, `join-group`)
- Edge Function HTTP methods: POST for mutations, GET for queries
- Supabase RPC function calls: `snake_case` matching database function names
- Query parameters: `snake_case` (e.g., `group_id`, `puzzle_date`)

**Dart/Flutter Code Naming Conventions:**
- Files: `snake_case.dart` (e.g., `puzzle_engine.dart`, `game_screen.dart`, `auth_provider.dart`)
- Classes: `PascalCase` (e.g., `PuzzleEngine`, `GameScreen`, `AuthProvider`)
- Variables and functions: `camelCase` (e.g., `solveTimeMs`, `getUserProfile`, `isAuthenticated`)
- Constants: `camelCase` for top-level, `camelCase` for class members (e.g., `defaultGridSize`, `maxGroupMembers`)
- Enums: `PascalCase` for type, `camelCase` for values (e.g., `Difficulty.easy`, `GroupRole.admin`)
- Providers: `camelCase` + `Provider` suffix (e.g., `puzzleProvider`, `authStateProvider`, `groupLeaderboardProvider`)
- Widgets: `PascalCase` matching file name (e.g., `GridPainter` in `grid_painter.dart`)
- Repositories: `PascalCase` + `Repository` suffix (e.g., `PuzzleRepository`, `GroupRepository`)
- Services: `PascalCase` + `Service` suffix (e.g., `SupabaseService`, `AnalyticsService`)

**Asset Naming Conventions:**
- Images: `snake_case` (e.g., `avatar_default.png`, `icon_streak_fire.svg`)
- Rive animations: `snake_case` (e.g., `celebration_confetti.riv`)
- Fonts: original font family name (e.g., `Inter`, `JetBrainsMono`)

### Structure Patterns

**Project Organization:**
Feature-based architecture with 4-layer internal structure per feature:

```
lib/features/{feature_name}/
  data/           # Repository implementations, data sources
  domain/         # Models, business logic, engine classes
    models/       # Data classes (immutable, with fromJson/toJson)
  providers/      # Riverpod providers for this feature
  presentation/   # Screens and widgets
    widgets/      # Reusable widgets scoped to this feature
```

**Where things live:**
- Tests: `test/unit/`, `test/widget/`, `test/integration/` -- mirroring source structure
- Core services: `lib/core/services/` (Supabase, Analytics, Notifications, Storage)
- Core utilities: `lib/core/utils/` (haptics, date_utils, share_utils)
- Core constants: `lib/core/constants/` (colors, sizes, strings)
- Core theme: `lib/core/theme/` (app_theme, dark_theme, light_theme)
- Core router: `lib/core/router/` (app_router with GoRouter config)
- Shared widgets: `lib/shared/widgets/` (app_button, app_card, loading_indicator, error_widget)
- Shared extensions: `lib/shared/extensions/` (context_extensions, datetime_extensions)
- Supabase migrations: `supabase/migrations/` (numbered SQL files)
- Supabase Edge Functions: `supabase/functions/{function-name}/index.ts`

**File Structure Patterns:**
- One public class per file (matching file name)
- Barrel exports (`index.dart`) are NOT used -- import each file explicitly
- Model files contain a single data class with `fromJson`, `toJson`, and `copyWith`
- Provider files contain one or more related providers
- Screen files contain a single screen widget that composes feature widgets
- Widget files contain a single reusable widget

### Format Patterns

**API Response Formats:**
- Supabase client returns `{ data, error }` tuples; always check `error` before using `data`
- Edge Function responses use HTTP status codes: 200 (success), 400 (bad request), 401 (unauthorized), 403 (forbidden), 429 (rate limited), 500 (internal error)
- Edge Function success response body: `{ "data": { ... } }`
- Edge Function error response body: `{ "error": { "code": "DESCRIPTIVE_ERROR_CODE", "message": "Human-readable message" } }`

**Error Codes (Edge Functions):**

| Code | Meaning |
|------|---------|
| `INVALID_PATH` | Submitted puzzle path does not match solution |
| `SOLVE_TOO_FAST` | Solve time below physical minimum threshold |
| `RATE_LIMITED` | Too many score submissions |
| `GROUP_FULL` | Group has reached maximum member limit |
| `INVALID_INVITE` | Invite code does not exist |
| `ALREADY_MEMBER` | User is already in this group |
| `NOT_AUTHORIZED` | User does not have permission for this action |
| `PUZZLE_NOT_FOUND` | No puzzle exists for the requested date |

**Data Formats:**
- Dates in database: `DATE` type for puzzle_date, `TIMESTAMPTZ` for timestamps
- Dates in JSON/API: ISO 8601 strings (e.g., `"2026-03-02"` for dates, `"2026-03-02T12:00:00Z"` for timestamps)
- Dates in Dart: `DateTime` objects, always UTC for server communication, local for display
- Solve time: stored as `INTEGER` milliseconds in database, displayed as `m:ss` or `m:ss.S` in UI
- IDs: UUID v4 strings (e.g., `"550e8400-e29b-41d4-a716-446655440000"`)
- Booleans in JSON: `true` / `false` (never 1/0)
- Null handling: null means "not set"; empty string means "explicitly empty"; never use null where empty string is appropriate

**JSON Field Naming:**
- Database fields and JSON responses: `snake_case` (e.g., `solve_time_ms`, `display_name`)
- Dart model properties: `camelCase` (e.g., `solveTimeMs`, `displayName`)
- Conversion handled by `fromJson` / `toJson` factory methods in each model class

### Communication Patterns

**Riverpod State Management Patterns:**

- Provider types:
  - `Provider` for computed/derived values
  - `AsyncNotifierProvider` for async data with mutation methods
  - `StreamProvider` for real-time data (e.g., leaderboard subscriptions)
  - `NotifierProvider` for synchronous mutable state (e.g., game state during play)
- Providers use `autoDispose` when they are screen-scoped (leaderboard for a specific group)
- Providers omit `autoDispose` when they are app-scoped (auth state, current puzzle)
- State updates are always immutable -- create new state objects via `copyWith` or constructor
- Async providers return `AsyncValue<T>` -- UI handles `loading`, `data`, and `error` states consistently

**Provider Naming Convention:**
- `{noun}Provider` for data providers (e.g., `puzzleProvider`, `profileProvider`)
- `{noun}{Qualifier}Provider` for scoped variants (e.g., `groupLeaderboardProvider`, `dailyPuzzleProvider`)
- Provider families use `.family` modifier for parameterized providers (e.g., `groupDetailProvider(groupId)`)

**Event and Analytics Patterns:**
- Analytics event names: `snake_case` (e.g., `puzzle_completed`, `group_joined`, `share_card_generated`)
- Event parameters: `snake_case` keys with primitive values (e.g., `{ "solve_time_ms": 42000, "hints_used": 1, "grid_size": "6x6" }`)
- Every screen logs a `screen_view` event on mount
- Critical user actions log both an analytics event and a performance trace

**Notification Patterns:**
- FCM topics: `daily_puzzle` (global), `group_{group_id}` (per-group activity)
- Notification payload includes `type` field for routing: `daily_reminder`, `group_solve`, `group_nudge`, `group_join`
- Deep link in notification data for navigation to relevant screen

### Process Patterns

**Error Handling Patterns:**
- Repository layer: catches all exceptions, returns `Result<T, AppError>` or lets Riverpod `AsyncValue.error` propagate
- Provider layer: exposes errors via `AsyncValue.error`; UI layer handles display
- Presentation layer: uses `.when(data:, loading:, error:)` pattern on `AsyncValue` consistently
- User-facing error messages: friendly text, never raw error messages or stack traces
- Technical errors logged to Firebase Crashlytics with context (user ID, screen, action)
- Network errors: detected by connectivity check; trigger offline mode fallback

**Offline Handling Patterns:**
- Connectivity state tracked via a global `connectivityProvider` (monitors network status)
- When offline:
  - Puzzle loads from Hive cache
  - Score submission queued in local sync queue (Hive box)
  - Leaderboards show cached data with "Last updated" timestamp
  - Group operations disabled with "Offline" indicator
- When connectivity returns:
  - Sync queue processes pending submissions in order
  - Conflict resolution: server timestamp wins for leaderboard ordering; if server has no record for an attempt, local data is accepted
  - Fresh data fetched for leaderboards and group state

**Loading State Patterns:**
- Loading states handled by Riverpod's `AsyncValue.loading`
- UI displays skeleton placeholders (shimmer effect) for list content during loading
- UI displays centered `CircularProgressIndicator` for full-screen loading (splash, initial data load)
- Buttons show inline loading indicator (spinner replacing text) during async operations
- Loading states are scoped -- one feature loading does not block others

**Navigation Patterns:**
- GoRouter routes defined declaratively in `app_router.dart`
- Navigation via `context.go()` for top-level tab changes, `context.push()` for detail screens
- Deep links resolve to specific routes: `/join/{code}` -> group join flow, `/puzzle/{date}` -> daily puzzle
- Back navigation: handled by GoRouter's stack; game screen uses `WillPopScope` to confirm exit during active play

### Enforcement Guidelines

**All AI Agents MUST:**

1. Follow the naming conventions exactly as specified above -- no deviation in casing, prefixes, or suffixes
2. Place files in the correct directory per the project structure patterns
3. Use Riverpod for all state management -- no `setState`, no `ChangeNotifier`, no `Bloc`
4. Use GoRouter for all navigation -- no `Navigator.push` calls
5. Handle all async data via `AsyncValue` pattern with loading, data, and error states
6. Write server communication through repository classes -- never call Supabase directly from providers or widgets
7. Include `fromJson` and `toJson` on all model classes that cross the network boundary
8. Log analytics events for all user-facing actions
9. Test all business logic with unit tests; test all screen rendering with widget tests
10. Never expose solution paths or puzzle answers in client-side code or logs

**Pattern Enforcement:**
- `flutter analyze` with strict analysis options catches naming and type violations
- Code review checklist includes pattern compliance check
- CI pipeline fails on analysis errors

### Pattern Examples

**Good Examples:**

```dart
// Model class with proper naming and serialization
class PuzzleAttempt {
  final String id;
  final String userId;
  final String puzzleId;
  final DateTime puzzleDate;
  final int solveTimeMs;
  final int hintsUsed;
  final int undosUsed;
  final bool completed;

  const PuzzleAttempt({
    required this.id,
    required this.userId,
    required this.puzzleId,
    required this.puzzleDate,
    required this.solveTimeMs,
    required this.hintsUsed,
    required this.undosUsed,
    required this.completed,
  });

  factory PuzzleAttempt.fromJson(Map<String, dynamic> json) {
    return PuzzleAttempt(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      puzzleId: json['puzzle_id'] as String,
      puzzleDate: DateTime.parse(json['puzzle_date'] as String),
      solveTimeMs: json['solve_time_ms'] as int,
      hintsUsed: json['hints_used'] as int,
      undosUsed: json['undos_used'] as int,
      completed: json['completed'] as bool,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'puzzle_id': puzzleId,
      'puzzle_date': puzzleDate.toIso8601String().split('T').first,
      'solve_time_ms': solveTimeMs,
      'hints_used': hintsUsed,
      'undos_used': undosUsed,
      'completed': completed,
    };
  }
}
```

```dart
// Repository with proper error handling and Supabase access
class PuzzleRepository {
  final SupabaseClient _client;

  PuzzleRepository(this._client);

  Future<Puzzle?> getPuzzleByDate(DateTime date) async {
    final dateStr = date.toIso8601String().split('T').first;
    final response = await _client
        .from('puzzles')
        .select('id, puzzle_date, grid_width, grid_height, day_of_week, difficulty, waypoints, walls')
        .eq('puzzle_date', dateStr)
        .maybeSingle();
    if (response == null) return null;
    return Puzzle.fromJson(response);
  }
}
```

```dart
// Provider with proper naming and async handling
@riverpod
class DailyPuzzle extends _$DailyPuzzle {
  @override
  Future<Puzzle> build() async {
    final repository = ref.watch(puzzleRepositoryProvider);
    final today = DateTime.now().toUtc();
    final cached = await ref.watch(puzzleCacheProvider).getPuzzle(today);
    if (cached != null) return cached;
    final puzzle = await repository.getPuzzleByDate(today);
    if (puzzle == null) throw Exception('No puzzle available for today');
    return puzzle;
  }
}
```

**Anti-Patterns (DO NOT DO):**

```dart
// BAD: Using setState instead of Riverpod
class GameScreen extends StatefulWidget { ... }
class _GameScreenState extends State<GameScreen> {
  Puzzle? puzzle;
  void _loadPuzzle() async {
    puzzle = await supabase.from('puzzles').select()...;  // BAD: direct Supabase call
    setState(() {});  // BAD: setState instead of Riverpod
  }
}

// BAD: Inconsistent naming
class puzzle_attempt { ... }  // BAD: should be PascalCase
final UserID = '...';  // BAD: should be camelCase
const MAX_GROUP_SIZE = 50;  // BAD: should be camelCase (maxGroupSize)

// BAD: Not handling async states
Widget build(BuildContext context) {
  final puzzle = ref.watch(puzzleProvider).value;  // BAD: ignores loading/error
  return Text(puzzle.toString());  // Will crash on null
}

// GOOD: Handle all async states
Widget build(BuildContext context) {
  final puzzleAsync = ref.watch(puzzleProvider);
  return puzzleAsync.when(
    loading: () => const LoadingIndicator(),
    error: (error, stack) => ErrorWidget(message: 'Failed to load puzzle'),
    data: (puzzle) => PuzzleGrid(puzzle: puzzle),
  );
}
```

---

## Project Structure & Boundaries

### Complete Project Directory Structure

```
icos/
├── .github/
│   └── workflows/
│       ├── ci.yml                          # Lint, test, build on push/PR
│       └── release.yml                     # Build + deploy to stores on tag
├── .vscode/
│   └── settings.json                       # Editor settings for Dart/Flutter
├── android/                                # Android platform project (managed by Flutter)
├── ios/                                    # iOS platform project (managed by Flutter)
├── assets/
│   ├── fonts/
│   │   ├── Inter/
│   │   └── JetBrainsMono/
│   ├── images/
│   │   ├── avatars/                        # Preset avatar images
│   │   ├── icons/                          # App icons and UI icons
│   │   └── onboarding/                     # Onboarding illustrations
│   ├── animations/
│   │   └── celebration_confetti.riv        # Rive celebration animation
│   └── puzzles/
│       └── fallback_puzzles.json           # 7 bundled offline fallback puzzles
├── lib/
│   ├── main.dart                           # Entry point: ProviderScope, app init
│   ├── app.dart                            # MaterialApp.router, theme, GoRouter
│   │
│   ├── core/
│   │   ├── constants/
│   │   │   ├── app_colors.dart             # Color palette (light + dark)
│   │   │   ├── app_sizes.dart              # Spacing, sizing, corner radius
│   │   │   └── app_strings.dart            # Static strings, error messages
│   │   ├── theme/
│   │   │   ├── app_theme.dart              # ThemeData factory
│   │   │   ├── dark_theme.dart             # Dark mode theme
│   │   │   └── light_theme.dart            # Light mode theme
│   │   ├── router/
│   │   │   └── app_router.dart             # GoRouter config, routes, deep links
│   │   ├── utils/
│   │   │   ├── haptics.dart                # HapticFeedback wrapper with toggle
│   │   │   ├── date_utils.dart             # Date formatting, week calculations
│   │   │   └── share_utils.dart            # Share sheet invocation
│   │   └── services/
│   │       ├── supabase_service.dart        # Supabase client initialization
│   │       ├── analytics_service.dart       # Firebase Analytics wrapper
│   │       ├── notification_service.dart    # FCM setup, token management
│   │       └── storage_service.dart         # Hive initialization, box management
│   │
│   ├── features/
│   │   ├── auth/
│   │   │   ├── data/
│   │   │   │   └── auth_repository.dart     # Auth operations (sign in, link, delete)
│   │   │   ├── domain/
│   │   │   │   └── auth_state.dart          # AuthState enum/model
│   │   │   ├── providers/
│   │   │   │   └── auth_provider.dart       # authStateProvider, authActionsProvider
│   │   │   └── presentation/
│   │   │       ├── login_screen.dart        # Sign-in screen
│   │   │       └── widgets/
│   │   │           ├── social_sign_in_button.dart
│   │   │           └── email_sign_in_form.dart
│   │   │
│   │   ├── puzzle/
│   │   │   ├── data/
│   │   │   │   ├── puzzle_repository.dart   # Fetch puzzles from Supabase
│   │   │   │   └── puzzle_cache.dart        # Hive-based puzzle cache
│   │   │   ├── domain/
│   │   │   │   ├── models/
│   │   │   │   │   ├── puzzle.dart          # Puzzle data class
│   │   │   │   │   ├── cell.dart            # Grid cell model
│   │   │   │   │   ├── wall.dart            # Wall barrier model
│   │   │   │   │   ├── waypoint.dart        # Numbered waypoint model
│   │   │   │   │   └── path_segment.dart    # Path segment model
│   │   │   │   ├── puzzle_engine.dart       # Path validation, completion detection
│   │   │   │   ├── puzzle_generator.dart    # Backbite algorithm (used in Edge Function)
│   │   │   │   └── puzzle_solver.dart       # DFS solver for hints & verification
│   │   │   ├── providers/
│   │   │   │   ├── puzzle_provider.dart     # dailyPuzzleProvider
│   │   │   │   ├── game_state_provider.dart # Active game state (path, time, hints)
│   │   │   │   └── timer_provider.dart      # Solve timer
│   │   │   └── presentation/
│   │   │       ├── game_screen.dart         # Full-screen puzzle gameplay
│   │   │       ├── result_screen.dart       # Post-completion results
│   │   │       └── widgets/
│   │   │           ├── grid_painter.dart    # CustomPainter for grid + path
│   │   │           ├── grid_widget.dart     # GestureDetector wrapper
│   │   │           ├── waypoint_widget.dart # Waypoint number circles
│   │   │           ├── timer_widget.dart    # Timer display
│   │   │           ├── hint_button.dart     # Hint request button
│   │   │           └── celebration_overlay.dart  # Rive confetti animation
│   │   │
│   │   ├── home/
│   │   │   ├── providers/
│   │   │   │   └── home_provider.dart       # Home screen aggregated data
│   │   │   └── presentation/
│   │   │       ├── home_screen.dart         # Main home tab
│   │   │       └── widgets/
│   │   │           ├── daily_puzzle_card.dart    # Today's puzzle card
│   │   │           ├── streak_badge.dart         # Streak fire icon + count
│   │   │           └── group_activity_card.dart  # Group solve summary
│   │   │
│   │   ├── groups/
│   │   │   ├── data/
│   │   │   │   └── group_repository.dart    # Group CRUD, membership ops
│   │   │   ├── domain/
│   │   │   │   ├── models/
│   │   │   │   │   ├── group.dart           # Group data class
│   │   │   │   │   └── group_member.dart    # GroupMember data class
│   │   │   │   └── group_service.dart       # Group business logic
│   │   │   ├── providers/
│   │   │   │   ├── groups_provider.dart     # User's groups list
│   │   │   │   └── leaderboard_provider.dart  # Daily/weekly leaderboard
│   │   │   └── presentation/
│   │   │       ├── groups_list_screen.dart   # Groups tab
│   │   │       ├── group_detail_screen.dart  # Group leaderboard + members
│   │   │       ├── create_group_screen.dart  # Create new group
│   │   │       ├── join_group_screen.dart    # Join via code
│   │   │       └── widgets/
│   │   │           ├── leaderboard_list.dart      # Ranked list widget
│   │   │           ├── leaderboard_entry.dart     # Single rank row
│   │   │           ├── invite_card.dart           # Invite code/link card
│   │   │           └── member_list.dart           # Group member list
│   │   │
│   │   ├── stats/
│   │   │   ├── providers/
│   │   │   │   └── stats_provider.dart      # User statistics aggregation
│   │   │   └── presentation/
│   │   │       ├── stats_screen.dart        # Stats tab
│   │   │       └── widgets/
│   │   │           ├── solve_time_chart.dart     # Time distribution chart
│   │   │           ├── streak_calendar.dart      # Calendar heatmap
│   │   │           └── stat_card.dart            # Individual stat display
│   │   │
│   │   ├── profile/
│   │   │   ├── data/
│   │   │   │   └── profile_repository.dart  # Profile read/update/delete
│   │   │   ├── providers/
│   │   │   │   └── profile_provider.dart    # Current user profile
│   │   │   └── presentation/
│   │   │       ├── profile_screen.dart      # Profile tab
│   │   │       └── widgets/
│   │   │           ├── avatar_selector.dart      # Preset avatar picker
│   │   │           └── settings_section.dart     # Settings list
│   │   │
│   │   └── sharing/
│   │       ├── domain/
│   │       │   └── share_card_generator.dart # Generate spoiler-free share image
│   │       └── presentation/
│   │           └── share_preview_screen.dart # Share card preview + actions
│   │
│   └── shared/
│       ├── widgets/
│       │   ├── app_button.dart              # Standard button component
│       │   ├── app_card.dart                # Standard card component
│       │   ├── loading_indicator.dart       # Loading spinner
│       │   └── error_widget.dart            # Error display with retry
│       └── extensions/
│           ├── context_extensions.dart      # BuildContext convenience methods
│           └── datetime_extensions.dart     # DateTime formatting helpers
│
├── supabase/
│   ├── config.toml                          # Supabase local dev config
│   ├── seed.sql                             # Sample data for development
│   ├── migrations/
│   │   ├── 001_initial_schema.sql           # Tables: profiles, puzzles, puzzle_attempts, streaks, groups, group_members
│   │   ├── 002_rls_policies.sql             # Row-Level Security policies
│   │   └── 003_functions.sql                # RPC functions: leaderboards, streak updates
│   └── functions/
│       ├── daily-puzzle/
│       │   └── index.ts                     # Cron: generate + schedule daily puzzles
│       ├── submit-score/
│       │   └── index.ts                     # Validate path, record attempt, update streak
│       ├── join-group/
│       │   └── index.ts                     # Process invite code, add member
│       └── generate-share-card/
│           └── index.ts                     # Generate shareable result image
│
├── test/
│   ├── unit/
│   │   ├── puzzle_engine_test.dart          # Path validation, completion detection
│   │   ├── puzzle_generator_test.dart       # Backbite algorithm correctness
│   │   ├── puzzle_solver_test.dart          # DFS solver, uniqueness verification
│   │   └── streak_calculator_test.dart      # Streak logic, freeze mechanics
│   ├── widget/
│   │   ├── grid_painter_test.dart           # Grid rendering golden tests
│   │   ├── game_screen_test.dart            # Game screen composition
│   │   └── leaderboard_test.dart            # Leaderboard display
│   └── integration/
│       ├── game_flow_test.dart              # Full puzzle solve flow
│       └── group_flow_test.dart             # Group create/join/leaderboard flow
│
├── analysis_options.yaml                    # Strict lint rules
├── pubspec.yaml                             # Dependencies and assets
├── .env.example                             # Environment variable template
├── .gitignore                               # Standard Flutter + Supabase ignores
├── fastlane/
│   ├── Appfile                              # App identifiers
│   ├── Fastfile                             # Lane definitions
│   └── Matchfile                            # Code signing config (iOS)
└── firebase.json                            # Firebase project config
```

### Architectural Boundaries

**API Boundaries:**

| Boundary | Client Side | Server Side | Protocol |
|----------|------------|-------------|----------|
| Authentication | `auth_repository.dart` | Supabase Auth (GoTrue) | Supabase Auth SDK |
| Puzzle Data | `puzzle_repository.dart` | `puzzles` table via PostgREST | Supabase Client SDK |
| Score Submission | `puzzle_repository.dart` | `submit-score` Edge Function | HTTP POST |
| Group Operations | `group_repository.dart` | `groups` + `group_members` tables, `join-group` Edge Function | Supabase Client SDK + HTTP POST |
| Leaderboards | `leaderboard_provider.dart` | PostgreSQL RPC functions | Supabase RPC |
| Real-time Updates | `leaderboard_provider.dart` | Supabase Realtime (WAL-based) | WebSocket |
| Push Notifications | `notification_service.dart` | Firebase Cloud Messaging | FCM SDK |
| File Storage | `profile_repository.dart` | Supabase Storage | Supabase Storage SDK |
| Analytics | `analytics_service.dart` | Firebase Analytics | Firebase SDK |

**Component Boundaries:**

- Feature modules communicate ONLY through Riverpod providers -- never import directly from another feature's `data/` or `presentation/` layer
- Shared code lives in `lib/shared/` (widgets, extensions) or `lib/core/` (services, constants, theme, router)
- Domain models from one feature may be referenced by another feature's provider (e.g., groups feature reads `PuzzleAttempt` model from puzzle feature)
- Presentation widgets are strictly scoped to their feature -- a groups widget does not render inside the puzzle feature's screens (instead, use shared widgets or compose at the screen level in the parent)

**Data Boundaries:**

- All database access goes through repository classes in each feature's `data/` layer
- Repositories accept and return domain model objects -- never raw `Map<String, dynamic>` to providers or presentation
- Hive cache access is encapsulated in `puzzle_cache.dart` and `storage_service.dart` -- no direct Hive box access from providers or widgets
- Supabase client instance is provided by `supabase_service.dart` and injected into repositories

### Requirements to Structure Mapping

**Feature Mapping:**

| PRD Category | Feature Module | Key Files |
|-------------|---------------|-----------|
| Puzzle Engine (FR1-FR11) | `features/puzzle/` | `puzzle_engine.dart`, `grid_painter.dart`, `grid_widget.dart`, `game_screen.dart` |
| Daily Puzzle System (FR12-FR16) | `features/puzzle/` | `puzzle_repository.dart`, `puzzle_cache.dart`, `puzzle_provider.dart` |
| Hint System (FR17-FR19) | `features/puzzle/` | `puzzle_solver.dart`, `game_state_provider.dart`, `hint_button.dart` |
| User Management (FR20-FR27) | `features/auth/` + `features/profile/` | `auth_repository.dart`, `auth_provider.dart`, `profile_repository.dart`, `profile_screen.dart` |
| Streaks & Statistics (FR28-FR33) | `features/stats/` | `stats_provider.dart`, `stats_screen.dart`, `streak_calendar.dart` |
| Groups & Leaderboards (FR34-FR44) | `features/groups/` | `group_repository.dart`, `groups_provider.dart`, `leaderboard_provider.dart`, `group_detail_screen.dart` |
| Sharing (FR45-FR48) | `features/sharing/` | `share_card_generator.dart`, `share_preview_screen.dart` |
| Offline Support (FR49-FR53) | `features/puzzle/data/` + `core/services/` | `puzzle_cache.dart`, `storage_service.dart`, `supabase_service.dart` |
| Settings & Preferences (FR54-FR58) | `features/profile/` | `profile_screen.dart`, `settings_section.dart` |
| Navigation & Structure (FR59-FR61) | `core/router/` + `features/home/` | `app_router.dart`, `home_screen.dart` |

**Cross-Cutting Concerns Mapping:**

| Concern | Primary Location | Touches |
|---------|-----------------|---------|
| Authentication state | `features/auth/providers/` | Every feature module (via provider dependency) |
| Offline/online state | `core/services/storage_service.dart` | puzzle, groups, sharing features |
| Error handling | `shared/widgets/error_widget.dart` | Every presentation layer |
| Analytics | `core/services/analytics_service.dart` | Every feature's providers and screens |
| Accessibility | `core/theme/`, `core/constants/` | Every presentation widget |
| Theme | `core/theme/` | Every presentation widget via ThemeData |
| Haptic feedback | `core/utils/haptics.dart` | puzzle, groups features |

### Integration Points

**Internal Communication:**
- Feature-to-feature: via Riverpod providers (e.g., `authStateProvider` consumed by `groupsProvider`)
- Screen-to-screen: via GoRouter navigation with typed route parameters
- Widget-to-provider: via `ref.watch()` (reactive) and `ref.read()` (imperative actions)
- Background processing: Hive sync queue processed by `storage_service.dart` on connectivity change

**External Integrations:**

| Service | Integration Point | SDK/Library |
|---------|------------------|-------------|
| Supabase (Database, Auth, Realtime, Storage) | `core/services/supabase_service.dart` | `supabase_flutter` |
| Firebase Analytics | `core/services/analytics_service.dart` | `firebase_analytics` |
| Firebase Crashlytics | `core/services/analytics_service.dart` | `firebase_crashlytics` |
| Firebase Performance | `core/services/analytics_service.dart` | `firebase_performance` |
| Firebase Remote Config | `core/services/analytics_service.dart` | `firebase_remote_config` |
| Firebase Cloud Messaging | `core/services/notification_service.dart` | `firebase_messaging` |
| Platform Share Sheet | `core/utils/share_utils.dart` | `share_plus` |
| Deep Links / Universal Links | `core/router/app_router.dart` | GoRouter + platform config |
| Hive (Local Storage) | `core/services/storage_service.dart` | `hive_flutter` |
| SharedPreferences | `core/services/storage_service.dart` | `shared_preferences` |

**Data Flow:**

```
User Action (gesture/tap)
    |
    v
Presentation Layer (Screen/Widget)
    |
    v
Provider Layer (Riverpod Provider)
    |
    +--> Local: Hive Cache (puzzle data, sync queue)
    |
    +--> Remote: Repository -> Supabase Client -> PostgreSQL
    |
    +--> Real-time: Supabase Realtime -> StreamProvider -> UI update
    |
    +--> Analytics: Analytics Service -> Firebase
    |
    v
State Update -> UI Rebuild (reactive via Riverpod)
```

### File Organization Patterns

**Configuration Files:**
- `.env.example` at project root: template for `SUPABASE_URL` and `SUPABASE_ANON_KEY`
- `analysis_options.yaml` at project root: strict lint rules
- `pubspec.yaml` at project root: dependencies, assets, fonts
- `firebase.json` at project root: Firebase project configuration
- `supabase/config.toml`: Supabase local development configuration

**Source Organization:**
- Entry point: `lib/main.dart` initializes services, wraps app in `ProviderScope`
- App shell: `lib/app.dart` configures `MaterialApp.router` with theme and GoRouter
- Core infrastructure: `lib/core/` (services, constants, theme, router, utils)
- Feature modules: `lib/features/{feature}/` with consistent 4-layer structure
- Shared components: `lib/shared/` (widgets, extensions)

**Test Organization:**
- Unit tests: `test/unit/` for business logic (puzzle engine, solver, generator, streak calculator)
- Widget tests: `test/widget/` for component rendering and interaction
- Integration tests: `test/integration/` for full user flow testing
- Test naming: `{source_file_name}_test.dart` (e.g., `puzzle_engine_test.dart`)

**Asset Organization:**
- Fonts: `assets/fonts/{font_family}/` (licensed font files)
- Images: `assets/images/{category}/` (avatars, icons, onboarding)
- Animations: `assets/animations/` (Rive files)
- Bundled data: `assets/puzzles/` (fallback offline puzzles)

### Development Workflow Integration

**Development Server Structure:**
- Flutter development: `flutter run` with hot reload
- Supabase local: `supabase start` for local PostgreSQL, Auth, and Edge Functions
- Environment: `.env.development` points to local Supabase instance

**Build Process Structure:**
- Debug builds: `flutter build apk --debug` / `flutter build ios --debug`
- Release builds: `flutter build appbundle` (Android) / `flutter build ipa` (iOS)
- Fastlane lanes handle signing, building, and uploading to stores

**Deployment Structure:**
- Staging: separate Supabase project + Firebase project for staging environment
- Production: dedicated Supabase project + Firebase project
- Migrations: applied via `supabase db push` targeting the appropriate project
- Edge Functions: deployed via `supabase functions deploy` targeting the appropriate project

---

## Architecture Validation Results

### Coherence Validation

**Decision Compatibility:**
All technology choices work together without conflicts:
- Flutter 3.41.x with Dart 3.8+ supports all chosen packages (Riverpod 3.x, GoRouter, Hive, supabase_flutter, Firebase SDKs)
- Supabase provides a unified backend (database, auth, realtime, functions, storage) eliminating multi-service coordination complexity
- Firebase SDKs for Flutter are mature and compatible with the Supabase auth flow (Firebase used only for analytics/monitoring/push, not auth)
- Riverpod 3.x's StreamProvider integrates naturally with Supabase Realtime subscriptions
- GoRouter's deep link support covers the group invite flow requirement

**Pattern Consistency:**
- Naming conventions are consistent: snake_case in database and JSON, camelCase in Dart, PascalCase for classes
- All state management uses Riverpod -- no mixed patterns
- All navigation uses GoRouter -- no mixed Navigator calls
- All data access goes through repositories -- no direct Supabase calls from UI
- All async states use AsyncValue pattern -- consistent loading/error/data handling

**Structure Alignment:**
- Feature-based directory structure maps 1:1 to PRD requirement categories
- Each feature module follows the same 4-layer pattern (data, domain, providers, presentation)
- Core services are shared infrastructure, not duplicated across features
- Test structure mirrors source structure for easy navigation

### Requirements Coverage Validation

**Functional Requirements Coverage:**
All 61 functional requirements are architecturally supported:

| FR Range | Coverage Status | Supporting Architecture |
|----------|----------------|----------------------|
| FR1-FR11 (Puzzle Engine) | Fully covered | CustomPainter rendering, GestureDetector for path drawing, PuzzleEngine for validation, haptics utility |
| FR12-FR16 (Daily Puzzle) | Fully covered | Edge Function cron for generation, PuzzleRepository + PuzzleCache for delivery, background fetch |
| FR17-FR19 (Hints) | Fully covered | PuzzleSolver for hint computation, GameStateProvider for daily limit tracking |
| FR20-FR27 (User Management) | Fully covered | Supabase Auth for all providers, AuthRepository for account linking, ProfileRepository for CRUD |
| FR28-FR33 (Streaks) | Fully covered | Streaks table, StatsProvider for computation, streak freeze logic in Edge Function |
| FR34-FR44 (Groups) | Fully covered | Groups + GroupMembers tables, GroupRepository, RLS policies, Realtime subscriptions |
| FR45-FR48 (Sharing) | Fully covered | ShareCardGenerator for image creation, share_utils for native share sheet, GoRouter for deep links |
| FR49-FR53 (Offline) | Fully covered | PuzzleCache (Hive), sync queue, bundled fallback puzzles, connectivity monitoring |
| FR54-FR58 (Settings) | Fully covered | SharedPreferences, ThemeData, per-group notification config |
| FR59-FR61 (Navigation) | Fully covered | GoRouter bottom tab navigation, deep link routing for invites |

**Non-Functional Requirements Coverage:**

| NFR Range | Coverage Status | Supporting Architecture |
|-----------|----------------|----------------------|
| NFR1-NFR6 (Performance) | Fully covered | Impeller engine for 60 FPS, lazy loading, Hive caching for <200ms loads, Edge Function optimization for <300ms submissions |
| NFR7-NFR12 (Security) | Fully covered | HTTPS enforced, secure token storage, server-side validation, RLS policies, rate limiting in Edge Functions |
| NFR13-NFR15 (Scalability) | Fully covered | Phased scaling strategy, proper indexing, connection pooling, Redis planned for growth phase |
| NFR16-NFR19 (Accessibility) | Fully covered | 44x44dp touch targets in sizing constants, colorblind mode in theme system, WCAG AA contrast in color palette, reduced motion via MediaQuery |
| NFR20-NFR22 (Reliability) | Fully covered | Sync queue with zero-loss guarantee, Crashlytics for <1% crash monitoring, background cache refresh with retry |

### Implementation Readiness Validation

**Decision Completeness:**
- All critical decisions documented with specific package versions
- Implementation patterns cover all identified conflict points (28 areas)
- Consistency rules are clear, with code examples for correct and incorrect patterns
- Technology versions verified via current web search

**Structure Completeness:**
- Complete directory tree with every file and directory specified
- All feature modules, core services, shared components, tests, and infrastructure files defined
- Supabase migrations and Edge Functions structured with clear naming
- Asset organization defined for fonts, images, animations, and bundled data

**Pattern Completeness:**
- Naming patterns cover database, API, Dart code, and assets
- Structure patterns cover project organization, file structure, and test organization
- Format patterns cover API responses, error codes, data serialization, and date handling
- Communication patterns cover state management, analytics, notifications, and navigation
- Process patterns cover error handling, offline behavior, loading states, and navigation

### Gap Analysis Results

**No critical gaps identified.** The architecture fully covers all 61 FRs and 22 NFRs.

**Minor enhancement opportunities (non-blocking):**
1. Accessibility: Screen reader (VoiceOver/TalkBack) support for grid navigation is listed as post-MVP in the product brief; basic Semantics widgets should still be included in grid rendering
2. Internationalization: Not mentioned in PRD; architecture supports it via Flutter's `intl` package if needed later
3. A/B testing: Firebase Remote Config is included but specific experiment definitions are deferred to post-launch

### Architecture Completeness Checklist

**Requirements Analysis**

- [x] Project context thoroughly analyzed (61 FRs, 22 NFRs, 10 categories)
- [x] Scale and complexity assessed (low complexity, greenfield, 5K-50K MAU targets)
- [x] Technical constraints identified (offline-first, anti-cheat, 50MB size budget, 60 FPS)
- [x] Cross-cutting concerns mapped (auth, offline, errors, analytics, accessibility, theme, haptics)

**Architectural Decisions**

- [x] Critical decisions documented with versions (Flutter 3.41.x, Riverpod 3.x, Supabase, Hive, GoRouter)
- [x] Technology stack fully specified (frontend, backend, analytics, CI/CD)
- [x] Integration patterns defined (Supabase SDK, Edge Functions, Firebase SDKs, Realtime WebSocket)
- [x] Performance considerations addressed (Impeller, caching, lazy loading, async state management)

**Implementation Patterns**

- [x] Naming conventions established (database, API, Dart code, assets)
- [x] Structure patterns defined (feature-based, 4-layer, core/shared separation)
- [x] Communication patterns specified (Riverpod providers, GoRouter navigation, Supabase Realtime)
- [x] Process patterns documented (error handling, offline sync, loading states)

**Project Structure**

- [x] Complete directory structure defined (every file and directory)
- [x] Component boundaries established (feature isolation, repository abstraction)
- [x] Integration points mapped (9 external services, internal provider communication)
- [x] Requirements to structure mapping complete (all FR categories mapped to feature modules)

### Architecture Readiness Assessment

**Overall Status:** READY FOR IMPLEMENTATION

**Confidence Level:** High -- based on comprehensive validation against all PRD requirements, coherent technology choices, and detailed implementation patterns.

**Key Strengths:**
1. Clean separation between offline-capable client and server-side validation ensures both UX responsiveness and anti-cheat integrity
2. Feature-based architecture maps directly to PRD requirement categories, making implementation stories straightforward to scope
3. Riverpod + Supabase Realtime provides a natural reactive data flow from database changes through to UI updates
4. Offline-first design with sync queue and bundled fallback puzzles ensures the core experience works in all connectivity conditions
5. Phased scaling strategy avoids over-engineering at launch while having a clear path for growth

**Areas for Future Enhancement:**
1. Redis caching layer for leaderboards when query performance degrades at scale
2. CDN-based puzzle delivery for global latency optimization
3. Database partitioning on puzzle_attempts for long-term data management
4. Advanced accessibility features (full screen reader support, one-handed mode)
5. Monetization infrastructure (in-app purchases for cosmetics) when business model is validated

### Implementation Handoff

**AI Agent Guidelines:**

1. Follow all architectural decisions exactly as documented in this file
2. Use implementation patterns consistently across all components -- refer to the naming, structure, format, communication, and process patterns sections
3. Respect project structure and boundaries -- place files in the correct directories, use repository abstraction for all data access
4. Refer to this document for all architectural questions before making independent decisions
5. When in doubt about a pattern, check the "Pattern Examples" section for good examples and anti-patterns

**First Implementation Priority:**

```bash
# 1. Create Flutter project
flutter create --org com.icos --project-name icos --platforms ios,android icos

# 2. Set up project structure per directory tree above

# 3. Initialize Supabase
supabase init

# 4. Apply database migrations
supabase db push

# 5. Add core dependencies to pubspec.yaml
# flutter_riverpod, riverpod_annotation, go_router, supabase_flutter,
# firebase_core, firebase_analytics, firebase_crashlytics,
# firebase_messaging, firebase_performance, firebase_remote_config,
# hive_flutter, shared_preferences, share_plus, rive
```

**Implementation Sequence:**
1. Project scaffold + CI pipeline (GitHub Actions)
2. Database schema + RLS policies + functions (Supabase migrations)
3. Auth flow (anonymous + account creation + linking)
4. Puzzle engine (grid rendering + path drawing + validation)
5. Daily puzzle system (Edge Function + caching + offline)
6. Home screen + navigation shell
7. Groups + leaderboards (CRUD + Realtime)
8. Sharing (share card generation + deep links)
9. Statistics + streaks
10. Push notifications (FCM)
11. Polish (animations, haptics, accessibility, themes)
12. Testing + performance profiling + store submission
