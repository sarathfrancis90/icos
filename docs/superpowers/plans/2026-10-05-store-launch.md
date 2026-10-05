# Icos Public Store Launch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Take Icos from "rejected on the App Store, closed testing on Play" to publicly released on both stores, with a backend that generates puzzles unattended and no known errors.

**Architecture:** One orchestrator session (planning, review, every outward-facing action) plus cheaper subagents for independent, well-scoped tasks. Work is split into five phases; Phase 1 tasks run in parallel, later phases are gated on the earlier ones. Nothing is submitted, released, or written to a secrets store without the owner's explicit yes at the gates listed below.

**Tech Stack:** Flutter 3.41.3 (`.fvmrc`), Supabase (project ref `pdvgddvubxldjnemdkok`), Deno edge functions, GitHub Actions, fastlane (`ios/fastlane`, `android/fastlane`), `scripts/asc.py`, `scripts/play.py`, Maestro (`.maestro/flows`).

**Spec:** `docs/superpowers/specs/2026-09-09-production-readiness-design.md`, `docs/RELEASE_RUNBOOK.md`

## Verified state on 2026-10-05

| Area | State | Evidence |
|---|---|---|
| Code | `1.0.0+4`, `flutter analyze` clean, 579 tests pass | run locally today |
| App Store | Version 1.0 **REJECTED**; review submission `0238efce…` is `UNRESOLVED_ISSUES` | `scripts/asc.py get /v1/apps/6810895361/appStoreVersions` |
| Rejection reason | **Unknown** — Apple does not expose Resolution Center text through the API | needs a signed-in browser |
| Google Play | Version code 4 on Internal and Closed testing; Open testing and Production empty | `scripts/play.py` tracks read |
| Play production access | **Unknown** — new personal developer accounts must run a closed test with 12 testers for 14 days first | needs Play Console |
| Nightly puzzle cron | Runs, but `daily-puzzle` answers `401 Unauthorized` | `net._http_response` |
| GitHub puzzle workflow | Failed 24 of 24 runs: no repo secrets, and the command omits the required `--from` | `gh run view 37269404931 --log-failed` |
| Puzzles in DB | 2026-09-08 → 2026-09-24. The app requests today's puzzle on demand when the row is missing, so players are not blocked; the gap is days nobody played | `daily-puzzle/index.ts:103`, `daily_puzzle_provider` |
| Migration `20260913000001_display_name_from_provider.sql` | In repo, **not applied** to the live DB | `supabase_migrations.schema_migrations` |
| Commit `08867e3` (sign-in fixes) | Not in any uploaded build | committed after build 4 |
| `app_config.store_urls` | `{}` — the force-update screen has nowhere to send people | live table |
| `docs/.well-known/assetlinks.json` | Still contains `REPLACE_WITH_PLAY_APP_SIGNING_SHA256` | grep |
| Email confirmations | Off (`supabase/config.toml:207`) | file |
| Supabase security advisor | Leaked-password protection off; `decrement_group_member_count` callable by any signed-in user | advisor run today |
| Sign-in providers | Google and Apple configured | `scripts/check_signin.py` |

## Global Constraints

- Product name is **Icos** everywhere; never reintroduce the old names.
- Migrations are additive: never edit a shipped file under `supabase/migrations/`.
- Repositories return `Result<T, AppError>`; no `print()`; strings through ARB; `EdgeInsetsDirectional`.
- `puzzle_core.ts` and the Dart solver stay in sync; `fixtures/puzzle_parity.json` must pass.
- Secrets are never printed, committed, or pasted into chat. They move from `supabase/functions/.env` straight into the destination with a pipe.
- Flutter builds use JDK 17; iOS builds need `pod install` after plugin changes.

## Owner gates (the only points that need a human)

| Gate | What the owner does | Blocks |
|---|---|---|
| G1 | Sign in to App Store Connect in the browser pane so the rejection text can be read | Phase 2 |
| G2 | Sign in to Play Console so production-access status can be read | Phase 4 timeline |
| G3 | Say yes to copying three secrets into GitHub repo secrets and re-setting the Vault key | Tasks 1, 2 |
| G4 | Give a real phone number for App Review contact | Task 12 |
| G5 | Say yes to each store submission, and later to each public release | Tasks 12, 13, 14 |
| G6 | If Play demands the 12-tester closed test: recruit testers (cannot be automated) | Play production |

