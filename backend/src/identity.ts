// Keeps public.profiles in step with Better Auth's ba."user" (the Neon
// replacement for Supabase's auth.users triggers), and moves a guest's
// progress onto the account it signs up with.
//
// profiles.id has no FK to ba."user": these functions are the only link. Every
// app FK points at profiles(id) ON UPDATE CASCADE, which is what lets
// rekeyGuest move a guest's attempts, streaks and groups in one UPDATE.
import { HTTPException } from "hono/http-exception";
import type { Context } from "hono";
import type { PoolClient } from "pg";
import { getAuth } from "./auth.js";
import { pool, q, tx } from "./db.js";
import { correlationIdFrom, errorResponse } from "./shared/http.js";

/** The parts of a Better Auth user these helpers read. */
export interface AuthUser {
  id: string;
  name?: string | null;
  email?: string | null;
  emailVerified?: boolean | null;
  isAnonymous?: boolean | null;
  createdAt?: Date | string | null;
}

/** What requireSession needs from a Better Auth instance. */
export interface SessionSource {
  api: { getSession(opts: { headers: Headers }): Promise<{ user: AuthUser } | null> };
}

export interface SessionUser {
  id: string;
  email: string | null;
  isAnonymous: boolean;
}

const APPLE_RELAY_DOMAIN = "privaterelay.appleid.com";
const MAX_NAME = 30;

/** Postgres initcap(): lower-case everything, upper-case each word's first letter. */
function initcap(s: string): string {
  return s.toLowerCase().replace(/(^|[^\p{L}\p{N}])(\p{L})/gu, (_m, sep: string, ch: string) => sep + ch.toUpperCase());
}

/**
 * The display name a sign-in provider implies, or null when there is none.
 * Same rules as the Supabase-era provider_display_name(): the provider's name;
 * else the email's local part tidied up ("jane.doe+x" -> "Jane Doe X"), except
 * for Apple "Hide My Email" relay addresses, whose local part is random.
 * Capped at 30 characters (the display_name limit).
 */
export function providerDisplayName(name: string | null | undefined, email: string | null | undefined): string | null {
  let value: string | null = name?.trim() || null;
  if (value === null && email) {
    const at = email.indexOf("@");
    if (at > 0 && email.slice(at + 1).toLowerCase() !== APPLE_RELAY_DOMAIN) {
      const local = email.slice(0, at);
      value = initcap(local.replace(/[._\-+]+/g, " ")).replace(/\s+/g, " ").trim() || null;
    }
  }
  return value === null ? null : value.slice(0, MAX_NAME);
}

/** "Player NNNN": the name a profile gets until the player picks one. */
export function placeholderName(): string {
  return `Player ${String(Math.floor(Math.random() * 10_000)).padStart(4, "0")}`;
}

type Queryable = Pick<PoolClient, "query">;

// SQL: true when $n is a name the display_name trigger would accept, so a
// provider name that is too short or profane leaves the placeholder in place
// instead of failing the sign-in.
const acceptableName = (n: number) =>
  `($${n}::text IS NOT NULL
     AND length(public.sanitize_text($${n}::text)) BETWEEN 2 AND 30
     AND NOT public.contains_profanity(public.sanitize_text($${n}::text)))`;

const IS_PLACEHOLDER = `(display_name ~ '^Player [0-9]{4}$' OR display_name = '')`;

const ANON_EMAIL_DOMAIN = "@anonymous.placeholder.invalid";
const PLACEHOLDER_RE = /^Player \d{4}$/;

/** An email worth storing: null for a guest's placeholder address. */
export function realEmailOf(email: string | null | undefined): string | null {
  return email && !email.toLowerCase().endsWith(ANON_EMAIL_DOMAIN) ? email : null;
}

/** A name worth storing: null for Better Auth's guest defaults. */
function realNameOf(name: string | null | undefined): string | null {
  const trimmed = name?.trim();
  return trimmed && trimmed !== "Anonymous" && !PLACEHOLDER_RE.test(trimmed) ? trimmed : null;
}

