# Icos Supabase backend

Postgres schema (migrations), Deno edge functions, pg_cron jobs and an RLS smoke
test. Design contract: `docs/superpowers/specs/2026-09-09-production-readiness-design.md`
sections 3.2 / 3.3.

## Layout

```
supabase/
├── config.toml            # local stack (ports 643xx) + per-function verify_jwt
├── seed.sql               # local seed: app_config defaults only
├── migrations/            # additive; never edit a shipped migration
├── functions/
│   ├── import_map.json    # npm:@supabase/supabase-js pin
│   ├── deno.json          # points deno at the import map (for `deno check`)
│   ├── _shared/http.ts    # cors, json(), Logger, getUser, requireServiceRole, banCheck
│   ├── _shared/puzzle_core.ts  # generator / validator (mirrors the Dart port)
│   ├── daily-puzzle/ submit-score/ join-group/ start-puzzle/ export-data/
└── tests/rls_smoke.sql    # policy assertions, local only
```

## Run locally

```bash
supabase start                 # first run pulls images; ports are 64321 (API) / 64322 (db)
supabase db reset              # applies every migration + seed.sql
supabase status                # prints URL, keys, DATABASE_URL

# RLS smoke test (inserts into auth.users -> LOCAL ONLY). psql is not required:
docker exec -i supabase_db_icos psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
  < supabase/tests/rls_smoke.sql
# or, with psql installed:
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/rls_smoke.sql

# Type-check / test the edge functions
cd supabase/functions
for f in daily-puzzle submit-score join-group start-puzzle export-data; do deno check --config deno.json $f/index.ts; done
deno test --config deno.json _shared/

supabase stop
```

To exercise functions locally, put secrets in `supabase/functions/.env`
(git-ignored) and run `supabase functions serve --env-file supabase/functions/.env`,
or add them under `[edge_runtime.secrets]` in `config.toml`.

## Secrets

| Where | Name | Purpose |
|-------|------|---------|
| Edge function secret (`supabase secrets set`) | `PUZZLE_SEED_SALT` | Seed salt for deterministic daily puzzles. **Required**; `daily-puzzle` fails closed (500 `MISSING_SEED_SALT`) without it. Never rotate after launch (changes every future puzzle). |
| Edge function env (injected automatically) | `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` | Used by `_shared/http.ts`. |
| Vault (`vault.create_secret`) | `service_role_key` | Bearer used by the pg_cron job to call `daily-puzzle`. |
| Vault | `project_url` | `https://<ref>.supabase.co` — the cron job reads it from Vault (no hard-coded URL). |

```sql
select vault.create_secret('https://<ref>.supabase.co', 'project_url');
select vault.create_secret('<service role key>', 'service_role_key');
```

```bash
supabase secrets set PUZZLE_SEED_SALT="$(openssl rand -hex 32)"
```

## Deploy

```bash
supabase link --project-ref <ref>
supabase db push                                  # migrations
supabase functions deploy daily-puzzle submit-score join-group start-puzzle export-data
# verify_jwt per function comes from config.toml (daily-puzzle = false: it authenticates itself)
```

After the first deploy, backfill today + tomorrow once:

```bash
curl -X POST "$PROJECT_URL/functions/v1/daily-puzzle" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" -H "Content-Type: application/json" \
  -d '{"date":"2026-09-10"}'
```

## Cron (pg_cron, all UTC)

| Job | Schedule | Function |
|-----|----------|----------|
| reset-weekly-freezes | `0 0 * * 1` | `reset_weekly_freezes()` — every streak gets 1 freeze |
| apply-streak-freezes | `5 0 * * *` | `apply_streak_freezes()` — spend a freeze for users who missed yesterday |
| generate-daily-puzzle | `15 0 * * *` | `trigger_daily_puzzle_generation()` — POSTs `{date}` for D+1 and D+2 |
| purge-deleted-accounts | `0 1 * * *` | `purge_deleted_accounts()` — 30-day grace → anonymize |
| purge-inactive-anonymous | `30 1 * * *` | `purge_inactive_anonymous()` — delete guests idle 90 days |
| prune-submission-log | `0 2 * * *` | `prune_submission_log()` — drop rate-limit rows older than 1 day |

Clients can also call `daily-puzzle` for today/tomorrow, so a missed cron run
never blocks play.

## Edge function contracts

All responses are JSON, carry `x-correlation-id` (echoed from the request header
or generated), and log one structured JSON line per event
(`{ts, level, fn, correlation_id, msg, ...}`). Every function answers
`GET /health` → `{status:"ok"}` and rejects banned / deletion-pending profiles with
403 `BANNED` / `DELETED`. Errors are `{error, code}`.

