---
stepsCompleted:
  - step-01-validate-prerequisites
  - step-02-design-epics
  - step-03-create-stories
  - step-04-final-validation
inputDocuments:
  - prd.md
  - architecture.md
  - ux-design-specification.md
  - visual-testing-strategy.md
---

# Icos - Epic Breakdown

## Overview

This document provides the complete epic and story breakdown for Icos, decomposing the requirements from the PRD, UX Design, Architecture, and production-readiness audit into implementable stories. All requirements target production readiness — no MVP phasing.

## Requirements Inventory

### Functional Requirements

#### Puzzle Engine (FR1-FR11)

FR1: Players can view a grid with numbered waypoints displayed as colored circles and wall barriers displayed as thick lines between cells
FR2: Players can draw a path by dragging their finger across adjacent grid cells
FR3: Players can undo path segments by dragging backward along the drawn path
FR4: Players can undo the last path segment via an undo button
FR5: Players can redo a previously undone segment via a redo button
FR6: Players can reset the entire puzzle to its initial empty state
FR7: Players can tap a cell on the drawn path to remove the path from that cell to the end
FR8: System validates that the path is continuous, visits all cells exactly once, passes through waypoints in numerical order, and respects wall barriers
FR9: System detects puzzle completion when all cells are filled and all waypoints are visited in order
FR10: System displays a celebration animation upon puzzle completion
FR11: System provides haptic feedback on cell entry (light), waypoint reached (medium), wall collision (error), and puzzle completion (success pattern)

#### Daily Puzzle System (FR12-FR16)

FR12: System delivers one puzzle per day, identical for all users worldwide
FR13: System scales puzzle difficulty by day of week: Monday (5x5, easy) through Sunday (8x8, hard)
FR14: System tracks solve time from first cell entry to puzzle completion, hidden during play and displayed on the result screen
FR15: System pre-generates puzzles 30 days in advance via server-side scheduled function
FR16: System pre-caches the next day's puzzle on the device 24 hours before its release date

#### Hint System (FR17-FR19)

FR17: Players can request a hint that reveals the correct path for the next 2-3 cells from their current position
FR18: System provides 3 free hints per day, resetting at midnight UTC
FR19: System tracks total hints used per puzzle attempt

#### User Management (FR20-FR27)

FR20: Players can start playing immediately without creating an account (anonymous session)
FR21: Players can create an account using email/password, Google Sign-In, or Apple Sign-In
FR22: Players can link an anonymous session to a new account without losing progress, streaks, or group memberships
FR23: Players can set a display name (text, max 20 characters)
FR24: Players can select an avatar from a set of preset avatar images
FR25: Players can update their display name and avatar at any time
FR26: Players can delete their account with a 30-day grace period before permanent data removal
FR27: System prompts account creation after the 3rd puzzle solve or when attempting to join a group

#### Streaks & Statistics (FR28-FR33)

FR28: System tracks the player's current consecutive-day solve streak
FR29: System tracks the player's longest-ever solve streak
FR30: System tracks total puzzles solved and average solve time
FR31: Players can use 1 streak freeze per week to preserve their streak when missing a day
FR32: System automatically applies streak freeze if player misses a day and has a freeze available
FR33: Players can view their statistics on a dedicated stats screen

#### Groups & Leaderboards (FR34-FR44)

FR34: Players can create a group with a name (max 30 characters) and optional description
FR35: System generates a unique 6-character alphanumeric invite code for each group
FR36: Players can join a group via invite code entry, deep link, or QR code scan
FR37: System enforces a maximum of 50 members per group
FR38: System displays a daily leaderboard per group ranked by hints used (ascending), then solve time (ascending), then undos used (ascending)
FR39: System displays a weekly leaderboard per group ranked by puzzles completed (descending), then average solve time (ascending)
FR40: Group admins can remove members from the group
FR41: Group admins can regenerate the invite code, invalidating the previous code
FR42: Players can leave a group at any time
FR43: Group creators (admins) can delete the group entirely
FR44: System displays which group members have and have not solved today's puzzle (without revealing solve details until the viewer has also solved)

#### Sharing (FR45-FR48)

FR45: Players can generate a spoiler-free share card showing grid size, solve time, day identifier, and an abstract path visualization that does not reveal the solution
FR46: Players can share the result card to any platform via the native OS share sheet
FR47: Players can copy the result card to the clipboard as text
FR48: Players can share a group invite via deep link, invite code text, or QR code image

#### Offline Support (FR49-FR53)

FR49: System caches tomorrow's puzzle on-device via background fetch at least 12 hours before release
FR50: Players can solve the daily puzzle without any network connectivity
FR51: System queues puzzle completion results locally when offline and syncs automatically when connectivity returns
FR52: System includes 7 bundled offline fallback puzzles for first-launch scenarios with no connectivity
FR53: System displays an offline indicator when no network connectivity is detected

#### Settings & Preferences (FR54-FR58)

FR54: Players can toggle haptic feedback on/off
FR55: Players can toggle sound effects on/off
FR56: Players can select a visual theme (light mode, dark mode, or follow system setting)
FR57: Players can configure notification preferences per group (on/off)
FR58: Players can view the app's privacy policy and terms of service

#### Navigation & Structure (FR59-FR61)

FR59: System provides bottom navigation with Home, Groups, Stats, and Profile tabs
FR60: Home screen displays the daily puzzle card (grid size, difficulty indicator, play button), current streak, and group activity summary
FR61: System supports deep links for group invites that open the app directly to the group join flow (or the app store if not installed)

#### Legal & Compliance (FR62-FR67)

FR62: System displays age verification gate (13+) on first launch before any data collection or gameplay
FR63: System presents privacy consent flow before enabling analytics or tracking, with granular opt-in/opt-out for analytics, crash reporting, and personalization
FR64: System presents Apple App Tracking Transparency (ATT) prompt on iOS before any tracking or attribution
FR65: System requires active acceptance of Terms of Service before account creation; ToS covers user-generated content policies, acceptable use, intellectual property, and dispute resolution
FR66: Players can export their personal data (solve history, stats, profile, group membership) as a downloadable file (GDPR Article 20 data portability)
FR67: System handles Data Subject Access Requests (DSAR) — backend supports generating a complete data export for any user within 30 days

#### App Lifecycle & State (FR68-FR75)

FR68: System checks minimum required app version on launch and displays a blocking force-update screen directing the user to the app store when the client version is below the required minimum
FR69: System auto-saves puzzle state (current path, hints used, undos used, elapsed time) to local storage on every move, allowing full resume after crash, app kill, or device restart
FR70: System pauses the solve timer when the app is backgrounded and resumes from the paused time when the app returns to foreground
FR71: System displays a branded splash screen with Icos logo during cold start
FR72: System locks screen orientation to portrait on phones (width < 768dp); supports both portrait and landscape on tablets
FR73: System displays a maintenance mode screen with estimated restoration time when the backend is unavailable, with automatic retry and graceful offline fallback for cached content
FR74: System restores app state after OS process death — returns user to the correct screen (puzzle in progress, result pending, home) based on persisted navigation state
FR75: System detects and rejects solve submissions with manipulated device clocks by comparing client-submitted timestamps against server wall-clock time with a configurable tolerance window

#### Timezone & Boundaries (FR76-FR78)

FR76: Daily puzzle rolls over at midnight UTC for all users worldwide; "today's puzzle" is defined by the current UTC date
FR77: Weekly leaderboard boundaries start Monday 00:00 UTC and end Sunday 23:59:59 UTC
FR78: Streak evaluation occurs at midnight UTC — a day is counted as "solved" if a valid completion is recorded before 23:59:59 UTC for that date

#### Content Moderation & Abuse Prevention (FR79-FR84)

FR79: System filters display names and group names against a configurable profanity/offensive content word list, rejecting prohibited content at creation and update time
FR80: System sanitizes all user-generated text input to prevent XSS, SQL injection, Unicode abuse (zalgo text, invisible characters, excessive combining marks), and emoji-only names
FR81: Players can report offensive display names, group names, or abusive behavior via an in-app reporting mechanism accessible from group member profiles and group detail screens
FR82: System enforces rate limits on group creation (max 5 groups per user per day) to prevent spam
FR83: System supports user-level bans — banned users cannot create accounts, join groups, or submit scores; ban is enforced at the auth and Edge Function layers
FR84: When a group admin deletes their account, admin role automatically transfers to the longest-tenured group member; if no members remain, the group is deleted

#### Multi-Device & Session Management (FR85-FR87)

FR85: System enforces one puzzle attempt per user per day across all devices — the first completed and server-verified solve is the recorded attempt; subsequent attempts on other devices see the "already solved" state
FR86: System supports concurrent sessions on multiple devices with consistent state synchronization for streaks, stats, group memberships, and profile data
FR87: System enforces session lifecycle — tokens expire after 30 days of inactivity, refresh tokens expire after 90 days, and users can view active sessions

#### Notifications (FR88-FR93)

FR88: System requests notification permission using a pre-permission screen explaining value ("Get daily puzzle reminders and group updates") before triggering the OS permission dialog, timed after first puzzle completion
FR89: System sends daily puzzle reminder notification at a user-configurable time (default 8:00 AM local time)
FR90: System sends group activity nudge notification ("You're the last one! N/M members have solved today") when applicable
FR91: System sends streak-at-risk notification ("Solve today to keep your N-day streak!") if the user has not solved by a configurable time (default 6:00 PM local)
FR92: Players can filter notification types independently in settings: daily reminder (on/off), group activity (on/off), streak alerts (on/off)
FR93: System displays in-app badge on Groups tab when new group activity has occurred since the user's last visit

#### Onboarding & Discovery (FR94-FR97)

FR94: System displays subtle first-time affordances on the puzzle screen — pulsing indicator on waypoint 1 and a brief "Drag to draw your path" tooltip on first play only, auto-dismissing after first drag gesture
FR95: System prompts in-app review (App Store / Play Store rating) after the 5th puzzle completion or 7-day streak milestone, maximum once per 90 days, using the native in-app review API
FR96: System provides colorblind mode discovery — on first launch, settings include a prominent "Accessibility" section; if system accessibility features are detected (e.g., color filters enabled), a one-time prompt suggests enabling colorblind mode
FR97: System provides a "welcome back" experience for returning users after 7+ days of inactivity, showing their last streak status and a "Start fresh" encouragement

#### Error Recovery & Resilience (FR98-FR103)

FR98: System displays retry mechanism for failed score submissions — result screen shows "Score pending" with a manual retry button; queued result is preserved locally and retried automatically on next app launch or connectivity change
FR99: System handles OAuth/account conversion failures gracefully — if linking fails, the anonymous session is fully preserved, an error message explains what happened, and the user can retry or dismiss
FR100: System displays specific error states for invite code failures: "Code not found" (invalid), "Code expired" (regenerated), "Group is full" (50 members), "Already a member" (redirects to group detail)
FR101: System handles deep link failures with an informative error screen and "Go to Home" navigation — covers deleted groups, malformed URLs, and expired invite codes
FR102: System displays error state when puzzle loading fails with no cache — shows an illustration with "No puzzle available" message and retry button; falls back to bundled puzzles if available
FR103: System handles puzzle pre-generation failures with automated alerting and a fallback mechanism — if tomorrow's puzzle is not generated, the cron function retries up to 3 times with exponential backoff, and an alert is triggered

#### Data Management (FR104-FR107)

FR104: System purges abandoned anonymous user data after 90 days of inactivity (no puzzle solves, no app opens)
FR105: On account deletion, system anonymizes leaderboard entries (displayed as "Deleted User") rather than removing historical scores from group leaderboards
FR106: System displays data staleness indicator on leaderboards — shows "Updated just now" / "Updated N minutes ago" / "Offline — showing cached data" based on last successful fetch
FR107: System suppresses the offline banner during active puzzle play to preserve flow state; the offline indicator appears only on non-game screens (home, groups, stats, result)

#### Localization & Formatting (FR108-FR110)

FR108: System uses Flutter localization framework (intl package with ARB files) for all user-facing strings, enabling future language additions without code changes
FR109: System formats dates, times, and numbers according to device locale (e.g., solve time "1:12.5", dates "March 2, 2026" or "2 March 2026")
FR110: System supports right-to-left (RTL) layout infrastructure — all layouts use directional-aware widgets (e.g., EdgeInsetsDirectional) to enable future Arabic/Hebrew support

#### Accessibility (FR111-FR117)

FR111: All non-game UI screens (Home, Groups, Stats, Profile, Settings) provide complete screen reader semantic labels and are fully navigable via VoiceOver (iOS) and TalkBack (Android)
FR112: Puzzle grid cells provide screen reader semantic labels: "Row N, Column M, [empty/filled/waypoint N/wall]" and are navigable via accessibility gestures
FR113: System provides tap-to-select alternative input mode for puzzle play — players can tap adjacent cells one at a time to build the path instead of dragging, accessible from puzzle screen settings
FR114: System provides visible focus indicators (focus ring) on all interactive elements when navigating via external keyboard or switch control
FR115: All text elements support dynamic type up to 200% scaling without layout overflow or truncation — layouts adapt via scroll, text wrapping, or reduced content density
FR116: System provides visual-only alternatives for audio feedback cues (screen flash, icon animations) for deaf/hard-of-hearing users on devices without haptic motors
FR117: System provides colorblind mode with three alternative palettes (deuteranopia, protanopia, tritanopia) selectable in settings, using patterns/textures in addition to color changes

#### Analytics & Attribution (FR118-FR122)

FR118: System tracks a defined analytics event taxonomy covering all critical user actions: puzzle_started, puzzle_completed, hint_used, share_tapped, group_created, group_joined, invite_sent, account_created, account_linked, streak_milestone, app_opened, screen_view
FR119: System tracks first-time user funnel: app_installed → first_puzzle_started → first_puzzle_completed → account_created → first_group_joined
FR120: System tracks attribution source for new users — distinguishes installs from share cards, deep links (group invites), organic app store, and unknown sources
FR121: System supports A/B testing via Firebase Remote Config with user cohort assignment, experiment event tracking, and server-side configuration of testable parameters (hint count, difficulty curve, onboarding flow)
FR122: System supports feature flags via Firebase Remote Config with default fallback values — enables kill switches for broken features and gradual rollouts of new functionality

#### UX Polish (FR123-FR126)

FR123: System scrolls input fields into view when the soft keyboard appears, ensuring no text field is hidden behind the keyboard on any screen
FR124: Invite code input field auto-uppercases input, enforces 6-character limit, and provides clear character count feedback
FR125: System animates theme transitions with a 300ms cross-fade when switching between light, dark, and system themes
FR126: System provides sound effects for key game interactions (soft tick on cell entry, chime on waypoint, thud on wall collision, fanfare on completion) that complement haptic feedback and can be independently toggled

### NonFunctional Requirements

#### Performance (NFR1-NFR6)

NFR1: Path drawing interaction renders at 60 FPS minimum on devices released 2022 or later, as measured by frame timing profiler
NFR2: App cold start completes in < 2 seconds on mid-range devices, as measured by time from process start to first frame rendered
NFR3: Cached daily puzzle loads and renders in < 200ms, as measured by analytics event timing
NFR4: Network-fetched daily puzzle loads in < 500ms on 4G connection, as measured by API response time + render time
NFR5: Score submission API call completes in < 300ms on 4G connection, as measured by API latency monitoring
NFR6: Group leaderboard loads in < 500ms for groups with 50 members, as measured by API response time

#### Security (NFR7-NFR12)

NFR7: All network communication uses HTTPS/TLS 1.2+
NFR8: Authentication tokens are stored in platform-secure credential storage
NFR9: Puzzle solution paths are never transmitted to the client; server re-validates submitted paths against stored solutions
NFR10: Score submissions are rate-limited to 10 per hour per user to prevent abuse
NFR11: Solve times under 3 seconds for any grid size are rejected as physically impossible
NFR12: Database access control policies enforce that users can only read their own attempts and only read data within groups they belong to

#### Scalability (NFR13-NFR15)

NFR13: Backend supports 10,000 concurrent users with < 10% performance degradation on production-tier infrastructure
NFR14: Database indexes support O(log n) lookup for puzzles by date, attempts by user, and group membership queries
NFR15: Puzzle pre-generation runs as a scheduled function handling 30-day batch generation in under 60 seconds

#### Accessibility (NFR16-NFR19)

NFR16: All touch targets meet minimum 44x44dp sizing per Apple HIG and Material Design guidelines
NFR17: Color is not the sole indicator of any game state — colorblind mode adds patterns/textures to distinguish path, waypoints, walls, and empty cells
NFR18: All UI text meets WCAG 2.1 AA contrast ratio (4.5:1 for body text, 3:1 for large text)
NFR19: App respects system-level reduced motion settings by disabling animations when enabled

#### Reliability (NFR20-NFR22)

NFR20: Offline-to-online sync achieves zero data loss for puzzle completions, as validated by integration testing with network interruption scenarios
NFR21: App crash rate remains below 1% of sessions, as measured by crash reporting service
NFR22: Background puzzle cache refresh succeeds on at least 95% of attempts, as measured by analytics events

#### Security Hardening (NFR23-NFR28)

NFR23: Group join attempts rate-limited to 10 per minute per IP address to prevent invite code brute-forcing
NFR24: Authentication attempts rate-limited to 5 per minute per IP address to prevent credential brute-forcing
NFR25: All user-generated text input (display names, group names, descriptions) sanitized against XSS, SQL injection, and Unicode abuse before storage
NFR26: Session tokens expire after 30 days of inactivity; refresh tokens expire after 90 days; expired sessions require re-authentication
NFR27: Certificate pinning enforced for Supabase API connections to prevent MITM attacks via compromised CAs or user-installed certificates
NFR28: API request integrity verified via HMAC signing on score submissions to prevent replay attacks — each submission includes a nonce and timestamp validated server-side

#### Infrastructure & Operations (NFR29-NFR36)

NFR29: Database backups run daily with 30-day retention and point-in-time recovery (PITR) capability; backup restoration tested quarterly
NFR30: All Edge Functions expose /health endpoints returning 200 OK for synthetic uptime monitoring probes
NFR31: Server-side structured JSON logging with correlation IDs on all Edge Functions, retained for 90 days minimum, searchable via Supabase log explorer or external service
NFR32: Automated alerting triggers when: crash rate exceeds 1%, Edge Function error rate exceeds 5%, daily-puzzle cron misses scheduled run, database CPU exceeds 80%, or score submission success rate drops below 95%
NFR33: CI/CD pipeline manages all secrets via GitHub Actions encrypted secrets; Supabase service role key, Firebase keys, and store credentials are never committed to source control
NFR34: Android upload keystore stored in a secure vault (e.g., 1Password, AWS Secrets Manager) with documented recovery procedure; loss prevention documented in runbook
NFR35: iOS code signing managed via Fastlane Match with encrypted Git storage for certificates and provisioning profiles; Match encryption passphrase stored in CI secrets
NFR36: All database migrations include tested rollback scripts; migrations run against staging environment before production; pre-migration database snapshot taken automatically

#### Network Resilience (NFR37-NFR39)

