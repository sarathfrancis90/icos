-- Better Auth tables (better-auth 1.7.18) in schema `ba`.
--
-- Generated with `npm run auth:generate` (npx auth@1.7.18 generate against a
-- branch with 0001-0003 applied; config scripts/auth_cli.ts: schemaName "ba",
-- generateId "uuid", plugins anonymous/bearer/jwt/expo, database rate limits
-- in model "ratelimit") and hand-adjusted: comments, the REVOKE below, and no
-- BEGIN/COMMIT (the migration runner wraps each file).
--
-- ba."user".id equals public.profiles.id (kept equal by src/identity.ts; no FK
-- between the two). Only the Function's owner role touches this schema: the
-- Data API roles get nothing.

CREATE SCHEMA IF NOT EXISTS ba;

CREATE TABLE ba."user" (
  "id"            uuid DEFAULT pg_catalog.gen_random_uuid() NOT NULL PRIMARY KEY,
  "name"          text NOT NULL,
  "email"         text NOT NULL UNIQUE,
  "emailVerified" boolean NOT NULL,
  "image"         text,
  "createdAt"     timestamptz DEFAULT CURRENT_TIMESTAMP NOT NULL,
  "updatedAt"     timestamptz DEFAULT CURRENT_TIMESTAMP NOT NULL,
  "isAnonymous"   boolean
);

CREATE TABLE ba."session" (
  "id"        uuid DEFAULT pg_catalog.gen_random_uuid() NOT NULL PRIMARY KEY,
  "expiresAt" timestamptz NOT NULL,
  "token"     text NOT NULL UNIQUE,
  "createdAt" timestamptz DEFAULT CURRENT_TIMESTAMP NOT NULL,
  "updatedAt" timestamptz NOT NULL,
  "ipAddress" text,
  "userAgent" text,
  "userId"    uuid NOT NULL REFERENCES ba."user" ("id") ON DELETE CASCADE
);

CREATE TABLE ba."account" (
  "id"                    uuid DEFAULT pg_catalog.gen_random_uuid() NOT NULL PRIMARY KEY,
  "accountId"             text NOT NULL,
  "providerId"            text NOT NULL,
  "userId"                uuid NOT NULL REFERENCES ba."user" ("id") ON DELETE CASCADE,
  "accessToken"           text,
  "refreshToken"          text,
  "idToken"               text,
  "accessTokenExpiresAt"  timestamptz,
  "refreshTokenExpiresAt" timestamptz,
  "scope"                 text,
  "password"              text,
  "createdAt"             timestamptz DEFAULT CURRENT_TIMESTAMP NOT NULL,
  "updatedAt"             timestamptz NOT NULL
);

CREATE TABLE ba."verification" (
  "id"         uuid DEFAULT pg_catalog.gen_random_uuid() NOT NULL PRIMARY KEY,
  "identifier" text NOT NULL,
  "value"      text NOT NULL,
  "expiresAt"  timestamptz NOT NULL,
  "createdAt"  timestamptz DEFAULT CURRENT_TIMESTAMP NOT NULL,
  "updatedAt"  timestamptz DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE ba."jwks" (
  "id"         uuid DEFAULT pg_catalog.gen_random_uuid() NOT NULL PRIMARY KEY,
  "publicKey"  text NOT NULL,
  "privateKey" text NOT NULL,
  "createdAt"  timestamptz NOT NULL,
  "expiresAt"  timestamptz,
  "alg"        text,
  "crv"        text
);

CREATE TABLE ba."ratelimit" (
  "id"          uuid DEFAULT pg_catalog.gen_random_uuid() NOT NULL PRIMARY KEY,
  "key"         text NOT NULL UNIQUE,
  "count"       integer NOT NULL,
  "lastRequest" bigint NOT NULL
);

CREATE INDEX "session_userId_idx" ON ba."session" ("userId");
CREATE INDEX "account_userId_idx" ON ba."account" ("userId");
CREATE INDEX "verification_identifier_idx" ON ba."verification" ("identifier");

REVOKE ALL ON SCHEMA ba FROM PUBLIC, authenticated, anonymous;
REVOKE ALL ON ALL TABLES IN SCHEMA ba FROM PUBLIC, authenticated, anonymous;
