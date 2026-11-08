// Better Auth for Icos, served by the Function under /auth/*.
//
// Tables live in schema `ba` (migrations/0004_better_auth.sql, applied by our
// own runner) with uuid ids, so ba."user".id can equal public.profiles.id. The
// database hooks below keep profiles in step (they replace the Supabase-era
// auth.users triggers). onLinkAccount moves a guest's progress onto the account
// it signs up or signs in with when that account owns no progress yet (no
// attempts, groups or streak; how old the account is does not matter), and
// otherwise discards the guest: an account with progress is never overwritten.
import { expo } from "@better-auth/expo";
import { betterAuth } from "better-auth";
import { anonymous, bearer, jwt } from "better-auth/plugins";
import { importPKCS8, SignJWT } from "jose";
import { PostgresDialect } from "kysely";
import { getPool } from "./db.js";
import { sendEmail as defaultSendEmail } from "./email.js";
import {
  discardGuest,
  ensureProfile,
  GuestLinkError,
  mirrorUserUpdate,
  placeholderName,
  recordLinkedAccount,
  rekeyGuest,
} from "./identity.js";
import { errorFields, Logger } from "./shared/http.js";

const SITE = "https://icos.sarathfrancis.work";
const RESET_URL = `${SITE}/reset`;
const VERIFIED_URL = `${SITE}/verified`;
const APPLE_BUNDLE_ID = "com.icos.game";
const APPLE_SECRET_TTL_S = 180 * 24 * 60 * 60;

export interface AppleConfig {
  clientId: string;
  /** The ES256 client-secret JWT, or a function that mints it on first use. */
  clientSecret: string | (() => Promise<string>);
  appBundleIdentifier: string;
}

/** The identity operations the hooks call; tests swap in failing versions. */
export interface IdentityOps {
  ensureProfile: typeof ensureProfile;
  mirrorUserUpdate: typeof mirrorUserUpdate;
  recordLinkedAccount: typeof recordLinkedAccount;
  rekeyGuest: typeof rekeyGuest;
  discardGuest: typeof discardGuest;
}

export interface AuthDeps {
  sendEmail: typeof defaultSendEmail;
  identity?: Partial<IdentityOps>;
  baseURL: string;
  secret: string;
  google?: { clientId: string; clientSecret: string };
  apple?: AppleConfig;
}

