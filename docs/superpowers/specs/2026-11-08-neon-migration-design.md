# Icos on Neon — migration design

_Date: 2026-11-08. Status: approved by the owner in principle ("full migration, clean slate, keep every feature, free limits, then ship"); the architecture choices below are the orchestrator's calls, stated to the owner and not vetoed._

## 1. Intent

Move Icos completely off Supabase onto Neon (Lakebase Postgres and its backend primitives) so the app runs at $0 a month on Neon's Free plan, without losing any user-visible feature, and ship the result as app version 1.1.0 to the App Store and Google Play.

The driver is cost: the Supabase organization bill is $62.15 a month (Pro plan plus always-on compute); Icos is one $10 compute instance of that. The owner chose Neon over the cheaper alternative of moving Icos to a free Supabase organization, and intends Icos to be the first project off Supabase.

## 2. Goals, non-goals, anti-goals

**Goals**
- Every feature in the 1.0.1 app keeps working: guest play on first launch, upgrading a guest to Google / Apple / email while keeping progress, signing in to an existing account from a new device, daily puzzle at midnight UTC, archive (30 days), streaks and freezes, groups with invite codes, daily and weekly leaderboards, live-feeling activity feed, blocking and reporting, account deletion with a 30-day grace period, data export, offline queue with signed score submission, push/local reminders, deep links.
- Stay inside Neon Free: 1 project, compute pinned to 0.25 CU with scale-to-zero, under 100 CU-hours and 5 GB egress a month, one Function under 10 active / 400 waiting capacity-hours and 1M invocations, under 1 GB storage.
- Clean slate: no user data is migrated. Puzzles are regenerated with a new seed salt. Old players start as new guests.
- Release 1.1.0 (+14) to both stores pointing only at Neon; then the Supabase project can be deleted.

**Non-goals**
- Migrating users, attempts, streaks or groups from Supabase.
- Realtime push (WebSocket/SSE). Polling while a screen is visible is the replacement.
- Tablet landscape, redo, avatars, nudges, and other PRD items that were not built in 1.0.

**Anti-goals (would make this a failure even if it "works")**
- Any path that bills the owner: autoscaling above 0.25 CU, a second Neon project, paid add-ons.
- Losing guest progress on upgrade, or merging a guest into someone else's existing account.
- Shipping with Supabase packages, URLs, keys or scheme names still in the app, the website, the legal pages or the docs.
- Writing secrets into the public repository.

## 3. Constraints and facts the design rests on

Verified against Neon docs on 2026-11-08 (research notes in the session scratchpad; URLs in `neon-research.md`):
- Functions run Node.js 24 only; the entrypoint is a default export with `fetch(request)` (a Hono app qualifies); npm dependencies are bundled with esbuild; slug `^[a-z0-9]{1,20}$`; URL `https://<branch_id>-<slug>.compute.<cell>.<region>.aws.neon.tech/`; no gate in front, so the function authenticates callers itself; use a module-scope `pg` `Pool` (`max: 5`) with `attachDatabasePool` on the pooled `DATABASE_URL`.
- Function Triggers: `triggers: { name: { type: "schedule", function, cron, functionPath } }`, cron in UTC, at-least-once with retries up to 72 h; authenticity is the presence of `X-Neon-Trigger-Invocation-Id` (Neon strips client-set `X-Neon-*` headers). Triggers fire while Postgres is suspended.
- Data API (PostgREST-compatible) is free; external auth: `authProvider: "external", jwksUrl`; tokens must carry `role: "authenticated"` and `sub`; it runs `SET ROLE` to that role, else `anonymous`; `auth.user_id()` (pg_session_jwt) returns `sub`; the schema cache needs `neon data-api refresh-schema` after migrations; enabling it creates an `auth` schema. Only one JWKS provider; do not enable Managed Auth.
- Free Postgres: `pgcrypto` yes; `pg_cron` and LISTEN/NOTIFY need scale-to-zero off (not possible on Free); `pg_net` absent. Over the CU-hour or egress cap the compute is suspended until the next cycle.
- Neon Realtime has JS SDKs only and an undocumented wire protocol; Managed Auth has no anonymous accounts.
- Better Auth 1.7.18 (ESM, Node ≥ 22.12): anonymous plugin links on the next sign-in/up/callback that carries the guest session and calls `onLinkAccount({anonymousUser, newUser})` then deletes the guest; `/sign-in/social` accepts a native `idToken` (no browser); browser OAuth from a native app goes through the `expo()` server plugin's `/expo-authorization-proxy` and returns the session as a `cookie` query parameter on a trusted custom-scheme URL; `bearer` plugin for header sessions; `jwt` plugin with `jwks.keyPairConfig` ES256 and `definePayload`; rate limiting with `storage: "database"`; password reset `POST /request-password-reset` then `POST /reset-password {newPassword, token}`; `requireEmailVerification: true` returns no session on sign-up and would orphan the guest, so it stays off.

