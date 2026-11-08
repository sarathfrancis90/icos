# Icos backend on Neon

Everything server-side for Icos runs in one Neon project on the Free plan:
Lakebase Postgres, one Neon Function (`api`), the PostgREST-compatible Data
API, and schedule triggers. Run every `neon` command from this directory;
`.neon` (git-ignored) links it to the project.

| Item | Value |
|---|---|
| Project | `icos` (`plain-wind-90305415`), `aws-us-east-1`, org `org-twilight-king-98704418` |
| Branches | `main` (production), `dev`, `test` |
| Function `api` (main) | `https://br-crimson-bird-bbpbnst1-api.compute.c-15.us-east-1.aws.neon.tech/` |
| Data API (main) | `https://ep-shiny-morning-bbkdox4x.apirest.c-15.us-east-1.aws.neon.tech/neondb/rest/v1` |
| Data API (dev / test) | `https://ep-soft-morning-bb0psfhw.apirest…/neondb/rest/v1` / `https://ep-royal-wildflower-bbmk73ms.apirest…/neondb/rest/v1` (same JWKS) |
| Data API auth | external JWKS = `<function>/auth/jwks` (ES256, Better Auth), `db-max-rows 200`, schema `public` |
| Compute | pinned 0.25 CU min/max on every branch (`neon.ts`); Free plan suspends after 5 min |

## Layout

- `neon.ts` — project policy: compute pins, the `api` function, schedule triggers, Data API.
- `src/index.ts` — Hono app: `/health`, `/auth/*` (Better Auth), `/api/*`, `/cron/*`.
- `migrations/*.sql` — 0001_schema … 0006_profile_column_grants, applied in order by `npm run migrate -- --url <unpooled url>`.
- `scripts/` — migrate, seed, smoke, puzzle generation; `auth_cli.ts` is the Better Auth CLI config behind `npm run auth:generate` (DDL only; deploys apply `migrations/0004_better_auth.sql`).
- `test/` — `npm test` (`node --test` via tsx). DB-backed tests need `NEON_TEST_DATABASE_URL`.

## Environment (`.env.neon`, git-ignored)

Pulled by `neon env pull --file .env.neon`: `DATABASE_URL`, `DATABASE_URL_UNPOOLED`,
`NEON_BRANCH`, `NEON_BRANCH_ID`, `NEON_FUNCTION_HOST_SUFFIX`. Added by hand:
`DEV_DATABASE_URL_UNPOOLED`, `NEON_TEST_DATABASE_URL`, and the Function secrets
declared in `neon.ts` (`BETTER_AUTH_SECRET`, `PUZZLE_SEED_SALT`, `GOOGLE_*`,
`APPLE_*`, `RESEND_API_KEY`, `REPORT_ALERT_TO`). Never commit this file.

## Commands

```bash
neon status                      # live config of the linked branch
neon config plan                 # dry run
neon deploy --env .env.neon -y   # apply neon.ts (function + triggers + pins)
neon functions get api           # URL and status
neon data-api refresh-schema --database neondb   # after every migration
neon logs query --source function --service-name neon-function/api --since 1h
neon checkout dev                # switch the linked branch (pulls its env)
```

## Data API facts (verified on dev, 2026-11-08)

- Every request needs a bearer JWT: a call without one gets **400** "missing authentication
  credentials", and an invalid or expired token also gets **400** (not 401). The app therefore
  always sends the session JWT, and the unauthenticated needs (app_config gate, today's puzzle
  before the guest session exists) use the public Function routes `GET /api/config` and
  `GET /api/puzzle/:date`.
- With a guest JWT: RLS returns only the caller's own `profiles` row; `Prefer: count=exact`
  yields `Content-Range` (206); RPCs return PostgREST's `{code, message, hint}` shape with the
  SQL HINT codes the app maps (42501 → 403); embeds such as `group_members?select=id,profiles(display_name,avatar_url)` parse.
- Changing the JWKS URL needs `neon data-api delete` + `create` (`update` has no JWKS flag).
- The Function URL differs per branch, so the Data API is managed per branch with the CLI, not in `neon.ts`.
- A forged `X-Neon-Trigger-Invocation-Id` header is stripped by Neon: `/cron/*` returns 401.

## Scripts

```bash
npm run seed:puzzles -- --url <unpooled url> --from 2026-11-01 --days 46   # needs PUZZLE_SEED_SALT
npm run smoke -- --api https://<function host>/ [--date YYYY-MM-DD]          # needs PUZZLE_SEED_SALT
```

## Notes

- Custom domains: `neon config plan` accepts `customDomains: ["api.icos.sarathfrancis.work"]`
  on this plan; applying it needs the owner's CNAME first (see the migration plan, Task 14).
- The Free plan rejects `suspendTimeout` (HTTP 412); the default 5 minutes applies.
