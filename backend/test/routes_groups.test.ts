// /api/join-group, /api/report, /api/block and /api/unblock over HTTP against
// the Neon `test` branch. Skips without NEON_TEST_DATABASE_URL.
import { after, before, describe, test } from "node:test";
import assert from "node:assert/strict";
import { setupApi, SKIP, type ApiHarness } from "./helpers/api.js";

describe("group routes", { skip: SKIP }, () => {
  let h: ApiHarness;

  before(async () => {
    h = await setupApi();
    process.env.REPORT_ALERT_TO = "alerts@example.com";
  });
  after(async () => {
    delete process.env.REPORT_ALERT_TO;
    await h?.close();
  });

  async function makeGroup(adminId: string): Promise<{ id: string; invite_code: string }> {
    const [row] = await h.q<{ code: string }>("SELECT public.generate_invite_code() AS code");
    const [group] = await h.q<{ id: string; invite_code: string }>(
      "INSERT INTO public.groups (name, invite_code, admin_id, member_count) VALUES ('Puzzlers', $1, $2, 0) RETURNING id, invite_code",
      [row.code, adminId],
    );
    await h.q("INSERT INTO public.group_members (group_id, user_id, role) VALUES ($1, $2, 'admin')", [
      group.id,
      adminId,
    ]);
    return group;
  }

  describe("POST /api/join-group", () => {
    test("400 INVALID_INVITE_CODE for a malformed code", async () => {
      const member = await h.signUpEmail();
      const { res, json } = await h.call("POST", "/api/join-group", { invite_code: "abc" }, member.token);
      assert.equal(res.status, 400);
      assert.deepEqual(json, { error: "Invite code must be 6 letters/digits", code: "INVALID_INVITE_CODE" });
    });

    test("403 ANONYMOUS_USER for a guest", async () => {
      const guest = await h.signInGuest();
      const { res, json } = await h.call("POST", "/api/join-group", { invite_code: "ABC123" }, guest.token);
      assert.equal(res.status, 403);
      assert.deepEqual(json, { error: "Create an account to join groups", code: "ANONYMOUS_USER" });
    });

    test("404 GROUP_NOT_FOUND for an unknown code", async () => {
      const member = await h.signUpEmail();
      const { res, json } = await h.call("POST", "/api/join-group", { invite_code: "ZZZZZ0" }, member.token);
      assert.equal(res.status, 404);
      assert.equal(json?.code, "GROUP_NOT_FOUND");
    });

    test("200 already_member:false with the full group row, then already_member:true", async () => {
      const admin = await h.signUpEmail("admin");
      const member = await h.signUpEmail();
      const group = await makeGroup(admin.id);

      const first = await h.call("POST", "/api/join-group", { invite_code: group.invite_code.toLowerCase() }, member.token);
      assert.equal(first.res.status, 200, JSON.stringify(first.json));
      assert.equal(first.json?.already_member, false);
      assert.equal(first.json?.group.id, group.id);
      assert.equal(first.json?.group.member_count, 2);
      assert.deepEqual(Object.keys(first.json?.group ?? {}).sort(), [
        "admin_id",
        "created_at",
        "description",
        "id",
        "invite_code",
        "is_active",
        "max_members",
        "member_count",
        "name",
        "updated_at",
      ]);
      const feed = await h.q("SELECT 1 FROM public.group_feed WHERE group_id = $1 AND user_id = $2 AND event = 'joined'", [
        group.id,
        member.id,
      ]);
      assert.equal(feed.length, 1);

      const second = await h.call("POST", "/api/join-group", { invite_code: group.invite_code }, member.token);
      assert.equal(second.res.status, 200);
      assert.equal(second.json?.already_member, true);
      assert.equal(second.json?.group.member_count, 2);
    });

    test("409 GROUP_FULL when the group is at capacity", async () => {
      const admin = await h.signUpEmail("admin");
      const member = await h.signUpEmail();
      const group = await makeGroup(admin.id);
      await h.q("UPDATE public.groups SET max_members = 1 WHERE id = $1", [group.id]);
      const { res, json } = await h.call("POST", "/api/join-group", { invite_code: group.invite_code }, member.token);
      assert.equal(res.status, 409);
      assert.equal(json?.code, "GROUP_FULL");
    });
  });

  describe("POST /api/report", () => {
    test("201 {id}, stores the report and emails the alert once", async () => {
      const reporter = await h.signInGuest();
      const target = await h.signInGuest();
      const before = h.routeEmails.length;
      const { res, json } = await h.call(
        "POST",
        "/api/report",
        { reported_user_id: target.id, reason: "harassment", details: "  rude​ name  " },
        reporter.token,
      );
      assert.equal(res.status, 201, JSON.stringify(json));
      assert.match(String(json?.id), /^[0-9a-f-]{36}$/);
      assert.deepEqual(Object.keys(json ?? {}), ["id"]);

      const [row] = await h.q<{ reporter_id: string; reported_user_id: string; reason: string; details: string }>(
        "SELECT reporter_id, reported_user_id, reason, details FROM public.reports WHERE id = $1",
        [json?.id],
      );
      assert.deepEqual(row, { reporter_id: reporter.id, reported_user_id: target.id, reason: "harassment", details: "rude name" });

      const sent = h.routeEmails.slice(before);
      assert.equal(sent.length, 1);
      assert.equal(sent[0].to, "alerts@example.com");
      assert.equal(sent[0].subject, `Icos report: harassment (user ${target.id})`);
      assert.match(String(sent[0].text), new RegExp(`Report id: ${json?.id}\\n`));
      assert.match(String(sent[0].text), /Details: rude name\n/);
      assert.match(String(sent[0].text), new RegExp(`Reporter: ${reporter.id}\\n`));
    });

    test("400 INVALID_FIELD for an unknown reason or a missing target; details capped at 1000", async () => {
      const reporter = await h.signInGuest();
      const target = await h.signInGuest();
      const reason = await h.call("POST", "/api/report", { reported_user_id: target.id, reason: "meh" }, reporter.token);
      assert.equal(reason.res.status, 400);
      assert.equal(reason.json?.field, "reason");
      const none = await h.call("POST", "/api/report", { reason: "spam" }, reporter.token);
      assert.equal(none.res.status, 400);
      assert.equal(none.json?.code, "INVALID_FIELD");

      const long = await h.call(
        "POST",
        "/api/report",
        { reported_user_id: target.id, reason: "other", details: "x".repeat(1500) },
        reporter.token,
      );
      assert.equal(long.res.status, 201);
      const [row] = await h.q<{ n: number }>("SELECT length(details) AS n FROM public.reports WHERE id = $1", [long.json?.id]);
      assert.equal(row.n, 1000);
    });
  });

  describe("POST /api/block and /api/unblock", () => {
    test("block inserts user_blocks and one blocked_by_user report (emailed once), unblock removes it", async () => {
      const blocker = await h.signInGuest();
      const target = await h.signInGuest();
      const before = h.routeEmails.length;

      const first = await h.call("POST", "/api/block", { user_id: target.id }, blocker.token);
      assert.equal(first.res.status, 200, JSON.stringify(first.json));
      assert.deepEqual(first.json, { blocked: true });
      const blocks = await h.q("SELECT 1 FROM public.user_blocks WHERE blocker_id = $1 AND blocked_id = $2", [
        blocker.id,
        target.id,
      ]);
      assert.equal(blocks.length, 1);

      // Block again, unblock, block again: still exactly one automatic report.
      assert.equal((await h.call("POST", "/api/block", { user_id: target.id }, blocker.token)).res.status, 200);
      const off = await h.call("POST", "/api/unblock", { user_id: target.id }, blocker.token);
      assert.equal(off.res.status, 200);
      assert.deepEqual(off.json, { blocked: false });
      assert.equal(
        (await h.q("SELECT 1 FROM public.user_blocks WHERE blocker_id = $1", [blocker.id])).length,
        0,
      );
      assert.equal((await h.call("POST", "/api/block", { user_id: target.id }, blocker.token)).res.status, 200);

      const reports = await h.q<{ reason: string; details: string }>(
        "SELECT reason, details FROM public.reports WHERE reporter_id = $1 AND reported_user_id = $2",
        [blocker.id, target.id],
      );
      assert.deepEqual(reports, [
        { reason: "blocked_by_user", details: "Automatic notice: the reporter blocked this user." },
      ]);
      const sent = h.routeEmails.slice(before);
      assert.equal(sent.length, 1);
      assert.equal(sent[0].subject, `Icos report: blocked_by_user (user ${target.id})`);
    });

    test("400 INVALID_FIELD on a self-block; 404 PROFILE_NOT_FOUND for an unknown user", async () => {
      const blocker = await h.signInGuest();
      const self = await h.call("POST", "/api/block", { user_id: blocker.id }, blocker.token);
      assert.equal(self.res.status, 400);
      assert.equal(self.json?.code, "INVALID_FIELD");
      const unknown = await h.call(
        "POST",
        "/api/block",
        { user_id: "00000000-0000-4000-8000-000000000000" },
        blocker.token,
      );
      assert.equal(unknown.res.status, 404);
      assert.equal(unknown.json?.code, "PROFILE_NOT_FOUND");
    });

    test("403 BANNED for a banned caller", async () => {
      const blocker = await h.signInGuest();
      const target = await h.signInGuest();
      await h.q("UPDATE public.profiles SET is_banned = true WHERE id = $1", [blocker.id]);
      const { res, json } = await h.call("POST", "/api/block", { user_id: target.id }, blocker.token);
      assert.equal(res.status, 403);
      assert.deepEqual(json, { error: "Account suspended", code: "BANNED" });
    });
  });
});
