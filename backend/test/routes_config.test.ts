// GET /api/config (no auth) against the Neon `test` branch.
// Skips without NEON_TEST_DATABASE_URL.
//
// Puzzle dates owned by this file: none (reads the seeded app_config rows only).
import { after, before, describe, test } from "node:test";
import assert from "node:assert/strict";
import { setupApi, SKIP, type ApiHarness } from "./helpers/api.js";

describe("config route", { skip: SKIP }, () => {
  let h: ApiHarness;

  before(async () => {
    h = await setupApi();
  });
  after(async () => {
    await h?.close();
  });

  test("200 with the four seeded keys and values, without a session, cacheable", async () => {
    const { res, json } = await h.call("GET", "/api/config");
    assert.equal(res.status, 200, JSON.stringify(json));
    assert.equal(res.headers.get("cache-control"), "public, max-age=300");
    assert.deepEqual(json, {
      config: {
        latest_version: "1.1.0",
        maintenance_mode: false,
        min_supported_version: "1.1.0",
        store_urls: {
          ios: "https://apps.apple.com/app/id6810895361",
          android: "https://play.google.com/store/apps/details?id=com.icos.game",
        },
      },
    });
  });

  test("405 for POST", async () => {
    const { res, json } = await h.call("POST", "/api/config", {});
    assert.equal(res.status, 405);
    assert.equal(json?.code, "METHOD_NOT_ALLOWED");
  });
});