## 4. Architecture

```
Flutter app (1.1.0)
 ├─ Auth: HTTPS → Neon Function "api" /auth/*  (Better Auth: anonymous, email, Google, Apple, bearer, jwt, expo)
 ├─ Tables & RPCs: HTTPS → Neon Data API  (PostgREST; Bearer = 15-min JWT from /auth/token; RLS by auth.user_id())
 ├─ Server logic: HTTPS → Neon Function "api" /api/*  (start-puzzle, submit-score, join-group, export-data, daily-puzzle, report)
 └─ Feed: polls Data API group_feed every 15 s while the group screen is visible
Neon project "icos" (aws-us-east-1, Free): Postgres (0.25 CU, scale-to-zero) + Function "api" + 7 schedule triggers → /cron/*
Email: Resend HTTPS API from the Function (auth mail + report alerts), from noreply@icos.sarathfrancis.work
Website (GitHub Pages, icos.sarathfrancis.work): /reset (password reset page), /verified (email confirmed page)
```

One Neon Function hosts everything server-side (fewer cold starts, one URL to register with Google and Apple). The database is the system of record; the Function connects as the database owner, which bypasses RLS and replaces Supabase's service role. Clients never hold a privileged key: anonymous Data API requests fall back to the `anonymous` role, which may only read `puzzles` and `app_config`.

## 5. Database

### 5.1 Schemas and roles
- `public`: the application schema (tables below). Owner: the project's default role; the Function uses it.
- `ba`: Better Auth tables (`user`, `session`, `account`, `verification`, `jwks`, `ratelimit`) created by `npx auth@latest migrate` with `database.schemaName: "ba"` and `advanced.database.generateId: "uuid"`. Not exposed through the Data API (`db-schemas public` only).
- `auth`: created by Neon when the Data API is enabled (pg_session_jwt: `auth.user_id()`). Our code never defines objects in it.
- `app`: helper functions we own: `app.uid() uuid` = `nullif(auth.user_id(), '')::uuid`; `app.is_anonymous_request()`; `app.role()` = `current_user`.
- Roles `authenticated` and `anonymous` are Neon's Data API roles; every former `TO authenticated` grant/policy keeps that role name; former `anon` becomes `anonymous`; former `service_role` policies are dropped (the owner role bypasses RLS).

### 5.2 Tables
Same 17 tables as today, re-created from a single consolidated migration (`neon/migrations/0001_schema.sql`) with these changes:
- `profiles.id` is the root identity: every former FK to `auth.users(id)` points to `profiles(id)` instead (puzzle_attempts, streaks, streak_freezes, puzzle_sessions, submission_log, groups.admin_id, group_members, group_feed, reports.reporter_id / reported_user_id, user_blocks). `profiles.id` has **no** FK to `ba.user`; the two are kept equal by the Function's hooks.
- `profiles` gains `email text`, `email_verified boolean default false`, `providers text[] default '{}'` (so the profile screen and export no longer need an auth admin API).
- `reports` loses its email trigger; alert emails are sent by the `/api/report` and `/api/block` routes (no cron, no DB trigger).
- `puzzles.seed_version` = 3 (new salt).
- Dropped: Vault/pg_net/pg_cron statements, `supabase_realtime` publication, `NOTIFY pgrst`, auth.users triggers, `auth.role()` policy, `protect_profile_columns`' `request.jwt.claims` reads (uses `current_user IN ('authenticated','anonymous')` instead).

### 5.3 Functions (SQL)
All current SECURITY DEFINER functions are ported verbatim with `auth.uid()` → `app.uid()`; grants `TO authenticated`. Removed: `handle_new_user`, `handle_user_updated`, `notify_report_filed`, `trigger_daily_puzzle_generation`, `decrement_group_member_count`, `update_group` (unused), `block_user`, `unblock_user` (now Function routes). `purge_deleted_accounts` and `purge_inactive_anonymous` no longer touch `auth.*`; the Function performs the `ba."user"` deletes (see 7.3). `provider_display_name(meta, email)` moves to TypeScript (it runs in the user-create hook).

