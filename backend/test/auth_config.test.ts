// Auth configuration from the environment and the Apple client secret (no DB).
import { describe, test } from "node:test";
import assert from "node:assert/strict";
import { decodeJwt, decodeProtectedHeader, exportPKCS8, generateKeyPair, importSPKI, exportSPKI, jwtVerify } from "jose";
import { authDepsFromEnv, GOOGLE_SECRET_PLACEHOLDER, mintAppleClientSecret } from "../src/auth.js";
import { Logger } from "../src/shared/http.js";

/** Records warnings instead of printing them. */
class RecordingLogger extends Logger {
  readonly warnings: string[] = [];
  override warn(msg: string): void {
    this.warnings.push(msg);
  }
}

const BASE = { BETTER_AUTH_SECRET: "s".repeat(40), AUTH_BASE_URL: "https://api.example.test" };

describe("authDepsFromEnv", () => {
  test("requires the secret and a base URL", () => {
    assert.throws(() => authDepsFromEnv({ AUTH_BASE_URL: "https://x.test" }), /BETTER_AUTH_SECRET/);
    assert.throws(() => authDepsFromEnv({ BETTER_AUTH_SECRET: "s" }), /AUTH_BASE_URL/);
  });

  test("falls back to the Function URL Neon injects", () => {
    const deps = authDepsFromEnv({
      BETTER_AUTH_SECRET: "s",
      NEON_BRANCH_ID: "br-abc-123",
      NEON_FUNCTION_HOST_SUFFIX: ".fn.example.test",
    });
    assert.equal(deps.baseURL, "https://br-abc-123-api.fn.example.test");
  });

  test("configures Apple only when its env is complete; Google needs only the client id", () => {
    const log = new RecordingLogger("auth", "test");
    const partial = authDepsFromEnv({ ...BASE, GOOGLE_WEB_CLIENT_ID: "g", APPLE_SERVICE_ID: "svc" }, log);
    assert.deepEqual(partial.google, { clientId: "g", clientSecret: GOOGLE_SECRET_PLACEHOLDER });
    assert.equal(GOOGLE_SECRET_PLACEHOLDER, "unset");
    assert.deepEqual(log.warnings, ["Google browser flow disabled until GOOGLE_WEB_CLIENT_SECRET is set"]);
    assert.equal(partial.apple, undefined);
    const none = authDepsFromEnv({ ...BASE }, log);
    assert.equal(none.google, undefined);
    assert.equal(log.warnings.length, 1, "no warning without a Google client id");
    const both = authDepsFromEnv({
      ...BASE,
      GOOGLE_WEB_CLIENT_ID: "g",
      GOOGLE_WEB_CLIENT_SECRET: "gs",
      APPLE_SERVICE_ID: "svc",
      APPLE_TEAM_ID: "team",
      APPLE_KEY_ID: "kid",
      APPLE_P8_BASE64: "cDg=",
    });
    assert.deepEqual(both.google, { clientId: "g", clientSecret: "gs" });
    assert.equal(both.apple?.clientId, "svc");
    assert.equal(both.apple?.appBundleIdentifier, "com.icos.game");
  });
});

describe("mintAppleClientSecret", () => {
  test("signs an ES256 JWT Apple accepts as a client secret", async () => {
    const { privateKey, publicKey } = await generateKeyPair("ES256", { extractable: true });
    const p8 = await exportPKCS8(privateKey);
    const now = Date.UTC(2026, 10, 8);
    const jwt = await mintAppleClientSecret({ p8, teamId: "TEAM123", keyId: "KEY456", serviceId: "io.icos.web", now });
    assert.deepEqual(decodeProtectedHeader(jwt), { alg: "ES256", kid: "KEY456" });
    const claims = decodeJwt(jwt);
    assert.equal(claims.iss, "TEAM123");
    assert.equal(claims.sub, "io.icos.web");
    assert.equal(claims.aud, "https://appleid.apple.com");
    assert.equal(claims.iat, now / 1000);
    assert.equal(claims.exp, now / 1000 + 180 * 86_400);
    const verifyKey = await importSPKI(await exportSPKI(publicKey), "ES256");
    await jwtVerify(jwt, verifyKey, { currentDate: new Date(now + 1000) });
  });
});