/** Creates the user's profile row if it does not exist yet (idempotent). */
export async function ensureProfile(user: AuthUser): Promise<void> {
  const anonymous = Boolean(user.isAnonymous);
  const email = anonymous ? null : realEmailOf(user.email);
  const provided = anonymous ? null : providerDisplayName(realNameOf(user.name), email);
  // A guest keeps the "Player NNNN" its auth user was created with.
  const placeholder = user.name && PLACEHOLDER_RE.test(user.name) ? user.name : placeholderName();
  await q(
    `INSERT INTO public.profiles (id, is_anonymous, email, email_verified, display_name)
     VALUES ($1, $2, $3, $4,
             CASE WHEN ${acceptableName(5)} THEN public.sanitize_text($5::text) ELSE $6 END)
     ON CONFLICT (id) DO NOTHING`,
    [user.id, anonymous, email, Boolean(user.emailVerified) && email !== null, provided, placeholder],
  );
}

/**
 * True when `userId` owns no progress (no attempts, group memberships or
 * streak). Deliberately not based on how new the account is: a guest signing
 * in to an account that never played re-keys its progress onto that account,
 * while an account with any progress is never overwritten.
 */
export async function isFreshAccount(userId: string, db: Queryable = pool): Promise<boolean> {
  const { rows } = await db.query<{ has_data: boolean }>(
    `SELECT EXISTS (SELECT 1 FROM public.puzzle_attempts WHERE user_id = $1)
         OR EXISTS (SELECT 1 FROM public.group_members WHERE user_id = $1)
         OR EXISTS (SELECT 1 FROM public.streaks WHERE user_id = $1) AS has_data`,
    [userId],
  );
  return !rows[0].has_data;
}

/**
 * Re-points the rows of the account being replaced that are not "progress"
 * (blocks, reports, streak freezes) at the guest's profile, so the final
 * UPDATE … SET id carries them back to the account via ON UPDATE CASCADE
 * instead of the profile DELETE cascading them away. Blocks that would
 * duplicate a guest block or become a self-block are dropped; a freeze date
 * both sides have is kept once.
 */
async function adoptTargetRows(c: Queryable, guestId: string, targetId: string): Promise<void> {
  await c.query(
    `DELETE FROM public.user_blocks b
      WHERE b.blocker_id = $2
        AND (b.blocked_id = $1
             OR EXISTS (SELECT 1 FROM public.user_blocks x WHERE x.blocker_id = $1 AND x.blocked_id = b.blocked_id))`,
    [guestId, targetId],
  );
  await c.query("UPDATE public.user_blocks SET blocker_id = $1 WHERE blocker_id = $2", [guestId, targetId]);
  await c.query(
    `DELETE FROM public.user_blocks b
      WHERE b.blocked_id = $2
        AND (b.blocker_id = $1
             OR EXISTS (SELECT 1 FROM public.user_blocks x WHERE x.blocked_id = $1 AND x.blocker_id = b.blocker_id))`,
    [guestId, targetId],
  );
  await c.query("UPDATE public.user_blocks SET blocked_id = $1 WHERE blocked_id = $2", [guestId, targetId]);
  await c.query("UPDATE public.reports SET reporter_id = $1 WHERE reporter_id = $2", [guestId, targetId]);
  await c.query("UPDATE public.reports SET reported_user_id = $1 WHERE reported_user_id = $2", [guestId, targetId]);
  await c.query(
    `DELETE FROM public.streak_freezes f
      WHERE f.user_id = $2
        AND EXISTS (SELECT 1 FROM public.streak_freezes g WHERE g.user_id = $1 AND g.frozen_date = f.frozen_date)`,
    [guestId, targetId],
  );
  await c.query("UPDATE public.streak_freezes SET user_id = $1 WHERE user_id = $2", [guestId, targetId]);
}

export interface RekeyOptions {
  /** Test seam: runs inside the transaction just before COMMIT. */
  beforeCommit?: (c: Queryable) => Promise<void>;
}

