---
stepsCompleted:
  - step-01-init
  - step-02-discovery
  - step-02b-vision
  - step-02c-executive-summary
  - step-03-success
  - step-04-journeys
  - step-05-domain
  - step-06-innovation
  - step-07-project-type
  - step-08-scoping
  - step-09-functional
  - step-10-nonfunctional
  - step-11-polish
  - edit-pass-validation-fixes
inputDocuments:
  - product-brief-Zip-2026-03-02.md
  - PLAN.md
classification:
  projectType: mobile_app
  domain: gaming_entertainment
  complexity: low
  projectContext: greenfield
documentCounts:
  briefCount: 1
  researchCount: 0
  brainstormingCount: 0
  projectDocsCount: 0
workflowType: prd
---

# Product Requirements Document - Icos

**Author:** Sarathfrancis
**Date:** 2026-03-02

## Executive Summary

Icos is a cross-platform mobile puzzle game (iOS and Android) where players draw a continuous path through a grid, connecting numbered waypoints in order while filling every cell. One puzzle is released daily for all users, with difficulty scaling from Monday (easy, 5x5) to Sunday (hard, 8x8).

The product addresses a gap in the daily puzzle market: no standalone app combines a compelling Hamiltonian path mechanic with private group leaderboards, offline-first play, and spoiler-free social sharing. LinkedIn's Zip popularized the mechanic but remains locked inside the LinkedIn platform with no social competition features. Wordle and NYT Games drive daily habits but lack real-time group leaderboards. Generic puzzle apps are ad-heavy with poor social features.

Icos targets 22-45 year old professionals who already play daily puzzles (Wordle, NYT Connections, LinkedIn Zip) and want a shared competitive experience with friends and coworkers.

### What Makes This Special

1. **Group leaderboards** transform a solo puzzle into a shared daily ritual — private groups (up to 50 members) with daily and weekly rankings
2. **Offline-first architecture** — puzzles pre-cached 24 hours in advance; play on flights, commutes, or rural areas with zero connectivity; results sync automatically
3. **Zero-friction onboarding** — anonymous auth enables play within 60 seconds of download, no sign-up wall
4. **Spoiler-free sharing** — Wordle-style abstract result cards that show performance without revealing the solution path
5. **Accessibility-first design** — colorblind modes, screen reader support, reduced motion, large text
6. **Platform-independent** — standalone app on both stores, no walled garden dependency

## Project Classification

- **Project Type:** Mobile App (iOS + Android, single Flutter codebase)
- **Domain:** Gaming / Entertainment (casual puzzle)
- **Complexity:** Low (no regulatory compliance, no payment processing, no sensitive data beyond email)
- **Project Context:** Greenfield — new product built from scratch

## Success Criteria

### User Success

- Players complete their first puzzle within 90 seconds of opening the app
- Players who solve 3+ puzzles in the first week return for day 7 at a rate > 40%
- Players who join a group solve the daily puzzle at a higher rate than solo players (group motivation effect)
- Players share their results at least once per week (> 15% daily share rate)
- Players maintain 3+ day streaks at a rate > 50% of weekly active users

### Business Success

**3-Month Targets:**
- 5,000+ monthly active users
- 500+ groups created organically
- 4.5+ average App Store / Play Store rating
- < 1% crash-free session rate

**12-Month Targets:**
- 50,000+ monthly active users
- Viral coefficient > 0.5 (each user brings 0.5+ new users through invites and shares)
- DAU/MAU ratio > 0.4 (strong daily habit indicator)
- Explore optional cosmetic monetization (themes, path colors) without ads

### Technical Success

- Path drawing renders at 60 FPS minimum on mid-range devices (2022+ budget phones)
- App cold start < 2 seconds
- Daily puzzle loads < 200ms from cache, < 500ms from network
- Score submission completes < 300ms
- Offline-to-online sync achieves zero data loss
- Server-side puzzle validation prevents cheated scores

### Measurable Outcomes

| Outcome | Metric | Target | Measurement |
|---------|--------|--------|-------------|
| Daily engagement | DAU/MAU ratio | > 0.4 | Analytics |
| Viral growth | New users via invites/shares per existing user | > 0.5 | Attribution tracking |
| Social adoption | % registered users in 1+ group | > 30% | Group membership data |
| Retention (D7) | Users returning 7 days after first solve | > 40% | Cohort analysis |
| Retention (D30) | Users returning 30 days after first solve | > 25% | Cohort analysis |
| Puzzle completion | % of DAU completing daily puzzle | > 70% | Completion events |

## Product Scope

