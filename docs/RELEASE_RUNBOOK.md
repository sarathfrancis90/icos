# Icos Release Runbook

Every manual step required to ship Icos (`com.icos.game`) to the App Store and
Google Play, in the order to do them. Automated steps live in `.github/workflows/`,
`android/fastlane/` and `ios/fastlane/`; this document covers only what a human must do.

Tick the boxes as you go. Items marked **(once)** are one-time setup; everything else
recurs per release.

---


> **Status 2026-09-10:** The game was renamed to **Icos** (bundle id `com.icos.game`, auth scheme `io.supabase.icos`, deep-link host `icos.sarathfrancis.work`). The Supabase project is still named **`icos`** in the dashboard (rename it under Project Settings, General); everything else is live: ref `pdvgddvubxldjnemdkok`, us-east-1,
> org "Francis Org") is LIVE with all 21 migrations applied, all 5 edge functions deployed,
> `PUZZLE_SEED_SALT` set, Vault entries (`project_url`, `service_role_key`) created, anonymous
> sign-ins + email/password enabled (email confirmations currently OFF for testing — turn them on
> in `supabase/config.toml` `[auth.email] enable_confirmations = true` and `supabase config push`
> before launch), the app-scheme redirect `io.supabase.icos://login-callback` registered, and
> 16 days of puzzles seeded (2026-09-08 → 2026-09-23). `.env.development` / `.env.production`
> already point at it. Migrations were applied through the Supabase MCP, so before the first
> `supabase db push` run `supabase link --project-ref pdvgddvubxldjnemdkok` and then
> `supabase migration repair --status applied <version>` for each file in `supabase/migrations/`
> (or `supabase migration list` to compare). Google / Apple OAuth providers are NOT configured yet
> (sections 3 and 5 below). Firebase is not configured (optional).

## 0. Prerequisites (local machine)

- [ ] macOS with Xcode 16+ and Command Line Tools (`xcode-select --install`)
- [ ] Flutter **3.41.3** (`.fvmrc` pins it; `fvm install` or `flutter version` to match)
- [ ] Java 17 and the Android SDK (`flutter doctor` must be green for Android + iOS). Android Studio's bundled JDK 25 is NOT supported by Gradle; point Flutter at Homebrew's JDK 17 once:
  `flutter config --jdk-dir="$(/usr/libexec/java_home -v 17)"` (already done on this Mac on 2026-09-09)
- [ ] CocoaPods specs up to date: `cd ios && pod repo update && pod install` (first iOS build after the Firebase/notification plugins were added needs this)
- [ ] Ruby 3.3 + Bundler: `bundle install` at the repo root installs fastlane and CocoaPods
- [ ] Deno 2.x (`brew install deno`) and the Supabase CLI (`brew install supabase/tap/supabase`)
- [ ] Access to: Apple Developer Program, Google Play Console, Supabase org, Firebase (optional), DNS for `icos.sarathfrancis.work`, this GitHub repo's Settings > Secrets

---

## 0b. Status of the automated setup (2026-09-11)

Done automatically via the App Store Connect API (`scripts/asc.py`):

| Item | Value |
|---|---|
| App record | `Icos: Daily Path Puzzle`, bundle `com.icos.game`, SKU `icos-ios`, Apple ID `6810895361` |
| Builds uploaded | 1.0 (1), (2) and (3), all processed. Build **3** (the line redesign) is attached to version 1.0 |
| Category | Games / Puzzle (secondary: Board) |
| Age rating | All content descriptors "None" (expect 4+) |
| Name, subtitle, description, keywords, promo text | Uploaded (en-US) |
| Support + marketing URL | `https://icos.sarathfrancis.work/` |
| Privacy policy URL | `https://icos.sarathfrancis.work/privacy-policy.html` |
| Screenshots | 7x iPhone 6.7" + 7x iPad 12.9", all processed. Re-shot 2026-09-11 from the line-redesign build, dark mode |
| App preview | 27s iPhone 6.7" gameplay video, 886x1920, accepted |
| Pricing | Free, base territory USA, all territories |
| Content rights | Does not use third-party content |
| Review contact | Sarath Francis, sarathfrancis90@gmail.com, **phone is a placeholder — replace it** |
| Demo account | Not required (guest play) |
| Release type | Manual (you press Release after approval) |

