// Pure identity helpers (no database).
import { describe, test } from "node:test";
import assert from "node:assert/strict";
import { Hono } from "hono";
import { placeholderName, providerDisplayName, requireSession, type SessionSource } from "../src/identity.js";

describe("providerDisplayName", () => {
  test("uses the provider's name", () => {
    assert.equal(providerDisplayName("Jane Doe", "jane@example.com"), "Jane Doe");
    assert.equal(providerDisplayName("  Jane Doe  ", null), "Jane Doe");
  });

  test("falls back to the email's local part, tidied up", () => {
    assert.equal(providerDisplayName(null, "jane.doe+x@example.com"), "Jane Doe X");
    assert.equal(providerDisplayName("   ", "JANE_DOE@example.com"), "Jane Doe");
    assert.equal(providerDisplayName(null, "a--b..c@example.com"), "A B C");
  });

  test("never derives a name from an Apple relay address", () => {
    assert.equal(providerDisplayName(null, "abc@privaterelay.appleid.com"), null);
    assert.equal(providerDisplayName(null, "k3x9q2@PrivateRelay.AppleID.com"), null);
  });

  test("returns null with nothing to go on", () => {
    assert.equal(providerDisplayName(null, null), null);
    assert.equal(providerDisplayName("", "not-an-email"), null);
    assert.equal(providerDisplayName(null, "@example.com"), null);
    assert.equal(providerDisplayName(null, "...@example.com"), null);
  });

  test("caps the name at 30 characters", () => {
    const long = "A".repeat(40);
    assert.equal(providerDisplayName(long, null), "A".repeat(30));
    assert.equal(providerDisplayName(null, `${"b".repeat(40)}@example.com`)?.length, 30);
  });
});

describe("placeholderName", () => {
  test("is Player NNNN", () => {
    for (let i = 0; i < 200; i++) assert.match(placeholderName(), /^Player \d{4}$/);
  });
});

describe("requireSession", () => {
  function appWith(source: SessionSource) {
    const app = new Hono();
    app.get("/api/me", async (c) => c.json(await requireSession(c, source)));
    return app;
  }

  test("returns the signed-in user", async () => {
    let seen: Headers | undefined;
    const app = appWith({
      api: {
        getSession: async ({ headers }) => {
          seen = headers;
          return { user: { id: "u1", email: "a@example.com", isAnonymous: false } };
        },
      },
    });
    const res = await app.request("/api/me", { headers: { authorization: "Bearer t" } });
    assert.equal(res.status, 200);
    assert.deepEqual(await res.json(), { id: "u1", email: "a@example.com", isAnonymous: false });
    assert.equal(seen?.get("authorization"), "Bearer t");
  });

  test("hides a guest's placeholder email", async () => {
    const app = appWith({
      api: { getSession: async () => ({ user: { id: "g1", email: "g1@anonymous.placeholder.invalid", isAnonymous: true } }) },
    });
    assert.deepEqual(await (await app.request("/api/me")).json(), { id: "g1", email: null, isAnonymous: true });
  });

  test("401 in the API error shape without a session", async () => {
    const res = await appWith({ api: { getSession: async () => null } }).request("/api/me");
    assert.equal(res.status, 401);
    assert.deepEqual(await res.json(), { error: "Not signed in", code: "UNAUTHORIZED" });
    assert.ok(res.headers.get("x-correlation-id"));
  });

  test("a failing session lookup is not reported as signed out", async () => {
    const app = appWith({ api: { getSession: async () => Promise.reject(new Error("db down")) } });
    app.onError((_err, c) => c.json({ error: "internal" }, 500));
    assert.equal((await app.request("/api/me")).status, 500);
  });
});