### 5.4 RLS
Identical policy set, expressed with `app.uid()`. `puzzles` and `app_config` are readable by `anonymous`. `group_feed` select policy unchanged (members minus blocked). `reports`: insert own, select own. The Data API is created with `--db-max-rows 200`.

### 5.5 Seed
`app_config` rows (`min_supported_version`, `latest_version`, `maintenance_mode`, `store_urls` with both store links), `banned_words` list, and puzzles for yesterday-30 … today+14 generated with the new `PUZZLE_SEED_SALT` by the Function's cron route (first run by hand).

## 6. The Function (`neon/functions/api/`)

Node 24, TypeScript, Hono, `pg`, `better-auth`, `jose`, bundled by the Neon CLI. Source lives in `neon/` at the repo root (`neon.ts`, `neon/functions/api/src/**`, `neon/migrations/**`, `neon/package.json`). Shared pure code (`puzzle_core.ts`, http helpers) moves from `supabase/functions/_shared/` to `neon/functions/api/src/shared/` unchanged in behaviour; `fixtures/puzzle_parity.json` moves with it and stays the Dart parity test.

### 6.1 Routes
| Route | Replaces | Notes |
|---|---|---|
| `ALL /auth/*` | Supabase Auth | Better Auth handler |
| `POST /api/start-puzzle` | start-puzzle | same contract |
| `POST /api/submit-score` | submit-score | same contract; `record_solve` via SQL; feed insert |
| `POST /api/join-group` | join-group | same contract (keeps 200 `{group, already_member}`) |
| `GET/POST /api/export-data` | export-data | reads `profiles.email/providers`, no admin API |
| `POST /api/daily-puzzle` | daily-puzzle | user callers: today/tomorrow only; cron: any |
| `POST /api/report` | client insert into `reports` | inserts, sends the alert email via Resend, returns 201 |
| `POST /api/block`, `POST /api/unblock` | `block_user` / `unblock_user` RPCs | direct SQL (insert/delete `user_blocks`, the automatic `blocked_by_user` report) and the alert email; `list_blocked_users` stays an RPC |
| `POST /api/account/upgrade-email` | `updateUser(email,password)` | same-id guest→email (see 7.2) |
| `POST /api/account/delete-request`, `/cancel` | RPCs | thin wrappers kept as RPCs too; the app keeps calling the RPCs |
| `POST /cron/<job>` | pg_cron | guarded by `X-Neon-Trigger-Invocation-Id`; idempotent per `scheduled_at` |
| `GET /health` | — | `{status, fn, ts}` |

Error contract unchanged: `{error, code}` with the same codes the Dart `EdgeInvoker` layer already classifies.

### 6.2 Auth configuration (Better Auth)
- `basePath: "/auth"`, `baseURL` = the Function URL, `secret` from env, `database: new Pool({connectionString: DATABASE_URL, max: 5})`, `schemaName: "ba"`, `generateId: "uuid"`.
- `trustedOrigins: ["io.icos://", "https://icos.sarathfrancis.work", "https://appleid.apple.com"]`.
- Plugins: `anonymous({ onLinkAccount })`, `bearer()`, `jwt({ jwks: { keyPairConfig: { alg: "ES256" } }, jwt: { expirationTime: "15m", definePayload: u => ({ sub: u.id, role: "authenticated", is_anonymous: u.isAnonymous ?? false, email: u.email }) } })`, `expo()` (server side only; enables the authorization proxy and the `cookie` handoff for `io.icos://` callbacks), `openAPI()` off in production.
- `emailAndPassword: { enabled: true, requireEmailVerification: false, minPasswordLength: 6, sendResetPassword }`, `emailVerification: { sendOnSignUp: true, sendVerificationEmail, autoSignInAfterVerification: false }`.
- `socialProviders.google { clientId: GOOGLE_WEB_CLIENT_ID, clientSecret }`, `socialProviders.apple { clientId: APPLE_SERVICE_ID, clientSecret: <ES256 JWT minted at boot from APPLE_P8, APPLE_TEAM_ID, APPLE_KEY_ID, 180 days>, appBundleIdentifier: "com.icos.game", audience: [APPLE_SERVICE_ID, "com.icos.game"] }`.
- `account.accountLinking: { enabled: true, allowDifferentEmails: true, trustedProviders: ["google", "apple", "email-password"] }`.
- `session: { expiresIn: 30 days, updateAge: 1 day }`, `rateLimit: { enabled: true, storage: "database", window: 10, max: 100 }`, `advanced.ipAddressHeaders: ["x-forwarded-for"]`.
- Emails via Resend REST (`RESEND_API_KEY`), from `Icos <noreply@icos.sarathfrancis.work>`: verification link → `https://icos.sarathfrancis.work/verified` after `/auth/verify-email`; reset link → `https://icos.sarathfrancis.work/reset?token=…` (universal link into the app; the page also works standalone and POSTs `/auth/reset-password`).

