# Setting up Sign in with Google and Sign in with Apple

Everything below is specific to this project. Values you can copy are in code blocks.

Verify progress at any time:

```bash
python3 scripts/check_signin.py
```

It reads Supabase's live provider state, so it tells you the truth rather than what a
config file claims.

## Constants you will need

| Thing | Value |
|---|---|
| Supabase project ref | `pdvgddvubxldjnemdkok` |
| Supabase OAuth callback | `https://pdvgddvubxldjnemdkok.supabase.co/auth/v1/callback` |
| App redirect scheme | `io.supabase.icos://login-callback` |
| iOS bundle ID / Android package | `com.icos.game` |
| Apple Team ID | `H845PX7Q62` |
| Android upload key SHA-1 | `FC:9D:C5:CC:E9:36:16:C4:8F:F1:7C:10:DA:6E:D1:9D:67:EC:8A:36` |
| Android Play app signing SHA-1 | copy from Play Console, see step G3 |

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
- Name: `Icos web (Supabase)`
- Authorised redirect URI:
  ```
  https://pdvgddvubxldjnemdkok.supabase.co/auth/v1/callback
  ```

Keep the **Client ID** and **Client secret**. This client is what Supabase uses, and
its id doubles as `serverClientId` on Android.

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

## G6. Turn the provider on in Supabase

Supabase dashboard > Authentication > Sign In / Providers > **Google**.

- Enable
- Client ID: the **web** client id from G2
- Client Secret: the **web** client secret from G2
- Authorised Client IDs: the **iOS** and **Android** client ids, comma separated

That last field is what makes native sign-in work. The app sends an id token minted for
the iOS or Android client, and Supabase rejects it unless the id is listed.

---

# Part 2: Apple

Sign in with Apple needs two halves. Native iOS needs almost nothing. The web flow,
which Android uses and which every anonymous-account link uses, needs a Services ID and
a key.

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
- Domains and Subdomains: `pdvgddvubxldjnemdkok.supabase.co`
- Return URLs:
  ```
  https://pdvgddvubxldjnemdkok.supabase.co/auth/v1/callback
  ```

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

## A4. Turn the provider on in Supabase

Supabase dashboard > Authentication > Sign In / Providers > **Apple**.

- Enable
- Authorised Client IDs:
  ```
  com.icos.game,com.icos.game.signin
  ```
  The bundle ID covers native iOS; the Services ID covers the web flow.
- Services ID: `com.icos.game.signin`
- Team ID: `H845PX7Q62`
- Key ID: from A3
- Private key: paste the whole contents of the `.p8`, `-----BEGIN` line included

---

# Part 3: Finish

## F1. Allowlist the redirect

Supabase > Authentication > URL Configuration > Redirect URLs, add:

```
io.supabase.icos://login-callback
```

The app signs in anonymously on first launch, so every sign-in press runs through
`linkIdentity`, which is a browser redirect. Without this the browser opens and
dead-ends.

## F2. Verify

```bash
python3 scripts/check_signin.py
```

Everything should read `ok`. If it does not, it names what is missing.

## F3. Rebuild

The iOS URL scheme is injected at build time from `GOOGLE_IOS_CLIENT_ID`, so the client
id must be in place before you build. Both stores need a fresh build with a bumped
version.