**Remaining blocker for submission: App Privacy.** Apple does not expose the data-usage
questionnaire in the API, so it must be answered once in the web UI:
App Store Connect > Icos > App Privacy > Get Started, then Publish.

Answer exactly this (it matches `ios/Runner/PrivacyInfo.xcprivacy` and the privacy policy):

| Data type | Collected | Linked to identity | Tracking | Purpose |
|---|---|---|---|---|
| Contact Info > Email Address | Yes (optional sign-up) | Yes | No | App Functionality |
| User Content > Other User Content (display name, group names) | Yes | Yes | No | App Functionality |
| Identifiers > User ID | Yes | Yes | No | App Functionality |
| Usage Data > Product Interaction | Yes | No | No | Analytics |
| Diagnostics > Crash Data | Yes | No | No | App Functionality |
| Diagnostics > Performance Data | Yes | No | No | App Functionality |

Everything else: **not collected**. "Do you or your third-party partners use data for
tracking?" -> **No**.

Then in App Store Connect press **Add for Review** > **Submit to App Review**. (The review
submission record already exists; adding the version fails until App Privacy is published.)

Also before submitting: replace the placeholder review phone number
(App Review Information > Contact) with a number Apple can actually reach.

### Google Play: one manual step left

The signed bundle is built and staged, but it cannot be pushed from here — Play
publishing needs a service-account key and there is none on this machine
(`android/play-store-credentials.json`, or the `PLAY_STORE_JSON_KEY` env var, both
absent). Either drop that key in and run `bundle exec fastlane android beta`, or upload
by hand:

| File | What it is |
|---|---|
| `release/google-play/icos-1.0.0-3.aab` | version code 3, obfuscated, signed with the upload key |
| `release/google-play/mapping-1.0.0-3.txt` | deobfuscation mapping; upload it alongside the bundle |
| `release/google-play/screenshots/` | 7 phone screenshots, 1080x2400, re-shot from this build |

### Store assets, and how they are produced

Screenshots are captured from a real device running a real solve, not composited.
`scripts/board_from_screen.py` reads the puzzle off the screen via the accessibility
tree, `test/visual/solve_board.dart` solves it with the app's own solver, and the
resulting cell order is replayed as taps. That means a fresh set can be shot on any day,
against whatever the daily puzzle happens to be.

Upload with `scripts/upload_screenshots.py` and `scripts/upload_preview.py`; `fastlane
deliver` silently uploads nothing when it cannot map a resolution to a display type.

App previews must carry a **stereo audio track**, even a silent one. Without it App Store
Connect accepts the upload and then fails the asset with `MOV_RESAVE_STEREO`.

---

## 1. Domain: `icos.sarathfrancis.work` (needed before universal links / app links verify)

The `docs/` folder is a static site (landing page, privacy policy, terms, `.well-known`).

- [ ] **(once)** GitHub repo > Settings > Pages > Source: *Deploy from a branch*, branch `main`, folder `/docs`
- [ ] **(once)** Custom domain: `icos.sarathfrancis.work`; tick *Enforce HTTPS* (wait for the certificate)
- [ ] **(once)** DNS at the registrar for `sarathfrancis.work`: one `CNAME` record,
      host `icos`, value `sarathfrancis90.github.io.` (note the trailing dot; no A records
      are needed for a subdomain). `docs/CNAME` already contains `icos.sarathfrancis.work`
