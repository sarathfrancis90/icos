/**
 * Tests for isServiceRoleRequest in http.ts. Run with:
 *   deno test -A supabase/functions/_shared/
 */
import { isServiceRoleRequest } from "./http.ts";

// Minimal assertion helpers (no external deps)
function assert(cond: boolean, msg: string): void {
  if (!cond) throw new Error(`assertion failed: ${msg}`);
}

const ENV_KEY = "SUPABASE_SERVICE_ROLE_KEY";
const STORED_KEY = "stored-service-key-for-tests";

function b64url(obj: unknown): string {
  return btoa(JSON.stringify(obj))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

function fakeJwt(role: string): string {
  return `${b64url({ alg: "HS256", typ: "JWT" })}.${b64url({ role })}.sig`;
}

function reqWith(token?: string): Request {
  const headers: Record<string, string> = {};
  if (token !== undefined) headers["Authorization"] = `Bearer ${token}`;
  return new Request("https://example.test/fn", { method: "POST", headers });
}

async function withEnv(fn: () => Promise<void>): Promise<void> {
  const prev = Deno.env.get(ENV_KEY);
  Deno.env.set(ENV_KEY, STORED_KEY);
  try {
    await fn();
  } finally {
    if (prev === undefined) Deno.env.delete(ENV_KEY);
    else Deno.env.set(ENV_KEY, prev);
  }
}

function spyProbe(result: boolean | Error) {
  const state = { calls: 0 };
  const probe = (_token: string): Promise<boolean> => {
    state.calls++;
    if (result instanceof Error) return Promise.reject(result);
    return Promise.resolve(result);
  };
  return { state, probe };
}

Deno.test("no Authorization header -> false, probe not called", async () => {
  await withEnv(async () => {
    const { state, probe } = spyProbe(true);
    const ok = await isServiceRoleRequest(reqWith(), probe);
    assert(ok === false, "expected false");
    assert(state.calls === 0, "probe must not be called");
  });
});

Deno.test("bearer equals env key -> true, probe not called", async () => {
  await withEnv(async () => {
    const { state, probe } = spyProbe(false);
    const ok = await isServiceRoleRequest(reqWith(STORED_KEY), probe);
    assert(ok === true, "expected true");
    assert(state.calls === 0, "probe must not be called");
  });
});

Deno.test("service_role JWT and probe true -> true", async () => {
  await withEnv(async () => {
    const { state, probe } = spyProbe(true);
    const ok = await isServiceRoleRequest(reqWith(fakeJwt("service_role")), probe);
    assert(ok === true, "expected true");
    assert(state.calls === 1, "probe called once");
  });
});

Deno.test("service_role JWT and probe false -> false", async () => {
  await withEnv(async () => {
    const { state, probe } = spyProbe(false);
    const ok = await isServiceRoleRequest(reqWith(fakeJwt("service_role")), probe);
    assert(ok === false, "expected false");
    assert(state.calls === 1, "probe called once");
  });
});

Deno.test("authenticated JWT -> false, probe not called", async () => {
  await withEnv(async () => {
    const { state, probe } = spyProbe(true);
    const ok = await isServiceRoleRequest(reqWith(fakeJwt("authenticated")), probe);
    assert(ok === false, "expected false");
    assert(state.calls === 0, "probe must not be called");
  });
});

Deno.test("non-JWT garbage token -> false, probe not called", async () => {
  await withEnv(async () => {
    const { state, probe } = spyProbe(true);
    for (const t of ["garbage", "a.b", "!!!.@@@.###", "a.b.c.d"]) {
      const ok = await isServiceRoleRequest(reqWith(t), probe);
      assert(ok === false, `expected false for ${t}`);
    }
    assert(state.calls === 0, "probe must not be called");
  });
});

Deno.test("probe throws -> false", async () => {
  await withEnv(async () => {
    const { probe } = spyProbe(new Error("boom"));
    const ok = await isServiceRoleRequest(reqWith(fakeJwt("service_role")), probe);
    assert(ok === false, "expected false");
  });
});
