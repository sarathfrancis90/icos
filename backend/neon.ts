// Neon project policy for Icos. Run every `neon` command from backend/.
//
// Free-plan guardrails: every branch is pinned to 0.25 CU so the project stays
// inside 100 CU-hours a month (the Free plan's 5-minute suspend is fixed and
// cannot be set here).
import { defineConfig } from "@neon/config/v1";

export default defineConfig({
  branch: () => ({
    postgres: {
      computeSettings: {
        autoscalingLimitMinCu: 0.25,
        autoscalingLimitMaxCu: 0.25,
      },
    },
  }),
  functions: {
    api: {
      name: "Icos API",
      source: "src/index.ts",
      env: {
        NODE_ENV: "production",
        // Required secrets (deploy fails fast when unset — never coerce to "").
        BETTER_AUTH_SECRET: { value: process.env.BETTER_AUTH_SECRET, required: true },
        PUZZLE_SEED_SALT: { value: process.env.PUZZLE_SEED_SALT, required: true },
        // Optional: public base URL of this function (custom domain). When unset the
        // code derives https://<branch>-api<host suffix> from Neon's injected vars.
        AUTH_BASE_URL: { value: process.env.AUTH_BASE_URL, required: false },
        // Optional integrations; a provider is disabled when its vars are unset.
        RESEND_API_KEY: { value: process.env.RESEND_API_KEY, required: false },
        REPORT_ALERT_TO: { value: process.env.REPORT_ALERT_TO, required: false },
        GOOGLE_WEB_CLIENT_ID: { value: process.env.GOOGLE_WEB_CLIENT_ID, required: false },
        GOOGLE_WEB_CLIENT_SECRET: { value: process.env.GOOGLE_WEB_CLIENT_SECRET, required: false },
        APPLE_SERVICE_ID: { value: process.env.APPLE_SERVICE_ID, required: false },
        APPLE_TEAM_ID: { value: process.env.APPLE_TEAM_ID, required: false },
        APPLE_KEY_ID: { value: process.env.APPLE_KEY_ID, required: false },
        APPLE_P8_BASE64: { value: process.env.APPLE_P8_BASE64, required: false },
      },
    },
  },
  // Nightly jobs (design §8), all inside 00:00-00:26 UTC so Postgres wakes
  // once a day for them. Each POSTs to the API's /cron/<job> route.
  triggers: {
    resetweeklyfreezes: { type: "schedule", function: "api", cron: "0 0 * * 1", functionPath: "/cron/reset-weekly-freezes" },
    applystreakfreezes: { type: "schedule", function: "api", cron: "5 0 * * *", functionPath: "/cron/apply-streak-freezes" },
    expirestalestreaks: { type: "schedule", function: "api", cron: "10 0 * * *", functionPath: "/cron/expire-stale-streaks" },
    dailypuzzle: { type: "schedule", function: "api", cron: "15 0 * * *", functionPath: "/cron/daily-puzzle" },
    purgedeleted: { type: "schedule", function: "api", cron: "20 0 * * *", functionPath: "/cron/purge-deleted-accounts" },
    purgeanonymous: { type: "schedule", function: "api", cron: "23 0 * * *", functionPath: "/cron/purge-inactive-anonymous" },
    prunesubmissionlog: { type: "schedule", function: "api", cron: "26 0 * * *", functionPath: "/cron/prune-submission-log" },
  },
});
