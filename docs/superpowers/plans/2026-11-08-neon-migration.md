# Icos → Neon Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run Icos entirely on a free Neon project (Postgres + one Function + Data API + schedule triggers) with every 1.0.1 feature intact, then ship app version 1.1.0 to both stores.

**Architecture:** A single Neon Function (Node 24, Hono) hosts self-hosted Better Auth at `/auth/*`, the former edge functions at `/api/*`, and cron handlers at `/cron/*`; the Flutter app reads tables and RPCs through Neon's PostgREST-compatible Data API using a 15-minute ES256 JWT from Better Auth, and `profiles` is the root identity table with `ON UPDATE CASCADE` so a guest can be re-keyed onto the account it upgrades to. Nightly jobs are Function Triggers clustered in one 30-minute UTC window; the activity feed is polled every 15 s while visible.

**Tech Stack:** Neon CLI 9.2 (`neon.ts`, `@neon/config`, `@neon/functions`), Node 24, TypeScript, Hono, `pg`, `better-auth` 1.7.x (plugins: anonymous, bearer, jwt, expo), `jose`, Resend REST; Flutter 3.41 with `postgrest`, `http`, `flutter_secure_storage`, `flutter_web_auth_2`, `google_sign_in`, `sign_in_with_apple`.

**Spec:** `docs/superpowers/specs/2026-11-08-neon-migration-design.md`

## Global Constraints

