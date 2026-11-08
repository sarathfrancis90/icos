import { afterEach, beforeEach, describe, test } from "node:test";
import assert from "node:assert/strict";
import { sendEmail } from "../src/email.js";

type Call = { url: string; init: RequestInit };

function stubFetch(response: () => Response | Promise<Response>) {
  const calls: Call[] = [];
  const fetch = (async (input: string | URL | Request, init?: RequestInit) => {
    calls.push({ url: String(input), init: init ?? {} });
    return response();
  }) as typeof globalThis.fetch;
  return { calls, fetch };
}

const MSG = { to: "player@example.com", subject: "Hi", html: "<p>Hi</p>", text: "Hi" };

describe("sendEmail", () => {
  let savedKey: string | undefined;
  beforeEach(() => {
    savedKey = process.env.RESEND_API_KEY;
    process.env.RESEND_API_KEY = "re_test_key";
  });
  afterEach(() => {
    if (savedKey === undefined) delete process.env.RESEND_API_KEY;
    else process.env.RESEND_API_KEY = savedKey;
  });

  test("posts the message to Resend and returns the id", async () => {
    const { calls, fetch } = stubFetch(() => Response.json({ id: "em_123" }));
    const res = await sendEmail(MSG, { fetch });
    assert.deepEqual(res, { ok: true, id: "em_123" });
    assert.equal(calls.length, 1);
    const { url, init } = calls[0];
    assert.equal(url, "https://api.resend.com/emails");
    assert.equal(init.method, "POST");
    const headers = new Headers(init.headers);
    assert.equal(headers.get("authorization"), "Bearer re_test_key");
    assert.equal(headers.get("content-type"), "application/json");
    assert.deepEqual(JSON.parse(String(init.body)), {
      from: "Icos <noreply@icos.sarathfrancis.work>",
      to: ["player@example.com"],
      subject: "Hi",
      html: "<p>Hi</p>",
      text: "Hi",
    });
  });

  test("passes a recipient list through and omits text when absent", async () => {
    const { calls, fetch } = stubFetch(() => Response.json({ id: "em_2" }));
    await sendEmail({ to: ["a@example.com", "b@example.com"], subject: "S", html: "<b>x</b>" }, { fetch });
    const body = JSON.parse(String(calls[0].init.body));
    assert.deepEqual(body.to, ["a@example.com", "b@example.com"]);
    assert.equal("text" in body, false);
  });

  test("a 500 yields ok:false", async (t) => {
    const error = t.mock.method(console, "error", () => {});
    const { fetch } = stubFetch(() => new Response("upstream broke", { status: 500 }));
    const res = await sendEmail(MSG, { fetch });
    assert.equal(res.ok, false);
    assert.match(res.error ?? "", /500/);
    assert.equal(error.mock.callCount(), 1);
  });

  test("a network error yields ok:false instead of throwing", async (t) => {
    t.mock.method(console, "error", () => {});
    const { fetch } = stubFetch(() => {
      throw new TypeError("fetch failed");
    });
    const res = await sendEmail(MSG, { fetch });
    assert.deepEqual(res, { ok: false, error: "fetch failed" });
  });

  test("an unset RESEND_API_KEY yields ok:false without calling fetch", async (t) => {
    delete process.env.RESEND_API_KEY;
    const warn = t.mock.method(console, "warn", () => {});
    const { calls, fetch } = stubFetch(() => Response.json({ id: "never" }));
    const res = await sendEmail(MSG, { fetch });
    assert.deepEqual(res, { ok: false, error: "RESEND_API_KEY unset" });
    assert.equal(calls.length, 0);
    assert.equal(warn.mock.callCount(), 1);
    const line = JSON.parse(String(warn.mock.calls[0].arguments[0]));
    assert.equal(line.level, "warn");
    assert.equal(line.fn, "email");
  });
});
