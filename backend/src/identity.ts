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
import { q, tx } from "./db.js";
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
const FRESH_ACCOUNT_MS = 60_000;

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

/** The email worth storing: null for a guest's placeholder address. */
function realEmail(user: AuthUser): string | null {
  return user.isAnonymous ? null : (user.email ?? null);
}

/** Creates the user's profile row if it does not exist yet. */
export async function ensureProfile(user: AuthUser): Promise<void> {
  const anonymous = Boolean(user.isAnonymous);
  const provided = anonymous ? null : providerDisplayName(user.name, user.email);
  await q(
    `INSERT INTO public.profiles (id, is_anonymous, email, email_verified, display_name)
     VALUES ($1, $2, $3, $4,
             CASE WHEN ${acceptableName(5)} THEN public.sanitize_text($5::text) ELSE $6 END)
     ON CONFLICT (id) DO NOTHING`,
    [user.id, anonymous, realEmail(user), Boolean(user.emailVerified) && !anonymous, provided, placeholderName()],
  );
}

/**
 * True when `newUser` was created moments ago and owns no progress yet, i.e.
 * the guest is signing UP (keep the guest's progress) rather than signing in
 * to an existing account (the guest's progress is discarded).
 */
export async function isFreshAccount(newUser: AuthUser): Promise<boolean> {
  const created = newUser.createdAt ? new Date(newUser.createdAt).getTime() : Number.NaN;
  if (!Number.isFinite(created) || Date.now() - created > FRESH_ACCOUNT_MS) return false;
  const [row] = await q<{ has_data: boolean }>(
    `SELECT EXISTS (SELECT 1 FROM public.puzzle_attempts WHERE user_id = $1)
         OR EXISTS (SELECT 1 FROM public.group_members WHERE user_id = $1)
         OR EXISTS (SELECT 1 FROM public.streaks WHERE user_id = $1) AS has_data`,
    [newUser.id],
  );
  return !row.has_data;
}

/**
 * Moves the guest's profile (and through ON UPDATE CASCADE all of its app data)
 * onto `newUser.id`, replacing the empty profile the sign-up just created.
 * Idempotent: returns false when the guest profile is already gone.
 */
export async function rekeyGuest(guestId: string, newUser: AuthUser): Promise<boolean> {
  if (guestId === newUser.id) return false;
  return tx(async (c) => {
    const guest = await c.query("SELECT 1 FROM public.profiles WHERE id = $1 FOR UPDATE", [guestId]);
    if (guest.rowCount === 0) return false;
    const fresh = await c.query<{ providers: string[] }>(
      "DELETE FROM public.profiles WHERE id = $1 RETURNING providers",
      [newUser.id],
    );
    await c.query(
      `UPDATE public.profiles
          SET id = $2,
              is_anonymous = false,
              email = $3,
              email_verified = $4,
              providers = ARRAY(SELECT DISTINCT unnest(providers || $5::text[]) ORDER BY 1),
              display_name = CASE WHEN ${IS_PLACEHOLDER} AND ${acceptableName(6)}
                                  THEN public.sanitize_text($6::text) ELSE display_name END,
              updated_at = now()
        WHERE id = $1`,
      [
        guestId,
        newUser.id,
        newUser.email ?? null,
        Boolean(newUser.emailVerified),
        fresh.rows[0]?.providers ?? [],
        providerDisplayName(newUser.name, newUser.email),
      ],
    );
    return true;
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
 * After an account (credential, google, apple) is attached to a user: record
 * the provider and, when it was attached to a guest (/auth/link-social keeps
 * the guest's id), turn the guest into a real account: ba."user" and the
 * profile stop being anonymous, take the provider's email when nobody else
 * uses it, and a placeholder name becomes the provider's name.
 */
export async function recordLinkedAccount(account: LinkedAccount): Promise<void> {
  const claims = idTokenClaims(account.idToken);
  const claimEmail = typeof claims.email === "string" ? claims.email.toLowerCase() : null;
  const claimVerified = claims.email_verified === true || claims.email_verified === "true";
  const claimName = typeof claims.name === "string" ? claims.name : null;
  await tx(async (c) => {
    await c.query(
      `UPDATE public.profiles
          SET providers = CASE WHEN $2 = ANY(providers) THEN providers ELSE array_append(providers, $2) END,
              updated_at = now()
        WHERE id = $1`,
      [account.userId, account.providerId],
    );
    const { rows } = await c.query<{ email: string; emailVerified: boolean; name: string | null }>(
      `UPDATE ba."user" u
          SET "isAnonymous" = false,
              email = CASE WHEN $2::text IS NOT NULL
                            AND NOT EXISTS (SELECT 1 FROM ba."user" o WHERE o.email = $2 AND o.id <> u.id)
                           THEN $2 ELSE u.email END,
              "emailVerified" = CASE WHEN $2::text IS NOT NULL
                                      AND NOT EXISTS (SELECT 1 FROM ba."user" o WHERE o.email = $2 AND o.id <> u.id)
                                     THEN $3 ELSE u."emailVerified" END,
              "updatedAt" = now()
        WHERE u.id = $1 AND u."isAnonymous"
        RETURNING u.email, u."emailVerified", u.name`,
      [account.userId, claimEmail, claimVerified],
    );
    const user = rows[0];
    if (!user) return; // not a guest: nothing else changes
    const email = user.email.endsWith("@anonymous.placeholder.invalid") ? null : user.email;
    await markProfileLinked(c, account.userId, email, email !== null && user.emailVerified, providerDisplayName(claimName, email));
  });
}

async function markProfileLinked(
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

/** Mirrors a ba."user" update (email, verification, name) into the profile. */
export async function mirrorUserUpdate(user: AuthUser): Promise<void> {
  if (user.isAnonymous) return;
  await q(
    `UPDATE public.profiles
        SET email = $2,
            email_verified = $3,
            is_anonymous = false,
            display_name = CASE WHEN ${IS_PLACEHOLDER} AND ${acceptableName(4)}
                                THEN public.sanitize_text($4::text) ELSE display_name END,
            updated_at = now()
      WHERE id = $1
        AND (email IS DISTINCT FROM $2 OR email_verified IS DISTINCT FROM $3 OR is_anonymous
             OR (${IS_PLACEHOLDER} AND $4::text IS NOT NULL))`,
    [user.id, user.email ?? null, Boolean(user.emailVerified), user.name?.trim() || null],
  );
}

/** The session behind an /api/* request, or a 401 in the API's error shape. */
export async function requireSession(c: Context, auth: SessionSource = getAuth()): Promise<SessionUser> {
  // A lookup failure (e.g. the database is down) propagates as a 500: turning
  // it into a 401 would make the app treat a healthy session as signed out.
  const session = await auth.api.getSession({ headers: c.req.raw.headers });
  if (!session) {
    const res = errorResponse(401, "Not signed in", "UNAUTHORIZED", correlationIdFrom(c.req.raw));
    throw new HTTPException(401, { res });
  }
  const { user } = session;
  return {
    id: user.id,
    email: user.isAnonymous ? null : (user.email ?? null),
    isAnonymous: Boolean(user.isAnonymous),
  };
}