### `POST /daily-puzzle` — verify_jwt=false (self-authenticating)
Auth: `Authorization: Bearer <service role key>` (any date) **or** user JWT (today/tomorrow only).
Body: `{ "date"?: "YYYY-MM-DD" }` (default tomorrow).
200 `{status:"exists", puzzle_date, puzzle}` · 201 `{status:"created", puzzle_date, puzzle}`
`puzzle` = public row (`id, puzzle_date, grid_size, waypoints, walls, difficulty, par_time_seconds, difficulty_score, seed_version, created_at`). The solution is never returned.
Errors: 400 `INVALID_JSON|INVALID_DATE`, 401, 403 `DATE_NOT_ALLOWED|BANNED|DELETED`, 500 `MISSING_SEED_SALT|INSERT_FAILED|INTERNAL`.

### `POST /start-puzzle`
Body: `{ "puzzle_date": "YYYY-MM-DD" }` (today … today-30).
200 `{puzzle_date, nonce, started_at, already_completed}` — idempotent: same nonce and original `started_at` on repeat calls.
Errors: 400 `INVALID_JSON|INVALID_DATE|DATE_OUT_OF_RANGE`, 401, 403, 404 `PUZZLE_NOT_FOUND`.

### `POST /submit-score`
Body:
```json
{ "puzzle_date":"YYYY-MM-DD", "time_seconds":123, "hints_used":0, "undos_used":2,
  "path":[[0,0],[0,1]], "signature":"<hex>", "queued_at":"2026-09-09T10:00:00Z" }
```
`signature` = HMAC-SHA256 hex, key = session `nonce`, message
`${puzzle_date}|${time_seconds}|${hints_used}|${undos_used}|${sha256hex(JSON.stringify(path))}`
(path serialised as compact JSON, e.g. `[[0,0],[0,1]]`). Optional; without it the attempt is stored `verified=false`.
Rules: date window today-7…today; rate limit 10/hour (`submission_log`); path validated with `validatePath`;
if a session exists: `time_seconds ≤ server_elapsed + 300` and signature (when given) must match;
`queued_at` may not be > now+300s; `is_archive` = finished after the puzzle's UTC day.
200 `{completed:true, verified, is_archive, streak:{current_streak,longest_streak,freeze_count,last_solve_date}, rank_hint?}`
200 `{completed:false, verified:false, reason, streak:null}` (invalid path; attempt stored, retry allowed)
Errors: 400 `INVALID_JSON|INVALID_FIELD|DATE_OUT_OF_RANGE|CLOCK_SKEW|IMPLAUSIBLE_TIME|BAD_SIGNATURE`,
401, 403, 404 `PUZZLE_NOT_FOUND`, 409 `ALREADY_COMPLETED`, 429 `RATE_LIMITED`.

### `POST /join-group`
Body: `{ "invite_code": "ABC123" }`. Anonymous users → 403 `ANONYMOUS_USER`.
200 `{group:{...full groups row}, already_member:boolean}`.
Errors: 400 `INVALID_JSON|INVALID_INVITE_CODE`, 404 `GROUP_NOT_FOUND`, 409 `GROUP_FULL|GROUP_INACTIVE|TOO_MANY_GROUPS`.

### `GET|POST /export-data`
200 `{exported_at, user, profile, attempts, streak, streak_freezes, groups:[{...group, role, joined_at}], reports_filed}`
(served as an attachment). Deletion-pending accounts may export.

## Database RPCs (PostgREST `rpc/…`, all `SECURITY DEFINER`, `search_path=''`)

| RPC | Args | Returns |
|-----|------|---------|
| `create_group` | `p_name, p_description` | `groups` row (creator is admin, member_count=1) |
| `update_group` | `p_group_id, p_name?, p_description?` | `groups` row |
| `remove_group_member` | `p_group_id, p_user_id` | `groups` row |
| `transfer_group_admin` | `p_group_id, p_new_admin_id` | `groups` row |
| `delete_group` | `p_group_id` | `groups` row (soft: `is_active=false`) |
| `leave_group` | `p_group_id` | void (admin leaving → oldest member promoted, or group deactivated) |
| `decrement_group_member_count` | `p_group_id` | void (compat shim: resyncs the trigger-maintained count) |
| `get_group_daily_leaderboard` | `p_group_id, p_puzzle_date` | `rank, user_id, display_name, avatar_url, time_seconds, hints_used, undos_used, completed, verified` |
| `get_group_weekly_leaderboard` | `p_group_id, p_week_start` | `rank, user_id, display_name, avatar_url, completed_count, avg_time_seconds, total_hints` |
| `request_account_deletion` / `cancel_account_deletion` | – | `profiles` row |
| `sanitize_text` | `p_input` | text (also callable from clients for previews) |

Errors raised by RPCs carry a machine-readable `HINT` (`NOT_ADMIN`, `NOT_A_MEMBER`,
`PROFANITY`, `INVALID_LENGTH`, `ANONYMOUS_USER`, `GROUP_FULL`, …) and SQLSTATE
`42501` (permission) / `22023` (validation) / `P0002` (not found).
