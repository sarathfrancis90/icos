// /api/export-data and /api/account/upgrade-email over HTTP against the Neon
// `test` branch. Skips without NEON_TEST_DATABASE_URL.
import { after, before, describe, test } from "node:test";
import assert from "node:assert/strict";
import { setupApi, SKIP, type ApiHarness } from "./helpers/api.js";

describe("account routes", { skip: SKIP }, () => {
  let h: ApiHarness;

  before(async () => {
    h = await setupApi();
  });
  after(async () => {
    await h?.close();
  });

  async function waitForAuthEmail(to: string, subject: string) {
    for (let i = 0; i < 50; i++) {
      const found = h.authEmails.find((m) => m.to === to && m.subject === subject);
      if (found) return found;
      await new Promise((r) => setTimeout(r, 50));
    }
    assert.fail(`no "${subject}" email to ${to}`);
  }

  describe("GET/POST /api/export-data", () => {
    test("200 with every section; user.providers comes from profiles.providers", async () => {
      const member = await h.signUpEmail("exporter");
      const other = await h.signInGuest();
      await h.q("INSERT INTO public.user_blocks (blocker_id, blocked_id) VALUES ($1, $2)", [member.id, other.id]);
      await h.q("INSERT INTO public.streak_freezes (user_id, frozen_date) VALUES ($1, '2026-03-04')", [member.id]);

      const { res, json } = await h.call("GET", "/api/export-data", undefined, member.token);
      assert.equal(res.status, 200, JSON.stringify(json));
      assert.equal(res.headers.get("content-disposition"), `attachment; filename="icos-export-${member.id}.json"`);
      assert.deepEqual(Object.keys(json ?? {}).sort(), [
        "attempts",
        "blocked_users",
        "exported_at",
        "groups",
        "profile",
        "reports_filed",
        "streak",
        "streak_freezes",
        "user",
      ]);
      assert.equal(json?.user.id, member.id);
      assert.equal(json?.user.email, member.email);
      assert.equal(json?.user.is_anonymous, false);
      assert.ok(json?.user.created_at);
      const [profile] = await h.q<{ providers: string[] }>("SELECT providers FROM public.profiles WHERE id = $1", [
        member.id,
      ]);
      assert.deepEqual(json?.user.providers, profile.providers);
      assert.ok(profile.providers.includes("credential"));
      assert.equal(json?.profile.id, member.id);
      assert.deepEqual(json?.attempts, []);
      assert.equal(json?.streak, null);
      assert.equal(json?.streak_freezes[0].frozen_date, "2026-03-04");
      assert.deepEqual(json?.groups, []);
      assert.deepEqual(json?.reports_filed, []);
      assert.equal(json?.blocked_users.length, 1);
      assert.equal(json?.blocked_users[0].blocked_user_id, other.id);
      assert.ok(json?.blocked_users[0].blocked_at);

      const post = await h.call("POST", "/api/export-data", undefined, member.token);
      assert.equal(post.res.status, 200);
    });

    test("401 without a session; 403 BANNED for a banned account", async () => {
      const anon = await h.call("GET", "/api/export-data");
      assert.equal(anon.res.status, 401);
      assert.deepEqual(anon.json, { error: "Not signed in", code: "UNAUTHORIZED" });

      const guest = await h.signInGuest();
      await h.q("UPDATE public.profiles SET is_banned = true WHERE id = $1", [guest.id]);
      const banned = await h.call("GET", "/api/export-data", undefined, guest.token);
      assert.equal(banned.res.status, 403);
      assert.deepEqual(banned.json, { error: "Account suspended", code: "BANNED" });
    });
  });

  describe("POST /api/account/upgrade-email", () => {
    test("turns a guest into an email account with the same id; sends the verification email", async () => {
      const guest = await h.signInGuest();
      const email = h.uniqueEmail("upgrader.jane");
      const { res, json } = await h.call(
        "POST",
        "/api/account/upgrade-email",
        { email: email.toUpperCase(), password: "brand-new-pass" },
        guest.token,
      );
      assert.equal(res.status, 200, JSON.stringify(json));
      assert.deepEqual(json, { user: { id: guest.id, email, is_anonymous: false, email_verified: false } });

      const [user] = await h.q<{ email: string; isAnonymous: boolean; emailVerified: boolean }>(
        `SELECT email, "isAnonymous", "emailVerified" FROM ba."user" WHERE id = $1`,
        [guest.id],
      );
      assert.deepEqual(user, { email, isAnonymous: false, emailVerified: false });
      const [profile] = await h.q<{ is_anonymous: boolean; email: string; display_name: string; providers: string[] }>(
        "SELECT is_anonymous, email, display_name, providers FROM public.profiles WHERE id = $1",
        [guest.id],
      );
      assert.equal(profile.is_anonymous, false);
      assert.equal(profile.email, email);
      assert.match(profile.display_name, /^Upgrader Jane/);
      assert.deepEqual(profile.providers, ["credential"]);
      await waitForAuthEmail(email, "Confirm your Icos email");

      // The same token still works, and the new password signs in to the same id.
      const me = await h.call("GET", "/api/export-data", undefined, guest.token);
      assert.equal(me.res.status, 200);
      assert.equal(me.json?.user.is_anonymous, false);
      const signIn = await h.call("POST", "/auth/sign-in/email", { email, password: "brand-new-pass" });
      assert.equal(signIn.res.status, 200, JSON.stringify(signIn.json));
      assert.equal(signIn.json?.user.id, guest.id);

      // No longer a guest.
      const again = await h.call(
        "POST",
        "/api/account/upgrade-email",
        { email: h.uniqueEmail("again"), password: "another-pass" },
        guest.token,
      );
      assert.equal(again.res.status, 400);
      assert.equal(again.json?.code, "NOT_ANONYMOUS");
    });

    test("409 EMAIL_EXISTS for a taken email (case-insensitive); the guest stays a guest", async () => {
      const member = await h.signUpEmail("taken");
      const guest = await h.signInGuest();
      const { res, json } = await h.call(
        "POST",
        "/api/account/upgrade-email",
        { email: member.email.toUpperCase(), password: "brand-new-pass" },
        guest.token,
      );
      assert.equal(res.status, 409);
      assert.deepEqual(json, { error: "An account with this email already exists", code: "EMAIL_EXISTS" });
      const [user] = await h.q<{ isAnonymous: boolean }>(`SELECT "isAnonymous" FROM ba."user" WHERE id = $1`, [
        guest.id,
      ]);
      assert.equal(user.isAnonymous, true);
    });

    test("400 INVALID_FIELD for a bad email or a short password", async () => {
      const guest = await h.signInGuest();
      const email = await h.call("POST", "/api/account/upgrade-email", { email: "nope", password: "123456" }, guest.token);
      assert.equal(email.res.status, 400);
      assert.equal(email.json?.field, "email");
      const pw = await h.call(
        "POST",
        "/api/account/upgrade-email",
        { email: h.uniqueEmail("short"), password: "12345" },
        guest.token,
      );
      assert.equal(pw.res.status, 400);
      assert.equal(pw.json?.field, "password");
    });
  });
});