- Neon Free only: one project (`icos`, `aws-us-east-1`), compute pinned `autoscalingLimitMinCu: 0.25, autoscalingLimitMaxCu: 0.25, suspendTimeout: "5m"` on every branch; no paid features.
- Function slug `api` (`^[a-z0-9]{1,20}$`); all Neon CLI commands run from `backend/` (where `neon.ts` and `.neon` live).
- Secrets only in git-ignored `backend/.env.neon` and Neon Function env; never printed, never committed; `.gitignore` gains `backend/.env.neon`, `backend/.neon`, `backend/node_modules`.
- The product name is Icos; the deep-link scheme is `io.icos`; no `supabase` string remains in `lib/`, `android/`, `ios/`, `docs/`, `.github/`, `scripts/`, `CLAUDE.md` when Task 13 finishes (`git grep -il supabase` is empty except the plan/spec history under `docs/superpowers/`).
- API contracts (`{error, code}` bodies, status codes, response fields) are byte-compatible with the current edge functions as listed in the spec §6.1; the Dart `EdgeInvoker` typedef and `EdgeResponse(status, body)` stay.
- Dart rules from CLAUDE.md apply: strings in `AppStrings`, `EdgeInsetsDirectional`, repositories return `Result<T, AppError>`, `flutter analyze` clean, no `print`.
- Commits: imperative subject, trailer `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`; stage only your own paths.
- Tests for the backend run with `node --test` (TypeScript via `tsx`); DB-backed tests use `NEON_TEST_DATABASE_URL` (the `test` branch's unpooled URL in `backend/.env.neon`) and must create and drop their own rows; unit tests must run without a database.

## Review Focus

1. **A guest upgrades on a slow network and the request is retried** — `onLinkAccount` runs twice; the second run must find no guest profile and return without error, and the account must end with exactly one profile row. (Task 5 test `link_twice_is_noop`.)
2. **A guest signs in to an existing account that already has a streak** — the existing account's rows must be untouched and the guest's rows deleted, never merged. (Task 5 test `existing_account_discards_guest`.)
3. **Data API request with an expired JWT** — the client must refresh via `/auth/token` once and retry, and a signed-out client must fall back to the `anonymous` role and still read `puzzles` and `app_config`. (Task 9 tests `refreshes_expired_jwt_once`, `anonymous_reads_public_tables`.)
4. **Trigger redelivery** — the same `scheduled_at` delivered twice must run the job once; a request without `X-Neon-Trigger-Invocation-Id` must get 401. (Task 7 tests.)
5. **An old 1.0.x install updates to 1.1.0** — stale Supabase session keys and Hive caches must be cleared before the first network call, and the fresh-start dialog shown exactly once. (Task 12 test `legacy_cleanup_runs_once`.)

---

## File structure

```
backend/
  neon.ts                      # project policy: branch compute pins, function api, triggers, dataApi (Task 1, 7, 8)
  package.json, tsconfig.json  # Node 24 ESM, scripts: test, typecheck, migrate, seed, smoke
  .env.neon (git-ignored)      # DATABASE_URL*, BETTER_AUTH_SECRET, PUZZLE_SEED_SALT, GOOGLE_*, APPLE_*, RESEND_API_KEY, NEON_TEST_DATABASE_URL
  migrations/0001_schema.sql   # schemas app/public, tables, indexes, RLS, grants       (Task 2)
  migrations/0002_functions.sql# SQL functions (ported), triggers                        (Task 3)
  migrations/0003_seed.sql     # app_config, banned_words                                 (Task 3)
  scripts/migrate.ts           # applies migrations/*.sql in order, records schema_migrations (Task 2)
  scripts/smoke.ts             # end-to-end against a branch: guest → start → submit        (Task 8)
  scripts/generate.ts          # fallback puzzles + parity fixtures (port of generate_puzzles.ts) (Task 4)
  src/index.ts                 # Hono app: mounts /health, /auth/*, /api/*, /cron/*        (Task 4, 5, 6, 7)
  src/db.ts                    # Pool + attachDatabasePool, q(), tx()                      (Task 4)
  src/email.ts                 # Resend sender                                             (Task 4)
  src/auth.ts                  # betterAuth(...) + hooks                                   (Task 5)
  src/identity.ts              # providerDisplayName(), rekeyGuest(), discardGuest(), ensureProfile() (Task 5)
  src/routes/puzzle.ts         # /api/daily-puzzle, /api/start-puzzle                      (Task 6)
  src/routes/score.ts          # /api/submit-score                                         (Task 6)
  src/routes/groups.ts         # /api/join-group, /api/block, /api/unblock, /api/report    (Task 6)
  src/routes/account.ts        # /api/export-data, /api/account/upgrade-email              (Task 6)
  src/routes/cron.ts           # /cron/*                                                   (Task 7)
  src/shared/http.ts           # port of _shared/http.ts minus Supabase clients            (Task 4)
  src/shared/puzzle_core.ts    # moved unchanged                                           (Task 4)
  src/shared/fixtures/puzzle_parity.json                                                   (Task 4)
  test/**/*.test.ts            # node --test
lib/core/backend/
  backend_config.dart, token_store.dart, app_user.dart, auth_event.dart, auth_client.dart, data_api.dart, api_client.dart   (Task 9)
lib/core/services/legacy_cleanup.dart                                                       (Task 12)
docs/config.json, docs/reset.html, docs/verified.html                                       (Task 13)
scripts/neon_usage.py                                                                       (Task 14)
```

---

### Task 1: Neon project, backend scaffold, first deploy

**Files:**
- Create: `backend/package.json`, `backend/tsconfig.json`, `backend/neon.ts`, `backend/src/index.ts`, `backend/README.md`
- Modify: `.gitignore`

**Interfaces:**
- Produces: `backend/neon.ts` exporting `defineConfig` with `branch()` pins and `functions.api = { name: "Icos API", source: "src/index.ts", env: {...} }`; the Function URL recorded in `backend/README.md` and the ledger; `.neon` linking `backend/` to project `icos`, branch `main`.

- [ ] **Step 1: Scaffold** — in `backend/`: `npm init -y` then `npm i hono pg better-auth jose @neon/functions @neon/config` and `npm i -D typescript tsx @types/pg @types/node`; `"type": "module"`; scripts `test: "tsx --test test/**/*.test.ts"`, `typecheck: "tsc --noEmit"`. `tsconfig` target ES2022, module NodeNext, strict.
- [ ] **Step 2: Hello function** — `src/index.ts`: Hono app with `GET /health` → `{status:"ok", fn:"api", ts}` and `GET /auth/jwks` → `{keys: []}` (placeholder until Task 5). `export default app`.
- [ ] **Step 3: `neon.ts`** — `branch: () => ({ postgres: { computeSettings: { autoscalingLimitMinCu: 0.25, autoscalingLimitMaxCu: 0.25, suspendTimeout: "5m" } } })`, `functions.api` as above with `env: { NODE_ENV: "production" }`. No `dataApi` yet.
- [ ] **Step 4: Create and link the project** — `neon link --org-id org-twilight-king-98704418 --project-name icos --region-id aws-us-east-1 --no-env-pull -y`; then `neon env pull --file .env.neon`. Verify: `neon status` shows the branch and compute pins after `neon deploy --env .env.neon -y`.
- [ ] **Step 5: Deploy and probe** — `neon deploy --env .env.neon -y`; `neon functions get api -o json` → record `invocation_url`; `curl <url>health` returns 200 with `fn: "api"`. Try `customDomains: ["api.icos.sarathfrancis.work"]` in `neon.ts` + `neon config plan`; record in the ledger whether the Free plan accepts it (do not deploy it yet if it needs DNS first).
- [ ] **Step 6: Enable the Data API** — `neon data-api create --database neondb --auth-provider external --jwks-url <url>auth/jwks --db-schemas public --db-max-rows 200 --add-default-grants`. Record the Data API URL. If Neon rejects the empty JWKS, record that and retry after Task 5.
- [ ] **Step 7: Branches** — `neon branches create --name dev` and `--name test`; pull their unpooled URLs into `.env.neon` as `DEV_DATABASE_URL_UNPOOLED` and `NEON_TEST_DATABASE_URL` (`neon connection-string <branch> --unpooled`).
- [ ] **Step 8: Commit** — `backend/` scaffold, `.gitignore`, `backend/README.md` (URLs, commands). No secrets.

### Task 2: Schema migration and migration runner

**Files:**
- Create: `backend/migrations/0001_schema.sql`, `backend/scripts/migrate.ts`, `backend/test/schema.test.ts`

**Interfaces:**
- Produces: all 17 tables of spec §5.2 in `public`; schema `app` with `app.uid() RETURNS uuid STABLE` (plpgsql: `EXECUTE 'SELECT auth.user_id()'` when `to_regprocedure('auth.user_id()')` is not null, else `current_setting('request.jwt.claims', true)::jsonb->>'sub'`), `app.is_service() RETURNS boolean` (`current_user NOT IN ('authenticated','anonymous')`); roles used: `authenticated`, `anonymous`; table `schema_migrations(version text primary key, applied_at)`; `npm run migrate -- --url <conn>` applies pending files in order inside one transaction each.

- [ ] **Step 1: Failing test** — `schema.test.ts` (skips when `NEON_TEST_DATABASE_URL` unset): after `migrate()`, asserts the 17 table names exist, `relrowsecurity` is true for each, every FK formerly to `auth.users` now references `profiles(id)` with `ON UPDATE CASCADE`, `profiles` has columns `email, email_verified, providers`, `puzzles.seed_version` default 3, grants: `anonymous` has SELECT on `puzzles` and `app_config` only.
- [ ] **Step 2: Run** — `npm test -- test/schema.test.ts` fails (no tables).
- [ ] **Step 3: Write `0001_schema.sql`** from the inventory (spec §5.2, §5.4): `CREATE SCHEMA IF NOT EXISTS app`; `app.uid()`, `app.is_service()`; tables in dependency order with the constraints, partial unique `puzzle_attempts_one_completed_per_day`, all indexes from the inventory; `ENABLE ROW LEVEL SECURITY` + the policies with `app.uid()`; `GRANT USAGE ON SCHEMA public TO authenticated, anonymous`; column grants exactly as today (`REVOKE ALL` on puzzle_solutions, puzzle_sessions, submission_log, banned_words, group_purged_members); `protect_profile_columns` trigger using `current_user`. Omit every Supabase-only statement.
- [ ] **Step 4: Write `migrate.ts`** — `pg` client on the given URL; creates `schema_migrations`; applies each `migrations/*.sql` not yet recorded, `BEGIN … COMMIT`, logs the file name only.
- [ ] **Step 5: Run** — against `NEON_TEST_DATABASE_URL`: `npm run migrate -- --url "$NEON_TEST_DATABASE_URL"` then the test passes. Re-running `migrate` applies nothing.
- [ ] **Step 6: Commit.**

### Task 3: SQL functions, triggers and seed

**Files:**
- Create: `backend/migrations/0002_functions.sql`, `backend/migrations/0003_seed.sql`, `backend/test/sql_functions.test.ts`

**Interfaces:**
- Produces: every SQL function of the inventory §2 except the removed ones (spec §5.3), same names/args/return types, `auth.uid()` → `app.uid()`, `TO authenticated` grants; triggers `update_*_updated_at`, `validate_profile_display_name`, `group_members_before_insert/after_change`, `protect_profile_columns`; seed rows for `app_config` (`min_supported_version "1.1.0"`, `latest_version "1.1.0"`, `maintenance_mode false`, `store_urls {ios, android}` from spec §13) and the `banned_words` list copied from `supabase/migrations/*reports*`.

- [ ] **Step 1: Failing tests** — using the test URL and `SET LOCAL ROLE authenticated; SELECT set_config('request.jwt.claims', '{"sub":"<uuid>","role":"authenticated"}', true)` inside a transaction: `create_group` then `get_group_daily_leaderboard` returns the inserted completed attempt ranked 1; `record_solve` on two consecutive dates gives `current_streak = 2`; `recompute_streak` with a freeze keeps the streak; `expire_stale_streaks` zeroes a stale row; `regenerate_invite_code` changes the code for the admin and raises 42501 for a member; `is_blocked_by_me` hides a blocked member from both leaderboards; `purge_deleted_accounts` anonymizes a profile past grace and keeps its attempt rows; `request_account_deletion` sets `deleted_at`. Each test creates its users as `profiles` rows (no `ba` dependency) and deletes them in `finally`.
- [ ] **Step 2: Run** — fails (functions missing).
- [ ] **Step 3: Write `0002_functions.sql`** — port from the current definitions listed in the inventory (`sanitize_text`, `contains_profanity`, `validate_name`, `generate_invite_code`, `assert_active_user`, `assert_group_member`, `is_group_member`, `shares_group_with`, `shares_former_group_with`, `is_blocked_by_me`, `create_group`, `remove_group_member`, `transfer_group_admin`, `delete_group`, `leave_group`, `regenerate_invite_code`, `get_group_daily_leaderboard`, `get_group_weekly_leaderboard`, `list_blocked_users`, `request_account_deletion`, `cancel_account_deletion`, `recompute_streak`, `record_solve`, `apply_streak_freezes`, `reset_weekly_freezes`, `expire_stale_streaks`, `prune_submission_log`, `detach_user_from_groups`, `purge_deleted_accounts`, `purge_inactive_anonymous`, the trigger functions). `purge_*` no longer reference `auth.*`; `purge_inactive_anonymous` deletes `profiles` rows only (the Function deletes `ba."user"`, Task 7); `purge_deleted_accounts` returns the purged ids (`RETURNS SETOF uuid`) so the Function can delete the auth users.
- [ ] **Step 4: Write `0003_seed.sql`** — idempotent `INSERT … ON CONFLICT DO NOTHING/UPDATE`.
- [ ] **Step 5: Run** — migrate test branch; tests pass.
- [ ] **Step 6: Commit.**

### Task 4: Function core: shared helpers, db, email, puzzle core port

**Files:**
- Create: `backend/src/shared/http.ts`, `backend/src/shared/puzzle_core.ts` (git mv from `supabase/functions/_shared/puzzle_core.ts`), `backend/src/shared/fixtures/puzzle_parity.json` (git mv), `backend/src/db.ts`, `backend/src/email.ts`, `backend/scripts/generate.ts`, `backend/test/{http,puzzle_core,email}.test.ts`
- Modify: `test/features/puzzle/domain/solver/*parity*_test.dart` (fixture path), `CLAUDE.md` (puzzle core path)

**Interfaces:**
- Produces: `http.ts` exports unchanged names (`corsHeaders, correlationIdFrom, Logger, errorFields, json, errorResponse, handleCommon, readJson, isInt, isIsoDate, utcToday, addDays, compareDates, ARCHIVE_WINDOW_DAYS, isWithinArchiveWindow, sha256Hex, hmacSha256Hex, randomNonce, scoreMessage, timingSafeEqual`) with Node `crypto`; `db.ts` exports `pool` (`new Pool({connectionString: process.env.DATABASE_URL, max: 5})` + `attachDatabasePool(pool)`), `q<T>(text, params): Promise<T[]>`, `tx<T>(fn: (c: PoolClient) => Promise<T>)`; `email.ts` exports `sendEmail({to, subject, html, text})` via `POST https://api.resend.com/emails` with `RESEND_API_KEY`, from `Icos <noreply@icos.sarathfrancis.work>`, returns `{ok, id?}` and never throws; `generate.ts` provides `fallback` and `fixtures` commands (ported from `scripts/generate_puzzles.ts`).

- [ ] **Step 1: Tests** — port `_shared/http_test.ts` and `_shared/puzzle_core_test.ts` to `node --test` (same cases, incl. the parity fixture); `email.test.ts` stubs `fetch` and asserts the request body and that a 500 yields `{ok:false}`.
- [ ] **Step 2: Run** — fails (modules missing).
- [ ] **Step 3: Implement** the four modules; `generate.ts` writes `assets/puzzles/fallback_puzzles.json` and the parity fixture exactly as the Deno script did (compare output byte-for-byte for the existing salt before switching salts).
- [ ] **Step 4: Run** — `npm test` passes; `flutter test test/features/puzzle` passes with the moved fixture.
- [ ] **Step 5: Commit.**

### Task 5: Better Auth server and identity hooks

**Files:**
- Create: `backend/src/auth.ts`, `backend/src/identity.ts`, `backend/test/identity.test.ts`, `backend/test/auth_http.test.ts`
- Modify: `backend/src/index.ts` (mount `/auth/*`, remove placeholder jwks), `backend/package.json` (script `auth:migrate: "npx auth@latest migrate --config src/auth.ts -y"`)

**Interfaces:**
- Produces: `auth` (betterAuth instance) configured per spec §6.2 with `basePath "/auth"`, `schemaName "ba"`, `generateId "uuid"`, plugins `anonymous({onLinkAccount})`, `bearer()`, `jwt({jwks:{keyPairConfig:{alg:"ES256"}}, jwt:{expirationTime:"15m", definePayload}})`, `expo()`; `identity.ts` exports `providerDisplayName(name: string|null, email: string|null): string|null` (rules of inventory §2 incl. `privaterelay.appleid.com` → null, max 30), `placeholderName(): string` (`Player NNNN`), `ensureProfile(c, user)`, `rekeyGuest(c, guestId, newUserId, newUser)` (UPDATE profiles SET id … per spec §7.1), `discardGuest(c, guestId)`, `isFreshAccount(c, newUser): Promise<boolean>` (createdAt within 60 s AND no attempts/groups/streaks); `requireSession(c): Promise<{id, email, isAnonymous}>` helper for `/api/*` built on `auth.api.getSession({headers})`.

- [ ] **Step 1: Unit tests (`identity.test.ts`, no DB)** — `providerDisplayName`: `("Jane Doe", …)` → `Jane Doe`; `(null, "jane.doe+x@example.com")` → `Jane Doe X`; `(null, "abc@privaterelay.appleid.com")` → null; 40-char name truncated to 30. `placeholderName()` matches `/^Player \d{4}$/`.
- [ ] **Step 2: DB tests (`auth_http.test.ts`, test branch)** — after `npm run auth:migrate` against the test URL, using `app.request()`: `POST /auth/sign-in/anonymous` → 200 with `set-auth-token`, a `profiles` row with `is_anonymous=true` and a placeholder name; `POST /auth/sign-up/email` with the guest bearer → 200, `profiles` has one row whose id = new user id, `is_anonymous=false`, the guest's pre-inserted `puzzle_attempts` row now points at the new id (`rekeyGuest`); `link_twice_is_noop`: calling `onLinkAccount` again with the same ids resolves without error and the row count is unchanged; `existing_account_discards_guest`: create user A with a streak row, sign in anonymously, `POST /auth/sign-in/email` as A with the guest bearer → A's streak unchanged, guest profile gone; `GET /auth/token` with a bearer → JWT whose header alg is ES256 and payload has `sub`, `role:"authenticated"`, `is_anonymous`; `GET /auth/jwks` returns one ES256 key.
- [ ] **Step 3: Run** — fails.
- [ ] **Step 4: Implement `auth.ts` and `identity.ts`**; hooks per spec §6.3 and §7.1; `sendResetPassword` → `sendEmail` with link `https://icos.sarathfrancis.work/reset?token=${token}`; `sendVerificationEmail` with `callbackURL=https://icos.sarathfrancis.work/verified`; Apple client secret minted at module load with `jose` `SignJWT` (ES256, `iss` team id, `sub` service id, `aud https://appleid.apple.com`, 180 days) from `APPLE_P8_BASE64`, `APPLE_TEAM_ID`, `APPLE_KEY_ID`; `rateLimit.storage "database"`.
- [ ] **Step 5: Run** — `npm run auth:migrate` (test URL), `npm test` passes; `npm run typecheck` clean.
- [ ] **Step 6: Commit.**

### Task 6: API routes (edge-function parity)

**Files:**
- Create: `backend/src/routes/{puzzle,score,groups,account}.ts`, `backend/test/routes_{puzzle,score,groups,account}.test.ts`
- Modify: `backend/src/index.ts`

**Interfaces:**
- Consumes: `requireSession`, `q`, `tx`, `sendEmail`, `validatePath`, `generatePuzzle`, `seedFor`, `weekdayDifficulty`.
- Produces: routes and contracts exactly as spec §6.1; `generateForDate(date): Promise<"exists"|"created">` exported from `puzzle.ts` (used by cron); `report` and `block` send the alert email to `REPORT_ALERT_TO` env (default `sarathfrancis90@gmail.com`) with the same subject/body as the old `notify_report_filed`.

- [ ] **Step 1: Tests (test branch)** — per route, with a real guest session from `/auth/sign-in/anonymous`: `start-puzzle` 404 for an unknown date, 200 with a 64-hex `nonce` and idempotent `started_at`; `submit-score` 400 `BAD_SIGNATURE` for a wrong HMAC, 200 `{completed:true, verified:true, streak.current_streak:1}` for a valid path signed with the nonce, 409 `ALREADY_COMPLETED` on repeat, 429 after 40 submissions in an hour (insert 40 `submission_log` rows directly), `completed:false, reason:"wrong_length"` for a short path; `join-group` 400 `INVALID_INVITE_CODE`, 403 `ANONYMOUS_USER` for a guest, 200 `{group, already_member:false}` then `already_member:true`; `export-data` 200 with keys `exported_at, user, profile, attempts, streak, streak_freezes, groups, reports_filed, blocked_users` and `user.providers` from `profiles.providers`; `report` 201 and `sendEmail` stub called once; `block` inserts `user_blocks` and one `blocked_by_user` report; `upgrade-email` turns a guest into an email account with the same id and 409 `EMAIL_EXISTS` for a taken email; `daily-puzzle` 403 `DATE_NOT_ALLOWED` for a user asking for `today+2`, 201 then 200 for tomorrow.
- [ ] **Step 2: Run** — fails.
- [ ] **Step 3: Implement** — port each Deno handler to a Hono router; replace supabase-js calls with SQL (`record_solve` via `SELECT * FROM public.record_solve($1,$2)`); rank hint query ported to SQL; `upsertAttempt` conflict → 409 on `23505`.
- [ ] **Step 4: Run** — passes; typecheck clean.
- [ ] **Step 5: Commit.**

### Task 7: Cron routes and triggers

**Files:**
- Create: `backend/src/routes/cron.ts`, `backend/migrations/0004_cron_runs.sql`, `backend/test/routes_cron.test.ts`
- Modify: `backend/neon.ts` (triggers per spec §8), `backend/src/index.ts`

**Interfaces:**
- Produces: `POST /cron/:job` for `reset-weekly-freezes, apply-streak-freezes, expire-stale-streaks, daily-puzzle, purge-deleted-accounts, purge-inactive-anonymous, prune-submission-log`; 401 without `X-Neon-Trigger-Invocation-Id`; 404 unknown job; 200 `{job, ran: boolean, result}`; table `cron_runs(job text, scheduled_at timestamptz, ran_at, primary key (job, scheduled_at))`; `purge-deleted-accounts` deletes `ba."user"` for each id returned by the SQL function; `purge-inactive-anonymous` deletes the matching `ba."user"` rows first then the profiles; `daily-puzzle` calls `generateForDate` for every missing date in `today … today+14` (`SELECT puzzle_date FROM puzzles WHERE puzzle_date BETWEEN …`).

- [ ] **Step 1: Tests** — 401 without header; duplicate `scheduled_at` → second call `ran:false`; `daily-puzzle` creates missing rows for the next 3 days when `PUZZLE_SEED_SALT` is set (use a 5x5 date range to keep CPU low); `purge-deleted-accounts` removes the `ba."user"` row of a profile past grace.
- [ ] **Step 2: Run** — fails.
- [ ] **Step 3: Implement** + add the seven `triggers` to `neon.ts` with `function: "api"` and the `functionPath`s.
- [ ] **Step 4: Run** — passes.
- [ ] **Step 5: Commit.**

### Task 8: Deploy to `dev`, probe the Data API, smoke test

**Files:**
- Create: `backend/scripts/smoke.ts`, `backend/test/data_api.test.ts`
- Modify: `backend/neon.ts` (`dataApi: { authProvider: "external", jwksUrl }` once the real jwks exists), `backend/README.md`

- [ ] **Step 1: Deploy to dev** — `neon checkout dev`; migrate (0001–0004) + `auth:migrate` against `DEV_DATABASE_URL_UNPOOLED`; `neon deploy --env .env.neon -y`; `neon data-api create` for dev with the dev function's `/auth/jwks`; `neon data-api refresh-schema`.
- [ ] **Step 2: Data API probe test (`data_api.test.ts`, runs against `DEV_DATA_API_URL` + a JWT from the dev function)** — asserts: anonymous `GET /puzzles?select=puzzle_date&limit=1` → 200; `GET /profiles?select=*` without a token → 200 `[]` (RLS); with the user's JWT → own row; embed `group_members?select=id,profiles(display_name,avatar_url)` → 200 with nested object; `POST /rpc/create_group` → 200 group row; `Prefer: count=exact` → `Content-Range` header; expired JWT → 401. Record which patterns fail (spec §15) and route them through the Function if any do.
- [ ] **Step 3: Smoke** — `smoke.ts`: anonymous sign-in → start-puzzle → compute HMAC → submit-score → expect `verified:true`; run against dev. Trigger `POST /cron/daily-puzzle` by hand with a fake header is impossible (Neon strips it) — instead run `neon triggers` listing and wait for the next scheduled fire, or call `generateForDate` through a temporary `npm run seed:puzzles -- --url` script that imports it directly (keep that script; it is the first-run seed for `main` too).
- [ ] **Step 4: Register `dataApi` in `neon.ts`** for repeatable deploys; `neon config plan` shows no drift.
- [ ] **Step 5: Commit** (README: dev URLs, probe results).

### Task 9: Flutter backend layer

**Files:**
- Create: `lib/core/backend/{backend_config,token_store,app_user,auth_event,auth_client,data_api,api_client}.dart`, `test/core/backend/{backend_config,auth_client,data_api,api_client}_test.dart`
- Modify: `pubspec.yaml` (add `postgrest`, `http`, `flutter_secure_storage`; keep `supabase_flutter` until Task 12), `.env.example`

**Interfaces:**
- Produces: `BackendConfig.load()` → `BackendConfig{apiBaseUrl, dataApiUrl, googleWebClientId, googleIosClientId, appleServiceId}` (dotenv defaults overridden by cached `https://icos.sarathfrancis.work/config.json`, 5 s timeout, SharedPreferences cache key `backend_config_json`); `TokenStore` (`read/write/clear sessionToken`, `cachedJwt`, `jwtExpiry`) on `FlutterSecureStorage`; `AppUser{id, email, emailVerified, isAnonymous, providers, name, createdAt}`; `AuthEvent{signedIn, signedOut, userUpdated, passwordRecovery}`; `AuthClient(http.Client, BackendConfig, TokenStore)` with `Future<Result<AppUser, AppError>> signInAnonymously()`, `signUpEmail(email, password)`, `signInEmail(email, password)`, `signInWithIdToken({provider, idToken, nonce?})`, `linkWithIdToken(...)`, `webOAuth(provider, {link})` (opens `/auth/expo-authorization-proxy?authorizationURL=…` via `FlutterWebAuth2.authenticate(callbackUrlScheme: "io.icos")`, parses `cookie` or `error`), `getSession()`, `freshJwt()` (refresh when `< 60 s` left), `signOut()`, `requestPasswordReset(email)`, `resetPassword(token, newPassword)`, `sendVerificationEmail()`, `upgradeEmail(email, password)`, `Stream<AuthEvent> events`, `AppUser? currentUser`; `DataApi(config, authClient)` exposing `PostgrestClient get client` with a header provider that sets `Authorization: Bearer <jwt>` when signed in and nothing when not; `ApiClient` implementing the existing `EdgeInvoker` typedef (`Future<EdgeResponse> invoke(String name, Map body)` → `POST {apiBaseUrl}/api/<name>` with the session bearer, 20 s timeout).

- [ ] **Step 1: Tests with `MockClient`** — `backend_config_test`: remote JSON overrides dotenv, failure keeps defaults; `auth_client_test`: anonymous sign-in stores `set-auth-token`, `signUpEmail` sends the guest bearer, `webOAuth` parses `io.icos://oauth-callback?cookie=__Secure-better-auth.session_token%3Dabc…` into token `abc…` and `?error=access_denied` into `AuthFailure`; `refreshes_expired_jwt_once`: a 401 from the Data API triggers one `/auth/token` call and a retry; `anonymous_reads_public_tables`: no token → no Authorization header; `api_client_test`: status and body mapping incl. non-JSON bodies.
- [ ] **Step 2: Run** — fails.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** — passes; `flutter analyze` clean.
- [ ] **Step 5: Commit.**

### Task 10: Auth provider rewrite

**Files:**
- Modify: `lib/features/auth/providers/auth_provider.dart`, `lib/features/auth/domain/auth_strategy.dart` (`kOAuthRedirectUri = 'io.icos://oauth-callback'`, decisions map to `AuthClient` calls), `lib/features/auth/providers/session_keeper.dart`, `lib/core/services/session_service.dart`, `lib/core/services/auth_session_provider.dart`, `lib/main.dart`, `lib/features/profile/presentation/profile_screen.dart`, `lib/features/profile/presentation/widgets/choose_display_name_sheet.dart`, `lib/features/profile/providers/profile_provider.dart`, `lib/features/stats/providers/stats_provider.dart`, `lib/features/auth/domain/auth_outcome.dart`
- Delete: `lib/features/auth/data/oauth_web_gateway.dart`
- Modify tests: `test/core/services/session_service_test.dart`, `test/features/auth/*_test.dart`, `test/features/profile/choose_display_name_test.dart`, `test/features/profile/providers/account_deletion_test.dart`, `test/features/groups/pending_invite_hygiene_test.dart`

**Interfaces:**
- Consumes: `AuthClient`, `AppUser`, `AuthEvent`.
- Produces: `authClientProvider`; `AuthNotifier` keeps its public API (`signInWithGoogle/Apple`, `signInToExistingWithOAuth`, `upgradeWithEmail`, `signUp`, `signInWithEmail`, `resendConfirmation`, `requestPasswordReset`, `completePasswordReset`, `signOut`, `handleAppResumed`) and outcomes (`AuthSuccess`, `AuthIdentityExists`, `AuthFailure`, `AuthCancelled`) so screens stay unchanged; `authSessionProvider` returns `userId` from `AuthClient.currentUser`.

- [ ] **Step 1: Adapt tests** — replace fake GoTrue `User/Session/AuthState` with `AppUser`/`AuthEvent` fakes and a `FakeAuthClient`; keep every existing scenario (guest upgrade keeps id, identity-exists dialog, password recovery latch, pending invite hygiene, user scope switch on sign-out).
- [ ] **Step 2: Run** — fails.
- [ ] **Step 3: Implement** — strategy table: iOS Google/Apple → native idToken (`linkWithIdToken` for guests, `signInWithIdToken` for existing); Android Google → native idToken; Android Apple → `webOAuth('apple')`; "existing account" path always sends the guest bearer so `onLinkAccount` discards the guest; 409 from `/auth/link-social` → `AuthIdentityExists`.
- [ ] **Step 4: Run** — passes; analyze clean.
- [ ] **Step 5: Commit.**

### Task 11: Repositories, feed polling, report/block via API

**Files:**
- Modify: `lib/core/services/app_config_service.dart`, `lib/core/services/sync_service.dart`, `lib/features/puzzle/data/{puzzle_repository,puzzle_session_service}.dart`, `lib/features/stats/data/stats_repository.dart`, `lib/features/profile/data/profile_repository.dart`, `lib/features/groups/data/group_repository.dart`, `lib/features/groups/providers/groups_provider.dart`
- Delete: `lib/core/services/edge_function_client.dart`, `lib/core/services/supabase_service.dart`
- Modify tests: `test/features/groups/data/group_repository_*_test.dart`, puzzle/sync tests that override `edgeInvokerProvider`

**Interfaces:**
- Consumes: `DataApi.client` (PostgREST), `ApiClient` as `edgeInvokerProvider`.
- Produces: identical repository method signatures; `GroupRepository.reportUser/reportGroup` → `POST /api/report`; `blockUser/unblockUser` → `/api/block`, `/api/unblock`; `GroupsProvider` feed: `startFeedPolling(groupId)` / `stopFeedPolling()` with `Timer.periodic(15 s)` fetching `group_feed?select=*,profiles(display_name,avatar_url)&group_id=eq.X&id=gt.<lastId>&order=id.desc&limit=50`, paused on `AppLifecycleState.paused`.

- [ ] **Step 1: Adapt tests** — repository tests keep asserting PostgREST URL shapes (now against `DATA_API_URL`) and error mapping; add `feed_polling_test` (fake async: tick → fetch → new rows appended; dispose cancels timer).
- [ ] **Step 2: Run** — fails. **Step 3: Implement.** **Step 4: Run** — passes. **Step 5: Commit.**

### Task 12: Fresh-start cleanup, scheme rename, dependency removal

**Files:**
- Create: `lib/core/services/legacy_cleanup.dart`, `test/core/services/legacy_cleanup_test.dart`, `lib/shared/widgets/fresh_start_dialog.dart`
- Modify: `lib/main.dart`, `lib/app.dart`, `android/app/src/main/AndroidManifest.xml`, `ios/Runner/Info.plist`, `pubspec.yaml` (remove `supabase_flutter`), `lib/core/constants/app_strings.dart`, `.env.example`, `.env.production`/`.env.development` keys (`API_BASE_URL`, `DATA_API_URL`, `APPLE_SERVICE_ID`; remove `SUPABASE_*`)
- Delete: `supabase/` (whole directory), `scripts/check_signin.py`, `scripts/apple_client_secret.py`, `scripts/generate_puzzles.ts`, `scripts/deno.json`, `.github/workflows/puzzles.yml`

**Interfaces:**
- Produces: `LegacyCleanup.runIfNeeded(prefs, hive)` → `bool showedNotice`: detects keys `supabase.auth.token` / prefix `sb-` / legacy Hive user box, clears caches, removes keys, sets `fresh_start_notice_shown=true`; `main.dart` calls it before `SessionService.ensureGuest()` and `app.dart` shows `FreshStartDialog` once (copy from spec §9.2 in `AppStrings.freshStartTitle/Body`).

- [ ] **Step 1: Test `legacy_cleanup_runs_once`** — with a `sb-` key present: returns true, key removed, flag set; second run returns false. **Step 2: Run** — fails. **Step 3: Implement**; rename scheme to `io.icos` in manifest (both intent filters), Info.plist, `auth_strategy.dart`; remove the package and files. **Step 4:** `flutter pub get`, `dart run build_runner build`, `flutter analyze`, full `flutter test` passes; `git grep -il supabase -- lib android ios scripts .github pubspec.yaml` is empty. **Step 5: Commit.**

### Task 13: Website, legal, CI and docs

**Files:**
- Create: `docs/config.json` (`{"api_base_url": "...", "data_api_url": "..."}` for `main`), `docs/reset.html`, `docs/verified.html`
- Modify: `docs/.well-known/apple-app-site-association` (add `/reset`), `docs/.well-known/assetlinks.json` (unchanged content; verify), `docs/privacy-policy.html`, `docs/terms.html`, `docs/index.html` (if it names Supabase), `.github/workflows/ci.yml` (replace the deno job with `node` job: `npm ci && npm run typecheck && npm test` in `backend/`, unit tests only), `.github/workflows/deploy-*.yml` (env keys), `CLAUDE.md` (stack table, schema section, edge functions → Function routes, security rules, paths), `docs/RELEASE_RUNBOOK.md` (new "Backend on Neon" section: commands, env file, triggers, usage script), `docs/SIGNIN_SETUP.md` (callback URLs for Google/Apple on the Function host, scheme `io.icos`), `supabase/README.md` → `backend/README.md` (RPC contracts kept)
- Add: `lib/core/router/app_router.dart` route `/reset` → `ResetPasswordScreen(token)` (existing recovery screen) for the universal link

- [ ] **Step 1:** `reset.html` posts `{newPassword, token}` to `${api}/auth/reset-password` and shows success/error; `verified.html` static. **Step 2:** CI job green locally (`act` not required; run the commands). **Step 3:** `flutter test` for the router (`/reset?token=abc` reaches the screen with the token). **Step 4: Commit.**

### Task 14: Production deploy on `main` and verification

**Files:**
- Create: `scripts/neon_usage.py` (Neon API: project consumption for the current month → compute hours, egress GB, storage; reads `NEON_API_KEY` from `backend/.env.neon`)
- Modify: `backend/README.md`, `docs/config.json` (final URLs), ledger

- [ ] **Step 1:** `neon checkout main`; migrate (0001–0004) + `auth:migrate` on `DATABASE_URL_UNPOOLED`; populate `backend/.env.neon` secrets (Google web id/secret from `oauth-clients/*.json`; `APPLE_SERVICE_ID`, `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_P8_BASE64` from the Sign in with Apple `.p8` on disk — the key id is the one `scripts/apple_client_secret.py` used; `RESEND_API_KEY` newly minted through the Resend connector; `BETTER_AUTH_SECRET`, `PUZZLE_SEED_SALT` from `openssl rand -hex 32`; `REPORT_ALERT_TO`); `neon deploy --env .env.neon -y`; `neon data-api create` (or update) with the main function's `/auth/jwks`; `refresh-schema`; `npm run seed:puzzles -- --url … --from <today-31> --days 46`; `neon triggers list` shows 7.
- [ ] **Step 2: Owner hand-off (one message):** add `https://<main-host>/auth/callback/google` to the Google web client, add the host and `https://<main-host>/auth/callback/apple` to the Apple Services ID; optional CNAME for `api.icos.sarathfrancis.work` if Task 1 found custom domains allowed (then `baseURL` and callbacks use it).
- [ ] **Step 3: Verify on emulators** — debug build with `.env.development` pointing at `main`: guest play → solve → streak 1; upgrade to email → same progress; second emulator: sign up, create group, both join, both solve, feed shows the other within 15 s, leaderboards, block/report (alert email received), leave/remove, sign-out/sign-in, delete request/cancel. Record in the ledger. Real-device Google/Apple sign-in after the owner registers the callbacks.
- [ ] **Step 4:** `python3 scripts/neon_usage.py` prints the month's usage; record baseline.
- [ ] **Step 5: Commit.**

### Task 15: Release 1.1.0 (+14) and cutover

- [ ] **Step 1:** `pubspec.yaml` → `1.1.0+14`; release notes (iOS `release_notes.txt`, Android changelog): "Icos moved to a new, faster backend. Progress starts fresh in this version."; commit; push; CI green.
- [ ] **Step 2:** `bash scripts/release.sh` (clean build, TestFlight upload, Play internal + alpha); attach build 14 to the "Public testers" group, what-to-test, beta review (`scripts/asc.py`, paths without `/v1`).
- [ ] **Step 3:** App Store: if version 1.0.1 is still `WAITING_FOR_REVIEW`, cancel its review submission (`PATCH reviewSubmissions/<id> {attributes:{canceled:true}}`) and create version `1.1.0` with build 14 + what's new, submit for review; if 1.0.1 was approved meanwhile, release it first, then submit 1.1.0.
- [ ] **Step 4:** After 1.1.0 is `READY_FOR_DISTRIBUTION` and on the Play closed track: set the Supabase `app_config.min_supported_version` to `1.1.0` (owner runs the one-line SQL if the session is blocked), update `docs/RELEASE_RUNBOOK.md` status rows, and tell the owner the Supabase project can be deleted.
- [ ] **Step 5:** Update memory files (`icos-launch-state`, `icos-neon-migration`) and the ledger; final usage check.