---

## Phase 1 — Backend hardening (parallel, one subagent each, Sonnet)

### Task 1: Make the nightly cron authenticate

**Files:**
- Create: `supabase/migrations/20261005000001_cron_auth_check.sql`
- Modify: `docs/RELEASE_RUNBOOK.md` (status block)

**Interfaces:**
- Produces: SQL function `public.daily_puzzle_cron_health()` returning `(last_status int, last_run timestamptz, days_ahead int)`, used by Task 2's workflow check.

- [ ] **Step 1: Find why the key is rejected, without reading it.** Compare digests only:

```sql
select length(decrypted_secret) as len,
       encode(extensions.digest(decrypted_secret, 'sha256'), 'hex') as sha
from vault.decrypted_secrets where name = 'service_role_key';
```

```bash
grep '^SUPABASE_SERVICE_ROLE_KEY=' supabase/functions/.env | cut -d= -f2- | tr -d '\n' | shasum -a 256
```

Different digests mean the Vault entry is stale (go to Step 2). Identical digests mean the function's own `SUPABASE_SERVICE_ROLE_KEY` differs from the legacy JWT (the project has moved to new-style API keys); in that case set a dedicated function secret `CRON_SERVICE_KEY` to the same value and make `requireServiceRole` in `supabase/functions/_shared/http.ts` accept either.

- [ ] **Step 2 (after G3): Reset the Vault entry from the local env file.**

```bash
KEY=$(grep '^SUPABASE_SERVICE_ROLE_KEY=' supabase/functions/.env | cut -d= -f2-)
psql "$SUPABASE_DB_URL" -v key="$KEY" -c "select vault.update_secret((select id from vault.secrets where name='service_role_key'), :'key');"
```

- [ ] **Step 3: Add the health function.**

```sql
create or replace function public.daily_puzzle_cron_health()
returns table (last_status int, last_run timestamptz, days_ahead int)
language sql security definer set search_path = '' as $$
  select
    (select r.status_code from net._http_response r order by r.created desc limit 1),
    (select max(r.created) from net._http_response r),
    (select coalesce(max(p.puzzle_date) - (now() at time zone 'utc')::date, -1) from public.puzzles p);
$$;
revoke all on function public.daily_puzzle_cron_health() from public, anon, authenticated;
```

- [ ] **Step 4: Verify.** Run `select public.trigger_daily_puzzle_generation();`, wait 30 s, then `select * from public.daily_puzzle_cron_health();`. Expected: `last_status = 200`, `days_ahead >= 1`.
- [ ] **Step 5: Commit** `Fix the nightly puzzle cron's rejected key and add a health check`.

### Task 2: Fix the GitHub puzzle workflow and make it the alarm

**Files:**
- Modify: `.github/workflows/puzzles.yml`

- [ ] **Step 1: Replace the run step** so it passes `--from` and fails loudly when secrets are absent:

```yaml
        run: |
          test -n "$SUPABASE_URL" && test -n "$SUPABASE_SERVICE_ROLE_KEY" && test -n "$PUZZLE_SEED_SALT" \
            || { echo "::error::Repo secrets SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY / PUZZLE_SEED_SALT are not set"; exit 1; }
          deno run -A scripts/generate_puzzles.ts daily \
            --from "$(date -u +%F)" \
            --days "${{ inputs.days || '14' }}" \
            --salt "$PUZZLE_SEED_SALT"
```

- [ ] **Step 2 (after G3): Set the three repo secrets** without echoing them:

```bash
for k in SUPABASE_URL SUPABASE_SERVICE_ROLE_KEY PUZZLE_SEED_SALT; do
  grep "^$k=" supabase/functions/.env | cut -d= -f2- | tr -d '\n' | gh secret set "$k"
done
```