function escapeHtml(s: string): string {
  return s.replace(/[&<>"']/g, (ch) => `&#${ch.charCodeAt(0)};`);
}

function emailBody(intro: string, action: string, link: string, outro: string) {
  const safe = escapeHtml(link);
  return {
    html: `<p>${intro}</p><p><a href="${safe}">${action}</a></p><p>${outro}</p>`,
    text: `${intro}\n\n${action}: ${link}\n\n${outro}`,
  };
}

function hookLogger(hook: string): Logger {
  return new Logger("auth", crypto.randomUUID(), { hook });
}

/** Runs a profile-sync hook; a SQL failure is logged, never thrown into Better Auth. */
async function softly(hook: string, fields: Record<string, unknown>, fn: () => Promise<unknown>): Promise<void> {
  try {
    await fn();
  } catch (err) {
    hookLogger(hook).error("auth hook failed", { ...fields, ...errorFields(err) });
  }
}

export function createAuth(deps: AuthDeps) {
  const { sendEmail } = deps;
  const ops: IdentityOps = {
    ensureProfile,
    mirrorUserUpdate,
    recordLinkedAccount,
    rekeyGuest,
    discardGuest,
    ...deps.identity,
  };
  let appleSecret: Promise<string> | undefined;
  const apple = deps.apple;

  return betterAuth({
    appName: "Icos",
    baseURL: deps.baseURL,
    basePath: "/auth",
    secret: deps.secret,
    database: {
      // Lazy: the pool (and DATABASE_URL) is only needed on the first query.
      dialect: new PostgresDialect({ pool: async () => getPool() }),
      type: "postgres",
      schemaName: "ba",
    },
    trustedOrigins: ["io.icos://", SITE, "https://appleid.apple.com"],
    emailAndPassword: {
      enabled: true,
      requireEmailVerification: false,
      minPasswordLength: 6,
      sendResetPassword: async ({ user, token }) => {
        const link = `${RESET_URL}?token=${encodeURIComponent(token)}`;
        await sendEmail({
          to: user.email,
          subject: "Reset your Icos password",
          ...emailBody(
            "Someone asked to reset the password of your Icos account.",
            "Choose a new password",
            link,
            "If that was not you, ignore this email: your password stays the same.",
          ),
        });
      },
    },
    emailVerification: {
      sendOnSignUp: true,
      autoSignInAfterVerification: false,
      sendVerificationEmail: async ({ user, url }) => {
        const link = new URL(url);
        link.searchParams.set("callbackURL", VERIFIED_URL);
        await sendEmail({
          to: user.email,
          subject: "Confirm your Icos email",
          ...emailBody(
            "Confirm this address for your Icos account.",
            "Confirm email",
            link.toString(),
            "If you did not create an Icos account, ignore this email.",
          ),
        });
      },
    },
    socialProviders: {
      ...(deps.google ? { google: { clientId: deps.google.clientId, clientSecret: deps.google.clientSecret } } : {}),
      ...(apple
        ? {
            apple: async () => {
              const secret = apple.clientSecret;
              appleSecret ??= typeof secret === "string" ? Promise.resolve(secret) : secret();
              return {
                clientId: apple.clientId,
                clientSecret: await appleSecret,
                appBundleIdentifier: apple.appBundleIdentifier,
                audience: [apple.clientId, apple.appBundleIdentifier],
              };
            },
          }
        : {}),
    },
    account: {
      accountLinking: {
        enabled: true,
        allowDifferentEmails: true,
        trustedProviders: ["google", "apple", "email-password"],
      },
    },
    user: { deleteUser: { enabled: false } }, // deletion is our 30-day flow
    session: { expiresIn: 60 * 60 * 24 * 30, updateAge: 60 * 60 * 24 },
    rateLimit: { enabled: true, storage: "database", window: 10, max: 100, modelName: "ratelimit" },
    advanced: {
      database: { generateId: "uuid" },
      ipAddress: { ipAddressHeaders: ["x-forwarded-for"] },
    },
    databaseHooks: {
      user: {
        create: {
          after: async (user) => softly("user.create.after", { user_id: user.id }, () => ops.ensureProfile(user)),
        },
        update: {
          after: async (user) => softly("user.update.after", { user_id: user.id }, () => ops.mirrorUserUpdate(user)),
        },
      },
      account: {
        create: {
          after: async (account) => {
            try {
              await ops.recordLinkedAccount(account);
            } catch (err) {
              hookLogger("account.create.after").error("auth hook failed", {
                user_id: account.userId,
                provider: account.providerId,
                ...errorFields(err),
              });
              // A guest that could not be turned into a real account must fail
              // the request; requireSession also repairs it on the next call.
              if (err instanceof GuestLinkError) throw err;
            }
          },
        },
      },
    },
    plugins: [
      anonymous({
        generateName: () => placeholderName(),
        onLinkAccount: async ({ anonymousUser, newUser }) => {
          const guestId = anonymousUser.user.id;
          const target = newUser.user;
          // The plugin also calls this when the session did not change user
          // (link-social keeps the guest id) or the new session is a guest.
          if (target.id === guestId || target.isAnonymous) return;
          try {
            const outcome = await ops.rekeyGuest(guestId, target);
            if (outcome === "has-progress") await ops.discardGuest(guestId);
          } catch (err) {
            hookLogger("onLinkAccount").error("guest link failed", {
              guest_id: guestId,
              user_id: target.id,
              ...errorFields(err),
            });
            throw err; // a failed re-key must fail the sign-in
          }
        },
      }),
      bearer(),
      jwt({
        jwks: { keyPairConfig: { alg: "ES256" } },
        jwt: {
          expirationTime: "15m",
          definePayload: (s) => ({
            sub: s.user.id,
            role: "authenticated",
            is_anonymous: Boolean(s.user.isAnonymous),
            email: s.user.isAnonymous ? null : (s.user.email ?? null),
          }),
        },
      }),
      expo(),
    ],
  });
}

export type Auth = ReturnType<typeof createAuth>;

/** Apple's client secret: an ES256 JWT signed with the Sign in with Apple key. */
export async function mintAppleClientSecret(opts: {
  p8: string;
  teamId: string;
  keyId: string;
  serviceId: string;
  now?: number;
}): Promise<string> {
  const key = await importPKCS8(opts.p8, "ES256");
  const iat = Math.floor((opts.now ?? Date.now()) / 1000);
  return new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: opts.keyId })
    .setIssuer(opts.teamId)
    .setSubject(opts.serviceId)
    .setAudience("https://appleid.apple.com")
    .setIssuedAt(iat)
    .setExpirationTime(iat + APPLE_SECRET_TTL_S)
    .sign(key);
}

