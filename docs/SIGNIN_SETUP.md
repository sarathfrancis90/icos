# Setting up Sign in with Google and Sign in with Apple

Everything below is specific to this project. Values you can copy are in code blocks.

Sign-in runs on Better Auth inside the Neon Function `api` (`backend/src/auth.ts`).
Google and Apple redirect to the Function host, so that host is what you register with
both. A provider is switched on simply by its secrets being present in the Function env
(`backend/.env.neon`, then `neon deploy --env .env.neon -y` from `backend/`).

Verify at any time:

```bash
curl -s https://<function host>/health
curl -s -X POST https://<function host>/auth/sign-in/social \
  -H 'Content-Type: application/json' -d '{"provider":"google","callbackURL":"io.icos://oauth-callback"}'
# 200 with a "url" = provider configured; 404 PROVIDER_NOT_FOUND = env not set
```

## Constants you will need

| Thing | Value |
|---|---|
| Function host (production, `main` branch) | `br-crimson-bird-bbpbnst1-api.compute.c-15.us-east-1.aws.neon.tech` (or `api.icos.sarathfrancis.work` once the custom domain is live) |
| Google OAuth callback | `https://<function host>/auth/callback/google` |
| Apple OAuth callback | `https://<function host>/auth/callback/apple` |
| App redirect scheme | `io.icos` (browser flow returns on `io.icos://oauth-callback`) |
| Apple Services ID | `com.icos.game.signin` |
| iOS bundle ID / Android package | `com.icos.game` |
| Apple Team ID | `H845PX7Q62` |
| Android upload key SHA-1 | `FC:9D:C5:CC:E9:36:16:C4:8F:F1:7C:10:DA:6E:D1:9D:67:EC:8A:36` |
| Android Play app signing SHA-1 | copy from Play Console, see step G3 |

Only the `main` host is registered with Google and Apple, so the browser flows work on
production only; `dev`/`test` branches use native id-token sign-ins.

---

# Part 1: Google

## G1. Configure the OAuth consent screen

Google Cloud Console > APIs & Services > OAuth consent screen. Use the project that
already holds the Play publisher service account, `sarath-personal-471604`, or any
project you prefer.

- User type: **External**
- App name: `Icos`
- Support email and developer contact email: your address
- Authorised domain: `sarathfrancis.work`
- Scopes: the defaults (`email`, `profile`, `openid`) are enough. Add nothing else.
- Publishing status: **Publish app**. Left in Testing, only accounts you list by hand
  can sign in, which looks exactly like a broken button to everyone else.

## G2. Create the Web client

APIs & Services > Credentials > Create credentials > OAuth client ID.

- Type: **Web application**
- Name: `Icos web`
- Authorised redirect URI:
  ```
  https://<function host>/auth/callback/google
  ```

Keep the **Client ID** and **Client secret**. This client is what the Function's Google
provider uses (`GOOGLE_WEB_CLIENT_ID`, `GOOGLE_WEB_CLIENT_SECRET`), and its id doubles as
`serverClientId` for native sign-in, so native id tokens are minted for it.

## G3. Create the Android client

Create credentials > OAuth client ID > **Android**.

- Name: `Icos Android`
- Package name: `com.icos.game`
- SHA-1: `FC:9D:C5:CC:E9:36:16:C4:8F:F1:7C:10:DA:6E:D1:9D:67:EC:8A:36`

Then create a **second** Android client, same package, using the **Play app signing**
SHA-1 from Play Console > Test and release > Setup > App signing.

Both are required. Play re-signs every build with its own key, so a client registered
only against the upload key works from Android Studio and fails from Play with
`DEVELOPER_ERROR` (status 10). This is the single most common way this setup breaks.

While you are on that Play Console page, copy the app signing **SHA-256** too and paste
it into `docs/.well-known/assetlinks.json`, replacing `REPLACE_WITH_PLAY_APP_SIGNING_SHA256`.
Android App Links will not verify until you do.

## G4. Create the iOS client

Create credentials > OAuth client ID > **iOS**.