NFR37: Network API calls use exponential backoff with jitter (initial 1s, max 30s, max 3 retries) for transient failures (5xx, timeout); non-retryable errors (4xx) fail immediately with user-facing error message
NFR38: HTTP request timeouts configured: connect timeout 5s, read timeout 10s for standard API calls, read timeout 30s for image generation (share card)
NFR39: Offline sync queue retries pending submissions with exponential backoff on reconnection; failed items are retried up to 5 times before being flagged for manual review in local storage

#### Data Integrity & Versioning (NFR40-NFR43)

NFR40: Client-side model deserialization validates all required fields, value ranges, and enum values; malformed server responses trigger graceful error display rather than crashes
NFR41: API versioning via Edge Function URL paths (e.g., /v1/submit-score) — old versions supported for minimum 90 days after new version deployment; version compatibility checked at app launch
NFR42: Local Hive cache includes schema version; on app update with cache format change, migration logic converts cached data to new format without data loss; failed migration falls back to cache clear and re-fetch
NFR43: pubspec.lock committed to version control; Flutter SDK version pinned via .fvmrc file; Supabase CLI version pinned in CI workflow

#### Memory & Performance Management (NFR44-NFR47)

NFR44: Puzzle game state auto-save completes in < 5ms per move using non-blocking I/O to avoid frame drops during path drawing
NFR45: Hive local cache limited to 50MB with LRU eviction policy; cache size monitored and reported via analytics; user notified if device storage is critically low
NFR46: Realtime WebSocket subscriptions cleaned up on group leave, screen disposal, and app background; maximum 5 concurrent subscriptions enforced
NFR47: Memory usage during puzzle rendering stays below 100MB including animations; animation controllers and Rive instances disposed on screen exit; memory pressure monitored via Firebase Performance

#### Accessibility Compliance (NFR48-NFR50)

NFR48: All non-game screens achieve 100% screen reader navigability verified by automated accessibility tests in CI and manual VoiceOver/TalkBack testing per release
NFR49: All text elements adapt to dynamic type up to 200% system font scaling without layout overflow, verified by golden tests at 100%, 150%, and 200% scale factors
NFR50: Orientation locked to portrait on phones (screen width < 768dp); portrait and landscape supported on tablets with adaptive grid layout

### Additional Requirements

**From Architecture:**

- Starter template: Custom Flutter project scaffold from PLAN.md Section 12 structure using `flutter create --org com.icos --project-name icos --platforms ios,android`
- Feature-based architecture: `lib/features/{feature}/data/domain/providers/presentation/` with 4-layer internal structure per feature
- Database: 6 PostgreSQL tables (profiles, puzzles, puzzle_attempts, streaks, groups, group_members) with SQL migrations in `supabase/migrations/`
- Row-Level Security (RLS) policies on all public tables enforcing access control at database layer
- Database RPC functions: `get_group_daily_leaderboard` and `get_group_weekly_leaderboard` for ranked queries
- Database indexes on puzzles(puzzle_date), puzzle_attempts(puzzle_date), puzzle_attempts(user_id), groups(invite_code), group_members(user_id)
- Authentication: Supabase Auth (GoTrue) with anonymous auth on first launch, OAuth linking via `linkIdentity`/`updateUser` API
- 4 Edge Functions (Deno runtime): daily-puzzle (cron), submit-score (HTTP POST), join-group (HTTP POST), generate-share-card (HTTP POST)
- State management: Riverpod 3.x (riverpod ^3.2.x, riverpod_annotation ^4.0.x) with AsyncNotifierProvider, StreamProvider, NotifierProvider patterns
- Navigation: GoRouter with declarative routes, deep link support (`/join/{invite_code}`, `/puzzle/{date}`), ShellRoute for bottom tabs
- Local storage: Hive for puzzle cache and offline sync queue, SharedPreferences for user settings
- Real-time: Supabase Realtime subscriptions on `puzzle_attempts` table for live leaderboard updates, channel-scoped to group_id
- Push notifications: Firebase Cloud Messaging with topics (`daily_puzzle`, `group_{group_id}`)
- CI/CD: GitHub Actions for lint/test/build + Fastlane for iOS/Android store deployment
- Monitoring: Firebase Crashlytics, Performance Monitoring, Analytics, Remote Config
- Environment configuration: `.env` files for development, staging, production with Supabase URL and anon key
- Error handling: Repository returns Result<T, AppError>, providers use AsyncValue, presentation uses `.when(data:, loading:, error:)` pattern
- Connectivity monitoring: Global `connectivityProvider` tracking network state for offline fallback
- Strict analysis: `analysis_options.yaml` with strict lint rules, `flutter analyze` in CI pipeline
- Testing structure: `test/unit/` for business logic, `test/widget/` for rendering, `test/integration/` for end-to-end flows
- Audit logging: Sensitive operations (account deletion, admin actions, account linking) logged with user ID, timestamp, and action type for compliance trail
- Query performance monitoring: `pg_stat_statements` enabled; slow query threshold set to 500ms with alerting
- Connection pool sizing: PgBouncer configured for expected concurrent connections based on user scale tier

**From UX Design:**

