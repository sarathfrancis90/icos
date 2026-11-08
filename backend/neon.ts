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
});
