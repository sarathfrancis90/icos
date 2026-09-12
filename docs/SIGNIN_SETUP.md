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

There is no field called "Authorised Client IDs". Supabase renamed it. The field is
just **Client IDs**, and it takes a comma-separated list — every client, web included:

```
876802621972-tsu3ss64bros8iub3mijmraaj20m3t67.apps.googleusercontent.com,876802621972-29bmvc0vva0n7qn1f9i2ufa0cunmjg8l.apps.googleusercontent.com,876802621972-d1meldlrheldggi3pa22oigfmfeutt8j.apps.googleusercontent.com,876802621972-fc2vik9e4rsgpk1tpu8jhdm1s2cqucmq.apps.googleusercontent.com,876802621972-uganblnaf7r2j4eoh4saqn6uer1mmv1i.apps.googleusercontent.com
```

**Client Secret (for OAuth)** takes the **web** client's secret, and only that one. It
is what the browser redirect flow uses. The native flows send an id token minted for one
of the ids above, and Supabase rejects any id not in that list.

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

The form is shorter than Apple's own docs imply. There are no separate Team ID,
Key ID or Services ID fields, and **Secret Key (for OAuth) does not take the `.p8`**.
Paste the raw key and it rejects it with "Secret key should be a JWT."

- **Client IDs** — **order matters**:
  ```
  com.icos.game.signin,com.icos.game
  ```
  Supabase validates native id tokens against the whole list, but hands the **first**
  entry to Apple as `client_id` for the web redirect. Apple's web flow only accepts a
  Services ID. Put the bundle id first and every web sign-in dies on Apple's side with
  `Invalid client id or web redirect url`, while native iOS sign-in still works, so the
  app looks half-broken for no visible reason.
- **Secret Key (for OAuth)**: an ES256 JWT signed with the `.p8`. Apple calls this the
  client secret. The team id, key id and services id all live inside it as claims,
  which is why the form does not ask for them separately. Generate it with:
  ```bash
  python3 scripts/apple_client_secret.py --key-id <KEY_ID> --copy
  ```
  `--copy` puts it on the clipboard rather than leaving it in terminal scrollback.
- **Allow users without an email**: leave off. Apple always returns an email for this
  app's scopes, and off is the safer default.

Apple caps the client secret at **six months**. The dashboard warns about this. When it
expires, web sign-in breaks and native iOS sign-in keeps working, which makes for a
confusing bug report. Re-run the script and paste the new value.

---

# Part 3: Finish

## F1. Enable manual linking

Supabase dashboard > Authentication > Sign In / Providers, scroll to the bottom, and
turn on **Manual Linking**. It is off by default.

This one is not optional and not obvious. The app signs in anonymously on first launch,
so pressing any sign-in button calls `linkIdentity` to attach the provider to that guest
user and carry the progress across. With manual linking off, Supabase answers:

```
404 {"error_code":"manual_linking_disabled","msg":"Manual linking is disabled"}
```

The app catches it and shows "Something went wrong. Please try again." Every provider
fails identically, which makes it look like the OAuth setup is wrong when it is fine.

## F2. Allowlist the redirect

Supabase > Authentication > URL Configuration > Redirect URLs, add:

```
io.supabase.icos://login-callback
```

The app signs in anonymously on first launch, so every sign-in press runs through
`linkIdentity`, which is a browser redirect. Without this the browser opens and
dead-ends.

## F3. Verify

```bash
python3 scripts/check_signin.py
```

Everything should read `ok`. If it does not, it names what is missing.

## F4. Rebuild

The iOS URL scheme is injected at build time from `GOOGLE_IOS_CLIENT_ID`, so the client
id must be in place before you build. Both stores need a fresh build with a bumped
version.