- Design direction: "Dark Immersive" with deep navy background (#0A1628), electric blue path (#3B82F6), coral-orange waypoints (#FF6B35)
- Three theme variants: light, dark, and system (follows OS setting), using Flutter ThemeData with custom extensions
- 12 custom components: PuzzleGrid, PathRenderer, WaypointCircle, WallBarrier, CelebrationOverlay, DailyPuzzleCard, StreakCounter, LeaderboardEntry, ShareCard, GroupInviteCard, HintButton, OfflineBanner
- 4 adaptive breakpoints: Compact (<375dp), Medium (375-413dp), Expanded (414-767dp), Tablet (768dp+)
- Portrait-locked on phones; adaptive landscape on tablets; grid sizing: `(screen_width - 48px) / grid_columns`
- Tablet: Grid size capped at 500dp width, content centered at max 600dp width; supports iPad Split View and Slide Over
- 12 animation timing specifications with curves and haptic pairings
- 7 haptic pattern definitions with iOS/Android platform implementations
- Celebration animation: 800ms total (200ms grid ripple + 600ms confetti burst), Rive or Flutter AnimationController
- Reduced motion variant: Simple green glow on grid border instead of full celebration
- Button hierarchy: Primary (ElevatedButton, full width, 48dp), Secondary (OutlinedButton, 40dp), Tertiary (TextButton, 36dp), Destructive (error color, confirmation required), Icon (44dp touch target)
- Empty states with actionable CTAs for all screens (0 groups, 0 solves, no puzzle available, expired invite code)
- Loading states: Skeleton shimmer for lists, CircularProgressIndicator for full-screen, inline spinner for buttons
- Bottom sheet patterns: Adaptive height (max 80%), drag handle, 24dp corner radius
- Confirmation dialogs for destructive actions
- SnackBar feedback: 3s success, 4s error with retry action
- WCAG 2.1 AA accessibility target with colorblind modes (deuteranopia, protanopia, tritanopia)
- Full screen reader support: semantic labels for all UI including grid cells, waypoints, leaderboard entries
- Gesture conflict prevention: Grid padding (24px), no system zoom on double-tap, no pull-to-refresh on puzzle screen
- Error state designs for: failed score submission, failed group join (invalid/expired/full), failed account conversion, failed puzzle fetch, network timeout transitions
- Keyboard handling: input fields scroll into view when soft keyboard appears on all form screens
- Data staleness indicators on leaderboards with "last updated" timestamps
- Offline banner suppressed during active puzzle play to preserve flow state
- Theme transition animation: 300ms cross-fade on theme switch
- First-time user affordances: pulsing waypoint 1, "Drag to draw" tooltip (auto-dismissing)
- Force update screen: full-screen blocking with app store link and explanation
- Maintenance mode screen: branded, with estimated restoration time and automatic retry
- Splash screen: branded Icos logo with background color matching selected theme

**From Visual Testing Strategy:**

- Golden tests for all custom components (PuzzleGrid, PathRenderer, ShareCard, etc.) covering all visual states
- Theme matrix: every component tested in light, dark, and colorblind themes
- Screen-level golden tests at 4 device sizes (iPhone SE, iPhone 15, Pixel 7, iPad Mini)
- Integration test screenshots for core user flows (first launch, puzzle solve, group join, offline play, share)
- Claude Code hooks for automated visual validation on every Dart file edit
- Visual gate hook on response completion running all golden tests
- Dynamic type golden tests at 100%, 150%, and 200% scaling

### FR Coverage Map

FR1: Epic 2 - Grid display with waypoints and walls
FR2: Epic 2 - Path drawing via finger drag
FR3: Epic 2 - Undo by dragging backward
FR4: Epic 2 - Undo button
FR5: Epic 2 - Redo button
FR6: Epic 2 - Reset puzzle
FR7: Epic 2 - Tap cell to truncate path
FR8: Epic 2 - Path validation (continuous, all cells, waypoint order, walls)
FR9: Epic 2 - Puzzle completion detection
FR10: Epic 2 - Celebration animation
FR11: Epic 2 - Haptic feedback patterns
FR12: Epic 3 - One puzzle per day for all users
FR13: Epic 3 - Difficulty scaling Mon-Sun
FR14: Epic 3 - Solve time tracking (hidden during play)
FR15: Epic 3 - Server-side 30-day puzzle pre-generation
FR16: Epic 3 - Pre-cache next day's puzzle 24h in advance
FR17: Epic 2 - Hint reveals next 2-3 cells
FR18: Epic 2 - 3 free hints per day (reset midnight UTC)
FR19: Epic 2 - Track hints used per attempt
FR20: Epic 1 - Anonymous play (no account required)
FR21: Epic 1 - Account creation (email, Google, Apple)
FR22: Epic 1 - Link anonymous session to account
FR23: Epic 1 - Set display name (max 20 chars)
FR24: Epic 1 - Select preset avatar
FR25: Epic 1 - Update display name and avatar
FR26: Epic 1 - Delete account (30-day grace period)
FR27: Epic 1 - Prompt account creation at 3rd solve or group join
FR28: Epic 3 - Track current streak
FR29: Epic 3 - Track longest-ever streak
FR30: Epic 3 - Track total puzzles solved and average time
FR31: Epic 3 - Streak freeze (1 per week)
FR32: Epic 3 - Auto-apply streak freeze
FR33: Epic 3 - Dedicated stats screen
FR34: Epic 4 - Create group (name, description)
FR35: Epic 4 - Generate 6-char invite code
FR36: Epic 4 - Join group via code, deep link, or QR
FR37: Epic 4 - Max 50 members per group
FR38: Epic 4 - Daily leaderboard (hints → time → undos)
FR39: Epic 4 - Weekly leaderboard (completed → avg time)
FR40: Epic 4 - Admin remove members
FR41: Epic 4 - Admin regenerate invite code
FR42: Epic 4 - Leave group
FR43: Epic 4 - Admin delete group
FR44: Epic 4 - Show solved/unsolved member states (spoiler-free)
FR45: Epic 5 - Generate spoiler-free share card
FR46: Epic 5 - Share via native OS share sheet
FR47: Epic 5 - Copy result to clipboard as text
FR48: Epic 5 - Share group invite (deep link, code, QR)
FR49: Epic 6 - Cache tomorrow's puzzle via background fetch
FR50: Epic 6 - Solve daily puzzle offline
FR51: Epic 6 - Queue results offline, auto-sync on reconnect
FR52: Epic 6 - 7 bundled offline fallback puzzles
FR53: Epic 6 - Offline indicator display
FR54: Epic 1 - Toggle haptic feedback
FR55: Epic 1 - Toggle sound effects
FR56: Epic 1 - Theme selection (light/dark/system)
FR57: Epic 7 - Notification preferences per group
FR58: Epic 1 - View privacy policy and ToS
FR59: Epic 1 - Bottom navigation (Home, Groups, Stats, Profile)
FR60: Epic 3 - Home screen (puzzle card, streak, group activity)
FR61: Epic 5 - Deep links for group invites
FR62: Epic 1 - Age verification gate (13+)
FR63: Epic 1 - Privacy consent flow before analytics
FR64: Epic 1 - Apple ATT prompt on iOS
FR65: Epic 1 - ToS active acceptance before account creation
FR66: Epic 10 - Data export (GDPR portability)
FR67: Epic 10 - DSAR handling (backend data export)
FR68: Epic 10 - Force update screen (min version check)
FR69: Epic 2 - Auto-save puzzle state every move
FR70: Epic 2 - Pause timer on app background
FR71: Epic 1 - Branded splash screen
FR72: Epic 1 - Orientation lock (portrait on phones)
FR73: Epic 10 - Maintenance mode screen
FR74: Epic 10 - State restoration after OS process death
FR75: Epic 10 - Clock manipulation detection
FR76: Epic 3 - Daily puzzle rollover at midnight UTC
FR77: Epic 3 - Weekly leaderboard boundary (Monday UTC)
FR78: Epic 3 - Streak evaluation at midnight UTC
FR79: Epic 8 - Profanity filter for names
FR80: Epic 8 - Input sanitization (XSS, injection, Unicode abuse)
FR81: Epic 8 - In-app reporting mechanism
FR82: Epic 4 - Rate limit group creation (5/day)
FR83: Epic 8 - User-level ban system
FR84: Epic 4 - Admin succession on account deletion
FR85: Epic 6 - One attempt per day across devices
FR86: Epic 6 - Concurrent session state sync
FR87: Epic 10 - Session lifecycle (token expiry, active sessions)
FR88: Epic 7 - Notification pre-permission screen
FR89: Epic 7 - Daily puzzle reminder notification
FR90: Epic 7 - Group activity nudge notification
FR91: Epic 7 - Streak-at-risk notification
FR92: Epic 7 - Notification type filtering in settings
FR93: Epic 7 - In-app badge on Groups tab
FR94: Epic 2 - First-time puzzle affordances
FR95: Epic 7 - App store rating prompt
FR96: Epic 9 - Colorblind mode discoverability
FR97: Epic 3 - Welcome back experience (7+ days inactive)
FR98: Epic 6 - Score submission failure recovery
FR99: Epic 10 - OAuth/account conversion failure recovery
FR100: Epic 4 - Invite code error states (invalid, expired, full, duplicate)
FR101: Epic 5 - Deep link failure handling
FR102: Epic 10 - Puzzle load failure state
FR103: Epic 10 - Puzzle generation failure alerting and retry
FR104: Epic 8 - Purge anonymous data after 90 days
FR105: Epic 8 - Anonymize deleted user leaderboard entries
FR106: Epic 4 - Data staleness indicators on leaderboards
FR107: Epic 6 - Suppress offline banner during puzzle play
FR108: Epic 1 - Localization framework (intl/ARB)
FR109: Epic 1 - Locale-aware date/time/number formatting
FR110: Epic 1 - RTL layout infrastructure
FR111: Epic 9 - Screen reader for non-game UI
FR112: Epic 9 - Screen reader for puzzle grid cells
FR113: Epic 2 - Tap-to-select alternative input mode
FR114: Epic 9 - Focus indicators for keyboard/switch navigation
FR115: Epic 9 - Dynamic type up to 200% scaling
FR116: Epic 9 - Visual alternatives for audio/haptic feedback
FR117: Epic 9 - Colorblind palettes (deuteranopia, protanopia, tritanopia)
FR118: Epic 11 - Analytics event taxonomy
FR119: Epic 11 - First-time user funnel tracking
FR120: Epic 11 - Attribution source tracking
FR121: Epic 11 - A/B testing via Remote Config
FR122: Epic 11 - Feature flags with default fallbacks
FR123: Epic 1 - Keyboard scroll handling for input fields
FR124: Epic 4 - Invite code input formatting (auto-uppercase, 6-char limit)
FR125: Epic 1 - Theme transition animation (300ms cross-fade)
FR126: Epic 2 - Sound effects for game interactions

## Epic List

### Epic 1: App Foundation & User Identity
Users can install the app, see a branded splash screen, complete age verification and privacy consent, play anonymously or create an account (email/Google/Apple), link anonymous sessions without data loss, manage their profile (display name, avatar), navigate between app sections via bottom tabs, select their preferred theme (light/dark/system), toggle haptic and sound preferences, and view privacy policy and terms of service. The app launches in portrait orientation on phones, supports localization infrastructure for future languages, and handles keyboard interactions correctly.

**FRs covered:** FR20, FR21, FR22, FR23, FR24, FR25, FR26, FR27, FR54, FR55, FR56, FR58, FR59, FR62, FR63, FR64, FR65, FR71, FR72, FR108, FR109, FR110, FR123, FR125
**Key NFRs:** NFR2 (cold start <2s), NFR7 (HTTPS/TLS), NFR8 (secure token storage), NFR24 (auth rate limiting), NFR26 (session expiry), NFR33 (CI secrets), NFR34 (Android keystore), NFR35 (iOS code signing), NFR41 (API versioning), NFR42 (cache migration), NFR43 (version pinning), NFR50 (orientation lock)
**Dependencies:** None — standalone foundation epic

### Epic 2: Core Puzzle Gameplay
Users can see the puzzle grid with waypoints and walls, draw paths by dragging their finger, undo by dragging backward or via buttons, redo, reset, tap to truncate, request hints (3/day), and experience celebration animation on completion. The game provides haptic feedback, sound effects, auto-saves state every move, pauses the timer when backgrounded, offers tap-to-select as an alternative input mode, and shows first-time affordances for new players.

**FRs covered:** FR1, FR2, FR3, FR4, FR5, FR6, FR7, FR8, FR9, FR10, FR11, FR17, FR18, FR19, FR69, FR70, FR94, FR113, FR126
**Key NFRs:** NFR1 (60 FPS), NFR3 (cached puzzle <200ms), NFR16 (44dp touch targets), NFR44 (auto-save <5ms), NFR47 (memory <100MB)
**Dependencies:** Epic 1 (auth, navigation, theme)

### Epic 3: Daily Challenge, Streaks & Statistics
Users receive a new puzzle every day at midnight UTC with difficulty scaling from Monday (5x5) through Sunday (8x8). Puzzles are pre-generated 30 days ahead and pre-cached 24 hours before release. Users track current and longest streaks, total solves, average time, and can use one streak freeze per week (auto-applied). The home screen displays the daily puzzle card, streak counter, and group activity summary. Returning users after 7+ days get a welcome back experience.

**FRs covered:** FR12, FR13, FR14, FR15, FR16, FR28, FR29, FR30, FR31, FR32, FR33, FR60, FR76, FR77, FR78, FR97
**Key NFRs:** NFR4 (network puzzle <500ms), NFR5 (score submission <300ms), NFR9 (server-side validation), NFR11 (anti-cheat timing), NFR13 (10K concurrent), NFR14 (O(log n) indexes), NFR15 (batch generation <60s)
**Dependencies:** Epic 1 (auth, navigation), Epic 2 (puzzle engine)

### Epic 4: Groups & Leaderboards
Users can create groups (name, description), get unique 6-character invite codes, join groups via code entry/deep link/QR scan, and compete on daily leaderboards (ranked by hints → time → undos) and weekly leaderboards (completed → avg time). Admins can remove members, regenerate invite codes, and delete groups. The system enforces 50-member limits, rate-limits group creation (5/day), handles admin succession on account deletion, displays solved/unsolved member states without spoilers, shows data staleness indicators, and provides clear error states for invalid/expired/full invite codes.

**FRs covered:** FR34, FR35, FR36, FR37, FR38, FR39, FR40, FR41, FR42, FR43, FR44, FR82, FR84, FR100, FR106, FR124
**Key NFRs:** NFR6 (leaderboard <500ms), NFR12 (RLS access control), NFR23 (invite code rate limiting), NFR25 (input sanitization), NFR46 (subscription cleanup)
**Dependencies:** Epic 1 (auth, profile), Epic 3 (daily puzzle, solve data)

### Epic 5: Sharing & Viral Growth
Users can generate spoiler-free share cards showing grid size, solve time, day identifier, and abstract path visualization. They can share via native OS share sheet, copy results to clipboard as text, and share group invites via deep links, invite codes, or QR code images. Deep links open the app directly to the group join flow or redirect to the app store if not installed. The system handles deep link failures gracefully with informative error screens.

**FRs covered:** FR45, FR46, FR47, FR48, FR61, FR101
**Key NFRs:** NFR38 (share card generation timeout 30s)
**Dependencies:** Epic 2 (puzzle completion), Epic 4 (groups, invite codes)

### Epic 6: Offline Play & Multi-Device Sync
Users can play offline with pre-cached puzzles (background fetch 12h+ before release) and 7 bundled fallback puzzles for first-launch offline scenarios. Puzzle results queue locally when offline and sync automatically on reconnection. The system enforces one puzzle attempt per day across all devices (first verified solve wins), maintains consistent state across concurrent sessions (streaks, stats, groups), provides score submission failure recovery with local preservation and retry, and suppresses the offline banner during active puzzle play to preserve flow state.

**FRs covered:** FR49, FR50, FR51, FR52, FR53, FR85, FR86, FR98, FR107
**Key NFRs:** NFR20 (zero data loss sync), NFR22 (95% cache refresh), NFR37 (exponential backoff), NFR39 (sync queue retry), NFR42 (cache migration), NFR45 (cache size limit 50MB)
**Dependencies:** Epic 2 (puzzle engine), Epic 3 (daily system, streaks)

### Epic 7: Notifications & Engagement
Users receive push notifications with a thoughtful permission strategy (pre-permission screen after first solve). Notification types include daily puzzle reminders (configurable time), group activity nudges ("You're the last one!"), and streak-at-risk alerts. Users can filter notification types independently and configure per-group preferences. The Groups tab shows an in-app badge for new activity. The system prompts app store ratings at optimal moments (5th solve or 7-day streak, max once per 90 days).

**FRs covered:** FR57, FR88, FR89, FR90, FR91, FR92, FR93, FR95
**Key NFRs:** NFR38 (network timeouts)
**Dependencies:** Epic 1 (auth), Epic 3 (streaks, solve data), Epic 4 (groups)

### Epic 8: Content Moderation & Safety
Users are protected from offensive content through profanity filtering on display names and group names, input sanitization against XSS/injection/Unicode abuse, and an in-app reporting mechanism for offensive content. The system supports user-level bans enforced at auth and Edge Function layers, purges abandoned anonymous user data after 90 days of inactivity, and anonymizes leaderboard entries for deleted accounts ("Deleted User") rather than removing historical scores.

**FRs covered:** FR79, FR80, FR81, FR83, FR104, FR105
**Key NFRs:** NFR25 (input sanitization)
**Dependencies:** Epic 1 (auth, profiles), Epic 4 (groups, leaderboards)

### Epic 9: Accessibility & Inclusive Design
All users can enjoy Icos regardless of ability. Screen reader support covers all non-game UI (Home, Groups, Stats, Profile, Settings) and puzzle grid cells with semantic labels. Users can enable colorblind mode (deuteranopia, protanopia, tritanopia palettes) with discoverability prompts. The app supports dynamic type up to 200% scaling without layout breakage, tap-to-select as an alternative to drag input, visible focus indicators for keyboard/switch navigation, and visual-only alternatives for audio/haptic feedback on devices without haptic motors.

**FRs covered:** FR96, FR111, FR112, FR114, FR115, FR116, FR117
**Key NFRs:** NFR16 (44dp touch targets), NFR17 (colorblind patterns), NFR18 (WCAG 2.1 AA contrast), NFR19 (reduced motion), NFR48 (screen reader verification), NFR49 (dynamic type golden tests)
**Dependencies:** Epic 1 (app shell, theme), Epic 2 (puzzle engine)

### Epic 10: Error Recovery & App Resilience
The app handles all failure scenarios gracefully. Force update blocks outdated clients with an app store redirect. Maintenance mode displays estimated restoration time with offline fallback. State restoration resumes the correct screen after OS process death. Clock manipulation detection rejects fraudulent submissions. OAuth/account conversion failures preserve the anonymous session with retry options. Puzzle load and generation failures show informative states with retry mechanisms. Users can export their data (GDPR portability) and the backend supports DSAR handling. Session lifecycle enforces token expiry and allows viewing active sessions.

**FRs covered:** FR66, FR67, FR68, FR73, FR74, FR75, FR87, FR99, FR102, FR103
**Key NFRs:** NFR28 (HMAC signing), NFR29 (daily backups), NFR30 (Edge Function health endpoints), NFR31 (structured logging), NFR32 (automated alerting), NFR36 (migration rollback), NFR40 (response validation)
**Dependencies:** Epic 1 (auth, app shell), Epic 2 (puzzle engine), Epic 3 (daily system, score submission), Epic 4 (groups)

### Epic 11: Analytics, Feature Flags & Optimization
The system tracks all critical user actions via a defined analytics event taxonomy, measures the first-time user funnel (install → solve → account → group), tracks attribution sources (share cards, deep links, organic), supports A/B testing via Firebase Remote Config with cohort assignment and experiment tracking, and enables feature flags with default fallback values for kill switches and gradual rollouts.

**FRs covered:** FR118, FR119, FR120, FR121, FR122
**Key NFRs:** NFR30 (logging), NFR31 (structured logging), NFR32 (alerting)
**Dependencies:** Epic 1 (auth, app shell)

---

## Epic Stories

## Epic 1: App Foundation & User Identity — Stories

### Story 1.1: Flutter Project Initialization & App Shell

As a player,
I want to launch the app and see a branded splash screen, navigate between sections via bottom tabs, and select my preferred theme,
So that I have a polished, navigable app experience from the first moment.

**Acceptance Criteria:**

**Given** the app has never been launched on this device
**When** the user opens the app for the first time
**Then** a branded Icos splash screen is displayed during cold start with the Icos logo and a background color matching the current theme
**And** the Flutter project is scaffolded per PLAN.md Section 12 structure with core dependencies installed (Riverpod, GoRouter, Supabase SDK, Firebase SDK)

**Given** the splash screen has completed loading
**When** the app finishes initialization
**Then** bottom navigation is displayed with exactly four tabs: Home, Groups, Stats, and Profile
**And** tapping each tab navigates to the corresponding screen shell (placeholder content is acceptable for screens not yet implemented)

**Given** the user is on any screen
**When** the user navigates to Profile > Theme Settings and selects light, dark, or system theme
**Then** the entire app theme updates immediately with a 300ms cross-fade animation between the old and new theme
**And** the selected theme preference persists across app restarts via SharedPreferences

**Given** the app is running on a phone with screen width < 768dp
**When** the user rotates the device to landscape
**Then** the app remains locked in portrait orientation and does not rotate

**Given** the Supabase project has been initialized
**When** the app connects to the backend for the first time
**Then** the profiles table exists in the database with columns: id (UUID PK, references auth.users), display_name (text, nullable), avatar_id (text, nullable), is_anonymous (boolean), created_at (timestamptz), updated_at (timestamptz)
**And** environment configuration is loaded from .env file containing Supabase URL and anon key

**Covers:** FR71, FR59, FR56, FR72, FR125

---

### Story 1.2: Legal Consent & Age Verification Gate

As a player,
I want to verify my age and provide privacy consent before any data is collected,
So that the app complies with COPPA, GDPR, and Apple privacy requirements.

**Acceptance Criteria:**

**Given** the app is launched for the very first time on a device
**When** the splash screen completes
**Then** an age verification screen is displayed before any other content, asking the user to confirm they are 13 years of age or older
**And** no analytics events, crash reports, or tracking data are collected until age verification is completed

**Given** the user is on the age verification screen
**When** the user confirms they are 13 or older
**Then** a privacy consent flow is presented with granular opt-in/opt-out toggles for: analytics data collection, crash reporting, and personalization
**And** each toggle clearly explains what data is collected and how it is used

**Given** the user is on the privacy consent screen
**When** the user makes their selections and taps "Continue"
**Then** consent preferences are persisted locally via SharedPreferences
**And** only the opted-in services are initialized (analytics, crash reporting, personalization)

**Given** the app is running on iOS and the user has opted into any form of tracking
**When** the privacy consent flow completes
**Then** the Apple App Tracking Transparency (ATT) prompt is displayed before any tracking or attribution begins
**And** if the user denies ATT, no IDFA-based tracking occurs but the app continues to function normally

**Given** the user indicates they are under 13 on the age verification screen
**When** the user taps the under-13 option
**Then** the app displays a message explaining the app is not available for users under 13 and does not proceed to any gameplay or data collection

**Covers:** FR62, FR63, FR64

---

### Story 1.3: Anonymous Authentication

As a player,
I want to start playing immediately without creating an account,
So that I can try the game without any friction or commitment.

**Acceptance Criteria:**

**Given** the user has completed age verification and privacy consent (Story 1.2)
**When** the app proceeds past the consent flow
**Then** the system silently creates an anonymous session via Supabase Auth without showing any authentication UI to the user
**And** a corresponding row is created in the profiles table with is_anonymous set to true

**Given** the anonymous session has been created
**When** the user navigates to any authenticated feature (puzzle play, stats, profile)
**Then** all features work seamlessly with the anonymous session and the user is never interrupted by login prompts during normal gameplay

**Given** the user closes and reopens the app
**When** the app launches again
**Then** the existing anonymous session is restored from secure credential storage without creating a duplicate session
**And** the user's anonymous profile data is preserved

**Given** the anonymous authentication request fails due to network error
**When** the app cannot reach Supabase Auth
**Then** the app displays an appropriate error message with a retry button and does not crash or show a blank screen

**Covers:** FR20

---

### Story 1.4: Account Creation with Social Sign-In

As a player,
I want to create an account using email, Google, or Apple Sign-In,
So that I can secure my progress and access my data across devices.

**Acceptance Criteria:**

**Given** the user navigates to the Profile tab and taps "Create Account" or "Sign In"
**When** the registration screen is displayed
**Then** three sign-in options are presented: email/password registration, Google Sign-In, and Apple Sign-In
**And** the Terms of Service acceptance checkbox is displayed and must be actively checked before any account creation method can proceed

**Given** the user selects email/password registration
**When** the user enters a valid email and password (minimum 8 characters) and accepts the ToS
**Then** the account is created via Supabase Auth, the user is signed in, and the profiles table is updated with is_anonymous set to false
**And** if the email is already in use, a clear error message "An account with this email already exists" is displayed

**Given** the user selects Google Sign-In
**When** the Google OAuth flow completes successfully and the user has accepted the ToS
**Then** the account is created or linked via Supabase Auth, the user is signed in, and the profiles table is updated accordingly

**Given** the user selects Apple Sign-In
**When** the Apple OAuth flow completes successfully and the user has accepted the ToS
**Then** the account is created or linked via Supabase Auth, the user is signed in, and the profiles table is updated accordingly
**And** Apple's "Hide My Email" relay is handled correctly

**Given** any sign-in method is attempted
**When** the OAuth flow fails or the network request times out
**Then** a specific error message is shown (e.g., "Sign-in was cancelled", "Network error — please try again") and the user remains on the registration screen without data loss

**Given** the user has not checked the Terms of Service checkbox
**When** the user attempts to proceed with any sign-in method
**Then** the "Create Account" / "Sign In" button is disabled and a helper text indicates "You must accept the Terms of Service to continue"

**Covers:** FR21, FR65

---

### Story 1.5: Anonymous-to-Account Linking & Conversion Prompt

As an anonymous player,
I want to upgrade to a full account and keep all my progress,
So that I do not lose my streaks, stats, or group memberships.

**Acceptance Criteria:**

**Given** the user is authenticated anonymously and has solved their 3rd puzzle
**When** the puzzle completion screen is displayed
**Then** a bottom sheet appears prompting the user to create an account with the message "Save your progress! Create an account to keep your streaks and stats."
**And** the bottom sheet is dismissible via swipe-down or a "Not now" button and does not reappear until the next qualifying trigger

**Given** the user is authenticated anonymously and attempts to join a group
**When** the user taps "Join Group" on any group join flow
**Then** a bottom sheet appears prompting account creation with the message "Create an account to join groups and compete with friends"
**And** the bottom sheet is dismissible and the join action is paused until the user either creates an account or dismisses the prompt

**Given** the anonymous user decides to create an account from the conversion prompt
**When** the user completes the account creation flow (email, Google, or Apple) via Supabase linkIdentity or updateUser
**Then** all existing data is preserved: current streak, longest streak, solve history, puzzle attempts, hints used, and any locally cached state
**And** the profiles table row is updated in-place (same user ID) with is_anonymous set to false

**Given** the account linking process fails (e.g., email already in use, network error)
**When** the linkIdentity or updateUser call returns an error
**Then** the anonymous session is fully preserved with no data loss, an error message explains what went wrong, and the user can retry or dismiss

**Covers:** FR22, FR27

---

### Story 1.6: Profile Management

As a player,
I want to set my display name and avatar and manage my account,
So that I have a recognizable identity in groups and leaderboards.

**Acceptance Criteria:**

**Given** the user navigates to the Profile tab
**When** the profile screen is displayed
**Then** the user sees their current display name (or "Anonymous" if not set), their current avatar (or a default silhouette), and an "Edit Profile" option

**Given** the user taps "Edit Profile"
**When** the user enters a display name
**Then** the display name field enforces a maximum of 20 characters with a visible character counter (e.g., "14/20")
**And** the display name is saved to the profiles table upon tapping "Save" and reflected immediately across all screens (profile, leaderboards, group member lists)

**Given** the user is on the Edit Profile screen
**When** the user taps on the avatar selection area
**Then** a grid of preset avatar images is displayed for selection
**And** tapping an avatar selects it visually with a highlight indicator and the selection is saved to the profiles table upon tapping "Save"

**Given** the user wants to delete their account
**When** the user navigates to Profile > Account > Delete Account
**Then** a confirmation dialog is displayed with the message "Your account will be permanently deleted after 30 days. You can sign in again within that period to cancel the deletion."
**And** upon confirmation, the account is marked for deletion with a 30-day grace period, the user is signed out, and a new anonymous session is created

**Given** a user's account is within the 30-day deletion grace period
**When** the user signs back in with the same credentials
**Then** the deletion is cancelled, the account is fully restored with all data intact, and the user is informed "Your account deletion has been cancelled"

**Covers:** FR23, FR24, FR25, FR26

---

### Story 1.7: Settings & Preferences

As a player,
I want to configure app settings like haptic feedback, sound effects, and view legal documents,
So that I can customize the app experience to my preferences.

**Acceptance Criteria:**

**Given** the user navigates to the Profile tab and taps "Settings"
**When** the settings screen is displayed
**Then** the following options are visible: Haptic Feedback toggle (default on), Sound Effects toggle (default on), Privacy Policy link, and Terms of Service link
**And** all toggle states persist across app restarts via SharedPreferences

**Given** the user toggles Haptic Feedback off
**When** the toggle is switched
**Then** no haptic feedback is produced anywhere in the app until the toggle is re-enabled
**And** the preference is saved immediately without requiring a "Save" button

**Given** the user toggles Sound Effects off
**When** the toggle is switched
**Then** no sound effects are produced anywhere in the app until the toggle is re-enabled
**And** the preference is saved immediately without requiring a "Save" button

**Given** the user taps "Privacy Policy" or "Terms of Service"
**When** the link is activated
**Then** the corresponding legal document is displayed within the app (in-app web view or formatted text screen)
**And** the user can navigate back to Settings via the back button

**Given** the app is configured for localization
**When** any user-facing string is rendered
**Then** all strings are sourced from ARB files via the Flutter intl package (no hardcoded user-facing strings in Dart code)
**And** date, time, and number formatting respects the device locale (e.g., "1:12.5" for solve time, locale-appropriate date formats)

**Given** the app layout is rendered on any screen
**When** a right-to-left (RTL) locale is active
**Then** all layouts use directional-aware widgets (EdgeInsetsDirectional, TextDirection-aware alignment) so the UI mirrors correctly
**And** all text input fields scroll into view when the soft keyboard appears, ensuring no input is hidden behind the keyboard

**Covers:** FR54, FR55, FR58, FR108, FR109, FR110, FR123

---

## Epic 2: Core Puzzle Gameplay — Stories

### Story 2.1: Puzzle Grid Rendering

As a player,
I want to see the puzzle grid with numbered waypoints and wall barriers clearly displayed,
So that I understand the puzzle layout before I begin solving.

**Acceptance Criteria:**

**Given** a puzzle has been loaded (from cache, network, or bundled fallback)
**When** the puzzle screen is displayed
**Then** a CustomPainter renders the grid with the correct number of rows and columns, with each cell clearly delineated by grid lines
**And** the grid width is calculated as `(screen_width - 48px) / grid_columns` to fit the screen with 24px padding on each side

**Given** the puzzle data includes waypoints
**When** the grid is rendered
**Then** each waypoint is displayed as a coral-orange (#FF6B35) numbered circle positioned at the center of its designated cell
**And** waypoint numbers are rendered in sequential order (1, 2, 3, ...) with legible white text inside the circles

**Given** the puzzle data includes wall barriers
**When** the grid is rendered
**Then** walls are displayed as thick lines (3-4dp) on the edges between adjacent cells where the wall exists
**And** walls are visually distinct from standard grid lines (thicker, darker/bolder color)

**Given** the puzzle grid is rendered in different themes
**When** the user switches between light and dark theme
**Then** the grid colors adapt to the current theme — dark theme uses deep navy background (#0A1628), light theme uses appropriate contrasting colors
**And** empty cells are visually distinct from filled cells in both themes

**Given** the puzzle grid is rendered on screens of different widths
**When** the screen size varies from compact (<375dp) to tablet (768dp+)
**Then** the grid scales proportionally while maintaining square cells and readable waypoint numbers
**And** on tablets, the grid width is capped at 500dp with the content centered

**Covers:** FR1

---

### Story 2.2: Path Drawing with Touch Gestures

As a player,
I want to draw my path by dragging my finger across the grid,
So that I can solve the puzzle intuitively with natural touch interaction.

**Acceptance Criteria:**

**Given** the puzzle grid is displayed and no path has been drawn
**When** the user places their finger on waypoint 1 and begins dragging
**Then** a GestureDetector translates screen coordinates to grid cell coordinates and the path begins from waypoint 1
**And** each cell entered is filled with the blue path color (#3B82F6) with a subtle glow effect, and the current (most recent) cell has a brighter highlight

**Given** the user is actively dragging a path
**When** the user's finger moves to an adjacent cell (horizontally or vertically, not diagonally)
**Then** the cell is added to the path if it is unvisited, and the path segment connecting the previous cell to the new cell is drawn
**And** the path validation ensures the move is to an adjacent cell (no skipping), the cell has not been visited already, and no wall barrier exists between the two cells

**Given** the user is drawing a path and encounters a wall barrier
**When** the user's finger moves in the direction of the wall
**Then** the path does not extend through the wall and the cell beyond the wall is not added to the path
**And** the system provides haptic/visual feedback indicating the wall collision (error haptic pattern)

**Given** the user is drawing a path that reaches a numbered waypoint
**When** the waypoint is the next expected waypoint in numerical order
**Then** the waypoint cell is added to the path normally
**And** if the waypoint is out of order (e.g., reaching waypoint 3 before waypoint 2), the cell can still be traversed but the out-of-order status is tracked for completion validation

**Given** the user lifts their finger from the screen
**When** the drag gesture ends
**Then** the current path state is preserved and the user can place their finger back on the last cell of the path to continue drawing from that point

**Covers:** FR2, FR8

---

### Story 2.3: Path Undo, Redo & Reset

As a player,
I want to undo mistakes, redo undone moves, and reset the puzzle,
So that I can correct errors without starting over unless I choose to.

**Acceptance Criteria:**

**Given** the user has drawn a path of 2 or more cells
**When** the user drags their finger backward along the already-drawn path (retracing)
**Then** each cell that the finger retraces is removed from the path with a smooth fade-out animation
**And** the path shrinks back to the point where the user's finger currently rests

**Given** the user has drawn a path of 1 or more cells
**When** the user taps the undo button
**Then** the last cell added to the path is removed with a smooth animation
**And** the undo action is added to the redo stack so it can be re-applied

**Given** the user has performed one or more undo actions
**When** the user taps the redo button
**Then** the most recently undone cell is restored to the path with a smooth animation
**And** the redo stack is cleared if the user draws a new cell manually (new move invalidates redo history)

**Given** the user has drawn any path on the grid
**When** the user taps the reset button
**Then** a confirmation dialog appears with the message "Reset puzzle? This will clear your entire path."
**And** upon confirmation, all cells are cleared, the path is emptied, the undo/redo stacks are cleared, and the grid returns to its initial state with only waypoints and walls visible

**Given** the user has drawn a path of 3 or more cells
**When** the user taps on a cell that is part of the drawn path (not the last cell)
**Then** all cells from the tapped cell to the end of the path are removed (truncated)
**And** the tapped cell becomes the new end of the path, and removed cells fade out smoothly

**Covers:** FR3, FR4, FR5, FR6, FR7

---

### Story 2.4: Puzzle Completion & Celebration

As a player,
I want to see a celebration when I complete the puzzle and view my solve time,
So that I feel rewarded and can track my performance.

**Acceptance Criteria:**

**Given** the user has filled every cell on the grid with their path
**When** the system validates that all cells are visited exactly once and all waypoints were passed through in numerical order
**Then** the puzzle is marked as complete and the celebration animation begins immediately

**Given** the puzzle is marked as complete
**When** the celebration animation plays
**Then** an 800ms animation sequence executes: first a 200ms grid ripple effect (cells illuminate outward from center), then a 600ms confetti burst overlay
**And** the celebration animation does not block user interaction — the user can dismiss or wait for it to complete

**Given** the device has reduced motion enabled in system accessibility settings
**When** the puzzle is completed
**Then** instead of the full celebration animation, a simple green glow effect appears on the grid border
**And** no confetti or rapid motion effects are displayed

**Given** the celebration animation has completed or been dismissed
**When** the result screen is displayed
**Then** the solve time is shown in large monospace text format (e.g., "1:23.4")
**And** a percentile placeholder is displayed (e.g., "Top --%" or "Ranking coming soon") for future server-side percentile calculation

**Given** the puzzle has been solved
**When** the user returns to the puzzle screen for today's puzzle
**Then** the completed grid is displayed with the solved path visible and a "Solved" badge, and the play controls are disabled

**Covers:** FR9, FR10, FR14

---

### Story 2.5: Haptic Feedback & Sound Effects

As a player,
I want to feel haptic vibrations and hear sound effects as I interact with the puzzle,
So that the gameplay feels tactile, responsive, and satisfying.

**Acceptance Criteria:**

**Given** the user has haptic feedback enabled in settings (default: on)
**When** the user interacts with the puzzle
**Then** 7 distinct haptic patterns are triggered at the appropriate moments: cellEntry (light impact), waypointReached (medium impact), wallCollision (error/notification pattern), puzzleComplete (success pattern — double tap), hintUsed (light impact), buttonTap (selection click), streakMilestone (success pattern)
**And** haptic implementations use platform-specific APIs (UIImpactFeedbackGenerator on iOS, HapticFeedback on Android)

**Given** the user has sound effects enabled in settings (default: on)
**When** the user interacts with the puzzle
**Then** 4 sound effects play at the corresponding moments: soft tick on cell entry, chime on waypoint reached, thud on wall collision, fanfare on puzzle completion
**And** sounds are loaded from bundled assets and play with negligible latency (<50ms)

**Given** the user has haptic feedback disabled in settings
**When** any haptic-triggering interaction occurs
**Then** no haptic feedback is produced and the interaction otherwise proceeds normally

**Given** the user has sound effects disabled in settings
**When** any sound-triggering interaction occurs
**Then** no sound effect is played and the interaction otherwise proceeds normally

**Given** the device does not support haptic feedback (e.g., older devices or emulators)
**When** haptic feedback is attempted
**Then** the system degrades gracefully with no errors or crashes, and the haptic call is silently skipped

**Covers:** FR11, FR126

---

### Story 2.6: Hint System

As a player,
I want to request hints when I am stuck,
So that I can make progress on difficult puzzles without giving up.

**Acceptance Criteria:**

**Given** the user is on the puzzle screen and has not used all daily hints
**When** the user taps the hint button
**Then** the correct next 2-3 cells from the user's current path endpoint are revealed with a glow animation, showing where the path should go next
**And** the revealed hint cells animate into place (fade-in with glow, ~300ms) and are added to the user's path automatically

**Given** the user has 3 free hints available at the start of each day
**When** the user uses a hint
**Then** the available hint count decreases by 1 and a badge on the hint button displays the remaining count (e.g., "2" remaining)
**And** the hints_used counter for this puzzle attempt is incremented by 1

**Given** the user has used all 3 hints for the day
**When** the user taps the hint button
**Then** the button displays a "No hints remaining" state (grayed out or with informative text)
**And** a brief message is shown: "Hints reset at midnight UTC" with the approximate time until reset

**Given** it is past midnight UTC
**When** the new day begins
**Then** the user's daily hint count resets to 3 regardless of how many were used the previous day
**And** the hint button badge updates to show 3 available

**Given** the user has used 1 or more hints on a puzzle
**When** the puzzle is completed or the attempt data is saved
**Then** the total hints_used for this attempt is tracked and included in any score submission

**Covers:** FR17, FR18, FR19

---

### Story 2.7: Puzzle State Auto-Save & Timer Management

As a player,
I want my puzzle progress to be automatically saved and my timer to pause when I leave the app,
So that I never lose progress due to interruptions, crashes, or app restarts.

**Acceptance Criteria:**

**Given** the user is actively solving a puzzle
**When** the user makes any move (draws a cell, undoes, uses a hint)
**Then** the complete puzzle state (current path, hints used, undos used, elapsed time) is saved to Hive local storage within 5ms using non-blocking I/O
**And** the save operation does not cause frame drops or visible stuttering during path drawing

**Given** the user is actively solving a puzzle and the timer is running
**When** the app is moved to the background (home button, app switcher, incoming call)
**Then** the solve timer pauses at the exact moment the app leaves the foreground
**And** the paused elapsed time is persisted to Hive so it survives process death

**Given** the app was previously backgrounded with a puzzle in progress
**When** the user returns to the app (foreground event)
**Then** the solve timer resumes from the exact paused time without adding the backgrounded duration
**And** the puzzle grid displays the same state as when the user left

**Given** the app was killed (process death, crash, or device restart) while a puzzle was in progress
**When** the user launches the app again
**Then** the system detects the saved puzzle state in Hive and offers to resume: "You have a puzzle in progress. Continue where you left off?"
**And** upon accepting, the full puzzle state is restored — path, hints used, undos used, and elapsed time

**Covers:** FR69, FR70

---

### Story 2.8: First-Time Affordances & Tap-to-Select Mode

As a new player,
I want guidance on how to start solving, and as any player, I want an alternative tap-based input mode,
So that I learn the game naturally and can choose the input method that works best for me.

**Acceptance Criteria:**

**Given** the user has never played a puzzle before (first play ever)
**When** the puzzle screen is displayed for the first time
**Then** waypoint 1 displays a pulsing animation (scale oscillation) to draw the user's attention as the starting point
**And** a tooltip reading "Drag to draw your path" is displayed near waypoint 1

**Given** the first-time affordances are displayed
**When** the user performs their first drag gesture on the puzzle grid
**Then** both the pulsing indicator and the tooltip auto-dismiss and do not appear again on subsequent puzzle sessions
**And** the "first play completed" flag is persisted in user preferences (SharedPreferences)

**Given** the user navigates to puzzle screen settings or accessibility settings
**When** the user toggles "Tap-to-Select Mode" on
**Then** the path drawing input changes from drag-based to tap-based: the user taps individual adjacent cells one at a time to build the path
**And** each tap validates adjacency and wall barriers identically to the drag-based input mode

**Given** tap-to-select mode is enabled
**When** the user taps a cell that is not adjacent to the current path endpoint
**Then** the tap is ignored and no feedback is given (or a subtle shake animation indicates the invalid move)
**And** the user can switch back to drag mode at any time via the same toggle

**Given** tap-to-select mode preference has been set
**When** the user returns to the app on a subsequent session
**Then** the tap-to-select preference is preserved and the puzzle defaults to the previously selected input mode

**Covers:** FR94, FR113

---

## Epic 3: Daily Challenge, Streaks & Statistics — Stories

### Story 3.1: Daily Puzzle Delivery & Difficulty Scaling

As a player,
I want to receive a fresh puzzle every day with increasing difficulty through the week,
So that I have a daily challenge that keeps me engaged with appropriate difficulty progression.

**Acceptance Criteria:**

**Given** it is a new UTC day and the user opens the app
**When** the home screen loads
**Then** the system fetches the puzzle for the current UTC date from the Supabase puzzles table and displays the puzzle card with grid size and difficulty label
**And** the puzzle data includes grid_width, grid_height, waypoints (JSONB), and walls (JSONB) but excludes solution_path

**Given** the puzzles table has been created
**When** queried for a specific date
**Then** the table schema includes: id (UUID PK), puzzle_date (DATE, UNIQUE), grid_width (integer), grid_height (integer), day_of_week (integer 0-6), difficulty (text), waypoints (JSONB), walls (JSONB), solution_path (JSONB), created_at (timestamptz)
**And** an index exists on puzzles(puzzle_date) for O(log n) date lookups

**Given** the day of the week determines puzzle difficulty
**When** puzzles are generated or displayed
**Then** Monday delivers a 5x5 (easy) grid, Tuesday a 5x5 or 6x6 (easy-medium), Wednesday a 6x6 (medium), Thursday a 6x6 or 7x7 (medium), Friday a 7x7 (medium-hard), Saturday a 7x7 or 8x8 (hard), and Sunday an 8x8 (hard) grid

**Given** the daily puzzle card is displayed on the home screen
**When** the user has not yet solved today's puzzle
**Then** the card shows the grid size (e.g., "6x6"), difficulty label (e.g., "Medium"), day name, and a prominent "Play" button
**And** if the user has already solved today's puzzle, the card shows "Solved" with their solve time and the "Play" button is replaced with "View Solution"

**Given** it is 11:59 PM UTC and the user is viewing the home screen
**When** midnight UTC arrives
**Then** the daily puzzle rolls over to the next day's puzzle and the home screen updates to reflect the new puzzle (either via app restart detection or periodic check)

**Covers:** FR12, FR13, FR76

---

### Story 3.2: Server-Side Puzzle Pre-Generation

As the system,
I want to pre-generate puzzles 30 days in advance via a scheduled server function,
So that a fresh, valid puzzle is always available for every day without manual intervention.

**Acceptance Criteria:**

**Given** the daily-puzzle Edge Function is deployed on Supabase
**When** the cron schedule triggers the function (once daily)
**Then** the function checks for any missing puzzles within the next 30 days from the current UTC date and generates them
**And** each generated puzzle uses the Backbite algorithm for Hamiltonian path generation on the grid size corresponding to that day of the week

**Given** the puzzle generation algorithm runs for a specific date
**When** a puzzle is generated
**Then** the puzzle is stored in the puzzles table with all fields populated: puzzle_date, grid_width, grid_height, day_of_week, difficulty, waypoints, walls, and solution_path
**And** the solution_path is stored server-side only and is never included in any client-facing API response

**Given** the Edge Function runs and all puzzles for the next 30 days already exist
**When** no gaps are found in the puzzle schedule
**Then** the function completes successfully without generating duplicate puzzles and logs "All puzzles up to date"

**Given** the puzzle generation function encounters an error (database failure, algorithm timeout)
**When** the generation fails
**Then** the function retries up to 3 times with exponential backoff before triggering an alert
**And** the /health endpoint for the daily-puzzle function returns 200 OK under normal operation

**Given** the batch generation runs
**When** 30 days of puzzles are generated in a single execution
**Then** the entire batch completes in under 60 seconds as per NFR15

**Covers:** FR15

---

### Story 3.3: Client-Side Puzzle Pre-Caching

As a player,
I want tomorrow's puzzle to be ready on my device before I need it,
So that I can start solving instantly even with a slow or unavailable network connection.

**Acceptance Criteria:**

**Given** the user has the app installed and has solved or viewed today's puzzle
**When** a background fetch is triggered (approximately 24 hours before the next puzzle's release date)
**Then** the next day's puzzle data (grid dimensions, waypoints, walls — excluding solution_path) is fetched from Supabase and stored in Hive local cache

**Given** the puzzle has been pre-cached in Hive
**When** the new UTC day begins and the user opens the app
**Then** the puzzle loads from the local cache in under 200ms (per NFR3) without requiring a network request
**And** the cached puzzle data matches what the server would return for that date

**Given** the background fetch fails (no network, server error)
**When** the next day arrives and no cached puzzle is available
**Then** the system performs an on-demand fetch from Supabase when the user opens the app
**And** the user sees a brief loading indicator while the puzzle is fetched over the network

**Given** the puzzle cache contains data for a previous day
**When** the current UTC date is beyond the cached puzzle's date
**Then** the stale cache entry is replaced with the current day's puzzle on the next successful fetch

**Covers:** FR16

---

### Story 3.4: Score Submission & Server Validation

As a player,
I want my solve to be verified by the server and recorded,
So that my results are trustworthy and count toward leaderboards and statistics.

**Acceptance Criteria:**

**Given** the user completes a puzzle on the client
**When** the client submits the solve to the submit-score Edge Function
**Then** the request includes: user_id, puzzle_id, puzzle_date, path (ordered list of cell coordinates), solve_time_ms, hints_used, and undos_used
**And** the Edge Function re-validates the submitted path against the stored solution_path to confirm it is a valid Hamiltonian path that respects waypoint order and wall barriers

**Given** the submit-score Edge Function receives a valid submission
**When** the path passes server-side validation and the solve time is at least 3 seconds (per NFR11)
**Then** the result is recorded in the puzzle_attempts table with verified set to true
**And** the puzzle_attempts table schema includes: id (UUID PK), user_id (UUID FK), puzzle_id (UUID FK), puzzle_date (DATE), solve_time_ms (integer), hints_used (integer), undos_used (integer), completed (boolean), verified (boolean), created_at (timestamptz), with a UNIQUE constraint on (user_id, puzzle_date)

**Given** the submit-score Edge Function receives a submission with solve_time_ms less than 3 seconds
**When** the timing check fails
**Then** the submission is rejected with an appropriate error code and the result is not recorded
**And** the client displays an error message to the user

**Given** a user has already submitted a verified solve for today's puzzle
**When** the user attempts to submit another solve for the same puzzle_date
**Then** the submission is rejected due to the UNIQUE(user_id, puzzle_date) constraint and the client displays the previously recorded result

**Given** multiple users are submitting scores simultaneously
**When** the submit-score Edge Function receives requests
**Then** rate limiting of 10 submissions per hour per user is enforced (per NFR10) and excess submissions receive a 429 Too Many Requests response

**Given** the puzzle_attempts table is created
**When** indexes are applied
**Then** indexes exist on puzzle_attempts(puzzle_date) and puzzle_attempts(user_id) for efficient querying

**Covers:** FR14, FR8

---

### Story 3.5: Streak Tracking & Freeze System

As a player,
I want my consecutive-day solving streak to be tracked and protected by streak freezes,
So that I am motivated to play daily and do not lose my streak from a single missed day.

**Acceptance Criteria:**

**Given** the streaks table has been created
**When** the schema is defined
**Then** the table includes: user_id (UUID PK, FK to profiles), current_streak (integer, default 0), longest_streak (integer, default 0), last_solve_date (DATE, nullable), streak_freezes_remaining (integer, default 1), updated_at (timestamptz)
**And** a streaks row is created for each user upon their first puzzle completion

**Given** the user solves today's puzzle and their last_solve_date is yesterday
**When** the score is submitted and verified
**Then** current_streak is incremented by 1, last_solve_date is updated to today's UTC date
**And** if the new current_streak exceeds longest_streak, longest_streak is updated to match

**Given** the user did not solve yesterday's puzzle and has streak_freezes_remaining > 0
**When** midnight UTC streak evaluation runs (or on next app open/solve)
**Then** the streak freeze is automatically applied: current_streak is preserved, streak_freezes_remaining is decremented by 1, and the user is informed "Streak freeze used! Your streak is safe."

**Given** the user did not solve yesterday's puzzle and has streak_freezes_remaining = 0
**When** midnight UTC streak evaluation runs
**Then** current_streak is reset to 0 and the user is informed "Your streak has ended" on their next app open

**Given** a new week begins (Monday 00:00 UTC)
**When** the weekly reset occurs
**Then** streak_freezes_remaining is reset to 1 for all users (1 freeze per week)

**Covers:** FR28, FR29, FR31, FR32, FR78

---

### Story 3.6: Statistics Screen

As a player,
I want to view my performance history and statistics,
So that I can track my improvement and celebrate my achievements.

**Acceptance Criteria:**

**Given** the user navigates to the Stats tab
**When** the statistics screen is displayed
**Then** the following metrics are shown: total puzzles solved (count of verified completions), average solve time (mean of all solve_time_ms values, formatted as "M:SS.s"), current streak, and longest-ever streak
**And** data is pulled from the puzzle_attempts table (aggregated) and the streaks table

**Given** the user has solved multiple puzzles
**When** the statistics screen is displayed
**Then** a solve time distribution chart (histogram or bar chart) is displayed showing the distribution of solve times across completed puzzles
**And** the chart groups solve times into meaningful buckets (e.g., <30s, 30-60s, 1-2min, 2-5min, 5min+)

**Given** the user has a solve history spanning multiple weeks
**When** the statistics screen is displayed
**Then** a streak calendar heatmap is displayed showing each day of the past 12 weeks, with solved days highlighted, frozen days marked distinctly, and missed days shown as empty
**And** the heatmap uses the same coral-orange color palette for consistency with the puzzle theme

**Given** the user has used hints across multiple puzzles
**When** the statistics screen is displayed
**Then** hint usage statistics are displayed: total hints used, average hints per puzzle, and percentage of puzzles solved without hints

**Given** the user has no puzzle history (new user or anonymous with no solves)
**When** the statistics screen is displayed
**Then** an empty state is shown with an illustration and the message "No stats yet — solve your first puzzle to see your progress!" with a CTA button "Play Today's Puzzle"

**Covers:** FR30, FR33

---

### Story 3.7: Home Screen Hub

As a player,
I want the home screen to show my daily puzzle status, streak, and group activity,
So that I have a central dashboard for my daily engagement.

**Acceptance Criteria:**

**Given** the user navigates to the Home tab
**When** the home screen is displayed
**Then** a DailyPuzzleCard is prominently displayed showing: grid size (e.g., "7x7"), difficulty label (e.g., "Medium-Hard"), and a "Play" button if unsolved or "Solved" indicator with solve time if already completed

**Given** the user has an active streak
**When** the home screen is displayed
**Then** a StreakCounter widget displays a fire icon with the current streak count (e.g., fire icon + "12")
**And** if the streak is at risk (no solve today and past 6 PM local time), the streak counter shows an "at-risk" visual state (pulsing or warning color)
**And** if a streak freeze was applied, the counter shows a "frozen" visual state (snowflake or blue tint)

**Given** the user is a member of one or more groups
**When** the home screen is displayed
**Then** a group activity summary section shows how many group members have solved today's puzzle (e.g., "3/8 members solved") for each group the user belongs to

**Given** the weekly leaderboard boundary information is relevant
**When** the home screen is displayed
**Then** the current week boundary is displayed or implied (Mon-Sun UTC) so the user understands when weekly rankings reset

**Given** the user is not a member of any groups and has no streak
**When** the home screen is displayed
**Then** the DailyPuzzleCard is still displayed, the streak counter shows "0" or a "Start your streak!" message, and the group activity section shows a CTA to "Create or Join a Group"

**Covers:** FR60, FR77

---

### Story 3.8: Welcome Back Experience

As a returning player who has been away for a while,
I want the app to acknowledge my return and encourage me to start fresh,
So that I feel welcomed rather than discouraged by a lost streak.

**Acceptance Criteria:**

**Given** the user has not opened the app or solved a puzzle for 7 or more consecutive days
**When** the user launches the app
**Then** a "Welcome Back" card is displayed prominently on the home screen above the daily puzzle card
**And** the card includes the user's last streak count (e.g., "Your last streak was 15 days!") and an encouraging message (e.g., "Ready to start a new streak?")

**Given** the welcome back card is displayed
**When** the user taps "Start Fresh" or dismisses the card
**Then** the card is dismissed and does not reappear during this session
**And** the home screen returns to its normal layout with the daily puzzle card and streak counter showing the current state (0 streak)

**Given** the user's last streak was 0 and they have been inactive for 7+ days
**When** the welcome back card is shown
**Then** the messaging focuses on re-engagement rather than streak recovery (e.g., "Welcome back! A new puzzle is waiting for you." without referencing a 0-day streak)

**Given** the user returns after exactly 6 days of inactivity
**When** the user launches the app
**Then** no welcome back card is shown (threshold is 7+ days) and the home screen loads normally

**Covers:** FR97

---

## Epic 4: Groups & Leaderboards — Stories

### Story 4.1: Group Creation & Invite Code Generation

As a player,
I want to create a group and get an invite code to share with friends,
So that we can compete together on daily puzzles.

**Acceptance Criteria:**

**Given** the user is authenticated (not anonymous) and navigates to the Groups tab
**When** the user taps "Create Group"
**Then** a group creation form is displayed with fields for: group name (required, max 30 characters with visible counter) and description (optional, max 200 characters)

**Given** the user fills in a valid group name and taps "Create"
**When** the group is created successfully
**Then** a new row is inserted into the groups table with schema: id (UUID PK), name (text, max 30), description (text, nullable), invite_code (text, UNIQUE, 6 characters alphanumeric), created_by (UUID FK to profiles), max_members (integer, DEFAULT 50), created_at (timestamptz)
**And** the creating user is added to the group_members table with role set to 'admin' (schema: group_id UUID + user_id UUID composite PK, role text 'admin'|'member', joined_at timestamptz)
**And** the unique 6-character alphanumeric invite code is generated and displayed to the user in a shareable format

**Given** the user has already created 5 groups today
**When** the user attempts to create another group
**Then** the creation is rejected with the message "You can create up to 5 groups per day. Try again tomorrow." (rate limit per FR82)

**Given** the invite code is generated
**When** the group detail screen is displayed
**Then** the invite code is shown prominently with a "Copy" button and options to share via other methods (deep link, QR — implemented in later stories)

**Given** the user enters a group name that is empty or exceeds 30 characters
**When** the user attempts to submit the form
**Then** the form shows inline validation errors: "Group name is required" or "Group name must be 30 characters or fewer"

**Covers:** FR34, FR35, FR82

---

### Story 4.2: Group Joining (Code, Deep Link, QR Scan)

As a player,
I want to join a group by entering an invite code, opening a deep link, or scanning a QR code,
So that I can easily connect with friends and start competing.

**Acceptance Criteria:**

**Given** the user is authenticated and navigates to the Groups tab
**When** the user taps "Join Group" and selects "Enter Code"
**Then** an input field is displayed that auto-uppercases all typed characters, enforces a 6-character limit, and shows a character count indicator (e.g., "4/6")
**And** upon entering a valid 6-character code and tapping "Join", the join-group Edge Function is called to validate and process the join

**Given** the user opens a deep link in the format /join/{invite_code}
**When** the app processes the deep link via GoRouter
**Then** the app navigates directly to the group join confirmation screen showing the group name and member count, with a "Join Group" button
**And** if the app is not installed, the deep link redirects to the appropriate app store

**Given** the user selects "Scan QR Code" from the join group options
**When** the camera permission is granted and a valid QR code containing a Icos invite link is scanned
**Then** the invite code is extracted from the QR code and the join flow proceeds identically to the deep link flow

**Given** a valid invite code is submitted to the join-group Edge Function
**When** the validation checks pass (code exists, group has fewer than 50 members, user is not already a member)
**Then** the user is added to the group_members table with role 'member' and the group detail screen is displayed with a success message "You've joined {group_name}!"

**Given** the invite code validation fails
**When** any of the following conditions are true
**Then** specific error messages are displayed: "Code not found" (invalid code), "Code expired" (code was regenerated), "Group is full" (50 members reached), "Already a member" (user is already in the group, redirects to group detail)

**Given** the user attempts to join a group while authenticated anonymously
**When** the join attempt is initiated
**Then** the account creation prompt from Story 1.5 is shown before proceeding with the join flow

**Covers:** FR36, FR37, FR100, FR124

---

### Story 4.3: Daily Group Leaderboard

As a group member,
I want to see how everyone did on today's puzzle,
So that I can compete with friends and see where I rank.

**Acceptance Criteria:**

**Given** the user is a member of a group and has navigated to the group detail screen
**When** the "Daily" leaderboard tab is selected (default)
**Then** a ranked list of group members who have solved today's puzzle is displayed, sorted by: hints_used ASC (fewer hints = better), then solve_time_ms ASC (faster = better), then undos_used ASC (fewer undos = better)
**And** each entry shows: rank position, display name, avatar, solve time, hints used, and undos used

**Given** the viewer has solved today's puzzle
**When** the daily leaderboard is displayed
**Then** members who have NOT solved today's puzzle are shown at the bottom of the list with the label "Hasn't solved yet" and no solve details revealed
**And** the viewer's own entry is visually highlighted in the ranked list

**Given** the viewer has NOT solved today's puzzle
**When** the daily leaderboard is displayed
**Then** members who have solved are shown with the label "Solved" but their solve time, hints, and undos are hidden to prevent spoilers
**And** the viewer sees a prompt "Solve today's puzzle to see full results"

**Given** the leaderboard data was fetched from the server
**When** the data is displayed
**Then** a data staleness indicator is shown: "Updated just now", "Updated N min ago", or "Offline — showing cached data" depending on the last successful fetch time

**Given** the user is viewing the daily leaderboard
**When** another group member submits a solve
**Then** the leaderboard updates in real-time via Supabase Realtime subscription on the puzzle_attempts table (scoped to the group's members)
**And** the database RPC function get_group_daily_leaderboard is used for the ranked query

**Covers:** FR38, FR44, FR106

---

### Story 4.4: Weekly Group Leaderboard

As a group member,
I want to see weekly standings for my group,
So that I can track consistent performance over the week.

**Acceptance Criteria:**

**Given** the user is viewing a group detail screen
**When** the user selects the "Weekly" leaderboard tab
**Then** a ranked list of group members is displayed for the current week (Monday 00:00 UTC through Sunday 23:59:59 UTC), sorted by: puzzles_completed DESC (more solves = better), then avg_solve_time ASC (faster average = better)
**And** each entry shows: rank position, display name, avatar, puzzles completed (e.g., "5/7"), and average solve time

**Given** the weekly leaderboard is displayed
**When** the current week boundary is active
**Then** the header shows the date range (e.g., "Mar 2 - Mar 8, 2026") and the database RPC function get_group_weekly_leaderboard is used for the ranked query

**Given** a group member has not solved any puzzles this week
**When** the weekly leaderboard is displayed
**Then** the member appears at the bottom of the list with "0 puzzles solved" and no average time displayed

**Given** it is Monday 00:00 UTC (start of a new week)
**When** the weekly leaderboard resets
**Then** all members start with 0 puzzles completed and the previous week's standings are no longer displayed (or are accessible via a "Previous Week" option if designed)

**Covers:** FR39

---

### Story 4.5: Group Admin Controls

As a group admin,
I want to manage my group by removing members, refreshing the invite code, and deleting the group,
So that I can maintain a safe and well-managed group environment.

**Acceptance Criteria:**

**Given** the user is an admin of a group and views the group member list
**When** the admin taps on a member (non-admin) and selects "Remove Member"
**Then** a confirmation dialog appears: "Remove {member_name} from {group_name}? They will need a new invite to rejoin."
**And** upon confirmation, the member is removed from the group_members table and the member list updates immediately

**Given** the user is an admin and navigates to group settings
**When** the admin taps "Regenerate Invite Code"
**Then** a confirmation dialog appears: "Generate a new invite code? The current code will stop working immediately."
**And** upon confirmation, a new unique 6-character alphanumeric code is generated, the old code is invalidated (any pending joins with the old code will receive "Code expired" error), and the new code is displayed

**Given** the user is an admin and navigates to group settings
**When** the admin taps "Delete Group"
**Then** a confirmation dialog appears with a destructive action style: "Delete {group_name}? This action cannot be undone. All members will be removed and all group data will be permanently deleted."
**And** upon confirmation, the group is deleted from the groups table (cascade deletes group_members), all members are removed, and the admin is navigated back to the Groups tab

**Given** a non-admin member is viewing the group
**When** the member looks at group settings or member options
**Then** the "Remove Member", "Regenerate Invite Code", and "Delete Group" options are not visible or accessible

**Covers:** FR40, FR41, FR43

---

### Story 4.6: Group Membership Management

As a group member,
I want to leave a group when I choose, and as the system, I want admin succession to be handled automatically,
So that groups remain functional even when members or admins depart.

**Acceptance Criteria:**

**Given** the user is a member (non-admin) of a group
**When** the user navigates to group settings and taps "Leave Group"
**Then** a confirmation dialog appears: "Leave {group_name}? You'll need a new invite code to rejoin."
**And** upon confirmation, the user's row is removed from group_members and the user is navigated to the Groups tab with the group no longer listed

**Given** the user is the admin of a group and deletes their account (via Story 1.6)
**When** the account deletion is processed
**Then** the admin role is automatically transferred to the longest-tenured member in the group (the member with the earliest joined_at timestamp)
**And** the new admin is the member who has been in the group the longest, and the group continues to function normally

**Given** the admin is the only member of the group and deletes their account
**When** the account deletion is processed
**Then** the group is automatically deleted since no members remain
**And** the group is removed from the groups table along with all associated group_members records

**Given** the user is an admin of a group
**When** the admin taps "Leave Group" in group settings
**Then** a confirmation dialog appears: "Leave {group_name}? As the admin, your role will transfer to the longest-tenured member."
**And** upon confirmation, the admin role transfers to the longest-tenured remaining member and the departing admin's row is removed from group_members

**Covers:** FR42, FR84

## Epic 5: Sharing & Viral Growth

Users can generate spoiler-free share cards showing grid size, solve time, day identifier, and abstract path visualization. They can share via native OS share sheet, copy results to clipboard as text, and share group invites via deep links, invite codes, or QR code images. Deep links open the app directly to the group join flow or redirect to the app store if not installed. The system handles deep link failures gracefully with informative error screens.

**FRs covered:** FR45, FR46, FR47, FR48, FR61, FR101
**Key NFRs:** NFR38 (share card generation timeout 30s)
**Dependencies:** Epic 2 (puzzle completion), Epic 4 (groups, invite codes)

---

### Story 5.1: Spoiler-Free Share Card Generation

As a player who has completed today's puzzle,
I want to generate a visually appealing share card that does not reveal the solution,
So that I can show off my result without spoiling the puzzle for others.

**Covers:** FR45

**Acceptance Criteria:**

**Given** a player has completed today's puzzle and is on the result screen
**When** the system generates the share card
**Then** the card renders at 280x380px with a dark background containing the Icos logo, day identifier (e.g., "Day 42"), grid size (e.g., "6x6"), solve time, and a "Can you beat my time?" call-to-action
**And** the card includes an abstract path visualization (e.g., a stylized grid outline with a colored trail that does NOT match the actual solution path) so the puzzle is not spoiled

**Given** the share card is being generated
**When** the rendering pipeline executes
**Then** the card is rendered using Flutter's RepaintBoundary widget captured via the `toImage()` method and converted to PNG bytes suitable for sharing

**Given** a player has already generated a share card for today's puzzle in this session
**When** the player navigates back to the result screen or taps share again
**Then** the previously generated card image is returned from an in-memory cache rather than re-rendered, avoiding redundant GPU work

**Given** the share card generation is in progress
**When** the rendering takes longer than expected
**Then** a loading indicator is displayed on the share button and the generation times out after 30 seconds (NFR38) with an error message "Unable to generate share card. Please try again."

**Given** the abstract path visualization is rendered
**When** a user who has not solved the puzzle views the shared card
**Then** the visualization does not reveal the solution path — it uses a decorative/abstract representation (e.g., a randomized squiggle or grid-based pattern) that conveys completion without showing cell-by-cell path order

---

### Story 5.2: Share & Copy Actions

As a player who has completed today's puzzle,
I want to share my result via the native share sheet or copy it to my clipboard,
So that I can easily post my result on social media or send it to friends.

**Covers:** FR46, FR47

**Acceptance Criteria:**

**Given** a player is on the result screen after completing a puzzle and a share card has been generated
**When** the player taps the "Share" button
**Then** the native OS share sheet (via `share_plus` package) opens with the generated share card image attached and a pre-composed text message including the day identifier and solve time (e.g., "Icos Day 42 - 6x6 in 1:23.4 - Can you beat my time?")

**Given** a player is on the result screen after completing a puzzle
**When** the player taps the "Copy" button
**Then** the result is copied to the system clipboard as formatted text (e.g., "Icos Day 42 (6x6)\nTime: 1:23.4\nHints: 0\nhttps://icos.sarathfrancis.work") without any image data

**Given** the player taps the "Copy" button
**When** the text is successfully copied to the clipboard
**Then** a success SnackBar appears for 3 seconds with the message "Result copied to clipboard!" and the SnackBar auto-dismisses

**Given** the native share sheet is opened
**When** the user cancels the share action or completes it
**Then** the app returns to the result screen without any state changes or errors

**Given** share card generation fails (e.g., out of memory on low-end device)
**When** the player taps the "Share" button
**Then** the share sheet opens with the text-only result (no image) as a graceful fallback, and no error is shown to the user

---

### Story 5.3: Group Invite Sharing & Deep Links

As a group admin or member,
I want to share my group's invite via deep link, text code, or QR code,
So that I can easily invite friends to join my group regardless of how they prefer to receive invitations.

**Covers:** FR48, FR61, FR101

**Acceptance Criteria:**

**Given** a player is viewing a group they belong to on the group detail screen
**When** the player taps the "Invite" button
**Then** a bottom sheet appears with three sharing options: (1) "Share Link" — shares a deep link `https://icos.sarathfrancis.work/join/{invite_code}`, (2) "Copy Code" — copies the 6-character invite code as text, and (3) "Share QR Code" — shares a generated QR code image encoding the deep link URL

**Given** a user who has Icos installed taps a deep link (`https://icos.sarathfrancis.work/join/{invite_code}`)
**When** the app opens or is brought to foreground
**Then** GoRouter navigates directly to the group join confirmation screen showing the group name, member count, and a "Join Group" button, pre-filled with the invite code from the URL

**Given** a user who does NOT have Icos installed taps a deep link
**When** the link is opened in a mobile browser
**Then** the user is redirected to the appropriate app store (App Store on iOS, Play Store on Android) to install Icos

**Given** a user taps a deep link for a group that has been deleted
**When** the app attempts to resolve the invite code
**Then** an error screen is displayed with the message "This group no longer exists" and a "Go to Home" navigation button

**Given** a user taps a deep link with a malformed URL (e.g., missing invite code, invalid path)
**When** the app attempts to parse the deep link
**Then** an error screen is displayed with the message "Invalid link" and a "Go to Home" navigation button

**Given** a user taps a deep link with an expired invite code (admin regenerated a new code)
**When** the app resolves the invite code against the server
**Then** an error screen is displayed with the message "This invite link has expired. Ask the group admin for a new one." and a "Go to Home" navigation button

---

## Epic 6: Offline Play & Multi-Device Sync

Users can play offline with pre-cached puzzles (background fetch 12h+ before release) and 7 bundled fallback puzzles for first-launch offline scenarios. Puzzle results queue locally when offline and sync automatically on reconnection. The system enforces one puzzle attempt per day across all devices (first verified solve wins), maintains consistent state across concurrent sessions (streaks, stats, groups), provides score submission failure recovery with local preservation and retry, and suppresses the offline banner during active puzzle play to preserve flow state.

**FRs covered:** FR49, FR50, FR51, FR52, FR53, FR85, FR86, FR98, FR107
**Key NFRs:** NFR20 (zero data loss sync), NFR22 (95% cache refresh), NFR37 (exponential backoff), NFR39 (sync queue retry), NFR42 (cache migration), NFR45 (cache size limit 50MB)
**Dependencies:** Epic 2 (puzzle engine), Epic 3 (daily system, streaks)

---

### Story 6.1: Offline Puzzle Caching & Fallback Puzzles

As a player,
I want tomorrow's puzzle to be pre-cached on my device and fallback puzzles available at first launch,
So that I can always play even if I have no internet connection.

**Covers:** FR49, FR52

**Acceptance Criteria:**

**Given** the app is running and has network connectivity
**When** the background fetch service runs (scheduled at least 12 hours before the next puzzle's release at midnight UTC)
**Then** tomorrow's puzzle data is fetched from the Supabase API and stored in the local Hive cache box, including grid dimensions, waypoints, walls, and metadata (but NOT the solution path, which remains server-only per NFR9)

**Given** a user installs and opens Icos for the first time with no network connectivity
**When** the app attempts to load today's puzzle
**Then** the app loads one of 7 bundled fallback puzzles from `assets/puzzles/fallback_puzzles.json`, selected based on the current day-of-week difficulty mapping (e.g., Monday = 5x5 easy), and marks it as a "practice puzzle" in the UI

**Given** the local Hive puzzle cache has grown beyond the configured LRU limit (as part of the 50MB total cache budget per NFR45)
**When** a new puzzle is cached
**Then** the least-recently-used puzzle entries are evicted to make room, preserving at minimum the current day's puzzle and tomorrow's pre-cached puzzle

**Given** the background fetch for tomorrow's puzzle fails (network error, server error)
**When** the fetch failure is detected
**Then** the system retries up to 3 times with exponential backoff (initial 1s, max 30s) and logs the failure via analytics; if all retries fail, the app will attempt to fetch the puzzle on-demand when the user opens the app the next day

**Given** the bundled fallback puzzles file exists at `assets/puzzles/fallback_puzzles.json`
**When** the app reads the fallback puzzles
**Then** the file contains exactly 7 puzzles covering grid sizes from 5x5 (easy) to 8x8 (hard) with valid waypoints, walls, and metadata conforming to the puzzle JSON schema

---

### Story 6.2: Offline Puzzle Play & UI Indicators

As a player without internet access,
I want to solve today's puzzle with all gameplay features working and see clear offline status on non-game screens,
So that I have an uninterrupted puzzle experience and understand what features are limited.

**Covers:** FR50, FR53, FR107

**Acceptance Criteria:**

**Given** the device has no network connectivity and today's puzzle is available in the local cache (or a fallback puzzle is loaded)
**When** the player opens the puzzle screen and begins playing
**Then** all core puzzle gameplay features work identically to online play: path drawing (FR2), undo by drag-back (FR3), undo/redo buttons (FR4/FR5), reset (FR6), tap-to-truncate (FR7), hint usage from local hint budget (FR17/FR18), haptic feedback (FR11), sound effects (FR126), auto-save (FR69), and timer pause on background (FR70)

**Given** the device has no network connectivity
**When** the player is on the home screen, groups screen, stats screen, or profile screen
**Then** an offline indicator banner is displayed at the top of the screen with the text "You're offline" styled as a subtle but visible bar (e.g., amber/yellow background, dark text)

**Given** the device has no network connectivity
**When** the player is actively playing a puzzle (puzzle screen is in focus and the player has started drawing a path)
**Then** the offline banner is NOT displayed, preserving the player's flow state and immersive puzzle experience

**Given** the device has no network connectivity and the player completes a puzzle
**When** the result screen is displayed
**Then** the result screen shows the solve time, hints used, and undos used, but displays "Will sync when online" in place of the percentile rank or global comparison that would normally appear
**And** the share card generation still works using locally rendered data

**Given** the device transitions from offline to online while the app is running
**When** the connectivity change is detected by the global `connectivityProvider`
**Then** the offline banner on non-game screens is removed within 2 seconds and any queued sync operations begin automatically

---

### Story 6.3: Automatic Sync & Score Recovery

As a player who solved a puzzle while offline,
I want my results to automatically sync when I reconnect and to have clear feedback if sync fails,
So that my scores and streaks are always accurately recorded.

**Covers:** FR51, FR98

**Acceptance Criteria:**

**Given** a player completes a puzzle while offline
**When** the solve result is recorded
**Then** the result (puzzle_date, solve_time_ms, hints_used, undos_used, path data, client timestamp) is added to a persistent Hive sync queue stored locally on-device, ensuring zero data loss even if the app is killed (NFR20)

**Given** the device regains network connectivity and there are items in the offline sync queue
**When** the auto-sync process triggers (on connectivity change detection)
**Then** queued results are submitted to the `submit-score` Edge Function with exponential backoff retry logic: initial delay 1 second, doubling each retry, capped at 30 seconds maximum delay, for up to 5 retry attempts per queued item

**Given** a queued score submission fails after all 5 retry attempts
**When** the max retry limit is reached
**Then** the failed item is flagged in local storage with `sync_status: 'failed'` and the result screen (if still visible or on next visit) displays "Score pending" with a manual "Retry" button the player can tap to re-attempt submission

**Given** a player is on the result screen and a score submission has failed
**When** the player taps the "Retry" button
**Then** the system immediately attempts to resubmit the score to the server, showing an inline loading spinner on the button, and updates the UI to "Score submitted!" on success or "Still unable to sync. Will retry automatically." on failure

**Given** the app is launched after being killed while offline sync items were pending
**When** the app initializes and detects network connectivity
**Then** the sync queue is loaded from Hive and pending/failed items are automatically retried with the same exponential backoff strategy, without requiring any user interaction

---

### Story 6.4: Multi-Device Enforcement & Session Sync

As a player who uses Icos on multiple devices,
I want my puzzle attempts enforced to one per day across all devices and my progress synced consistently,
So that the game is fair and my stats are always up to date regardless of which device I use.

**Covers:** FR85, FR86

**Acceptance Criteria:**

**Given** a player has already solved today's puzzle on Device A and the solve has been server-verified
**When** the player opens Icos on Device B and navigates to today's puzzle
**Then** Device B displays the "already solved" state showing the existing result (solve time, hints used, undos used) fetched from the server, rather than allowing a new attempt
**And** the puzzle grid is shown in its completed state (path filled in) as a read-only view

**Given** a player starts solving today's puzzle on Device A (but has not completed it) and then opens Icos on Device B
**When** Device B loads today's puzzle
**Then** Device B shows a fresh puzzle state (not the in-progress state from Device A), because in-progress state is local-only; the first device to submit a server-verified completion is the recorded attempt

**Given** a player completes a puzzle on one device and the server records the solve
**When** the player opens Icos on another device
**Then** the streaks data (current_streak, longest_streak, last_solve_date), total puzzles solved, average solve time, and streak_freezes_remaining are consistent with the server state, fetched via a pull-based refresh on app foreground

**Given** a player joins or leaves a group on one device
**When** the player opens Icos on another device
**Then** the group memberships are consistent — the groups list reflects the current server state, fetched on app foreground via Supabase query on the `group_members` table filtered by the user's ID

**Given** a player's profile (display_name, avatar_id) is updated on one device
**When** the player opens Icos on another device
**Then** the updated profile data is reflected within the next foreground refresh cycle, pulled from the `profiles` table via Supabase client SDK

**Given** the player is a member of one or more groups and the app is in the foreground
**When** another group member submits a solve for today's puzzle
**Then** the leaderboard updates in near real-time via Supabase Realtime subscriptions on the `puzzle_attempts` table scoped to the group's ID, without requiring a manual refresh

---

## Epic 7: Notifications & Engagement

Users receive push notifications with a thoughtful permission strategy (pre-permission screen after first solve). Notification types include daily puzzle reminders (configurable time), group activity nudges ("You're the last one!"), and streak-at-risk alerts. Users can filter notification types independently and configure per-group preferences. The Groups tab shows an in-app badge for new activity. The system prompts app store ratings at optimal moments (5th solve or 7-day streak, max once per 90 days).

**FRs covered:** FR57, FR88, FR89, FR90, FR91, FR92, FR93, FR95
**Key NFRs:** NFR38 (network timeouts)
**Dependencies:** Epic 1 (auth), Epic 3 (streaks, solve data), Epic 4 (groups)

---

### Story 7.1: Push Notification Infrastructure & Permission Flow

As a new player who just completed my first puzzle,
I want to be asked about notifications in a clear, non-intrusive way that explains the value,
So that I can make an informed decision about enabling push notifications.

**Covers:** FR88

**Acceptance Criteria:**

**Given** the app is configured with Firebase Cloud Messaging (FCM) for push notification delivery
**When** the app launches for the first time
**Then** FCM is initialized, a device token is obtained (or refreshed if expired), and the token is stored in the user's profile on the server for targeted notification delivery
**And** the OS-level notification permission dialog is NOT triggered at this point

**Given** a player completes their first puzzle ever (first_puzzle_completed event)
**When** the result screen is dismissed and the player returns to the home screen
**Then** a pre-permission screen is displayed as a modal bottom sheet explaining: "Get daily puzzle reminders and group updates" with descriptive icons for each notification type, an "Enable" button (primary style), and a "Not Now" button (tertiary/text style)

**Given** the pre-permission screen is displayed
**When** the player taps "Enable"
**Then** the OS-level notification permission dialog is triggered (iOS APNs prompt / Android notification channel permission), and upon granting, the device is subscribed to the `daily_puzzle` FCM topic
**And** the permission state (`notifications_enabled: true`, `permission_prompted: true`) is persisted in SharedPreferences

**Given** the pre-permission screen is displayed
**When** the player taps "Not Now"
**Then** the pre-permission screen is dismissed without triggering the OS permission dialog, and the state `permission_prompted: true, notifications_declined: true` is stored in SharedPreferences so the prompt is not shown again unless the user later enables notifications from Settings

**Given** the user has granted notification permission
**When** the user joins a group with ID `{group_id}`
**Then** the device is automatically subscribed to the FCM topic `group_{group_id}` for group-specific notifications

**Given** the user leaves or is removed from a group with ID `{group_id}`
**When** the membership change is processed
**Then** the device is automatically unsubscribed from the FCM topic `group_{group_id}`

---

### Story 7.2: Daily Puzzle Reminder Notification

As a player,
I want to receive a daily reminder when the new puzzle is available,
So that I do not forget to play and can maintain my streak.

**Covers:** FR89

**Acceptance Criteria:**

**Given** a player has enabled notifications and the daily puzzle reminder type is turned on (default: on)
**When** the user-configured reminder time is reached (default: 8:00 AM in the user's local timezone)
**Then** a push notification is delivered with title "Icos" and body "Today's Icos is ready -- [day_of_week] [grid_size]" (e.g., "Today's Icos is ready -- Wednesday 6x6")

**Given** a player has already solved today's puzzle before the reminder time
**When** the notification scheduling logic evaluates whether to send the reminder
**Then** the notification is NOT sent for that day, because the player has already completed the puzzle

**Given** a player taps the daily puzzle reminder notification
**When** the app opens or is brought to foreground
**Then** the app navigates directly to the puzzle screen for today's puzzle, bypassing the home screen

**Given** a player wants to change the reminder time
**When** the player navigates to Settings > Notifications and adjusts the "Daily reminder time" picker
**Then** the new time is persisted in SharedPreferences and subsequent daily reminders are scheduled at the updated time
**And** the time picker uses the device's locale format (12-hour or 24-hour)

---

### Story 7.3: Group Activity & Streak Alert Notifications

As a group member and active player,
I want to receive nudges when my group is waiting for me and alerts when my streak is at risk,
So that I stay engaged with my group and do not accidentally lose my streak.

**Covers:** FR90, FR91

**Acceptance Criteria:**

**Given** a group has M total members and N members have solved today's puzzle where N = M-1 (only one member remains unsolved)
**When** the server-side notification logic evaluates group completion status
**Then** a push notification is sent ONLY to the unsolved member(s) with title "Icos" and body "You're the last one! [N]/[M] members have solved today's puzzle" (e.g., "You're the last one! 4/5 members have solved today's puzzle")
**And** the notification payload includes a deep link to the puzzle screen

**Given** a player has an active streak of N days and has NOT solved today's puzzle
**When** the configurable streak alert time is reached (default: 6:00 PM local time)
**Then** a push notification is delivered with title "Icos" and body "Solve today to keep your [N]-day streak!" (e.g., "Solve today to keep your 12-day streak!")

**Given** a player has already solved today's puzzle before the streak alert time
**When** the streak alert notification scheduling logic runs
**Then** the streak alert notification is NOT sent, because the streak is already preserved for today

**Given** a player taps a group nudge or streak alert notification
**When** the app opens or comes to foreground
**Then** the app navigates directly to the puzzle screen via the deep link data included in the notification payload

**Given** a player belongs to multiple groups where they are the last unsolved member
**When** the group nudge logic runs
**Then** only one consolidated nudge notification is sent (not one per group), with the body referencing the group with the most members or the most recently active group

---

### Story 7.4: Notification Preferences & In-App Badges

As a player,
I want granular control over which notifications I receive and to see visual indicators for new group activity,
So that I am not overwhelmed by unwanted notifications and can quickly spot updates.

**Covers:** FR57, FR92, FR93

**Acceptance Criteria:**

**Given** a player navigates to Settings > Notifications
**When** the notification preferences screen loads
**Then** three independently toggleable notification types are displayed: "Daily puzzle reminder" (default: on), "Group activity" (default: on), and "Streak alerts" (default: on), each with a descriptive subtitle explaining what it controls
**And** below the type toggles, a list of the player's groups appears, each with an individual on/off toggle (per FR57) controlling whether group-specific notifications are received for that group (default: on)

**Given** a player toggles "Group activity" notifications to OFF
**When** the toggle is saved
**Then** the device is unsubscribed from all `group_{id}` FCM topics for the player's groups, and no group nudge notifications are delivered until re-enabled
**And** per-group toggles below are grayed out / disabled since the parent type is off

**Given** a player toggles a specific group's notification to OFF while the "Group activity" parent toggle remains ON
**When** the toggle is saved
**Then** the device is unsubscribed from only that group's `group_{id}` FCM topic, while other group notifications continue as normal

**Given** a player has not visited the Groups tab since a group member completed today's puzzle
**When** the player views the bottom navigation bar on any screen
**Then** a badge indicator (small colored dot) is displayed on the Groups tab icon, indicating new activity

**Given** a player taps on the Groups tab
**When** the Groups screen loads and displays the updated group information
**Then** the badge indicator on the Groups tab is cleared immediately and the last-visited timestamp for the Groups tab is updated in local storage

**Given** the app is in the foreground and a real-time event arrives indicating a group member solved today's puzzle
**When** the player is NOT currently viewing the Groups tab
**Then** the badge indicator appears on the Groups tab icon in the bottom navigation bar without any disruptive notification or modal

---

### Story 7.5: App Store Rating Prompt

As the product team,
I want to prompt satisfied players to rate the app at optimal engagement moments,
So that the app accumulates positive store ratings to drive organic discovery.

**Covers:** FR95

**Acceptance Criteria:**

**Given** a player has completed their 5th puzzle overall (cumulative total)
**When** the result screen is displayed after the 5th completion
**Then** the native in-app review API is triggered (StoreKit `SKStoreReviewController.requestReview()` on iOS, Play In-App Review API `ReviewManager` on Android) after a 2-second delay to let the player see their result first

**Given** a player achieves a 7-day streak milestone (current_streak reaches exactly 7 for the first time or after a reset)
**When** the streak milestone celebration is shown
**Then** the native in-app review API is triggered after the milestone animation completes

**Given** the in-app review prompt has been shown within the last 90 days
**When** another trigger condition is met (5th puzzle or 7-day streak)
**Then** the prompt is NOT shown, respecting the 90-day cooldown
**And** the `last_rating_prompt_date` stored in SharedPreferences is checked before any trigger fires

**Given** the player has already submitted a rating (tracked via a `has_rated` boolean in SharedPreferences, set to true after a successful prompt display — note: iOS/Android APIs do not confirm actual rating submission, so this flag is set after the prompt is shown, not after actual rating)
**When** another trigger condition is met
**Then** the rating prompt is never shown again for this user

---

## Epic 8: Content Moderation & Safety

Users are protected from offensive content through profanity filtering on display names and group names, input sanitization against XSS/injection/Unicode abuse, and an in-app reporting mechanism for offensive content. The system supports user-level bans enforced at auth and Edge Function layers, purges abandoned anonymous user data after 90 days of inactivity, and anonymizes leaderboard entries for deleted accounts ("Deleted User") rather than removing historical scores.

**FRs covered:** FR79, FR80, FR81, FR83, FR104, FR105
**Key NFRs:** NFR25 (input sanitization)
**Dependencies:** Epic 1 (auth, profiles), Epic 4 (groups, leaderboards)

---

### Story 8.1: Content Filtering & Input Sanitization

As a player,
I want display names and group names to be filtered for offensive content and all text input to be sanitized,
So that the community remains safe and the system is protected from malicious input.

**Covers:** FR79, FR80

**Acceptance Criteria:**

**Given** a player is setting or updating their display name (FR23, FR25)
**When** the submitted name matches any entry in the configurable profanity/offensive content word list (stored as a JSON asset bundled with the app and as a server-side configuration for Edge Function validation)
**Then** the input is rejected immediately with the error message "Name contains prohibited content" displayed as an inline validation error below the text field, and the name is NOT saved

**Given** a player is creating or updating a group name (FR34)
**When** the submitted group name matches any entry in the profanity word list
**Then** the input is rejected with the error message "Name contains prohibited content" displayed as an inline validation error, and the group name is NOT updated

**Given** a player submits a display name or group name containing HTML tags (e.g., `<script>alert('xss')</script>`) or SQL injection patterns (e.g., `'; DROP TABLE profiles;--`)
**When** the input is processed
**Then** HTML tags are stripped, SQL injection patterns are neutralized, and the sanitized text is stored; if the sanitized result is empty or invalid, the input is rejected with "Invalid name" error

**Given** a player submits a name with Unicode abuse (excessive combining marks/zalgo text like "Z&#x0361;a&#x0361;l&#x0361;g&#x0361;o", invisible characters like zero-width spaces, or emoji-only names like a single emoji with no alphanumeric text)
**When** the input is processed by the sanitization pipeline
**Then** excessive combining marks (more than 2 per base character) are stripped, invisible Unicode characters are removed, and emoji-only names are rejected with the error message "Name must contain at least one letter or number"

**Given** any user-generated text input passes client-side validation
**When** the data is submitted to the server (via Supabase client SDK or Edge Function)
**Then** the SAME profanity check and sanitization logic is applied server-side in the Edge Function (or database trigger) as a defense-in-depth measure, rejecting inputs that somehow bypass client validation with an appropriate HTTP 400 error response

**Given** the profanity word list needs to be updated (new terms added, false positives removed)
**When** an app update is deployed or the server-side configuration is refreshed
**Then** the updated word list takes effect for all future name submissions without requiring database migration or server restart; existing names that now match the updated list are NOT retroactively changed

---

### Story 8.2: In-App Reporting Mechanism

As a player who encounters offensive content or abusive behavior,
I want to report it through an in-app mechanism,
So that the platform team can review and take action to keep the community safe.

**Covers:** FR81

**Acceptance Criteria:**

**Given** a player is viewing a group member's profile (accessible from group detail > member list > tap member)
**When** the player taps the "Report" button (shown as a flag icon or "Report" text action)
**Then** a report bottom sheet is displayed with the following report type options: "Offensive display name", "Offensive group name", "Abusive behavior", and "Other", plus an optional free-text description field (max 500 characters)

**Given** a player is viewing a group detail screen
**When** the player taps the "Report" option (accessible via the overflow/more menu)
**Then** a report bottom sheet is displayed with report type options relevant to the group context: "Offensive group name", "Abusive behavior", and "Other", plus the optional description field

**Given** a player selects a report type and optionally adds a description, then taps "Submit Report"
**When** the report is submitted
**Then** a new record is inserted into the `reports` table with fields: `id` (UUID), `reporter_id` (current user's UUID), `reported_user_id` (UUID of the reported user, or null for group reports), `reported_group_id` (UUID of the group if reporting a group), `report_type` (enum: 'offensive_display_name', 'offensive_group_name', 'abusive_behavior', 'other'), `description` (text, nullable), `created_at` (timestamptz), and `status` (default: 'pending')
**And** a confirmation message is shown: "Report submitted. We'll review it within 48 hours."

**Given** a player attempts to submit a report without selecting a report type
**When** the player taps "Submit Report"
**Then** the submit button remains disabled or an inline validation error "Please select a reason" is displayed, preventing empty reports

**Given** a player has already submitted a report for the same user or group within the last 24 hours
**When** the player attempts to submit another report for the same target
**Then** the system displays "You've already reported this. We're reviewing it." and does NOT create a duplicate report record

**Given** the `reports` table is created
**When** the database migration runs
**Then** the table includes RLS policies ensuring: reporters can only insert reports (not read/update/delete), reporters cannot report themselves, and only admin/service role can read and update report status

---

### Story 8.3: User Ban System

As the platform team,
I want to ban users who violate community standards at the system level,
So that banned users cannot interact with the platform and other users are protected.

**Covers:** FR83

**Acceptance Criteria:**

**Given** a user account has been flagged for banning by the platform team
**When** an admin sets `is_banned = true` on the user's `profiles` row via the Supabase dashboard (or a future admin Edge Function)
**Then** the ban flag is persisted on the `profiles` table as a `BOOLEAN` column `is_banned` (default: `false`)

**Given** a banned user attempts to log in (email/password, Google, or Apple OAuth)
**When** the authentication succeeds at the Supabase Auth layer but the app checks the user's profile
**Then** the login is rejected with a full-screen error message: "Your account has been suspended. Contact sarathfrancis90@gmail.com for assistance." and the user is signed out immediately
**And** this check occurs via a post-auth profile fetch that reads `is_banned` from the `profiles` table before allowing navigation to the home screen

**Given** a banned user's device still has a valid session token (not yet expired)
**When** the banned user makes any API request (score submission, group join, group creation, profile update) via an Edge Function
**Then** the Edge Function checks `is_banned` on the `profiles` table for the authenticated user and returns HTTP 403 Forbidden with body `{"error": "Account suspended"}` for ALL requests from banned users

**Given** a banned user attempts to create a new anonymous account on the same device
**When** the new anonymous session is created
**Then** the new account is NOT automatically banned (bans are account-level, not device-level), because device-level bans could affect shared devices; the ban is scoped to the specific `profiles.id`

**Given** the `is_banned` column is added to the `profiles` table
**When** the database migration runs
**Then** the column is added as `is_banned BOOLEAN NOT NULL DEFAULT false` and an index `idx_profiles_banned` is created for efficient banned-user lookups in Edge Functions
**And** existing RLS policies are updated so that banned users' read access to group data and leaderboard data is revoked

---

### Story 8.4: Data Lifecycle Management

As the platform team,
I want abandoned anonymous accounts to be automatically purged and deleted accounts to be gracefully anonymized,
So that we minimize data storage costs, comply with data protection principles, and preserve historical leaderboard integrity.

**Covers:** FR104, FR105

**Acceptance Criteria:**

**Given** an anonymous user (profile where `is_anonymous = true`) has had no activity for 90 consecutive days (no puzzle solves, no app opens — determined by `last_active_at` timestamp on the `profiles` table or latest `puzzle_attempts.created_at`)
**When** the scheduled data purge Edge Function (or Supabase database cron job via `pg_cron`) runs on its daily schedule
**Then** the user's data is permanently deleted: `profiles` row, all `puzzle_attempts` rows, `streaks` row, all `group_members` rows (removing them from any groups), and the corresponding `auth.users` entry is deleted via the Supabase Admin API
**And** the purge operation is logged with the anonymized user count for audit purposes

**Given** a registered (non-anonymous) user deletes their account (FR26, 30-day grace period has elapsed)
**When** the permanent deletion process executes
**Then** the user's `profiles` row is updated: `display_name` is set to "Deleted User", `avatar_id` is set to a special "deleted_user" placeholder avatar, and `is_deleted = true` is set
**And** the user's `puzzle_attempts` rows are NOT deleted — they remain in the database so that group leaderboard historical entries are preserved

**Given** a group leaderboard is rendered and includes entries from a deleted user
**When** the leaderboard data is fetched and displayed
**Then** the deleted user's entries appear with the display name "Deleted User" and the anonymized placeholder avatar, with their historical solve times and scores intact
**And** the leaderboard rank calculation includes these entries (they are not filtered out)

**Given** the data purge cron job encounters an error (database timeout, permission error)
**When** the purge function fails
**Then** the error is logged with structured JSON including the error type, timestamp, and correlation ID, an alert is triggered per NFR32 monitoring rules, and the purge is retried on the next scheduled run without data loss or partial deletions (the purge for each user is wrapped in a database transaction)

**Given** the data purge job runs and identifies eligible anonymous users
**When** some of those users have `puzzle_attempts` records that appear on group leaderboards
**Then** those leaderboard entries are anonymized (display name set to "Deleted User", avatar set to placeholder) BEFORE the profile and auth records are deleted, preserving leaderboard integrity using the same pattern as registered account deletion
## Epic 9: Accessibility & Inclusive Design

All users can enjoy Icos regardless of ability. Screen reader support covers all non-game UI (Home, Groups, Stats, Profile, Settings) and puzzle grid cells with semantic labels. Users can enable colorblind mode (deuteranopia, protanopia, tritanopia palettes) with discoverability prompts. The app supports dynamic type up to 200% scaling without layout breakage, visible focus indicators for keyboard/switch navigation, and visual-only alternatives for audio/haptic feedback on devices without haptic motors.

**FRs covered:** FR96, FR111, FR112, FR114, FR115, FR116, FR117
**Key NFRs:** NFR16 (44dp touch targets), NFR17 (colorblind patterns), NFR18 (WCAG 2.1 AA contrast), NFR19 (reduced motion), NFR48 (screen reader verification), NFR49 (dynamic type golden tests)
**Dependencies:** Epic 1 (app shell, theme), Epic 2 (puzzle engine)

---

### Story 9.1: Screen Reader Support for Non-Game UI

As a visually impaired player,
I want all non-game screens to be fully accessible via screen reader,
So that I can navigate the app, check my stats, manage groups, and adjust settings independently.

**Covers:** FR111

**Acceptance Criteria:**

**Given** a user with VoiceOver (iOS) or TalkBack (Android) enabled
**When** they navigate the Home screen
**Then** every interactive element (daily puzzle card play button, streak counter, group activity items) has a descriptive semantic label (e.g., "Play today's puzzle, 6 by 6 grid, medium difficulty")
**And** navigation landmarks are tagged with proper heading semantics (e.g., "Today's Puzzle" as heading level 1, "Your Streak" as heading level 2)

**Given** a user with a screen reader navigating the Groups screen
**When** they swipe through the group list
**Then** each group entry announces the group name, member count, and the user's solve status for today (e.g., "Puzzle Friends, 12 members, you have not solved today")
**And** the bottom navigation tabs each have semantic labels including their selected state (e.g., "Groups tab, selected" or "Stats tab, not selected")

**Given** a user with a screen reader on the Stats screen
**When** they navigate through statistics
**Then** all stat values are announced with context (e.g., "Current streak: 14 days", "Average solve time: 2 minutes 34 seconds", "Total puzzles solved: 87")
**And** chart or visual data representations include text alternatives summarizing the data

**Given** a user with a screen reader on the Profile and Settings screens
**When** they navigate settings toggles and options
**Then** each toggle announces its label and current state (e.g., "Haptic feedback, on, double tap to toggle")
**And** theme selection announces the current selection (e.g., "Theme, dark mode selected")
**And** all buttons announce their action (e.g., "Delete account, button" or "Export my data, button")

**Given** a decorative element (background gradient, decorative divider, brand illustration) on any non-game screen
**When** the screen reader traverses the screen
**Then** the decorative element is excluded from the accessibility tree via ExcludeSemantics or equivalent, so the user does not encounter meaningless announcements

**Given** a developer running automated accessibility tests in CI
**When** the test suite executes against each non-game screen (Home, Groups, Stats, Profile, Settings)
**Then** all interactive elements have non-empty semantic labels
**And** the accessibility tree contains at least one heading landmark per screen section
**And** no interactive element is unreachable via sequential screen reader navigation

---

### Story 9.2: Screen Reader Support for Puzzle Grid

As a visually impaired player,
I want the puzzle grid to be accessible via screen reader with meaningful cell descriptions,
So that I can understand the grid layout, track my path progress, and play the puzzle using accessibility gestures.

**Covers:** FR112

**Acceptance Criteria:**

**Given** a user with VoiceOver or TalkBack enabled on the puzzle screen
**When** they navigate to a grid cell
**Then** the cell is announced with its position and state: "Row [N], Column [M], [empty / filled / waypoint [number] / wall on [direction]]" (e.g., "Row 2, Column 3, waypoint 1, reached")
**And** adjacent wall barriers are included in the cell description when present (e.g., "Row 2, Column 3, empty, wall on right")

**Given** a user navigating the grid via screen reader swipe gestures
**When** they swipe right or down through the grid
**Then** cells are traversed in a logical reading order (left-to-right, top-to-bottom)
**And** the user can navigate to any cell in the grid without being blocked by walls or path state

**Given** a puzzle with waypoints numbered 1 through N
**When** the screen reader focuses on a waypoint cell
**Then** the cell announces whether the waypoint has been reached or not (e.g., "Waypoint 3, unreached" or "Waypoint 2, reached")
**And** logically grouped elements (waypoint circle and cell background) are merged via MergeSemantics so the user hears one combined announcement per cell rather than separate announcements for sub-elements

**Given** the user draws a path through cells (via tap-to-select accessibility mode)
**When** the path state changes (cell added or removed from path)
**Then** the screen reader announces the path progress: "Path drawn through [X] of [Y] cells" as a live region update
**And** the newly filled cell announces its updated state ("Row 3, Column 2, filled")

**Given** a user with a screen reader who completes the puzzle
**When** all cells are filled and all waypoints visited in order
**Then** the celebration state is announced: "Puzzle complete! Solved in [time]. [hints] hints used."
**And** the result screen elements are fully accessible with semantic labels for solve time, hint count, share button, and return-to-home button

**Given** a developer validating screen reader support for the puzzle grid
**When** running accessibility integration tests
**Then** every cell in a 5x5, 6x6, 7x7, and 8x8 grid has a non-empty semantic label
**And** the waypoint reached/unreached state updates correctly in the accessibility tree when the path crosses a waypoint

---

### Story 9.3: Colorblind Mode & Discoverability

As a colorblind player,
I want alternative color palettes with distinguishing patterns and textures,
So that I can differentiate between path cells, waypoints, walls, and empty cells without relying solely on color.

**Covers:** FR96, FR117

**Acceptance Criteria:**

**Given** a user navigating to Settings > Accessibility
**When** they view the colorblind mode options
**Then** three alternative palettes are listed: "Deuteranopia (red-green)", "Protanopia (red-green)", and "Tritanopia (blue-yellow)"
**And** each palette option shows a small preview swatch illustrating the colors used for path, waypoint, wall, and empty cell
**And** a "None (default)" option is available and selected by default

**Given** a user selects a colorblind palette (e.g., deuteranopia)
**When** the setting is applied
**Then** the puzzle grid immediately updates to use the selected palette's colors
**And** path cells display a crosshatch pattern overlay in addition to the color change
**And** waypoint cells display a dot pattern overlay in addition to the color change
**And** wall barriers display a dashed pattern in addition to the color change
**And** the palette selection persists across app restarts via local storage

**Given** a user on first launch whose device has system-level accessibility color filters enabled (e.g., iOS color filters or Android color correction)
**When** the app detects the system accessibility setting
**Then** a one-time, non-blocking prompt appears: "It looks like you use color adjustments. Icos has colorblind-friendly modes. Would you like to try one?"
**And** the prompt offers "Go to Settings" and "Not now" options
**And** dismissing with "Not now" records that the prompt was shown, preventing it from appearing again

**Given** a user on the Settings screen who has not interacted with accessibility features
**When** they view the Settings screen
**Then** an "Accessibility" section is prominently displayed (not buried under sub-menus)
**And** the section includes colorblind mode, dynamic type information, and visual feedback alternatives

**Given** a user with a colorblind palette selected who views the share card
**When** they generate a share card after completing a puzzle
**Then** the share card uses the standard (non-colorblind) palette so that recipients see the canonical visual representation
**And** the share card does not include pattern overlays, since those are for in-app accessibility only

**Given** a developer creating golden tests for colorblind modes
**When** golden tests run for the puzzle grid
**Then** each colorblind palette (deuteranopia, protanopia, tritanopia) has golden test images capturing the grid with patterns and colors
**And** the default palette golden test does not include pattern overlays

---

### Story 9.4: Dynamic Type, Focus Indicators & Alternative Feedback

As a player with low vision, motor impairments, or hearing limitations,
I want the app to scale text, show focus indicators, and provide visual alternatives for audio/haptic cues,
So that I can read all content comfortably, navigate via external keyboard or switch control, and receive game feedback regardless of device capabilities.

**Covers:** FR114, FR115, FR116

**Acceptance Criteria:**

**Given** a user with system font scaling set to 200%
**When** they view any screen in the app (Home, Groups, Stats, Profile, Settings, Puzzle)
**Then** all text elements scale to match the 200% system setting without being truncated or clipped
**And** layouts adapt via scrolling (ScrollView wrapping), text wrapping, or reduced content density to prevent overflow
**And** no text overlaps other text or interactive elements

**Given** a developer running golden tests for dynamic type
**When** golden tests execute at 100%, 150%, and 200% scale factors
**Then** golden images are generated for all key screens (Home, Puzzle, Groups list, Stats, Profile, Settings) at each scale factor
**And** all golden images pass without layout overflow, text truncation, or element overlap
**And** interactive elements maintain minimum 44x44dp touch targets at all scale factors

**Given** a user navigating the app via an external Bluetooth keyboard or switch control device
**When** they tab through interactive elements
**Then** a visible focus ring (2dp border, high-contrast color distinct from the element background) appears around the currently focused element
**And** the focus ring is visible in both light and dark themes
**And** focus moves in a logical order matching the visual layout (top-to-bottom, left-to-right within sections)

**Given** a user on a device without a haptic motor (e.g., older iPad, certain Android tablets)
**When** a game event that normally triggers haptic feedback occurs (cell entry, waypoint reached, wall collision, puzzle completion)
**Then** a visual alternative is provided: a brief screen-edge flash (100ms, semi-transparent overlay) for error events (wall collision) and a subtle icon animation (scale bounce) for positive events (cell entry, waypoint, completion)
**And** these visual alternatives also activate when the user has disabled haptic feedback in Settings

**Given** a user who has audio/haptic feedback disabled and a game event occurs
**When** a wall collision or puzzle completion event fires
**Then** the visual alternative feedback (flash or animation) is displayed
**And** the visual feedback does not interfere with gameplay (no blocking overlays, no input delay)
**And** the visual feedback respects the system "reduce motion" accessibility setting (if reduced motion is on, use a static color highlight instead of animation)

**Given** a user adjusting system font size while the app is in the background
**When** the app returns to the foreground
**Then** the app re-renders with the updated font scale without requiring a restart
**And** any in-progress puzzle state is preserved (path, hints, timer) during the re-render

---

## Epic 10: Error Recovery & App Resilience

The app handles all failure scenarios gracefully. Force update blocks outdated clients with an app store redirect. Maintenance mode displays estimated restoration time with offline fallback. State restoration resumes the correct screen after OS process death. Clock manipulation detection rejects fraudulent submissions. OAuth/account conversion failures preserve the anonymous session with retry options. Puzzle load and generation failures show informative states with retry mechanisms. Users can export their data (GDPR portability) and the backend supports DSAR handling. Session lifecycle enforces token expiry and allows viewing active sessions.

**FRs covered:** FR66, FR67, FR68, FR73, FR74, FR75, FR87, FR99, FR102, FR103
**Key NFRs:** NFR28 (HMAC signing), NFR29 (daily backups), NFR30 (Edge Function health endpoints), NFR31 (structured logging), NFR32 (automated alerting), NFR36 (migration rollback), NFR40 (response validation)
**Dependencies:** Epic 1 (auth, app shell), Epic 2 (puzzle engine), Epic 3 (daily system, score submission), Epic 4 (groups)

---

### Story 10.1: Force Update & Maintenance Mode

As a player using an outdated or during-maintenance app,
I want clear guidance on updating or waiting for service restoration,
So that I understand why the app is unavailable and know exactly what action to take.

**Covers:** FR68, FR73

**Acceptance Criteria:**

**Given** a user launches the app with a client version below the minimum required version configured in Firebase Remote Config (or Supabase equivalent)
**When** the app completes the version check during startup
**Then** a full-screen blocking UI is displayed with: the Icos logo, a message explaining "A new version of Icos is required", a description of why the update is needed, and a prominent "Update Now" button linking to the appropriate app store (App Store on iOS, Play Store on Android)
**And** no dismiss option, back gesture, or navigation is available -- the user cannot bypass the force update screen
**And** the version check uses the semantic version comparison (major.minor.patch)

**Given** the backend returns a 503 status code on any API call or the health check endpoint (`/health`) returns a non-200 response
**When** the app detects the backend is unavailable
**Then** a branded maintenance mode screen is displayed showing: the Icos logo, "We're performing maintenance" message, an estimated restoration time if provided in the response (or "We'll be back shortly" if not), and a visual countdown or spinner indicating automatic retry
**And** the app automatically retries the health check every 30 seconds in the background
**And** when the health check succeeds, the maintenance screen dismisses automatically and the user is returned to their previous screen

**Given** a user is on the maintenance mode screen and has cached puzzle data available
**When** the maintenance screen is displayed
**Then** a "Play Offline" option is available below the maintenance message
**And** tapping "Play Offline" navigates the user to the cached puzzle with an offline indicator, allowing them to solve while waiting for service restoration
**And** solve results are queued for sync when connectivity returns (per Epic 6 offline sync)

**Given** a user with no network connectivity launches the app
**When** the version check fails due to no connectivity (not a version mismatch)
**Then** the app does NOT show the force update screen
**And** the app proceeds to load normally with cached data and offline mode
**And** the version check retries on next successful network request

**Given** a developer configuring the minimum version
**When** they update the `minimum_app_version` field in Firebase Remote Config
**Then** the new minimum version propagates to clients within the Remote Config fetch interval
**And** the configuration includes separate minimum versions for iOS and Android platforms

---

### Story 10.2: App State Restoration & Session Lifecycle

As a player whose app was terminated by the OS or whose session has expired,
I want my app to restore to where I left off or gracefully prompt re-authentication,
So that I don't lose my place or my progress due to system interruptions.

**Covers:** FR74, FR87

**Acceptance Criteria:**

**Given** a user is on the puzzle screen with an in-progress puzzle (path partially drawn, hints used, timer running)
**When** the OS kills the app process (low memory, forced termination) and the user relaunches the app
**Then** the app restores to the puzzle screen with the full puzzle state intact: current path, hints used count, undos used count, and elapsed time (from auto-saved state per FR69)
**And** the timer resumes from the saved elapsed time, not from zero
**And** the restoration happens without showing an intermediate loading screen for longer than 500ms

**Given** a user is on the result screen (puzzle just completed, viewing solve time and share options)
**When** the OS kills the app process and the user relaunches
**Then** the app restores to the result screen showing their solve time, hint count, and share options
**And** if the result has not yet been synced to the server, a "Score pending" indicator is shown with retry capability

**Given** a user is on the home screen (no active puzzle session)
**When** the OS kills the app process and the user relaunches
**Then** the app restores to the home screen
**And** navigation state is restored (the correct bottom tab is selected based on the last-viewed tab)

**Given** a user whose authentication token has expired (30 days of inactivity since last token refresh)
**When** they open the app or perform an action requiring authentication
**Then** a friendly re-authentication prompt is displayed: "Welcome back! Please sign in to continue." with options to sign in via their original method (Google, Apple, or email)
**And** the prompt does not discard any locally cached data (puzzle state, stats, settings)
**And** after successful re-authentication, the user is returned to the screen they were trying to access

**Given** a user whose refresh token has expired (90 days since issuance)
**When** they attempt to refresh their session
**Then** a full re-authentication is required with a message: "Your session has expired for security. Please sign in again."
**And** all local data tied to the account is preserved and re-associated after sign-in
**And** anonymous users whose tokens expire are silently re-created as new anonymous sessions (previous anonymous data is not recoverable unless linked)

**Given** an authenticated user navigating to Profile > Settings > Active Sessions
**When** they view the active sessions section
**Then** a list of active sessions is displayed showing: device type (iOS/Android), last active timestamp, and current session indicator
**And** the current session is clearly marked (e.g., "This device")

---

### Story 10.3: Clock Manipulation Detection

As the system operator,
I want to detect and reject solve submissions from users who have manipulated their device clock,
So that leaderboard integrity is maintained and cheating via time manipulation is prevented.

**Covers:** FR75

**Acceptance Criteria:**

**Given** a user submits a puzzle solve to the `submit-score` Edge Function
**When** the server receives the submission containing a client-submitted timestamp
**Then** the server compares the client timestamp against the server's wall-clock time
**And** if the absolute difference exceeds the configurable tolerance window (default: 5 minutes), the submission is rejected with a 422 status code and error message "Time verification failed. Please check your device clock settings."
**And** the tolerance window is configurable via environment variable or database config without requiring code deployment

**Given** a user submits a solve with a solve time less than 3 seconds (for any grid size)
**When** the server validates the solve time
**Then** the submission is rejected with a 422 status code and error message "Invalid solve time"
**And** the rejection is logged with the user ID, submitted solve time, grid size, and client timestamp for audit purposes

**Given** a user submits a solve with a solve time greater than 24 hours
**When** the server validates the solve time
**Then** the submission is rejected as a sanity check failure with a 422 status code and error message "Solve time exceeds maximum allowed duration"
**And** this prevents stale or manipulated submissions from entering the leaderboard

**Given** a user's submission is rejected due to clock manipulation detection
**When** the rejection response is received by the client
**Then** the client displays the error message to the user
**And** the rejected submission does NOT count as the user's daily attempt -- the user can correct their device clock and retry
**And** the puzzle state remains solvable (not locked into "already solved" state)

**Given** a user in a timezone with legitimate clock offset (e.g., minor device drift, NTP sync delay)
**When** they submit a solve within the tolerance window
**Then** the submission is accepted normally
**And** the server logs a warning (but does not reject) for submissions with client-server time differences between 3 and 5 minutes for monitoring purposes

**Given** a developer reviewing clock manipulation rejection logs
**When** they query the structured logs
**Then** each rejection entry includes: user_id, client_timestamp, server_timestamp, computed_difference_ms, submitted_solve_time_ms, grid_size, and rejection_reason
**And** the logs are retained for 90 days per NFR31

---

### Story 10.4: Error Recovery for Auth & Puzzle Operations

As a player experiencing authentication or puzzle loading failures,
I want the app to handle errors gracefully without losing my data,
So that I can recover from failures and continue playing without frustration.

**Covers:** FR99, FR102, FR103

**Acceptance Criteria:**

**Given** a user attempting to link their anonymous session to a Google or Apple account
**When** the OAuth sign-in or account linking operation fails (network error, OAuth provider error, account already linked to another user)
**Then** the anonymous session is fully preserved -- no data is lost (puzzle history, streaks, group memberships all intact)
**And** an error message is displayed explaining what happened: "Sign-in failed. Your progress is safe." with specific context if available (e.g., "This Google account is already linked to another Icos account")
**And** two action buttons are shown: "Try Again" (re-initiates the OAuth flow) and "Not Now" (dismisses the error and returns to the previous screen)

**Given** a user opens the app with no cached puzzle data and no network connectivity
**When** the puzzle loading attempt fails
**Then** the home screen displays an illustration with the message "No puzzle available" and a "Retry" button
**And** if bundled fallback puzzles are available (per FR52, 7 bundled puzzles), a secondary option "Play a practice puzzle" is shown below the retry button
**And** tapping "Play a practice puzzle" loads one of the bundled puzzles with a "Practice Mode" indicator (solve does not count toward stats or streaks)
**And** tapping "Retry" re-attempts the network fetch with a loading indicator

**Given** the daily puzzle cron function (`daily-puzzle` Edge Function) fails to generate tomorrow's puzzle
**When** the initial generation attempt fails
**Then** the system retries up to 3 times with exponential backoff (first retry after 1 minute, second after 4 minutes, third after 16 minutes)
**And** if all 3 retries fail, an alert is triggered to the developer via configured channel (email and/or Slack webhook) containing: failure timestamp, error details, puzzle date that failed, and retry count

**Given** all puzzle generation retries have been exhausted for tomorrow's date
**When** the alert has been sent and no manual intervention has occurred before the puzzle rollover time (midnight UTC)
**Then** the system falls back to serving the previous day's puzzle type as an emergency fallback (e.g., if Wednesday's puzzle was supposed to be 7x7 and failed, serve a new 7x7 puzzle using the generation algorithm with a different seed)
**And** the fallback puzzle is tagged as `is_fallback: true` in the database for audit tracking
**And** users are unaware of the fallback -- the experience is seamless

**Given** a user encounters a puzzle load failure after a successful daily fetch (corrupted cache or deserialization error)
**When** the cached puzzle fails to load
**Then** the app clears the corrupted cache entry and re-fetches from the server
**And** if the re-fetch also fails (no connectivity), the bundled fallback or "No puzzle available" state is shown
**And** the cache corruption event is logged to crash reporting with the error details for debugging

---

### Story 10.5: Data Export & DSAR Handling

As a player who wants control over my personal data,
I want to export all my data and know that data subject access requests are handled properly,
So that my GDPR rights to data portability and access are respected.

**Covers:** FR66, FR67

**Acceptance Criteria:**

**Given** an authenticated user navigating to Profile > Settings
**When** they tap the "Export My Data" button
**Then** a confirmation dialog appears explaining: "This will generate a file containing your profile information, solve history, streak data, and group memberships. This may take a moment."
**And** tapping "Export" initiates the data export generation
**And** a loading indicator is shown during generation with the message "Preparing your data..."

**Given** the data export has been generated successfully
**When** the export file is ready
**Then** the file is available in JSON format containing: profile information (display name, avatar, account creation date, email if applicable), complete solve history (dates, solve times, hints used, undos used, grid sizes), streak history (current streak, longest streak, streak freeze usage dates), and group memberships (group names, join dates, role)
**And** the native OS share sheet is presented, allowing the user to save to Files, send via email, AirDrop, or any other share target
**And** the export file does NOT contain authentication tokens, passwords, or internal system identifiers

**Given** an authenticated user taps "Export My Data"
**When** the export generation fails (server error, timeout, no connectivity)
**Then** an error message is shown: "We couldn't generate your data export right now. Please try again later."
**And** a "Retry" button is available
**And** the error is logged for developer investigation

**Given** an admin or compliance officer needs to fulfill a Data Subject Access Request (DSAR)
**When** they invoke the DSAR backend endpoint (Edge Function or admin API) with a user_id
**Then** the system generates a complete data package within the endpoint's execution time containing all user data: profile, solve history, streaks, group memberships, analytics events associated with the user, account activity log (creation date, linking events, deletion requests)
**And** the DSAR response is generated within the 30-day GDPR requirement window
**And** the endpoint requires admin-level authentication (service role key) and logs the DSAR request with the requesting admin's identity and timestamp

**Given** a user who has requested account deletion (in the 30-day grace period per FR26)
**When** they request a data export
**Then** the data export is still available during the grace period
**And** the export includes a field indicating "Account scheduled for deletion on [date]"
**And** after the 30-day grace period and permanent deletion, the DSAR endpoint returns a minimal response confirming the account was deleted and the deletion date

---

## Epic 11: Analytics, Feature Flags & Optimization

The system tracks all critical user actions via a defined analytics event taxonomy, measures the first-time user funnel (install to solve to account to group), tracks attribution sources (share cards, deep links, organic), supports A/B testing via Firebase Remote Config with cohort assignment and experiment tracking, and enables feature flags with default fallback values for kill switches and gradual rollouts.

**FRs covered:** FR118, FR119, FR120, FR121, FR122
**Key NFRs:** NFR30 (logging), NFR31 (structured logging), NFR32 (alerting)
**Dependencies:** Epic 1 (auth, app shell)

---

### Story 11.1: Analytics Event Taxonomy & Core Tracking

As a product owner,
I want all critical user actions tracked via a well-defined analytics event taxonomy,
So that I can understand how users interact with the app and make data-driven decisions.

**Covers:** FR118

**Acceptance Criteria:**

**Given** the analytics service is initialized on app startup
**When** the user opens the app
**Then** an `app_opened` event is fired with parameters: `timestamp`, `user_id` (anonymized hash for anonymous users, actual ID for authenticated users), `app_version`, `platform` (iOS/Android), and `session_id`
**And** a `screen_view` event is fired on every screen mount (Home, Puzzle, Groups list, Group detail, Stats, Profile, Settings) with parameter `screen_name`
**And** no analytics events are fired if the user has opted out of analytics via the privacy consent flow (FR63)

**Given** a user interacts with the puzzle system
**When** they start a puzzle, complete a puzzle, or use a hint
**Then** `puzzle_started` fires with parameters: `puzzle_date`, `grid_size`, `day_of_week`
**And** `puzzle_completed` fires with parameters: `puzzle_date`, `grid_size`, `solve_time_ms`, `hints_used`, `undos_used`, `day_of_week`
**And** `hint_used` fires with parameters: `puzzle_date`, `grid_size`, `hint_number` (1st, 2nd, or 3rd), `cells_revealed`
**And** all timing values are in milliseconds for consistency

**Given** a user interacts with social features
**When** they create a group, join a group, send an invite, tap share, or complete a share
**Then** `group_created` fires with parameter `group_id`
**And** `group_joined` fires with parameters: `group_id`, `join_method` (invite_code, deep_link, qr_code)
**And** `invite_sent` fires with parameters: `group_id`, `invite_method` (deep_link, code_text, qr_image)
**And** `share_tapped` fires with parameter `share_type` (result_card, clipboard_text, group_invite)
**And** `share_completed` fires with parameters: `share_type`, `share_target` (if available from share sheet callback)

**Given** a user performs account-related actions or reaches a streak milestone
**When** they create an account or link an anonymous session
**Then** `account_created` fires with parameters: `auth_method` (email, google, apple), `was_anonymous` (boolean)
**And** `account_linked` fires with parameters: `auth_method`, `anonymous_puzzles_solved` (count of puzzles solved before linking)
**And** `streak_milestone` fires with parameter `streak_count` at milestones: 7, 14, 30, 60, 90, 180, 365 days

**Given** a developer reviewing the analytics implementation
**When** they inspect the analytics service code
**Then** all event names and parameter keys are defined as constants in a single analytics taxonomy file (e.g., `analytics_events.dart`) to prevent typos and ensure consistency
**And** each event includes a `timestamp` parameter in ISO 8601 format
**And** user_id for anonymous users is a stable anonymized identifier (not the Supabase anonymous user ID directly) to prevent PII leakage

**Given** a user who has opted out of analytics (FR63)
**When** any trackable action occurs
**Then** no analytics events are sent to Firebase Analytics
**And** the analytics service checks consent state before every event dispatch
**And** crash reporting consent is evaluated separately from analytics consent (a user can opt out of analytics but still allow crash reporting)

---

### Story 11.2: Funnel & Attribution Tracking

As a growth analyst,
I want to track the first-time user funnel and acquisition sources,
So that I can measure conversion rates, optimize onboarding, and understand which channels drive installs.

**Covers:** FR119, FR120

**Acceptance Criteria:**

**Given** a new user installs and opens the app for the first time
**When** they progress through the first-time user journey
**Then** the following funnel events are tracked in sequence with timestamps: `app_installed` (first-ever app open, detected via absence of any local storage marker), `first_puzzle_started` (first time the user begins a puzzle), `first_puzzle_completed` (first time the user solves a puzzle), `account_created` (first time the user creates a non-anonymous account), `first_group_joined` (first time the user joins a group)
**And** each funnel event includes a `time_since_install_ms` parameter measuring elapsed time since `app_installed`
**And** funnel events fire exactly once per user lifetime (guarded by persistent local flags)

**Given** a user arrives via a deep link (group invite)
**When** the app opens from the deep link
**Then** the attribution source is recorded as `deep_link` with additional parameter `link_type` (group_invite)
**And** the `acquisition_source` field is written to the user's `profiles` table row upon account creation
**And** UTM parameters are parsed from the deep link URL if present (`utm_source`, `utm_medium`, `utm_campaign`) and stored as additional attribution metadata

**Given** a user arrives via a share card link
**When** the app opens from the share card URL
**Then** the attribution source is recorded as `share_card`
**And** the referrer's anonymized user_id is captured if included in the share link parameters (for referral tracking)

**Given** a user installs the app organically from the app store with no referral context
**When** the app opens for the first time with no deep link, no share card, and no referral data
**Then** the attribution source is recorded as `organic_app_store`
**And** if the platform provides install referrer data (Google Play Install Referrer API on Android), that data is captured and stored

**Given** the attribution source cannot be determined
**When** no referral data, deep link, or install referrer is available
**Then** the attribution source is recorded as `unknown`
**And** the system does not fabricate or guess attribution -- "unknown" is an explicitly valid value

**Given** a product analyst querying attribution data
**When** they query the `profiles` table filtered by `acquisition_source`
**Then** every user row has a non-null `acquisition_source` value (one of: `deep_link`, `share_card`, `organic_app_store`, `unknown`)
**And** users acquired via deep link include the parsed UTM parameters in a `utm_metadata` JSONB field
**And** funnel conversion rates can be calculated by joining funnel events with attribution source

---

### Story 11.3: Feature Flags & A/B Testing Infrastructure

As a product engineer,
I want feature flags and A/B testing infrastructure via Firebase Remote Config,
So that I can safely roll out features, kill broken functionality instantly, and experiment with variations to optimize the user experience.

**Covers:** FR121, FR122

**Acceptance Criteria:**

**Given** the app initializes Firebase Remote Config on startup
**When** the config values are fetched
**Then** all feature flags have hardcoded default fallback values in the app code, ensuring the app functions correctly even if Remote Config is unreachable
**And** the fetch interval is set to a minimum of 12 hours in production (to avoid quota issues) with a 24-hour stale config TTL (configs older than 24 hours trigger a background re-fetch on next app open)
**And** in debug/development builds, the fetch interval is reduced to 0 for rapid testing

**Given** a critical bug is discovered in a shipped feature (e.g., share cards are crashing)
**When** the engineering team sets the kill switch flag (e.g., `disable_share_cards: true`) in Firebase Remote Config
**Then** clients that fetch the updated config will hide or disable the affected feature
**And** the UI gracefully degrades: the share button is hidden or displays "Sharing temporarily unavailable" rather than crashing
**And** kill switch flags are checked before feature entry points, not deeply nested in the feature code, ensuring they reliably prevent access
**And** kill switch flags follow the naming convention `disable_{feature_name}` for consistency

**Given** the product team wants to run an A/B test (e.g., testing 3 hints vs. 5 hints per day)
**When** the experiment is configured in Firebase Remote Config
**Then** users are assigned to cohorts deterministically based on a hash of their `user_id` (ensuring the same user always sees the same variant across sessions and devices)
**And** the experiment parameters are served via Remote Config keys (e.g., `daily_hint_count` returning 3 or 5 based on cohort)
**And** the cohort assignment (`experiment_cohort`) is included as a parameter on all relevant analytics events (e.g., `hint_used`, `puzzle_completed`) to enable outcome analysis

**Given** a gradual rollout is configured for a new feature (e.g., `enable_new_celebration`)
**When** the rollout percentage is set (e.g., 10% of users)
**Then** the feature is enabled for the specified percentage of users, determined by user_id hash
**And** the rollout percentage can be increased (10% -> 25% -> 50% -> 100%) without reassigning users who already have the feature enabled
**And** rolling back to 0% disables the feature for all users

**Given** the app cannot reach Firebase Remote Config (no connectivity, service outage)
**When** config fetch fails
**Then** the app uses the last successfully fetched config values from local cache
**And** if no cached config exists (first launch with no connectivity), the hardcoded default values are used
**And** a warning is logged (not shown to the user) indicating config fetch failure with the error details
**And** the app retries config fetch on the next app foreground event

**Given** a developer adding a new feature flag or experiment parameter
**When** they implement the flag in code
**Then** the flag is registered in a central `remote_config_defaults.dart` file with its key name, default value, and description comment
**And** the flag is accessed through a typed provider (e.g., `featureFlagsProvider`) rather than raw string key lookups, preventing key typos
**And** the provider returns the strongly-typed value (bool for kill switches, int/String for experiment parameters) with the fallback default