### MVP - Minimum Viable Product

Core puzzle gameplay + daily puzzle system + groups with leaderboards + offline support + social sharing.

**MVP must deliver:**
- Playable puzzle with touch-based path drawing, undo/redo, reset
- One daily puzzle for all users with Mon-Sun difficulty curve
- Hint system (3/day, reveal next 2-3 cells)
- Anonymous play with optional account creation (email, Google, Apple)
- Personal streaks and basic statistics
- Group creation/joining with invite codes and deep links
- Daily and weekly group leaderboards
- Spoiler-free result sharing
- Offline puzzle caching and automatic result sync
- Celebration animation on puzzle completion

### Growth Features (Post-MVP)

- Practice mode with unlimited randomly generated puzzles
- Achievement/badge system (streak milestones, speed records, social goals)
- Weekly challenge puzzles (larger 9x9/10x10 grids)
- Archive to replay missed daily puzzles
- Global leaderboard (top 100 daily solvers)
- Interactive onboarding tutorial
- Push notification strategy (daily puzzle reminder, group activity nudges)

### Vision (Future)

- **Ghost Race** — after both players solve, watch animated solve-path replays overlaid like racing game ghosts
- **Path Heatmap** — aggregate visualization of where all players globally struggled on each puzzle
- **Puzzle DNA** — unique abstract art generated from each solve path, shareable as profile art
- **Group Streak** — collective group streak tracking (% of members who solved today)
- **Speed Run Mode** — solve 5 consecutive puzzles with combined time tracked
- **Head-to-Head Mode** — real-time race against a group member on the same puzzle
- **Cosmetic Customization** — themes, path colors, grid styles, celebration animations (monetization path)

### MVP Strategy & Philosophy

**Approach:** Experience MVP — deliver the complete core loop (solve puzzle → see leaderboard → share result) with polish, rather than a feature-heavy but rough product.

**Rationale:** Daily puzzle games succeed on habit formation and delight. A polished core experience with smooth animations, haptic feedback, and satisfying completion moments drives retention better than more features with rough UX.

### Risk Mitigation Strategy

**Technical Risks:**
- Puzzle generation algorithm complexity → mitigated by Backbite algorithm (well-studied, efficient for Hamiltonian paths) and 30-day pre-generation buffer
- 60 FPS path drawing on low-end devices → mitigated by hardware-accelerated rendering engine (lighter than full game engine)
- Offline sync conflicts → mitigated by simple conflict resolution (server timestamp wins; one attempt per user per day eliminates most conflicts)

**Market Risks:**
- LinkedIn improves Zip with social features → mitigated by Icos's platform independence, group depth, and offline support
- Low initial adoption → mitigated by viral mechanics (share cards, group invites) and zero-friction anonymous onboarding

**Resource Risks:**
- Solo developer bottleneck → mitigated by phased approach; MVP delivers core value; features can be added incrementally
- Backend free tier limits → mitigated by aggressive client-side caching reducing API calls and bandwidth

## User Journeys

### Journey 1: Dana Discovers Icos (Primary User — Daily Puzzler)

Dana, 30, is a product designer who plays Wordle every morning with her coffee. Her coworker texts the group chat: "I solved today's Icos in 0:38! Can you beat me?" with a colorful share card.

Dana taps the link and downloads the app. It opens immediately to today's puzzle — no sign-up screen, no tutorial gate. She drags her finger across the 6x6 grid, connecting waypoints 1 through 8 in order while filling every cell. The path draws smoothly with a subtle blue glow. When she hits a waypoint, the circle pulses coral-orange with a satisfying haptic tap.

She backtracks by dragging backwards — the path erases smoothly. After 1 minute 12 seconds, she fills the last cell. Confetti bursts across the screen. "1:12" appears in large monospace text. Below: "Faster than 62% of players today."

She taps "Join Group" from the share card link, sees her coworker at #1 with 0:38, and she's #2 at 1:12. Three other coworkers haven't solved yet. She screenshots the leaderboard and sends it to the group chat: "Challenge accepted."

The next morning, a notification appears: "Today's Icos is ready — 5x5 Monday." She's hooked. Day 3, she creates an account to preserve her streak.

### Journey 2: Chris Chases the Streak (Primary User — Competitive Optimizer)

Chris, 27, is a software engineer on day 47 of his Icos streak. He opens the app at 6:15 AM before anyone else in his three groups. Today is Thursday — a 6x7 grid, medium-hard difficulty.