### 6.3 Hooks that replace the Supabase triggers
- `databaseHooks.user.create.after(user)`: insert `profiles(id, is_anonymous, email, email_verified, display_name)` where `display_name = providerDisplayName(user.name, user.email) ?? 'Player NNNN'` (same rules as today incl. the Apple relay placeholder).
- `databaseHooks.account.create.after(account)`: append the provider to `profiles.providers`; if the linked user was anonymous, set `is_anonymous=false`, copy email/verified; if the display name is a placeholder, replace it with the provider name.
- `databaseHooks.user.update.after`: mirror `email`, `emailVerified`, `name` changes into `profiles`.
- `anonymous.onLinkAccount({anonymousUser, newUser})`: see 7.1.

## 7. Identity flows

### 7.1 Guest → account (keep progress) vs sign-in to existing account (discard guest)
The app always sends the guest's bearer token on `/auth/sign-up/email`, `/auth/sign-in/email`, `/auth/sign-in/social` (idToken) and the authorization-proxy web flow. Better Auth's anonymous plugin then calls `onLinkAccount`:
- If `newUser.createdAt` is within 60 s of now and `newUser` has no rows in `puzzle_attempts`, `group_members` or `streaks` → **upgrade**: in one transaction, delete the just-created `profiles` row of `newUser`, then `UPDATE profiles SET id = newUser.id, is_anonymous=false, email=…, email_verified=…, display_name = CASE placeholder → provider name` where `id = anonymousUser.id` (all app FKs cascade on update: every FK to `profiles(id)` is declared `ON UPDATE CASCADE`). Streaks/attempts/groups follow automatically.
- Otherwise → **existing account**: do nothing; the plugin deletes the guest user, and the Function deletes the guest's `profiles` row (cascading the guest's app data), matching today's "guest progress stays on this device" wording.
- The hook is idempotent: if the guest profile no longer exists, it returns.

### 7.2 Same-id upgrades the app offers today
- Social (Google/Apple) from a guest: the app calls `/auth/link-social` with the guest token (native idToken when available). Better Auth attaches the account to the guest's own id; `account.create.after` flips `is_anonymous`. If the identity already belongs to another user (409), the app shows the existing-account dialog and, on confirm, performs 7.1's existing-account path via `/auth/sign-in/social`.
- Email from a guest: `POST /api/account/upgrade-email {email, password}` (guest bearer): server sets `ba.user.email`, `auth.api.setPassword`, `is_anonymous=false`, sends the verification email. Returns the same session token. Conflict on email → 409 `EMAIL_EXISTS`; the app offers sign-in instead.

### 7.3 Account deletion and purges
- `request_account_deletion` / `cancel_account_deletion` SQL functions unchanged (30-day grace, `deleted_at`).
- `/cron/purge-deleted-accounts`: for each profile past grace: record `group_purged_members`, detach from groups, delete `puzzle_sessions`/`submission_log`, anonymize the profile ("Deleted User", null avatar, `email=null`, `providers='{}'`, `purged_at=now()`), then `DELETE FROM ba."user" WHERE id = …` (cascades sessions/accounts). Leaderboard rows survive.
- `/cron/purge-inactive-anonymous`: `DELETE FROM profiles` (cascade) and `DELETE FROM ba."user"` for guests inactive 90 days.

## 8. Scheduled jobs (Function Triggers, UTC)
All nightly jobs run inside one 30-minute window so Postgres wakes once a day for them (each wake costs at least 5 minutes of compute; the 15-minute report notifier from the first draft was dropped for this reason — it alone would have cost about 60 CU-hours a month).

