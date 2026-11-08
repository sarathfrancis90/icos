// Tests for src/shared/http.ts. The archive-window cases are ported from the
// former edge-function suite; the isServiceRoleRequest cases left with that
// helper (service auth moves to the auth middleware).
import { describe, test } from "node:test";
import assert from "node:assert/strict";
import {
  addDays,
  ARCHIVE_WINDOW_DAYS,
  compareDates,
  correlationIdFrom,
  corsHeaders,
  errorFields,
  errorResponse,
  handleCommon,
  hmacSha256Hex,
  isInt,
  isIsoDate,
  isWithinArchiveWindow,
  json,
  randomNonce,
  readJson,
  scoreMessage,
  sha256Hex,
  timingSafeEqual,
  utcToday,
} from "../src/shared/http.js";

describe("archive window (shared by start-puzzle and submit-score)", () => {
  test("30 days, inclusive at both ends", () => {
    const today = "2026-10-07";
    assert.equal(ARCHIVE_WINDOW_DAYS, 30, "window is 30 days");
    assert.ok(isWithinArchiveWindow(today, today), "today accepted");
    assert.ok(isWithinArchiveWindow("2026-09-30", today), "day 7 accepted");
    assert.ok(isWithinArchiveWindow("2026-09-29", today), "day 8 accepted");
    assert.ok(isWithinArchiveWindow("2026-09-07", today), "day 30 accepted");
    assert.ok(!isWithinArchiveWindow("2026-09-06", today), "day 31 rejected");
    assert.ok(!isWithinArchiveWindow("2026-10-08", today), "tomorrow rejected");
  });

  test("crosses month and year boundaries", () => {
    assert.ok(isWithinArchiveWindow("2026-12-02", "2027-01-01"), "day 30 across a year accepted");
    assert.ok(!isWithinArchiveWindow("2026-12-01", "2027-01-01"), "day 31 across a year rejected");
    assert.ok(isWithinArchiveWindow("2028-01-30", "2028-02-29"), "day 30 into a leap day accepted");
  });
});

describe("crypto helpers (Web Crypto on Node)", () => {
  test("sha256Hex matches the FIPS 180-2 'abc' vector", async () => {
    assert.equal(
      await sha256Hex("abc"),
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
    );
  });

  test("hmacSha256Hex matches RFC 4231 test case 2", async () => {
    assert.equal(
      await hmacSha256Hex("Jefe", "what do ya want for nothing?"),
      "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843",
    );
  });

  test("randomNonce is hex of the requested length and not repeated", () => {
    const a = randomNonce();
    assert.match(a, /^[0-9a-f]{64}$/);
    assert.match(randomNonce(8), /^[0-9a-f]{16}$/);
    assert.notEqual(a, randomNonce());
  });

  test("timingSafeEqual", () => {
    assert.equal(timingSafeEqual("secret", "secret"), true);
    assert.equal(timingSafeEqual("secret", "secreT"), false);
    assert.equal(timingSafeEqual("secret", "secret!"), false);
    assert.equal(timingSafeEqual("", ""), true);
  });

  test("scoreMessage is date|time|hints|undos|hash", () => {
    assert.equal(scoreMessage("2026-11-08", 95, 1, 3, "ab12"), "2026-11-08|95|1|3|ab12");
  });
});

describe("validation and dates", () => {
  test("isInt", () => {
    assert.ok(isInt(5, 0, 10));
    assert.ok(!isInt(5.5, 0, 10));
    assert.ok(!isInt(11, 0, 10));
    assert.ok(!isInt("5", 0, 10));
  });

  test("isIsoDate accepts real dates only", () => {
    assert.ok(isIsoDate("2028-02-29"));
    assert.ok(!isIsoDate("2027-02-29"));
    assert.ok(!isIsoDate("2026-13-01"));
    assert.ok(!isIsoDate("2026-1-01"));
    assert.ok(!isIsoDate(20260101));
  });

  test("addDays / compareDates / utcToday", () => {
    assert.equal(addDays("2026-12-31", 1), "2027-01-01");
    assert.equal(addDays("2026-03-01", -1), "2026-02-28");
    assert.equal(compareDates("2026-01-01", "2026-01-02"), -1);
    assert.equal(compareDates("2026-01-02", "2026-01-01"), 1);
    assert.equal(compareDates("2026-01-01", "2026-01-01"), 0);
    assert.equal(utcToday(), new Date().toISOString().slice(0, 10));
  });

  test("readJson returns objects, {} for empty bodies, null otherwise", async () => {
    const req = (body: string) => new Request("https://x.test/", { method: "POST", body });
    assert.deepEqual(await readJson(req('{"a":1}')), { a: 1 });
    assert.deepEqual(await readJson(req("   ")), {});
    assert.equal(await readJson(req("[1]")), null);
    assert.equal(await readJson(req("null")), null);
    assert.equal(await readJson(req("{nope")), null);
  });

  test("errorFields", () => {
    const f = errorFields(new TypeError("bad"));
    assert.equal(f.error, "bad");
    assert.equal(f.error_name, "TypeError");
    assert.deepEqual(errorFields("plain"), { error: "plain" });
  });
});

describe("responses", () => {
  test("correlationIdFrom keeps a well-formed header and replaces anything else", () => {
    const withId = (v?: string) =>
      new Request("https://x.test/", { headers: v === undefined ? {} : { "x-correlation-id": v } });
    assert.equal(correlationIdFrom(withId("abc-123")), "abc-123");
    const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
    assert.match(correlationIdFrom(withId()), uuid);
    assert.match(correlationIdFrom(withId("bad id!")), uuid);
  });

  test("json sets content type and no-store, and leaves CORS to the middleware", async () => {
    const res = json({ a: 1 }, 201, { "x-extra": "1" });
    assert.equal(res.status, 201);
    assert.equal(res.headers.get("content-type"), "application/json; charset=utf-8");
    assert.equal(res.headers.get("cache-control"), "no-store");
    assert.equal(res.headers.get("access-control-allow-origin"), null);
    assert.equal(res.headers.get("x-extra"), "1");
    assert.deepEqual(await res.json(), { a: 1 });
  });

  test("errorResponse echoes the correlation id", async () => {
    const res = errorResponse(403, "nope", "BANNED", "cid-1", { retry: false });
    assert.equal(res.status, 403);
    assert.equal(res.headers.get("x-correlation-id"), "cid-1");
    assert.deepEqual(await res.json(), { error: "nope", code: "BANNED", retry: false });
  });

  test("handleCommon answers OPTIONS and /health only", async () => {
    const pre = handleCommon(new Request("https://x.test/fn", { method: "OPTIONS" }), "fn");
    assert.equal(pre?.status, 200);
    const health = handleCommon(new Request("https://x.test/fn/health"), "fn");
    assert.equal((await health?.json()).fn, "fn");
    assert.equal(handleCommon(new Request("https://x.test/fn", { method: "POST" }), "fn"), null);
  });
});