He studies the waypoint positions for 5 seconds, then starts drawing. No hints — he hasn't used one since day 12. He backtracks twice when he realizes a path won't reach waypoint 5 without isolating a corner. At 0:52, the grid is complete. His stats page shows: average solve time trending down, 47-day streak (longest ever), #1 rank in 2 of 3 groups this week.

He checks the weekly leaderboard — he's ahead by 14 seconds total. He navigates to his stats: solve time distribution shows he's consistently under 1 minute for 6x6 and below. He taps share and sends his result card to Twitter/X.

On Saturday, he's traveling and has no cell service. He opens the app — yesterday's puzzle was already cached. He solves it offline. When he lands and reconnects, his result syncs automatically. Streak preserved.

### Journey 3: Sam Builds the Office Group (Primary User — Social Organizer)

Sam, 35, is an engineering manager who wants a fun daily ritual for her 12-person team. She creates an account, taps "Create Group," names it "Platform Team," and gets invite code "ZP3K9M." She shares the deep link in Slack.

Within 2 hours, 8 team members have joined. By end of day, 6 have solved the puzzle. The leaderboard shows an intern at #1 with 0:29 — the channel goes wild. Sam hasn't solved yet. She gets a push notification: "You're the last one! 7/8 members have solved today." She solves it on the subway home (offline), and her result appears on the leaderboard when she surfaces.

Over the following weeks, the remaining 4 team members join. Sam creates a second group for her college friends. The daily standup now starts with "Did you see the leaderboard?"

### Journey 4: New User via Share Card (Secondary User — Casual Discoverer)

Alex, 40, sees a Icos share card on Instagram Stories from a friend. The card shows a 7x7 grid silhouette with colored blocks indicating the general path shape, time "0:55," and the text "I solved today's Icos in 0:55! Can you beat my time?"

Alex taps through to the App Store, downloads Icos (38 MB), and opens it. No account creation — the puzzle is immediately playable. Alex completes it with 2 hints in 2:30. The result screen says "Faster than 28% of players." Below: "Create an account to save your streak and join groups." Alex continues as anonymous for 3 more days, then creates an account after a group invite from a coworker.

### Journey 5: Admin Managing Group Issues (Edge Case — Group Admin)

Sam notices a group member posting offensive display names. She opens the group member list, taps the member, and selects "Remove from group." The member is removed immediately and can no longer see group data. Sam taps "Regenerate Invite Code" to prevent the removed user from rejoining with the old code. A new code "ZP8R2Q" is generated. She shares the updated link in Slack.

### Journey Requirements Summary

| Journey | Key Capabilities Revealed |
|---------|--------------------------|
| Dana (Discovery) | Anonymous play, share card rendering, group joining via link, instant puzzle access, account creation prompt |
| Chris (Streak) | Streak tracking, offline play + sync, statistics dashboard, solve time analytics, hint tracking, weekly leaderboard |
| Sam (Group Builder) | Group CRUD, invite codes/links, member management, push notifications, admin controls |
| Alex (Discoverer) | App store deep link, zero-friction onboarding, anonymous-to-account conversion, hint usage |
| Sam Admin (Edge Case) | Member removal, invite code regeneration, abuse prevention |

## Innovation & Novel Patterns

### Detected Innovation Areas

Icos's core gameplay (Hamiltonian path puzzle) is proven but the social wrapper and specific differentiating features represent genuine innovation in the casual puzzle space:

1. **Group Leaderboard Mechanic** — No daily puzzle app offers private group leaderboards with real-time ranking. This transforms a solo experience into a social competition without requiring simultaneous play.

2. **Spoiler-Free Sharing System** — Abstract path visualization that conveys performance without revealing the solution. Enables social sharing without ruining the puzzle for recipients.

3. **Ghost Race (Post-MVP)** — Animated replay of a friend's solve path overlaid on yours after both complete. Novel application of racing game ghost mechanic to puzzle games.

4. **Path Heatmap (Post-MVP)** — Aggregate crowd-sourced difficulty visualization. No puzzle game shows players where others collectively struggled.

5. **Puzzle DNA (Post-MVP)** — Generative art from solve paths. Each solve produces a unique visual fingerprint — combines puzzle completion with shareable art generation.

### Validation Approach

- MVP validates group leaderboard engagement (target: 30%+ of registered users in groups)
- Share rate validates spoiler-free sharing (target: 15%+ daily share rate)
- Post-MVP features validated via A/B testing with Firebase Remote Config
- Ghost Race validated by measuring replay engagement within groups

### Risk Mitigation

- If group adoption is low, the core solo puzzle experience still provides retention via streaks and daily habit
- If sharing adoption is low, group invites provide an alternative viral growth channel
- Post-MVP features are additive — none are required for core product viability