/**
 * Moves the guest's profile (and through ON UPDATE CASCADE all of its app data)
 * onto `newUser.id`, replacing that user's profile row, when `newUser` owns no
 * progress (isFreshAccount, checked with both profile rows locked). Keeps the
 * replaced row's providers, ban, pending deletion, blocks, reports and
 * streak freezes (adoptTargetRows).
 * Returns "rekeyed", "has-progress" (nothing changed: the caller discards the
 * guest) or "gone" (guest profile already moved or deleted: idempotent).
 */
export async function rekeyGuest(
  guestId: string,
  newUser: AuthUser,
  opts: RekeyOptions = {},
): Promise<"rekeyed" | "has-progress" | "gone"> {
  if (guestId === newUser.id) return "gone";
  return tx(async (c) => {
    const guest = await c.query("SELECT 1 FROM public.profiles WHERE id = $1 AND is_anonymous FOR UPDATE", [guestId]);
    if (guest.rowCount === 0) return "gone";
    await c.query("SELECT 1 FROM public.profiles WHERE id = $1 FOR UPDATE", [newUser.id]);
    if (!(await isFreshAccount(newUser.id, c))) return "has-progress";
    await adoptTargetRows(c, guestId, newUser.id);
    const replaced = await c.query<{ providers: string[]; is_banned: boolean; deleted_at: Date | null }>(
      "DELETE FROM public.profiles WHERE id = $1 RETURNING providers, is_banned, deleted_at",
      [newUser.id],
    );
    const old = replaced.rows[0];
    const email = realEmailOf(newUser.email);
    await c.query(
      `UPDATE public.profiles
          SET id = $2,
              is_anonymous = false,
              email = $3,
              email_verified = $4,
              providers = ARRAY(SELECT DISTINCT unnest(providers || $5::text[]) ORDER BY 1),
              display_name = CASE WHEN ${IS_PLACEHOLDER} AND ${acceptableName(6)}
                                  THEN public.sanitize_text($6::text) ELSE display_name END,
              is_banned = is_banned OR $7,
              deleted_at = coalesce($8, deleted_at),
              updated_at = now()
        WHERE id = $1`,
      [
        guestId,
        newUser.id,
        email,
        Boolean(newUser.emailVerified) && email !== null,
        old?.providers ?? [],
        providerDisplayName(realNameOf(newUser.name), email),
        old?.is_banned ?? false,
        old?.deleted_at ?? null,
      ],
    );
    await opts.beforeCommit?.(c);
    return "rekeyed";
  });
}

/** Deletes a guest's profile; its app data goes with it (ON DELETE CASCADE). */
export async function discardGuest(guestId: string): Promise<void> {
  await q("DELETE FROM public.profiles WHERE id = $1 AND is_anonymous", [guestId]);
}

/** Decoded (not verified) claims of an id_token Better Auth already verified. */
function idTokenClaims(idToken: string | null | undefined): Record<string, unknown> {
  const payload = idToken?.split(".")[1];
  if (!payload) return {};
  try {
    const parsed = JSON.parse(Buffer.from(payload, "base64url").toString("utf8")) as unknown;
    return parsed && typeof parsed === "object" ? (parsed as Record<string, unknown>) : {};
  } catch {
    return {};
  }
}

export interface LinkedAccount {
  userId: string;
  providerId: string;
  idToken?: string | null;
}

/**
 * A failure while turning a guest into a real account. The account hook
 * rethrows it so /auth/link-social (or the OAuth callback) fails visibly
 * instead of leaving a real account flagged as a guest.
 */
export class GuestLinkError extends Error {
  constructor(cause: unknown) {
    super(`guest link failed: ${cause instanceof Error ? cause.message : String(cause)}`, { cause });
    this.name = "GuestLinkError";
  }
}