- [ ] `docs/.nojekyll` exists (it does) so the `.well-known/` directory is published
- [ ] After Apple + Google setup below, fill the placeholders:
  - `docs/.well-known/apple-app-site-association`: DONE (Team ID `H845PX7Q62`)
  - `docs/.well-known/assetlinks.json`: replace `REPLACE_WITH_PLAY_APP_SIGNING_SHA256` with the
    **Play App Signing** certificate SHA-256 (Play Console > Setup > App signing > *App signing key certificate*),
    not the upload key. Add the upload-key fingerprint as a second array entry if you side-load release builds.
- [ ] Verify after deploy:
  ```bash
  curl -sI https://icos.sarathfrancis.work/.well-known/apple-app-site-association | grep -i content-type   # must be JSON, no redirect
  curl -s https://icos.sarathfrancis.work/.well-known/assetlinks.json | python3 -m json.tool
  ```
  Then check with https://developer.android.com/training/app-links/verify-android-applinks and
  https://app-site-association.cdn-apple.com/a/v1/icos.sarathfrancis.work (Apple CDN cache, can take up to 24h).

---

## 2. Supabase project

- [ ] **(once)** Create the production project at https://supabase.com/dashboard (region close to your users; note the **Project ref**)
- [ ] **(once)** Link and push the schema:
  ```bash
  supabase login
  supabase link --project-ref <PROJECT_REF>
  supabase db push                       # applies supabase/migrations/*
  supabase functions deploy daily-puzzle
  supabase functions deploy submit-score
  supabase functions deploy join-group
  ```
- [ ] **(once)** Edge-function secrets:
  ```bash
  openssl rand -hex 32                   # -> PUZZLE_SEED_SALT (keep it forever; puzzles are derived from it)
  supabase secrets set PUZZLE_SEED_SALT=<value>
  ```
- [ ] **(once)** Vault entries (Dashboard > Project Settings > Vault) used by the daily cron:
      `service_role_key` = the service-role key, `project_url` = `https://<PROJECT_REF>.supabase.co`
- [ ] **(once)** Authentication > Providers:
  - Enable **Anonymous sign-ins**
  - **Email**: enable; disable "Confirm email" only if you want frictionless upgrade (recommended: keep confirmation on)
  - **Google**: Client ID = the *Web* client ID, Client secret = its secret (from step 5); add the iOS client ID to *Authorized Client IDs*
  - **Apple**: Services ID + Team ID + Key ID + private key (`.p8`) from step 3; also list the bundle id `com.icos.game` in *Authorized Client IDs*
- [ ] **(once)** Authentication > URL Configuration > *Redirect URLs*: add `io.supabase.icos://login-callback` and `https://icos.sarathfrancis.work/*`
- [ ] **(once)** Database > Replication (Realtime): enable the `group_feed` table (and any other table the client subscribes to)
- [ ] **(once)** Copy **Project URL** and **anon key** (Project Settings > API) into `.env.production` locally and into GitHub secrets `SUPABASE_URL` / `SUPABASE_ANON_KEY`; copy the **service_role** key into `SUPABASE_SERVICE_ROLE_KEY` (GitHub only, never in the app)
- [ ] Seed the first two weeks of puzzles: run the *Generate daily puzzles* workflow manually (Actions > Generate daily puzzles > Run workflow), or locally:
  ```bash
  SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... deno run -A scripts/generate_puzzles.ts daily --days 14 --salt "$PUZZLE_SEED_SALT"
  ```
- [ ] Per release: `supabase db push` and `supabase functions deploy` for anything changed since the last tag

---

## 3. Apple Developer + App Store Connect

- [ ] **(once)** Enrol in the Apple Developer Program (Individual or Organisation). Note the **Team ID** (Membership page, 10 chars) -> secret `APPLE_TEAM_ID`
- [ ] **(once)** Certificates, IDs & Profiles > Identifiers > **App ID** `com.icos.game` (explicit) with capabilities:
  - Associated Domains
  - Push Notifications
  - Sign in with Apple
- [ ] **(once)** Identifiers > **Services ID** (e.g. `com.icos.game.signin`) with Sign in with Apple enabled;
      configure it with domain `<PROJECT_REF>.supabase.co` and return URL `https://<PROJECT_REF>.supabase.co/auth/v1/callback`