- Name: `Icos iOS`
- Bundle ID: `com.icos.game`

## G5. Put the ids in the env file

```bash
scripts/set_google_ids.sh <web-client-id> <ios-client-id>
```

Pass the full ids ending in `.apps.googleusercontent.com`. The script validates them,
writes `.env.production`, and re-runs the preflight.

Also set the same two as GitHub secrets `GOOGLE_WEB_CLIENT_ID` and `GOOGLE_IOS_CLIENT_ID`
so CI builds match.

## G6. Turn the provider on in the Function

Add to `backend/.env.neon`:

```
GOOGLE_WEB_CLIENT_ID=<web client id>
GOOGLE_WEB_CLIENT_SECRET=<web client secret>
```

then `neon deploy --env .env.neon -y` from `backend/`. The app's native sign-in sends an
id token whose audience is the web client id (it is passed as `serverClientId`), which is
the id Better Auth checks.

---

# Part 2: Apple

Sign in with Apple needs two halves. Native iOS needs almost nothing (the id token's
audience is the bundle id, which the Function accepts alongside the Services ID). The
web flow, which Android uses, needs a Services ID and a key.

## A1. Confirm the capability on the App ID

Apple Developer > Certificates, Identifiers & Profiles > Identifiers > `com.icos.game`.
**Sign In with Apple** must be ticked. The entitlement is already in
`ios/Runner/Runner.entitlements`, so this is usually a no-op.

## A2. Create a Services ID

Identifiers > **+** > **Services IDs**.

- Description: `Icos Sign in with Apple`
- Identifier: `com.icos.game.signin` (it must differ from the bundle ID)

Save, reopen it, tick **Sign In with Apple**, press **Configure**:

- Primary App ID: `com.icos.game`
- Domains and Subdomains: `<function host>`
- Return URLs:
  ```
  https://<function host>/auth/callback/apple
  ```

### Apple on Android

Android shows the same Sign in with Apple button as iOS, directly under Google. It
always uses the browser flow through Better Auth's authorization proxy
(`/auth/expo-authorization-proxy`, link-social for a guest, sign-in otherwise) with the
Services ID `com.icos.game.signin`; the native Apple SDK is never called on Android.
Nothing extra is needed in Google Play or the Play Console. The Services ID's Return URL
must be the Apple callback in the constants table above, and the app receives the result
on `io.icos://oauth-callback`, which the Android manifest already handles.

## A3. Create a Sign in with Apple key

Keys > **+**.

- Name: `Icos Sign in with Apple`
- Tick **Sign In with Apple**, Configure, Primary App ID `com.icos.game`

Download the `.p8`. It downloads **once**. Note the Key ID.

This is a different key from `ios/AuthKey_9UC6PN6P9K.p8`, which is the App Store Connect
API key. Do not reuse that one.

Save it next to the other one, where git ignores it:

```
ios/AuthKey_SignInWithApple_<KEY_ID>.p8
```

## A4. Turn the provider on in the Function

Add to `backend/.env.neon`:

```
APPLE_SERVICE_ID=com.icos.game.signin
APPLE_TEAM_ID=H845PX7Q62
APPLE_KEY_ID=<KEY_ID>
APPLE_P8_BASE64=<base64 of the .p8 file>      # base64 -i ios/AuthKey_SignInWithApple_<KEY_ID>.p8
```

then `neon deploy --env .env.neon -y`. The Function mints Apple's client secret (an
ES256 JWT, valid 180 days) from the key at boot, so there is nothing to paste or renew
by hand; a redeploy or cold start mints a fresh one.

The app's env files carry `APPLE_SERVICE_ID=com.icos.game.signin` too (the Android
browser flow needs it).

---

# Part 3: Finish

## F1. Verify

Run the curl checks at the top of this page for `google` and `apple`, then sign in on a
real device with each provider, once as a guest with progress (the progress must stay)
and once on a fresh install.

## F2. Rebuild

The iOS URL scheme is injected at build time from `GOOGLE_IOS_CLIENT_ID`, so the client
id must be in place before you build. Both stores need a fresh build with a bumped
version.