/**
 * After an account (credential, google, apple) is attached to a user: record
 * the provider and, when it was attached to a guest (/auth/link-social keeps
 * the guest's id), turn the guest into a real account: ba."user" and the
 * profile stop being anonymous, take the provider's email when nobody else
 * uses it, and a placeholder name becomes the provider's name. One
 * transaction: on failure nothing of ours is written.
 * Returns the account's email after the flip, or undefined for a non-guest.
 */
export async function recordLinkedAccount(
  account: LinkedAccount,
  opts: RekeyOptions = {},
): Promise<{ email: string | null } | undefined> {
  const claims = idTokenClaims(account.idToken);
  const claimEmail = typeof claims.email === "string" ? claims.email.toLowerCase() : null;
  const claimVerified = claims.email_verified === true || claims.email_verified === "true";
  const claimName = typeof claims.name === "string" ? claims.name : null;
  return tx(async (c) => {
    // If even this fails we cannot tell whether the user is a guest, so fail
    // the request rather than risk leaving a real account flagged as one.
    const who = await c
      .query<{ isAnonymous: boolean | null }>(`SELECT "isAnonymous" FROM ba."user" WHERE id = $1 FOR UPDATE`, [
        account.userId,
      ])
      .catch((err: unknown) => {
        throw new GuestLinkError(err);
      });
    await c.query(
      `UPDATE public.profiles
          SET providers = CASE WHEN $2 = ANY(providers) THEN providers ELSE array_append(providers, $2) END,
              updated_at = now()
        WHERE id = $1`,
      [account.userId, account.providerId],
    );
    if (!who.rows[0]?.isAnonymous) return undefined; // not a guest: nothing else changes
    try {
      const { rows } = await c.query<{ email: string; emailVerified: boolean }>(
        `UPDATE ba."user" u
            SET "isAnonymous" = false,
                email = CASE WHEN $2::text IS NOT NULL
                              AND NOT EXISTS (SELECT 1 FROM ba."user" o WHERE o.email = $2 AND o.id <> u.id)
                             THEN $2 ELSE u.email END,
                "emailVerified" = CASE WHEN $2::text IS NOT NULL
                                        AND NOT EXISTS (SELECT 1 FROM ba."user" o WHERE o.email = $2 AND o.id <> u.id)
                                       THEN $3 ELSE u."emailVerified" END,
                "updatedAt" = now()
          WHERE u.id = $1
          RETURNING u.email, u."emailVerified"`,
        [account.userId, claimEmail, claimVerified],
      );
      const email = realEmailOf(rows[0].email);
      await markProfileLinked(c, account.userId, email, email !== null && rows[0].emailVerified, providerDisplayName(claimName, email));
      await opts.beforeCommit?.(c);
      return { email };
    } catch (err) {
      throw new GuestLinkError(err);
    }
  });
}

/** Flips a profile to a real account (email, verification, provider name for a placeholder). */
export async function markProfileLinked(
  c: Queryable,
  id: string,
  email: string | null,
  emailVerified: boolean,
  name: string | null,
): Promise<void> {
  await c.query(
    `UPDATE public.profiles
        SET is_anonymous = false,
            email = coalesce($2, email),
            email_verified = CASE WHEN $2::text IS NULL THEN email_verified ELSE $3 END,
            display_name = CASE WHEN ${IS_PLACEHOLDER} AND ${acceptableName(4)}
                                THEN public.sanitize_text($4::text) ELSE display_name END,
            updated_at = now()
      WHERE id = $1`,
    [id, email, emailVerified, name],
  );
}

/**
 * Mirrors a ba."user" update (email, verification, name) into the profile.
 * Guest defaults ("Anonymous", "Player NNNN", …@anonymous.placeholder.invalid)
 * count as no value and are never copied.
 */
