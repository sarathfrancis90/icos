// Browser CORS for the website (no DB): docs/reset.html on the site origin
// POSTs JSON to /auth/reset-password, so its preflight must succeed, other
// origins must not be allowed, and the app (no Origin header) is unaffected.
import { describe, test } from "node:test";
import assert from "node:assert/strict";
import type { Auth } from "../src/auth.js";
import { createApp, WEB_ORIGIN } from "../src/index.js";
import { SilentLogger } from "./helpers/api.js";

/** A Better Auth stand-in whose handler records what reached it. */
function stubApp() {
  const seen: { method: string; path: string; body: string; contentType: string | null }[] = [];
  const auth = {
    handler: async (req: Request) => {
      seen.push({
        method: req.method,
        path: new URL(req.url).pathname,
        body: await req.text(),
        contentType: req.headers.get("content-type"),
      });
      return new Response(JSON.stringify({ status: true }), { headers: { "content-type": "application/json" } });
    },
    api: { getSession: async () => null },
  } as unknown as Auth;
  const app = createApp(() => auth, { logger: (fn, cid) => new SilentLogger(fn, cid) });
  return { app, seen };
}

function preflight(origin: string, path = "/auth/reset-password"): RequestInit & { path: string } {
  return {
    path,
    method: "OPTIONS",
    headers: {
      Origin: origin,
      "Access-Control-Request-Method": "POST",
      "Access-Control-Request-Headers": "content-type",
    },
  };
}

describe("CORS", () => {
  test("the site's preflight for /auth/reset-password is allowed (204)", async () => {
    const { app, seen } = stubApp();
    const { path, ...init } = preflight(WEB_ORIGIN);
    const res = await app.request(`http://localhost${path}`, init);
    assert.equal(res.status, 204);
    assert.equal(res.headers.get("access-control-allow-origin"), WEB_ORIGIN);
    assert.match(String(res.headers.get("access-control-allow-headers")), /Content-Type/i);
    assert.match(String(res.headers.get("access-control-allow-headers")), /Authorization/i);
    assert.match(String(res.headers.get("access-control-allow-methods")), /POST/);
    assert.equal(res.headers.get("access-control-max-age"), "600");
    assert.equal(res.headers.get("access-control-allow-credentials"), null);
    assert.equal(seen.length, 0, "the preflight never reaches Better Auth");
  });

  test("a preflight from another origin gets no allow-origin header", async () => {
    const { app } = stubApp();
    const { path, ...init } = preflight("https://evil.example");
    const res = await app.request(`http://localhost${path}`, init);
    assert.equal(res.headers.get("access-control-allow-origin"), null);
  });

  test("the site's POST reaches Better Auth unchanged and carries the allow-origin header", async () => {
    const { app, seen } = stubApp();
    const body = JSON.stringify({ token: "t", newPassword: "new-pass-1" });
    const res = await app.request("http://localhost/auth/reset-password", {
      method: "POST",
      headers: { Origin: WEB_ORIGIN, "Content-Type": "application/json" },
      body,
    });
    assert.equal(res.status, 200);
    assert.equal(res.headers.get("access-control-allow-origin"), WEB_ORIGIN);
    assert.deepEqual(seen, [
      { method: "POST", path: "/auth/reset-password", body, contentType: "application/json" },
    ]);
  });

  test("a POST without an Origin header (the app) works as before", async () => {
    const { app, seen } = stubApp();
    const body = JSON.stringify({ token: "t", newPassword: "new-pass-1" });
    const res = await app.request("http://localhost/auth/reset-password", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body,
    });
    assert.equal(res.status, 200);
    assert.deepEqual(await res.json(), { status: true });
    assert.equal(seen.length, 1);
    assert.equal(seen[0].body, body);
  });

  test("/api preflights from the site are allowed too", async () => {
    const { app } = stubApp();
    const { path, ...init } = preflight(WEB_ORIGIN, "/api/config");
    const res = await app.request(`http://localhost${path}`, init);
    assert.equal(res.status, 204);
    assert.equal(res.headers.get("access-control-allow-origin"), WEB_ORIGIN);
  });

  test("/api responses allow only the site's origin", async () => {
    const { app } = stubApp();
    for (const [origin, allowed] of [
      ["https://evil.example", null],
      [WEB_ORIGIN, WEB_ORIGIN],
    ] as const) {
      const res = await app.request("http://localhost/api/start-puzzle", { method: "POST", headers: { Origin: origin }, body: "{}" });
      assert.equal(res.status, 401);
      assert.equal(res.headers.get("access-control-allow-origin"), allowed);
    }
  });

  test("/api responses to the app still carry the edge functions' headers", async () => {
    const { app } = stubApp();
    const res = await app.request("http://localhost/api/start-puzzle", { method: "POST", body: "{}" });
    assert.equal(res.status, 401);
    assert.ok(res.headers.get("x-correlation-id"));
  });
});