- [ ] **Step 3: Verify.** `gh workflow run puzzles.yml`, then `gh run watch`. Expected: success, and `select max(puzzle_date) from puzzles` is today + 13.
- [ ] **Step 4: Backfill the gap** so the archive has no holes: `deno run -A scripts/generate_puzzles.ts daily --from 2026-09-25 --days 11 --salt "$PUZZLE_SEED_SALT"` with the same env. Expected: `select count(*) from puzzles where puzzle_date between '2026-09-08' and current_date` equals the number of days in that range.
- [ ] **Step 5: Commit** `Puzzle workflow: pass --from, fail clearly without secrets`.

### Task 3: Apply the pending migration and repair migration history

**Files:** none changed; `supabase/migrations/20260913000001_display_name_from_provider.sql` is applied as is.

- [ ] **Step 1:** Apply the file through the Supabase MCP `apply_migration` (name `display_name_from_provider`).
- [ ] **Step 2: Verify the backfill.** `select count(*) from profiles p join auth.users u on u.id = p.id where u.is_anonymous is not true and p.display_name ~ '^Player \d+$' and u.raw_user_meta_data ? 'full_name';` Expected: `0`.
- [ ] **Step 3:** `supabase link --project-ref pdvgddvubxldjnemdkok`, then `supabase migration repair --status applied <version>` for each local file, then `supabase migration list`. Expected: every local version shows as applied remotely.

### Task 4: Close the security-advisor findings that are real

**Files:**
- Create: `supabase/migrations/20261005000002_advisor_hardening.sql`
- Modify: `supabase/config.toml` (`[auth.email] enable_confirmations = true`, password `min_length`/HIBP setting)

- [ ] **Step 1: Write the migration.** `decrement_group_member_count` is trigger-internal and must not be an RPC:

```sql
revoke execute on function public.decrement_group_member_count(uuid) from public, anon, authenticated;
```

The other 13 `SECURITY DEFINER` warnings are the documented client RPCs (`create_group`, `leave_group`, leaderboards, account deletion) and stay as they are; `is_group_member` and `shares_group_with` are used inside RLS policies and stay.