export async function mirrorUserUpdate(user: AuthUser): Promise<void> {
  if (user.isAnonymous) return;
  const email = realEmailOf(user.email);
  await q(
    `UPDATE public.profiles
        SET email = coalesce($2, email),
            email_verified = CASE WHEN $2::text IS NULL THEN email_verified ELSE $3 END,
            is_anonymous = false,
            display_name = CASE WHEN ${IS_PLACEHOLDER} AND ${acceptableName(4)}
                                THEN public.sanitize_text($4::text) ELSE display_name END,
            updated_at = now()
      WHERE id = $1
        AND (($2::text IS NOT NULL AND (email IS DISTINCT FROM $2 OR email_verified IS DISTINCT FROM $3))
             OR is_anonymous
             OR (${IS_PLACEHOLDER} AND $4::text IS NOT NULL))`,
    [user.id, email, Boolean(user.emailVerified) && email !== null, realNameOf(user.name)],
  );
}

/**
 * Repairs what a failed auth hook can leave behind, for the session's user:
 * a missing profile (user.create.after failed) is created, and a guest that
 * already has a linked sign-in account (the anonymous plugin writes none, so
 * any ba.account row is a real credential) is flipped to a real account.
 * One cheap SELECT when nothing needs repair.
 */
export async function syncSessionUser(user: AuthUser): Promise<SessionUser> {
  const anonymous = Boolean(user.isAnonymous);
  const [row] = await q<{ has_profile: boolean; providerId: string | null; idToken: string | null }>(
    `SELECT EXISTS (SELECT 1 FROM public.profiles WHERE id = $1) AS has_profile,
            a."providerId", a."idToken"
       FROM (SELECT 1) one
       LEFT JOIN LATERAL (
         SELECT "providerId", "idToken" FROM ba.account
          WHERE "userId" = $1 AND $2
          ORDER BY "createdAt" DESC LIMIT 1
       ) a ON true`,
    [user.id, anonymous],
  );
  if (!row.has_profile) await ensureProfile(user);
  if (anonymous && row.providerId) {
    const linked = await recordLinkedAccount({ userId: user.id, providerId: row.providerId, idToken: row.idToken });
    if (linked) return { id: user.id, email: linked.email, isAnonymous: false };
  }
  return { id: user.id, email: anonymous ? null : realEmailOf(user.email), isAnonymous: anonymous };
}

/** The session behind an /api/* request, or a 401 in the API's error shape. */
export async function requireSession(
  c: Context,
  auth: SessionSource = getAuth(),
  sync: (user: AuthUser) => Promise<SessionUser> = syncSessionUser,
): Promise<SessionUser> {
  // A lookup failure (e.g. the database is down) propagates as a 500: turning
  // it into a 401 would make the app treat a healthy session as signed out.
  const session = await auth.api.getSession({ headers: c.req.raw.headers });
  if (!session) {
    const res = errorResponse(401, "Not signed in", "UNAUTHORIZED", correlationIdFrom(c.req.raw));
    throw new HTTPException(401, { res });
  }
  return sync(session.user);
}

/** The profile fields the /api/* gate reads. */
export interface ProfileGate {
  id: string;
  is_banned: boolean;
  is_anonymous: boolean;
  deleted_at: Date | null;
  display_name: string;
}

export type BanCheckResult =
  | { ok: true; profile: ProfileGate }
  | { ok: false; status: number; code: string; message: string };

/**
 * The edge functions' banCheck: the caller's profile must exist, not be
 * banned and not be pending deletion. Same statuses, codes and messages.
 */
export async function banCheck(userId: string): Promise<BanCheckResult> {
  let rows: ProfileGate[];
  try {
    rows = await q<ProfileGate>(
      "SELECT id, is_banned, is_anonymous, deleted_at, display_name FROM public.profiles WHERE id = $1 LIMIT 1",
      [userId],
    );
  } catch {
    return { ok: false, status: 500, code: "PROFILE_LOOKUP_FAILED", message: "Could not load profile" };
  }
  const profile = rows[0];
  if (!profile) return { ok: false, status: 403, code: "PROFILE_NOT_FOUND", message: "Profile not found" };
  if (profile.is_banned) return { ok: false, status: 403, code: "BANNED", message: "Account suspended" };
  if (profile.deleted_at) {
    return { ok: false, status: 403, code: "DELETED", message: "Account scheduled for deletion" };
  }
  return { ok: true, profile };
}
