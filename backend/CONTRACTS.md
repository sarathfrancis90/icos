# Icos backend contracts

Request/response contracts for the Neon backend: the Function `api` routes, the
Data API RPCs, the schedule triggers and the Function environment. Project ids,
URLs and CLI commands are in `README.md`; the design is
`docs/superpowers/specs/2026-11-08-neon-migration-design.md`.

## Conventions

- Base URL: the Function origin (`API_BASE_URL`, trailing slash). Production:
  `https://br-crimson-bird-bbpbnst1-api.compute.c-15.us-east-1.aws.neon.tech/`.
  The app also reads `https://icos.sarathfrancis.work/config.json`
  (`{api_base_url, data_api_url}`) at startup and prefers it.
- `/api/*` responses are JSON, carry `x-correlation-id` (echoed from the request
  header or generated) and log one structured JSON line per event
  (`{ts, level, fn, correlation_id, msg, ...}`).
- Errors are `{error, code}` (plus optional fields such as `field`).
- Signed-in routes take `Authorization: Bearer <session token>` (Better Auth
  `bearer` plugin) and reject banned / deletion-pending profiles with 403
  `BANNED` / `DELETED` (`banCheck` in `src/identity.ts`), unless noted.
  No or invalid session: 401.
- CORS: `/api/*` answers `OPTIONS` and sends `Access-Control-Allow-Origin: *`.

## Auth (`ALL /auth/*`, Better Auth)

Better Auth's own endpoints under `basePath: "/auth"`. The app uses:
`sign-in/anonymous`, `sign-up/email`, `sign-in/email`, `sign-in/social`
(native `idToken`), `link-social`, `expo-authorization-proxy` (browser OAuth,
callback `io.icos://oauth-callback?cookie=…`), `get-session`, `token`
(15-minute ES256 JWT for the Data API), `jwks`, `sign-out`,
`request-password-reset`, `reset-password`, `send-verification-email`,
`verify-email`, and the OAuth callbacks `callback/google`, `callback/apple`.

- Sessions: 30 days, refreshed once a day on use.
- JWT payload: `{sub, role: "authenticated", is_anonymous, email}`.
- Password reset mail links to `https://icos.sarathfrancis.work/reset?token=…`
  (a universal link into the app; the page also works standalone).
  `POST /auth/reset-password {newPassword, token}` → 200, or 4xx `{message, code}`
  (`INVALID_TOKEN` for a bad or expired token). A reset does NOT sign the user in.
- Verification mail redirects to `https://icos.sarathfrancis.work/verified`.
- Trusted origins: `io.icos://`, `https://icos.sarathfrancis.work`,
  `https://appleid.apple.com`.
- Guest upgrade (`anonymous.onLinkAccount`): a brand-new account with no app data
  takes over the guest's profile (same app data, the guest's `profiles.id` is
  re-keyed with `ON UPDATE CASCADE`); signing in to an existing account discards
  the guest and its profile.

## Function routes

### `GET /health`
200 `{status: "ok", fn: "api", ts}`. No auth.

### `GET /api/config`
No auth. 200 `{config: {min_supported_version, latest_version, maintenance_mode, store_urls, ...}}`
(the `app_config` rows as one object, so the force-update / maintenance gate works
before a session exists). Each Function instance serves it from memory for 60 s, so an
`app_config` change can take up to a minute to show.