| Trigger | cron | functionPath | Body |
|---|---|---|---|
| resetweeklyfreezes | `0 0 * * 1` | `/cron/reset-weekly-freezes` | `SELECT public.reset_weekly_freezes()` |
| applystreakfreezes | `5 0 * * *` | `/cron/apply-streak-freezes` | SQL |
| expirestalestreaks | `10 0 * * *` | `/cron/expire-stale-streaks` | SQL |
| dailypuzzle | `15 0 * * *` | `/cron/daily-puzzle` | generate every missing date in today … today+14 |
| purgedeleted | `20 0 * * *` | `/cron/purge-deleted-accounts` | 7.3 |
| purgeanonymous | `23 0 * * *` | `/cron/purge-inactive-anonymous` | 7.3 |
| prunesubmissionlog | `26 0 * * *` | `/cron/prune-submission-log` | SQL |

Every handler checks the invocation header, records `(trigger, scheduled_at)` in `cron_runs` to ignore duplicate deliveries, and returns 200 on success. `.github/workflows/puzzles.yml` is deleted (the trigger retries for 72 h and generates a 14-day buffer).

## 9. Flutter client

### 9.1 New backend layer (`lib/core/backend/`)
- `BackendConfig` from dotenv: `API_BASE_URL`, `DATA_API_URL`, `GOOGLE_WEB_CLIENT_ID`, `GOOGLE_IOS_CLIENT_ID`, `APPLE_SERVICE_ID`. At startup the app also fetches `https://icos.sarathfrancis.work/config.json` (`{api_base_url, data_api_url}`, 5 s timeout, cached in SharedPreferences) and prefers it over the compiled defaults, so a changed Neon host can be fixed without a store release. The Function is additionally exposed on a custom domain `api.icos.sarathfrancis.work` (`customDomains` in `neon.ts`) when the Free plan allows it, which keeps the Google/Apple callbacks stable; if not allowed, the generated host is used and re-registered on change.
- `TokenStore` (flutter_secure_storage): session token, cached JWT + expiry. (Change from today: tokens leave SharedPreferences; CLAUDE.md is updated.)
- `AuthClient`: typed wrappers for `/auth/sign-in/anonymous`, `/auth/sign-up/email`, `/auth/sign-in/email`, `/auth/sign-in/social` (idToken), `/auth/link-social`, `/auth/expo-authorization-proxy` (web flow via flutter_web_auth_2, callback `io.icos://oauth-callback`, parse `cookie` → session token; `error` → failure), `/auth/get-session`, `/auth/token`, `/auth/sign-out`, `/auth/request-password-reset`, `/auth/reset-password`, `/auth/send-verification-email`, `/api/account/upgrade-email`. Exposes `AppUser {id, email, emailVerified, isAnonymous, providers, name, createdAt}` and a broadcast `Stream<AuthEvent>` (`signedIn`, `signedOut`, `userUpdated`, `passwordRecovery`) so `auth_provider.dart`, `session_keeper.dart` and `main.dart` keep their shape.
- `DataApi`: a `PostgrestClient` (package `postgrest`) pointed at `DATA_API_URL` with a header provider that injects `Authorization: Bearer <fresh JWT>` (refreshing via `/auth/token` when < 60 s left; no header when signed out → anonymous role). Repositories swap `SupabaseService.client.from/rpc` for `DataApi.from/rpc`; query shapes unchanged; `PostgrestException` mapping unchanged.
- `ApiClient` replaces `EdgeFunctionClient`: `POST {API_BASE_URL}/api/<name>` with the bearer session token; returns `EdgeResponse(status, body)` so `sync_service`, `puzzle_session_service`, `puzzle_repository`, `group_repository`, `profile_repository` keep their contracts (`EdgeInvoker` typedef stays).
- Feed: `groups_provider` replaces the Realtime channel with a `Timer.periodic(15 s)` poll of `group_feed?group_id=eq.X&id=gt.<lastId>` while the detail screen is mounted and the app is in the foreground; stops on dispose/background.

### 9.2 Fresh-start notice for upgraders
On first launch of 1.1.0, if SharedPreferences holds a Supabase session key (`supabase.auth.token` or any key prefixed `sb-`) or Hive holds the old user id, the app clears its local caches, removes those keys and shows a one-time dialog: "Icos has moved to a new home. Progress and groups start fresh in this version; your streak begins again today." (AppStrings). Nothing else is migrated.

### 9.3 Removed
`supabase_flutter` and transitive direct uses; `SupabaseService`; `oauth_web_gateway.dart` (replaced by `AuthClient.webOAuth`); the `io.supabase.icos` scheme (now `io.icos`, in AndroidManifest, Info.plist, `auth_strategy.dart`); `SUPABASE_*` env keys; `scripts/check_signin.py`, `scripts/apple_client_secret.py` (secret minted by the Function).