- [ ] **Step 2: Add a regression test** in `supabase/tests/` (or the existing SQL test location; follow what is there) asserting `has_function_privilege('authenticated', 'public.decrement_group_member_count(uuid)', 'execute')` is false.
- [ ] **Step 3: Email.** Turn confirmations on only after custom SMTP is configured (Supabase's built-in sender is limited to a few mails per hour). Configure SMTP through Resend for `sarathfrancis.work`, send a test sign-up, confirm the link opens `io.supabase.icos://login-callback`. If the domain cannot be verified this week, leave confirmations off and record that in the runbook rather than shipping a sign-up that cannot send mail.
- [ ] **Step 4:** Enable leaked-password protection (Auth settings). Re-run the security advisor. Expected: neither the leaked-password warning nor `decrement_group_member_count` appears.
- [ ] **Step 5: Commit** `Revoke a trigger helper from clients; turn on email confirmations`.

### Task 5: Full-surface audit for "no errors" (three read-only subagents in parallel, Haiku/Sonnet)

No files changed; each returns a findings list with `file:line` and a reproduction.

- [ ] **Agent A — edge functions:** run `deno test supabase/functions/`, read the last 7 days of edge-function and Postgres logs through the Supabase MCP, list every 4xx/5xx by function and cause.
- [ ] **Agent B — client error paths:** for each repository under `lib/features/*/data/`, confirm every call returns `Result` and every provider consumer has an `error:` branch with retry; list violations.
- [ ] **Agent C — store compliance:** check `ios/Runner/PrivacyInfo.xcprivacy`, `Info.plist` usage strings, account deletion reachable in-app, Sign in with Apple parity, `docs/privacy-policy.html` against what the app collects; list anything App Review commonly rejects (guidelines 2.1, 4.8, 5.1.1).
- [ ] **Orchestrator:** triage findings into "fix before build 5" and "not a defect"; fold the fixes into Task 7.

---

## Phase 2 — Understand and fix the rejection (orchestrator, after G1)

### Task 6: Read the rejection

- [ ] **Step 1:** Open `https://appstoreconnect.apple.com/apps/6810895361/distribution` in the browser pane; the owner signs in. Read the App Review message and any attached screenshots. Record the guideline numbers and Apple's exact reproduction steps in `docs/RELEASE_RUNBOOK.md` under section 0b.
- [ ] **Step 2:** Reproduce each cited issue on the iOS simulator with build 4's commit (`fcfae07`) and again on `main`. Commit `08867e3` already fixes three sign-in defects (no route for returning users, Google conflict dead end, placeholder display name); note which rejection items it already covers.

### Task 7: Fix what is left (one subagent per defect, TDD)

Scope is set by Task 6 and Task 5. Each fix follows `superpowers:test-driven-development`: failing widget or unit test first, minimal change, `flutter analyze && flutter test` green, one commit per defect. The orchestrator reviews every diff before it lands.

---

## Phase 3 — Release candidate (orchestrator)

### Task 8: Build 5

**Files:** `pubspec.yaml` (`version: 1.0.0+5`)

- [ ] `flutter analyze` → `No issues found!`
- [ ] `flutter test` → all pass
- [ ] `deno test supabase/functions/` → all pass, including the parity fixture
- [ ] Commit `Bump to 1.0.0+5`, push, CI green.

### Task 9: Device verification against the live backend

- [ ] iOS simulator (iPhone and iPad) and Android emulator: run every flow in `.maestro/flows` one device at a time.
- [ ] Manually exercise on each platform what Maestro cannot: Google sign-in, Apple sign-in, guest → account link, sign out → fresh guest, delete account, join group by code, offline solve then reconnect and sync.
- [ ] Confirm the leaderboard shows the provider display name, not `Player NNNN`.
- [ ] Any failure goes back to Task 7. No submission until this task is fully green.

---

## Phase 4 — Submit (orchestrator, each step behind G5)

### Task 10: Upload

- [ ] `cd ios && bundle exec fastlane beta` → build 5 processed in TestFlight.
- [ ] `cd android && bundle exec fastlane internal`, then `closed` → version code 5 on both tracks.

### Task 11: Deep links

- [ ] Read the Play App Signing SHA-256 from Play Console > Setup > App signing; replace `REPLACE_WITH_PLAY_APP_SIGNING_SHA256` in `docs/.well-known/assetlinks.json`; push.
- [ ] `curl -s https://icos.sarathfrancis.work/.well-known/assetlinks.json | python3 -m json.tool` shows the fingerprint; `adb shell pm get-app-links com.icos.game` reports `verified`.

### Task 12: App Store resubmission

- [ ] Set the real review phone number (G4) through `scripts/asc.py`.
- [ ] Attach build 5 to version 1.0, reply in Resolution Center with one line per cited issue and how to see the fix, submit.
- [ ] Check state daily: `python3 scripts/asc.py get /v1/apps/6810895361/appStoreVersions`. A new rejection loops back to Task 6.

### Task 13: Play production

- [ ] If G2 shows production access is already granted: `bundle exec fastlane promote_to_production from:beta`, 20% staged rollout, submit for review.
- [ ] If Play requires the closed test: this is a 14-day wait with 12 opted-in testers (G6). Keep build 5 on Closed testing, apply for production access the day the requirement is met, then promote.

---

## Phase 5 — Go public and keep it up

### Task 14: Release (G5)

- [ ] App Store: after `PENDING_DEVELOPER_RELEASE`, release version 1.0.
- [ ] Play: raise the rollout 20% → 50% → 100% over three days if the crash-free rate holds.
- [ ] Set `app_config.store_urls` to the two live store URLs; confirm the force-update screen's button opens them.
- [ ] Add the store badges and links to `docs/index.html`.

### Task 15: Close the loop

- [ ] Watch for seven days: `daily_puzzle_cron_health()`, the puzzle workflow, edge-function error rate, store crash reports.
- [ ] Update `docs/RELEASE_RUNBOOK.md` status blocks, the `CLAUDE.md` "Last Updated" line, and mark `_bmad-output/implementation-artifacts/sprint-status.yaml` stories done to match what shipped.

## What cannot be promised

- Review outcomes and timing belong to Apple and Google; the plan loops on rejection instead of assuming approval.
- If Play enforces the 12-tester rule, Android cannot go public in under two weeks regardless of code readiness.
- Firebase (analytics, Crashlytics) is still unconfigured and stays optional; without it, crash visibility after launch is limited to the stores' own reports.