### `GET /api/puzzle/:date`
No auth. 200 `{puzzle}` (public columns, cacheable 5 min; found puzzles are also kept in
the Function's memory for 60 s per date, misses are not).
Errors: 400 `INVALID_DATE|DATE_OUT_OF_RANGE` (outside the archive window), 404 `PUZZLE_NOT_FOUND`.

### `POST /api/daily-puzzle`
Signed-in users may ask for today or tomorrow (UTC) only; `/cron/daily-puzzle`
generates any missing date in today … today+14.
Body: `{ "date"?: "YYYY-MM-DD" }` (default tomorrow).
200 `{status:"exists", puzzle_date, puzzle}` · 201 `{status:"created", puzzle_date, puzzle}`.
`puzzle` = public row (`id, puzzle_date, grid_size, waypoints, walls, difficulty, par_time_seconds, difficulty_score, seed_version, created_at`).
The reference solution goes to `puzzle_solutions` and is never returned.
Errors: 400 `INVALID_JSON|INVALID_DATE`, 401, 403 `DATE_NOT_ALLOWED|BANNED|DELETED`, 500 `MISSING_SEED_SALT|INSERT_FAILED|INTERNAL`.

### `POST /api/start-puzzle`
Body: `{ "puzzle_date": "YYYY-MM-DD" }` (today … today-30).
200 `{puzzle_date, nonce, started_at, already_completed}`. Idempotent: the same
nonce and the original `started_at` on repeat calls.
Errors: 400 `INVALID_JSON|INVALID_DATE|DATE_OUT_OF_RANGE`, 401, 403, 404 `PUZZLE_NOT_FOUND`.

### `POST /api/submit-score`
Body:
```json
{ "puzzle_date":"YYYY-MM-DD", "time_seconds":123, "hints_used":0, "undos_used":2,
  "path":[[0,0],[0,1]], "signature":"<hex>", "queued_at":"2026-11-08T10:00:00Z" }
```
`signature` = HMAC-SHA256 hex, key = session `nonce`, message
`${puzzle_date}|${time_seconds}|${hints_used}|${undos_used}|${sha256hex(JSON.stringify(path))}`
(path serialised as compact JSON, e.g. `[[0,0],[0,1]]`). Optional; without it the
attempt is stored `verified=false`.
Rules: date window today-30 … today (`ARCHIVE_WINDOW_DAYS` in `src/shared/http.ts`,
shared with `start-puzzle`); rate limit 40/hour (`submission_log`); path validated
with `puzzle_core.validatePath`; if a session exists, `time_seconds ≤ server_elapsed + 300`
and the signature (when given) must match; `queued_at` may not be later than now+300 s;
`is_archive` = finished after the puzzle's UTC day. A completed solve runs
`record_solve` and adds a `group_feed` entry for each of the player's groups.
200 `{completed:true, verified, is_archive, streak:{current_streak,longest_streak,freeze_count,last_solve_date}, rank_hint?}`
200 `{completed:false, verified:false, reason, streak:null}` (invalid path; attempt stored, retry allowed)
Errors: 400 `INVALID_JSON|INVALID_FIELD|DATE_OUT_OF_RANGE|CLOCK_SKEW|IMPLAUSIBLE_TIME|BAD_SIGNATURE`,
401, 403, 404 `PUZZLE_NOT_FOUND`, 409 `ALREADY_COMPLETED`, 429 `RATE_LIMITED`.

### `POST /api/join-group`
Body: `{ "invite_code": "ABC123" }`. Guests → 403 `ANONYMOUS_USER`.
200 `{group:{...full groups row}, already_member:boolean}`.
Errors: 400 `INVALID_JSON|INVALID_INVITE_CODE`, 404 `GROUP_NOT_FOUND`, 409 `GROUP_FULL|GROUP_INACTIVE|TOO_MANY_GROUPS`.

### `POST /api/report`
Body: `{ "reported_user_id" | "reported_group_id", "reason", "details"? }`,
`reason` ∈ `inappropriate_name, harassment, cheating, spam, other`.
Inserts into `reports` and emails the alert to `REPORT_ALERT_TO` (Resend; best effort).
At most 10 reports per reporter in a rolling 24 h (block notices count); the 11th gets
429 `RATE_LIMITED` (`Too many reports; try again later`), nothing is stored and no email is sent.
201 `{id}`. Errors: 400 `INVALID_JSON|INVALID_FIELD`, 401, 403, 404 `PROFILE_NOT_FOUND|GROUP_NOT_FOUND`, 429 `RATE_LIMITED`.

### `POST /api/block`, `POST /api/unblock`
Body: `{ "user_id": "<uuid>" }`.
`block` inserts into `user_blocks` (idempotent); a new block also files one
`reports` row (`reason = 'blocked_by_user'`) and sends the alert email.
200 `{blocked:true}` / `{blocked:false}` (unblock is idempotent).
Errors: 400 `INVALID_JSON|INVALID_FIELD` (missing, malformed or self), 401, 403, 404 `PROFILE_NOT_FOUND` (block only).
Effect: the leaderboard RPCs drop rows for users the caller blocked (ranks follow the
filtered set) and the `group_feed` member policy hides their entries. The blocked user
is not told; member lists are not filtered, so an admin can still remove the member.

### `POST /api/account/upgrade-email`
Guest bearer only. Body: `{ "email", "password" }` (password ≥ 6).
Sets the email and password on the guest's own id, flips `is_anonymous=false` and
sends the verification email; the session token stays valid.
200 `{user:{id, email, is_anonymous:false, email_verified:false}}`.
Errors: 400 `NOT_ANONYMOUS|INVALID_FIELD`, 401, 409 `EMAIL_EXISTS`.

### `GET|POST /api/export-data`
200 `{exported_at, user, profile, attempts, streak, streak_freezes, groups:[{...group, role, joined_at}], reports_filed, blocked_users}`
served as an attachment (`icos-export-<id>.json`). Deletion-pending accounts may
export (that is the grace period's point). Errors: 401, 403 `PROFILE_NOT_FOUND|BANNED`.

### `POST /cron/<job>`
Only Neon schedule triggers can call these: Neon strips client-set `X-Neon-*`
headers, so `X-Neon-Trigger-Invocation-Id` proves a trigger delivery (else 401
`UNAUTHORIZED`). Unknown job → 404 `UNKNOWN_JOB`.
`(job, data.scheduled_at)` is claimed in `cron_runs` first: a duplicate delivery
answers 200 `{job, ran:false}`; a run answers 200 `{job, ran:true, result}`; a
failed run frees its slot and answers 503 + `Retry-After: 300`
`{error, code:"JOB_FAILED"}` so Neon retries.

## Schedule triggers (`neon.ts`, UTC)

All nightly jobs run inside 00:00–00:26 so Postgres wakes once a day for them.

| Trigger | Cron | Path | Work |
|---|---|---|---|
| resetweeklyfreezes | `0 0 * * 1` | `/cron/reset-weekly-freezes` | `reset_weekly_freezes()`: every streak gets 1 freeze |
| applystreakfreezes | `5 0 * * *` | `/cron/apply-streak-freezes` | `apply_streak_freezes()`: spend a freeze for users who missed yesterday |
| expirestalestreaks | `10 0 * * *` | `/cron/expire-stale-streaks` | `expire_stale_streaks()`: recompute streaks whose last solve/freeze is before yesterday |
| dailypuzzle | `15 0 * * *` | `/cron/daily-puzzle` | generate every missing date in today … today+14 |
| purgedeleted | `20 0 * * *` | `/cron/purge-deleted-accounts` | `purge_deleted_accounts()` (30-day grace → anonymize), then delete the `ba."user"` rows |
| purgeanonymous | `23 0 * * *` | `/cron/purge-inactive-anonymous` | `purge_inactive_anonymous()` (guests idle 90 days) and their `ba."user"` rows |
| prunesubmissionlog | `26 0 * * *` | `/cron/prune-submission-log` | `prune_submission_log()`: drop rate-limit rows older than 1 day |

Signed-in clients can also call `/api/daily-puzzle` for today/tomorrow, so a missed
run never blocks play.

## Database RPCs (Data API `POST rpc/<name>`)

All `SECURITY DEFINER`, `search_path=''`, the caller is `app.uid()` (the JWT
`sub`); `EXECUTE` granted to `authenticated` only.

| RPC | Args | Returns |
|-----|------|---------|
| `create_group` | `p_name, p_description?` | `groups` row (creator is admin, member_count=1) |
| `remove_group_member` | `p_group_id, p_user_id` | `groups` row (also writes a `left` feed event with payload `{"removed": true}`) |
| `transfer_group_admin` | `p_group_id, p_new_admin_id` | `groups` row |
| `delete_group` | `p_group_id` | `groups` row (soft: `is_active=false`) |
| `regenerate_invite_code` | `p_group_id` | `groups` row with a new `invite_code` (admin only, `42501`/`NOT_ADMIN` otherwise; the old code stops working) |
| `leave_group` | `p_group_id` | void (admin leaving → oldest member promoted, or group deactivated; writes a `left` feed event) |
| `get_group_daily_leaderboard` | `p_group_id, p_puzzle_date` | `rank, user_id, display_name, avatar_url, time_seconds, hints_used, undos_used, completed, verified` (hints ASC, time ASC, undos ASC) |
| `get_group_weekly_leaderboard` | `p_group_id, p_week_start` | `rank, user_id, display_name, avatar_url, completed_count, avg_time_seconds, total_hints` (completed DESC, avg time ASC) |
| `list_blocked_users` | – | `user_id, display_name, blocked_at` (caller's blocks, newest first; `''` names show as `Anonymous`) |
| `request_account_deletion` / `cancel_account_deletion` | – | `profiles` row (`deleted_at` set / cleared; 30-day grace) |
| `sanitize_text` | `p_input` | text (also callable for previews) |
| `contains_profanity` | `p_input` | boolean |
| `validate_name` | `p_input, p_field?` | sanitized text, or raises `PROFANITY` / `INVALID_LENGTH` |

Blocking has no RPC: use `/api/block` / `/api/unblock`. `is_blocked_by_me(p_user_id)`
is the STABLE helper behind the leaderboard RPCs and the `group_feed` policy.
Owner-only functions (run by the Function, never granted to Data API roles):
`recompute_streak`, `record_solve`, `apply_streak_freezes`, `reset_weekly_freezes`,
`expire_stale_streaks`, `prune_submission_log`, `detach_user_from_groups`,
`purge_deleted_accounts`, `purge_inactive_anonymous`.

Deleted accounts: when `purge_deleted_accounts()` anonymizes a profile it records the
user's groups in `group_purged_members` (owner-only table) before removing their
`group_members` rows. Both leaderboard RPCs count those rows as members and render
purged profiles as `Deleted User` with no avatar, and members can read a purged former
co-member's profile so feed entries resolve to `Deleted User`. Member lists and
`member_count` do not include them.

Errors raised by RPCs carry a machine-readable `HINT` (`NOT_ADMIN`, `NOT_A_MEMBER`,
`PROFANITY`, `INVALID_LENGTH`, `ANONYMOUS_USER`, `GROUP_FULL`, …) and SQLSTATE
`42501` (permission) / `22023` (validation) / `P0002` (not found). The Data API
returns them as PostgREST's `{code, message, hint}`.

## Data API

- Every request needs a bearer JWT from `/auth/token` (no or invalid token → 400).
- RLS with `app.uid()` on every public table; role `anonymous` may only read
  `puzzles` and `app_config`. `db-max-rows 200`; schema `public` only (`ba` is not exposed).
- `profiles` is column-granted (`0006_profile_column_grants.sql`): `authenticated` may
  SELECT `id, display_name, avatar_url, is_anonymous, is_banned, colorblind_mode,
  theme_mode, haptic_enabled, sound_enabled, notification_enabled, deleted_at, purged_at,
  created_at, updated_at` and UPDATE `display_name, avatar_url, colorblind_mode,
  theme_mode, haptic_enabled, sound_enabled, notification_enabled, updated_at`.
  `email`, `email_verified`, `providers` and `last_active_at` are never readable through
  the Data API (use `/api/export-data` for your own). Any other column → `42501`.
- Clients cannot insert into `reports`; use `POST /api/report`.
- External JWKS = `<function>/auth/jwks`. Changing it needs `neon data-api delete` + `create`.

## Function environment (`.env.neon`, git-ignored; declared in `neon.ts`)

| Name | Required | Purpose |
|------|----------|---------|
| `BETTER_AUTH_SECRET` | yes | Better Auth signing/encryption secret |
| `PUZZLE_SEED_SALT` | yes | Seed salt for deterministic daily puzzles; generation fails closed (500 `MISSING_SEED_SALT`) without it. Never rotate after launch (changes every future puzzle) |
| `AUTH_BASE_URL` | no | Public Function URL (custom domain); default `https://<branch id>-api<NEON_FUNCTION_HOST_SUFFIX>` |
| `RESEND_API_KEY` | no | Auth mail and report alerts; mail is skipped when unset |
| `REPORT_ALERT_TO` | no | Recipient of report / block alerts |
| `GOOGLE_WEB_CLIENT_ID`, `GOOGLE_WEB_CLIENT_SECRET` | no | Google provider (disabled when unset) |
| `APPLE_SERVICE_ID`, `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_P8_BASE64` | no | Apple provider; the client secret is minted at boot (ES256, 180 days) |
| `DATABASE_URL`, `NEON_BRANCH_ID`, `NEON_FUNCTION_HOST_SUFFIX` | injected | Set by Neon for the Function |

Local-only (scripts and tests): `DATABASE_URL_UNPOOLED`, `DEV_DATABASE_URL_UNPOOLED`,
`NEON_TEST_DATABASE_URL` (DB-backed tests skip without it).