/** APPLE_P8_BASE64 holds the .p8 file base64-encoded (PEM, or bare DER). */
function decodeP8(b64: string): string {
  const raw = Buffer.from(b64, "base64");
  const text = raw.toString("utf8");
  if (text.includes("-----BEGIN")) return text;
  const body = raw.toString("base64").replace(/(.{64})/g, "$1\n");
  return `-----BEGIN PRIVATE KEY-----\n${body}\n-----END PRIVATE KEY-----\n`;
}

/** This Function's own URL, from the variables Neon injects (slug "api"). */
function functionUrl(env: NodeJS.ProcessEnv): string | undefined {
  const { NEON_BRANCH_ID, NEON_FUNCTION_HOST_SUFFIX } = env;
  return NEON_BRANCH_ID && NEON_FUNCTION_HOST_SUFFIX
    ? `https://${NEON_BRANCH_ID}-api${NEON_FUNCTION_HOST_SUFFIX}`
    : undefined;
}

/** Builds the dependencies from the environment; providers only when configured. */
export function authDepsFromEnv(env: NodeJS.ProcessEnv = process.env): AuthDeps {
  const secret = env.BETTER_AUTH_SECRET;
  if (!secret) throw new Error("BETTER_AUTH_SECRET is not set");
  const baseURL = env.AUTH_BASE_URL || functionUrl(env);
  if (!baseURL) throw new Error("AUTH_BASE_URL is not set");
  const deps: AuthDeps = { sendEmail: defaultSendEmail, baseURL, secret };
  if (env.GOOGLE_WEB_CLIENT_ID && env.GOOGLE_WEB_CLIENT_SECRET) {
    deps.google = { clientId: env.GOOGLE_WEB_CLIENT_ID, clientSecret: env.GOOGLE_WEB_CLIENT_SECRET };
  }
  const { APPLE_SERVICE_ID, APPLE_TEAM_ID, APPLE_KEY_ID, APPLE_P8_BASE64 } = env;
  if (APPLE_SERVICE_ID && APPLE_TEAM_ID && APPLE_KEY_ID && APPLE_P8_BASE64) {
    deps.apple = {
      clientId: APPLE_SERVICE_ID,
      appBundleIdentifier: APPLE_BUNDLE_ID,
      clientSecret: () =>
        mintAppleClientSecret({
          p8: decodeP8(APPLE_P8_BASE64),
          teamId: APPLE_TEAM_ID,
          keyId: APPLE_KEY_ID,
          serviceId: APPLE_SERVICE_ID,
        }),
    };
  }
  return deps;
}

let instance: Auth | undefined;

/** The process-wide Better Auth instance, built from the environment on first use. */
export function getAuth(): Auth {
  instance ??= createAuth(authDepsFromEnv());
  return instance;
}