## Mobile App Specific Requirements

### Platform Requirements

- **iOS:** iOS 15.0+ (covers 95%+ of active devices)
- **Android:** Android 8.0 (API 26)+ (covers 95%+ of active devices)
- **Framework:** Flutter 3.x with single codebase, 95%+ code reuse across platforms
- **Rendering:** CustomPainter + Canvas API for 60 FPS path drawing via Impeller engine

### Device Permissions

- **Internet** — puzzle sync, leaderboards, auth (graceful offline fallback)
- **Push Notifications** — daily puzzle alerts, group activity (opt-in per group)
- **Haptic Engine** — tactile feedback on cell entry, waypoint hit, wall collision, completion (toggleable)
- **Share Sheet** — native platform share for result cards and invite links
- **Local Storage** — puzzle cache (Hive), preferences (SharedPreferences), offline queue

### Offline Strategy

- Puzzles pre-cached 24 hours in advance via silent background fetch
- 7 bundled fallback puzzles included in app binary for first-launch offline scenario
- Offline puzzle completions queued locally and synced on reconnection
- Conflict resolution: server timestamp wins for leaderboard ordering; local data preserved if server has no record
- Offline indicator in UI when no connectivity detected

### App Size & Performance Targets

- Initial download < 50 MB (target: 35-40 MB)
- Maximum local cache size: 50 MB (configurable, auto-prunes oldest cached puzzles)
- Memory usage < 150 MB during gameplay
- Battery impact: minimal (no GPS, no camera, no continuous network)

## Functional Requirements

### Puzzle Engine *(Journeys: Dana, Chris, Alex)*

- FR1: Players can view a grid with numbered waypoints displayed as colored circles and wall barriers displayed as thick lines between cells
- FR2: Players can draw a path by dragging their finger across adjacent grid cells
- FR3: Players can undo path segments by dragging backward along the drawn path
- FR4: Players can undo the last path segment via an undo button
- FR5: Players can redo a previously undone segment via a redo button
- FR6: Players can reset the entire puzzle to its initial empty state
- FR7: Players can tap a cell on the drawn path to remove the path from that cell to the end
- FR8: System validates that the path is continuous, visits all cells exactly once, passes through waypoints in numerical order, and respects wall barriers
- FR9: System detects puzzle completion when all cells are filled and all waypoints are visited in order
- FR10: System displays a celebration animation upon puzzle completion
- FR11: System provides haptic feedback on cell entry (light), waypoint reached (medium), wall collision (error), and puzzle completion (success pattern)

### Daily Puzzle System *(Journeys: Dana, Chris)*

- FR12: System delivers one puzzle per day, identical for all users worldwide
- FR13: System scales puzzle difficulty by day of week: Monday (5x5, easy) through Sunday (8x8, hard)
- FR14: System tracks solve time from first cell entry to puzzle completion, hidden during play and displayed on the result screen
- FR15: System pre-generates puzzles 30 days in advance via server-side scheduled function
- FR16: System pre-caches the next day's puzzle on the device 24 hours before its release date

### Hint System *(Journeys: Alex)*

- FR17: Players can request a hint that reveals the correct path for the next 2-3 cells from their current position
- FR18: System provides 3 free hints per day, resetting at midnight UTC
- FR19: System tracks total hints used per puzzle attempt

### User Management *(Journeys: Dana, Alex)*

- FR20: Players can start playing immediately without creating an account (anonymous session)
- FR21: Players can create an account using email/password, Google Sign-In, or Apple Sign-In
- FR22: Players can link an anonymous session to a new account without losing progress, streaks, or group memberships
- FR23: Players can set a display name (text, max 20 characters)
- FR24: Players can select an avatar from a set of preset avatar images
- FR25: Players can update their display name and avatar at any time
- FR26: Players can delete their account with a 30-day grace period before permanent data removal
- FR27: System prompts account creation after the 3rd puzzle solve or when attempting to join a group

### Streaks & Statistics *(Journeys: Chris)*

- FR28: System tracks the player's current consecutive-day solve streak
- FR29: System tracks the player's longest-ever solve streak
- FR30: System tracks total puzzles solved and average solve time
- FR31: Players can use 1 streak freeze per week to preserve their streak when missing a day
- FR32: System automatically applies streak freeze if player misses a day and has a freeze available
- FR33: Players can view their statistics on a dedicated stats screen

### Groups & Leaderboards *(Journeys: Sam, Sam Admin)*

