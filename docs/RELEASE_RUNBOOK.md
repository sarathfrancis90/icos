# Icos Release Runbook

Every manual step required to ship Icos (`com.icos.game`) to the App Store and
Google Play, in the order to do them. Automated steps live in `.github/workflows/`,
`android/fastlane/` and `ios/fastlane/`; this document covers only what a human must do.

Tick the boxes as you go. Items marked **(once)** are one-time setup; everything else
recurs per release.

---


> **Status 2026-09-09:** The Supabase project **`icos`** (ref `pdvgddvubxldjnemdkok`, us-east-1,
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
- [ ] Access to: Apple Developer Program, Google Play Console, Supabase org, Firebase (optional), DNS for `icos.app`, this GitHub repo's Settings > Secrets

---

## 1. Domain: `icos.app` (needed before universal links / app links verify)

The `docs/` folder is a static site (landing page, privacy policy, terms, `.well-known`).

- [ ] **(once)** GitHub repo > Settings > Pages > Source: *Deploy from a branch*, branch `main`, folder `/docs`
- [ ] **(once)** Custom domain: `icos.app`; tick *Enforce HTTPS* (wait for the certificate)
- [ ] **(once)** DNS at your registrar: `A` records for the apex to GitHub Pages IPs
      (`185.199.108.153`, `185.199.109.153`, `185.199.110.153`, `185.199.111.153`) and a
      `CNAME` for `www` to `<github-user>.github.io`
- [ ] `docs/.nojekyll` exists (it does) so the `.well-known/` directory is published
- [ ] After Apple + Google setup below, fill the placeholders:
  - `docs/.well-known/apple-app-site-association`: replace `TEAMID` with your Apple Team ID (both occurrences)
  - `docs/.well-known/assetlinks.json`: replace `REPLACE_WITH_UPLOAD_KEY_SHA256` with the
    **Play App Signing** certificate SHA-256 (Play Console > Setup > App signing > *App signing key certificate*),
    not the upload key. Add the upload-key fingerprint as a second array entry if you side-load release builds.
- [ ] Verify after deploy:
  ```bash
  curl -sI https://icos.app/.well-known/apple-app-site-association | grep -i content-type   # must be JSON, no redirect
  curl -s https://icos.app/.well-known/assetlinks.json | python3 -m json.tool
  ```
  Then check with https://developer.android.com/training/app-links/verify-android-applinks and
  https://app-site-association.cdn-apple.com/a/v1/icos.app (Apple CDN cache, can take up to 24h).

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
- [ ] **(once)** Authentication > URL Configuration > *Redirect URLs*: add `io.supabase.icos://login-callback` and `https://icos.app/*`
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
- [ ] **(once)** Google Sign-In on iOS: replace `com.googleusercontent.apps.REPLACE_WITH_IOS_CLIENT_ID` in `ios/Runner/Info.plist`
      with the reversed iOS client ID (CI does this automatically from `GOOGLE_IOS_CLIENT_ID`; for local builds edit the file, but do not commit the real value)
- [ ] **(once)** App Store Connect > App > **App Privacy**: answers must match `ios/Runner/PrivacyInfo.xcprivacy` and `docs/privacy-policy.html`:
  - Email Address, User ID, Gameplay Content: linked to identity, app functionality, no tracking
  - Crash Data, Performance Data, Product Interaction: not linked, analytics/app functionality, no tracking
  - Tracking: **No**
- [ ] **(once)** App Information: Privacy Policy URL `https://icos.app/privacy-policy.html`, category *Games > Puzzle*, age rating questionnaire (expect 4+), content rights
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
  - Privacy policy: `https://icos.app/privacy-policy.html`
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
adb shell am start -a android.intent.action.VIEW -d "https://icos.app/join/ABC123" com.icos.game
xcrun simctl openurl booted "https://icos.app/join/ABC123"
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