- [ ] **(once)** Keys > **Sign in with Apple key** (`.p8`): note Key ID; upload to Supabase Apple provider (step 2)
- [ ] **(once)** Keys > **APNs key** (`.p8`, "Apple Push Notifications service"): upload to Firebase > Project settings > Cloud Messaging > Apple app configuration (step 5). Skip if not using push
- [ ] **(once)** App Store Connect > Users and Access > Integrations > **App Store Connect API** > Generate key with *App Manager* role.
      Download the `.p8` **once** (cannot be re-downloaded). Record:
      - Key ID -> secret `ASC_KEY_ID`
      - Issuer ID -> secret `ASC_ISSUER_ID`
      - `base64 -i AuthKey_XXXX.p8 | pbcopy` -> secret `ASC_KEY_P8_BASE64`
- [ ] **(once)** App Store Connect > Apps > **+ New App**: iOS, name *Icos*, primary language English (U.S.), bundle ID `com.icos.game`, SKU `icos-ios`.
      Note the **ITC team ID** (visible in the URL of https://appstoreconnect.apple.com/access/users or via `fastlane spaceship`) -> secret `APPLE_ITC_TEAM_ID`. Your Apple account email -> secret `APPLE_ID`
- [ ] **(once)** Code signing via **match**:
  ```bash
  # 1. create a PRIVATE git repo, e.g. github.com/<you>/icos-certificates
  # 2. from the repo root:
  export MATCH_GIT_URL=git@github.com:<you>/icos-certificates.git
  export MATCH_PASSWORD='<strong passphrase>'          # -> secret MATCH_PASSWORD
  export APPLE_TEAM_ID=<TEAM_ID> APPLE_ITC_TEAM_ID=<ITC_ID> APPLE_ID=<email>
  cd ios && bundle exec fastlane match appstore        # creates distribution cert + App Store profile
  ```
  For CI, create a GitHub **personal access token** (classic, `repo` scope) on an account that can read the
  certificates repo and set `MATCH_GIT_BASIC_AUTHORIZATION` = `echo -n "<github-user>:<token>" | base64`.
  Use the HTTPS form of the repo URL in `MATCH_GIT_URL` when using basic auth.
- [ ] **(once)** Google Sign-In on iOS: set the `GOOGLE_IOS_CLIENT_ID` secret. `deploy-ios.yml` appends the reversed client ID as a URL scheme in `ios/Runner/Info.plist` at build time. Info.plist must NOT contain a placeholder scheme: App Store validation rejects it with error 90158
- [ ] **(once)** App Store Connect > App > **App Privacy**: answers must match `ios/Runner/PrivacyInfo.xcprivacy` and `docs/privacy-policy.html`:
  - Email Address, User ID, Gameplay Content: linked to identity, app functionality, no tracking
  - Crash Data, Performance Data, Product Interaction: not linked, analytics/app functionality, no tracking
  - Tracking: **No**
- [ ] **(once)** App Information: Privacy Policy URL `https://icos.sarathfrancis.work/privacy-policy.html`, category *Games > Puzzle*, age rating questionnaire (expect 4+), content rights
- [ ] **(once)** Sign in with Apple review requirement: because the app offers Google sign-in it **must** also offer Sign in with Apple (it does); keep both visible on the sign-in screen
- [ ] Per release: bump `version:` in `pubspec.yaml` (`1.0.0+3` -> build number must be higher than the last upload), commit, tag `vX.Y.Z`, push the tag. `deploy-ios.yml` uploads to TestFlight
- [ ] Per release: TestFlight > add the build to a test group (internal testers need no review; external testers require a short beta review)
- [ ] Per release: promote to review — either in ASC (select build, fill "What's New", submit) or:
  ```bash
  cd ios && bundle exec fastlane release build_number:<N>
  ```
  Then release manually in ASC once approved (`automatic_release` is off)

---

## 4. Google Play Console

- [ ] **(once)** Register a Play Console developer account (one-time fee). **New personal accounts must run a closed test with at least 12 testers opted-in continuously for 14 days before production access is granted** — start this as early as possible
- [ ] **(once)** Create the upload keystore (keep it and the passwords in a password manager; losing it means a new app listing):
  ```bash
  keytool -genkey -v \
    -keystore ~/icos-upload-keystore.jks \
    -keyalg RSA -keysize 2048 -validity 10000 \
    -alias upload \
    -dname "CN=Icos, OU=Mobile, O=Icos, L=City, ST=State, C=US"
  ```
  Then locally create `android/key.properties` (git-ignored):
  ```
  storePassword=<store password>
  keyPassword=<key password>
  keyAlias=upload
  storeFile=/Users/<you>/icos-upload-keystore.jks
  ```
  GitHub secrets: `ANDROID_KEYSTORE_BASE64` = `base64 -i ~/icos-upload-keystore.jks | pbcopy`,
  `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_PASSWORD`, `ANDROID_KEY_ALIAS` (= `upload`)
- [ ] **(once)** Play Console > **Create app**: name *Icos*, default language English (US), App, Free
- [ ] **(once)** Setup > **App signing**: accept *Play App Signing* (Google holds the signing key; you keep the upload key). After the first upload, copy the *App signing key certificate* SHA-256 into `docs/.well-known/assetlinks.json` (step 1)
- [ ] **(once)** Service account for fastlane: Google Cloud Console > IAM > Service accounts > create `icos-play-publisher`, create a **JSON key**;
      Play Console > Users and permissions > Invite new users > paste the service-account email with *Release manager* rights (or app-level: Release to production, Manage testing tracks).
      Secret `PLAY_STORE_CREDENTIALS` = `base64 -i service-account.json | pbcopy`. Locally save it as `android/play-store-credentials.json` (git-ignored)
- [ ] **(once)** First upload **must be manual** (fastlane cannot create the first release): build locally (section 7) and upload the AAB to *Internal testing* in the console
- [ ] **(once)** Policy > App content, answer every item:
  - Privacy policy: `https://icos.sarathfrancis.work/privacy-policy.html`
  - Ads: No
  - App access: all functionality available without special access (guest mode) — provide a test account anyway
  - Content rating questionnaire (IARC): Game > Puzzle; no violence/gambling/user-generated *media*; expect *Everyone*
  - Target audience: 13+ (do not target children)
  - **Data safety** — must match the privacy policy and `PrivacyInfo.xcprivacy`:
    | Data type | Collected | Shared | Required | Purpose |
    |---|---|---|---|---|
    | Personal info > Email address | Yes (optional, on sign-up) | No | Optional | Account management |
    | Personal info > Name (display name) | Yes | No | Optional | App functionality, Account management |
    | Personal info > User IDs | Yes | No | Required | App functionality, Account management |
    | App activity > In-app actions / Other user-generated content (solve records, group names) | Yes | No | Required | App functionality |
    | App info & performance > Crash logs, Diagnostics | Yes | No | Required | Analytics |
    | Device or other IDs (Firebase instance id) | Yes | No | Required | Analytics |
    Encrypted in transit: **Yes**. Deletion mechanism: **Yes** (in-app, Profile > Delete account). Security practices: independent review **No**
  - News app: No; COVID: No; Government app: No; Financial features: No; Health: No
  - Advertising ID: **No** (we do not use AAID; if Firebase Analytics is enabled, answer *Yes* and state Analytics)
- [ ] **(once)** Grow > Store presence > Main store listing: short/full description (`release/google-play/store_listing.txt`),
      icon `release/google-play/hi_res_icon.png` (512x512), feature graphic `release/google-play/feature_graphic.png` (1024x500), phone screenshots (`release/google-play/screenshots/`)
- [ ] **(once)** Testing > Closed testing > create track *beta* with an email list of >= 12 testers; share the opt-in link; wait 14 days; then *Apply for production access* (Dashboard)
- [ ] Per release: tag `vX.Y.Z` -> `deploy-android.yml` uploads to *internal*. To promote without rebuilding:
  ```bash
  cd android && bundle exec fastlane promote_to_production          # internal -> production
  cd android && bundle exec fastlane promote_to_production from:beta
  ```
  or run *Deploy Android* manually with `track = beta|production`
- [ ] Per release: Play Console > Production > review release notes > *Start rollout* (start with a staged rollout, e.g. 20%)

---

## 5. Google Cloud OAuth (Google Sign-In) — required for the Google provider

- [ ] **(once)** Google Cloud Console > APIs & Services > OAuth consent screen: External, app name Icos, support email, privacy policy URL, scopes `email`, `profile`, `openid`; publish (verification not needed for these scopes)
- [ ] **(once)** Credentials > Create OAuth client ID:
  - **Web application** (used by Supabase and as Android `serverClientId`): authorised redirect URI `https://<PROJECT_REF>.supabase.co/auth/v1/callback` -> `GOOGLE_WEB_CLIENT_ID` (+ secret for Supabase)
  - **Android**: package `com.icos.game`, SHA-1 of **both** the upload key (`keytool -list -v -keystore ~/icos-upload-keystore.jks -alias upload`) and the Play App Signing key (Play Console > App signing) — create one client per fingerprint
  - **iOS**: bundle ID `com.icos.game` -> `GOOGLE_IOS_CLIENT_ID`
- [ ] Put the two IDs into `.env.production` locally and GitHub secrets `GOOGLE_WEB_CLIENT_ID`, `GOOGLE_IOS_CLIENT_ID`

---

## 6. Firebase (optional — analytics, Crashlytics, push)

Skip this section entirely if you launch without Firebase; leave the `FIREBASE_*` secrets empty.

- [ ] **(once)** https://console.firebase.google.com > Add project (you can reuse the Google Cloud project from step 5 so the OAuth clients are shared)
- [ ] **(once)** Add **Android app** `com.icos.game` with both SHA-1/SHA-256 fingerprints; download `google-services.json` -> `android/app/google-services.json` locally (git-ignored) and secret `GOOGLE_SERVICES_JSON_BASE64`
- [ ] **(once)** Add **iOS app** `com.icos.game`; download `GoogleService-Info.plist` -> `ios/Runner/GoogleService-Info.plist` locally (git-ignored, must also be added to the Runner target in Xcode if you build locally) and secret `GOOGLE_SERVICE_INFO_PLIST_BASE64`
- [ ] **(once)** Copy Project settings values into `.env.production` / secrets: `FIREBASE_PROJECT_ID`, `FIREBASE_MESSAGING_SENDER_ID`, `FIREBASE_STORAGE_BUCKET`, `FIREBASE_ANDROID_API_KEY`, `FIREBASE_ANDROID_APP_ID`, `FIREBASE_IOS_API_KEY`, `FIREBASE_IOS_APP_ID`
- [ ] **(once)** Cloud Messaging > Apple app configuration > upload the APNs key from step 3
- [ ] **(once)** Crashlytics > enable for both apps (first crash report activates the dashboard)

---

## 7. Local release builds (sanity check before the first CI run)

```bash
# Fill .env.production (copy .env.example, real values). It is git-ignored and bundled as an asset.
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze --fatal-warnings && flutter test

# Android — requires android/key.properties. Without it the build FAILS on purpose;
# set ALLOW_DEBUG_SIGNING=true only for throw-away local testing.
#
# Do NOT add --no-pub here. Flutter regenerates GeneratedPluginRegistrant.java as
# part of the pub step, and only then does it drop dev-dependency plugins. Skip
# it and the release build fails with
#   "package dev.flutter.plugins.integration_test does not exist".
flutter build appbundle --release --obfuscate --split-debug-info=build/app/outputs/symbols --dart-define-from-file=.env.production
#   -> build/app/outputs/bundle/release/app-release.aab
#   -> build/app/outputs/mapping/release/mapping.txt   (upload with the AAB; fastlane does this)

# iOS — mirrors the beta lane
cd ios && pod install && cd ..
export MATCH_GIT_URL=... MATCH_PASSWORD=... APPLE_TEAM_ID=... APPLE_ITC_TEAM_ID=... APPLE_ID=... \
       ASC_KEY_ID=... ASC_ISSUER_ID=... ASC_KEY_PATH=$PWD/ios/AuthKey.p8
cd ios && bundle exec fastlane beta
```

Test deep links on a device:
```bash
adb shell am start -a android.intent.action.VIEW -d "https://icos.sarathfrancis.work/join/ABC123" com.icos.game
xcrun simctl openurl booted "https://icos.sarathfrancis.work/join/ABC123"
```

---

## 8. GitHub Actions secrets

Repo > Settings > Secrets and variables > Actions. Every secret referenced by a workflow:

| Secret | Used by | Source |
|---|---|---|
| `SUPABASE_URL` | deploy-android, deploy-ios, puzzles | Supabase > Project Settings > API |
| `SUPABASE_ANON_KEY` | deploy-android, deploy-ios | Supabase > Project Settings > API |
| `SUPABASE_SERVICE_ROLE_KEY` | puzzles | Supabase > Project Settings > API (service_role) |
| `PUZZLE_SEED_SALT` | puzzles | `openssl rand -hex 32`; same value as the Supabase secret |
| `GOOGLE_WEB_CLIENT_ID` | deploy-android, deploy-ios | Google Cloud > Credentials (Web client) |
| `GOOGLE_IOS_CLIENT_ID` | deploy-android, deploy-ios | Google Cloud > Credentials (iOS client) |
| `FIREBASE_PROJECT_ID` | deploy-android, deploy-ios (optional) | Firebase > Project settings |
| `FIREBASE_MESSAGING_SENDER_ID` | deploy-android, deploy-ios (optional) | Firebase > Project settings > Cloud Messaging |
| `FIREBASE_STORAGE_BUCKET` | deploy-android, deploy-ios (optional) | Firebase > Project settings |
| `FIREBASE_ANDROID_API_KEY` | deploy-android, deploy-ios (optional) | `google-services.json` > `current_key` |
| `FIREBASE_ANDROID_APP_ID` | deploy-android, deploy-ios (optional) | `google-services.json` > `mobilesdk_app_id` |
| `FIREBASE_IOS_API_KEY` | deploy-android, deploy-ios (optional) | `GoogleService-Info.plist` > `API_KEY` |
| `FIREBASE_IOS_APP_ID` | deploy-android, deploy-ios (optional) | `GoogleService-Info.plist` > `GOOGLE_APP_ID` |
| `GOOGLE_SERVICES_JSON_BASE64` | deploy-android (optional) | `base64 -i google-services.json` |
| `GOOGLE_SERVICE_INFO_PLIST_BASE64` | deploy-ios (optional) | `base64 -i GoogleService-Info.plist` |
| `ANDROID_KEYSTORE_BASE64` | deploy-android | `base64 -i icos-upload-keystore.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | deploy-android | keystore store password |
| `ANDROID_KEY_PASSWORD` | deploy-android | keystore key password |
| `ANDROID_KEY_ALIAS` | deploy-android | `upload` (defaults to `upload` if unset) |
| `PLAY_STORE_CREDENTIALS` | deploy-android | `base64 -i service-account.json` |
| `ASC_KEY_P8_BASE64` | deploy-ios | `base64 -i AuthKey_<KEYID>.p8` |
| `ASC_KEY_ID` | deploy-ios | App Store Connect API key ID |
| `ASC_ISSUER_ID` | deploy-ios | App Store Connect API issuer ID |
| `MATCH_GIT_URL` | deploy-ios | HTTPS URL of the private certificates repo |
| `MATCH_PASSWORD` | deploy-ios | match encryption passphrase |
| `MATCH_GIT_BASIC_AUTHORIZATION` | deploy-ios | `echo -n "user:token" \| base64` |
| `APPLE_TEAM_ID` | deploy-ios | Developer Portal > Membership |
| `APPLE_ITC_TEAM_ID` | deploy-ios | App Store Connect team ID |
| `APPLE_ID` | deploy-ios | Apple account email |

`ci.yml` needs no secrets. Workflows:

| Workflow | Trigger | What it does |
|---|---|---|
| `ci.yml` | PR / push to `main` | codegen, `flutter analyze`, `flutter test`, `deno test` on `supabase/functions/_shared/`, debug APK build |
| `deploy-android.yml` | tag `v*` or manual (track input) | builds signed AAB, uploads AAB + mapping + symbols as artifacts, `fastlane internal|beta|production` |
| `deploy-ios.yml` | tag `v*` or manual | `fastlane beta` (match -> build once -> TestFlight); uploads IPA + dSYM + symbols |
| `puzzles.yml` | daily 00:20 UTC or manual | `deno run -A scripts/generate_puzzles.ts daily --days 14` |

---

## 9. Store listing assets checklist

Text: `release/google-play/store_listing.txt` (Play) and `ios/fastlane/metadata/en-US/*` (App Store).

**App Store Connect (screenshots are required for each size that has no fallback):**
- [ ] iPhone 6.9" (iPhone 16 Pro Max): 1320 x 2868 px — 3 to 10 images (**required**)
- [ ] iPhone 6.7" (iPhone 15 Pro Max/14 Plus): 1290 x 2796 px — optional if 6.9" is supplied
- [ ] iPhone 6.5" (iPhone 11 Pro Max/XS Max): 1284 x 2778 or 1242 x 2688 px — **required** unless 6.9" scales down (ASC now auto-scales; verify in the listing preview)
- [ ] iPhone 5.5" (iPhone 8 Plus): 1242 x 2208 px — optional (only needed if you support < iOS 15; we do not)
- [ ] iPad 13" (iPad Pro M4): 2064 x 2752 px — **required** because `TARGETED_DEVICE_FAMILY = 1,2` (app supports iPad)
- [ ] App icon: supplied by the asset catalog (1024 x 1024, no alpha)
- [ ] App preview video (optional), promotional text (170 chars), description (4000), keywords (100), support URL, marketing URL, copyright

**Google Play:**
- [ ] Phone screenshots: 2 to 8, each side 320-3840 px, aspect 16:9 or 9:16 (existing: `release/google-play/screenshots/`, 1080 x 2400)
- [ ] 7" and 10" tablet screenshots (optional but avoids the "designed for phones" badge)
- [ ] Hi-res icon 512 x 512 PNG (`release/google-play/hi_res_icon.png`)
- [ ] Feature graphic 1024 x 500 PNG/JPG (`release/google-play/feature_graphic.png`)
- [ ] Short description (80 chars), full description (4000 chars), release notes per track

Capture screenshots with the Maestro flows in `scripts/run_visual_tests.sh` or from a simulator/emulator at the sizes above; no device frames or status-bar edits are required.

---

## 10. Release day sequence (per version)

1. `git checkout main && git pull`; bump `version:` in `pubspec.yaml`; update `ios/fastlane/metadata/en-US/release_notes.txt` and `android/fastlane/metadata/android/en-US/changelogs/default.txt`
2. `supabase db push` / `supabase functions deploy` if backend changed; confirm puzzles exist for the next 14 days (`select puzzle_date from puzzles order by puzzle_date desc limit 14;`)
3. Commit, `git tag vX.Y.Z`, `git push --tags` -> both deploy workflows run
4. Android: verify the internal build on a device, then `fastlane promote_to_production` (or console) with a staged rollout
5. iOS: verify the TestFlight build, then `fastlane release build_number:<N>` or submit from ASC; release manually after approval
6. Watch Crashlytics / Supabase logs for 24 h; keep the previous AAB/IPA artifacts (90-day retention in Actions) for rollback
