#!/usr/bin/env bash
# Build the release for both stores from a clean tree and upload it.
#
#   scripts/release.sh            # iOS -> TestFlight, Android -> internal + alpha
#   scripts/release.sh ios        # one platform only
#   scripts/release.sh android
#
# Always starts with `flutter clean`: an incremental iOS release build can
# package a simulator slice of a plugin framework and App Store Connect then
# rejects the IPA. Keep the log outside build/ (it is wiped by the clean).
#
# Needs: .env.production, the App Store Connect API key in
# ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8, and
# android/play-store-credentials.json. Nothing here prints secrets.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

ASC_KEY_ID="${ASC_KEY_ID:-9UC6PN6P9K}"
ASC_ISSUER_ID="${ASC_ISSUER_ID:-09ca85e3-ffa2-4b6c-ada5-7c031ec5eb14}"
PLATFORMS="${1:-ios android}"
VERSION="$(grep -E '^version:' pubspec.yaml | awk '{print $2}')"

echo "== $(date) clean ($VERSION)"
flutter clean >/dev/null
flutter pub get >/dev/null
dart run build_runner build --delete-conflicting-outputs | tail -1

if [[ " $PLATFORMS " == *" ios "* ]]; then
  echo "== iOS $VERSION"
  scripts/inject_google_url_scheme.sh .env.production
  trap 'git checkout -- ios/Runner/Info.plist' EXIT
  flutter build ipa --release --export-method app-store \
    --obfuscate --split-debug-info=build/ios/symbols
  git checkout -- ios/Runner/Info.plist
  trap - EXIT
  IPA="$(ls build/ios/ipa/*.ipa | head -1)"
  echo "== upload $IPA"
  xcrun altool --upload-app -f "$IPA" -t ios \
    --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" 2>&1 \
    | grep -E "UPLOAD|Delivery UUID|error|Error" || true
fi

if [[ " $PLATFORMS " == *" android "* ]]; then
  echo "== android $VERSION"
  flutter build appbundle --release --obfuscate \
    --split-debug-info=build/app/outputs/symbols | tail -1
  python3 scripts/play_release.py
fi

echo "== done $(date)"