### 9.4 Kept as is
Game engine, puzzle solver (Dart mirror + parity fixture), offline queue and HMAC signing, notifications, router, theming, Maestro flows (updated selectors only where copy changes), golden/widget tests not touching auth.

## 10. Website and legal
- `docs/reset.html` (password reset form → `POST {API}/auth/reset-password`), `docs/verified.html`.
- `docs/.well-known/apple-app-site-association` and `assetlinks.json`: add `/reset` path.
- Privacy policy and terms: replace Supabase with Neon (Databricks) as processor; add Resend; keep Google/Apple.

## 11. Security
- Clients never hold a privileged key. The Data API enforces RLS with `app.uid()`; `anonymous` may only read puzzles and config.
- The Function verifies sessions (Better Auth) on `/api/*`; `/cron/*` accepts only Neon-originated requests; `/api/daily-puzzle` limits users to today/tomorrow.
- HMAC-signed score submissions, 5-min clock tolerance, 40/hour rate limit, server-side path validation: unchanged.
- Secrets live only in Neon Function env (set with `neon deploy --env .env.neon`, file git-ignored) and in GitHub Actions secrets for CI.

## 12. Free-plan guardrails
- `neon.ts` `branch()` pins `autoscalingLimitMinCu: 0.25, autoscalingLimitMaxCu: 0.25, suspendTimeout: "5m"` for every branch.
- Data API `db_max_rows 200`; feed polling only while visible; `app_config` cached 1 h on the client (already); leaderboard reads unchanged (small).
- Puzzle generation: one puzzle per day in cron (14-day buffer), node budget unchanged.
- Budget estimate at a few dozen daily players: nightly window ≈ 4 CU-hours/month; ~50 player sessions a day each waking the compute for ≥ 5 minutes ≈ 30 CU-hours/month; dev-branch use during the build ≈ 10. Headroom ≈ 50 CU-hours. If the cap is hit the compute is suspended until the next cycle and the app falls back to offline play (bundled puzzles, queued scores); that is accepted. `scripts/neon_usage.py` prints the month's compute hours and egress from the Neon API so the owner can watch the cap; it is run at the end of every release.

## 13. Cutover and release
1. Build everything against a `dev` Neon branch; run the Dart suite, the Function's tests, and the two-emulator social flow with freshly created QA accounts (native-token sign-ins; the browser OAuth flow is verified on `main` only, since only the `main` host is registered with Google and Apple).
2. Deploy to the `main` Neon branch; seed; register the Google and Apple callback URLs (owner); verify sign-ins on a real device.
3. Ship 1.1.0 (+14): TestFlight public group + App Store review; Play internal + closed. If 1.0.1 is still waiting for review, cancel that submission and submit 1.1.0 instead.
4. "Live" means App Store production plus the Play closed track (Play production stays gated on testers). Then set the old Supabase `app_config.min_supported_version` to `1.1.0` so stale builds prompt an update, and the owner deletes the Supabase project.

## 14. Owner-only steps
- Google Cloud console: add `https://<function-host>/auth/callback/google` to the web OAuth client's redirect URIs.
- Apple Developer: add the Function host and `https://<function-host>/auth/callback/apple` to the Services ID; confirm the Sign in with Apple key id.
- Secrets for the Function env (git-ignored `.env.neon`): Google web client id/secret from the `oauth-clients/` JSON already on disk; the Sign in with Apple key `.p8`, key id and team id already on disk; a NEW Resend API key minted through the Resend connector (the old one stays in Supabase Vault); `BETTER_AUTH_SECRET` and `PUZZLE_SEED_SALT` freshly generated. The owner is asked only if one of these cannot be found.
- DNS: one CNAME `api.icos.sarathfrancis.work` → the Function host, if custom domains are available on Free.
- Delete the Supabase project after 1.1.0 is live.

## 15. Left to the builder
- Exact Hono module layout, test harness (`node --test` with a Neon `test` branch), and how `puzzle_core.ts` is shared with `scripts/` after the Deno scripts are retired.
- Copy for the reset/verified pages (plain, matching the site).
- Whether the Dart `postgrest` package's `rpc` needs `Prefer: params=single-object` for any RPC on Neon's PostgREST version (test on the dev branch; fall back to a Function route for any RPC that misbehaves).
