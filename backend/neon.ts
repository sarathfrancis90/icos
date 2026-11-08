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