- FR34: Players can create a group with a name (max 30 characters) and optional description
- FR35: System generates a unique 6-character alphanumeric invite code for each group
- FR36: Players can join a group via invite code entry, deep link, or QR code scan
- FR37: System enforces a maximum of 50 members per group
- FR38: System displays a daily leaderboard per group ranked by hints used (ascending), then solve time (ascending), then undos used (ascending)
- FR39: System displays a weekly leaderboard per group ranked by puzzles completed (descending), then average solve time (ascending)
- FR40: Group admins can remove members from the group
- FR41: Group admins can regenerate the invite code, invalidating the previous code
- FR42: Players can leave a group at any time
- FR43: Group creators (admins) can delete the group entirely
- FR44: System displays which group members have and have not solved today's puzzle (without revealing solve details until the viewer has also solved)

### Sharing *(Journeys: Dana, Chris, Alex)*

- FR45: Players can generate a spoiler-free share card showing grid size, solve time, day identifier, and an abstract path visualization that does not reveal the solution
- FR46: Players can share the result card to any platform via the native OS share sheet
- FR47: Players can copy the result card to the clipboard as text
- FR48: Players can share a group invite via deep link, invite code text, or QR code image

### Offline Support *(Journeys: Chris, Sam)*

- FR49: System caches tomorrow's puzzle on-device via background fetch at least 12 hours before release
- FR50: Players can solve the daily puzzle without any network connectivity
- FR51: System queues puzzle completion results locally when offline and syncs automatically when connectivity returns
- FR52: System includes 7 bundled offline fallback puzzles for first-launch scenarios with no connectivity
- FR53: System displays an offline indicator when no network connectivity is detected

### Settings & Preferences *(Journeys: All)*

- FR54: Players can toggle haptic feedback on/off
- FR55: Players can toggle sound effects on/off
- FR56: Players can select a visual theme (light mode, dark mode)
- FR57: Players can configure notification preferences per group (on/off)
- FR58: Players can view the app's privacy policy and terms of service

### Navigation & Structure *(Journeys: All)*

- FR59: System provides bottom navigation with Home, Groups, Stats, and Profile tabs
- FR60: Home screen displays the daily puzzle card (grid size, difficulty indicator, play button), current streak, and group activity summary
- FR61: System supports deep links for group invites that open the app directly to the group join flow (or the app store if not installed)

## Non-Functional Requirements

### Performance

- NFR1: Path drawing interaction renders at 60 FPS minimum on devices released 2022 or later, as measured by frame timing profiler
- NFR2: App cold start completes in < 2 seconds on mid-range devices, as measured by time from process start to first frame rendered
- NFR3: Cached daily puzzle loads and renders in < 200ms, as measured by analytics event timing
- NFR4: Network-fetched daily puzzle loads in < 500ms on 4G connection, as measured by API response time + render time
- NFR5: Score submission API call completes in < 300ms on 4G connection, as measured by API latency monitoring
- NFR6: Group leaderboard loads in < 500ms for groups with 50 members, as measured by API response time

### Security

- NFR7: All network communication uses HTTPS/TLS 1.2+
- NFR8: Authentication tokens are stored in platform-secure credential storage
- NFR9: Puzzle solution paths are never transmitted to the client; server re-validates submitted paths against stored solutions
- NFR10: Score submissions are rate-limited to 10 per hour per user to prevent abuse
- NFR11: Solve times under 3 seconds for any grid size are rejected as physically impossible
- NFR12: Database access control policies enforce that users can only read their own attempts and only read data within groups they belong to

### Scalability

- NFR13: Backend supports 10,000 concurrent users with < 10% performance degradation on production-tier infrastructure
- NFR14: Database indexes support O(log n) lookup for puzzles by date, attempts by user, and group membership queries
- NFR15: Puzzle pre-generation runs as a scheduled function handling 30-day batch generation in under 60 seconds

### Accessibility

- NFR16: All touch targets meet minimum 44x44dp sizing per Apple HIG and Material Design guidelines
- NFR17: Color is not the sole indicator of any game state — colorblind mode adds patterns/textures to distinguish path, waypoints, walls, and empty cells
- NFR18: All UI text meets WCAG 2.1 AA contrast ratio (4.5:1 for body text, 3:1 for large text)
- NFR19: App respects system-level reduced motion settings by disabling animations when enabled

### Reliability

- NFR20: Offline-to-online sync achieves zero data loss for puzzle completions, as validated by integration testing with network interruption scenarios
- NFR21: App crash rate remains below 1% of sessions, as measured by crash reporting service
- NFR22: Background puzzle cache refresh succeeds on at least 95% of attempts, as measured by analytics events
