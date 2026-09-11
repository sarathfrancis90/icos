#!/usr/bin/env bash
# Append the reversed Google iOS client ID to Info.plist as a URL scheme.
#
# Google Sign-In needs the scheme, but it must not be committed: App Store
# validation rejects placeholder schemes with error 90158. So it is injected at
# build time and reverted afterwards.
#
# Refuses to write anything unless the client id is real. A blank or REPLACE_ME
# value previously produced the scheme "com.googleusercontent.apps." — a
# meaningless stub that still shipped.
#
# Usage: scripts/inject_google_url_scheme.sh [path/to/.env]
set -euo pipefail

ENV_FILE="${1:-.env.production}"
PLIST="ios/Runner/Info.plist"

value_of() {
  # Last assignment wins, matching how dotenv parsers resolve duplicates.
  grep -E "^$1=" "$ENV_FILE" | tail -n 1 | cut -d= -f2- | tr -d '"' | xargs || true
}

CID="$(value_of GOOGLE_IOS_CLIENT_ID)"

if [ -z "$CID" ]; then
  echo "GOOGLE_IOS_CLIENT_ID is empty in $ENV_FILE; skipping URL scheme." >&2
  echo "Google sign-in will not work in this build." >&2
  exit 0
fi
if [[ "$CID" == REPLACE_ME* ]]; then
  echo "GOOGLE_IOS_CLIENT_ID is still the placeholder in $ENV_FILE." >&2
  exit 1
fi
if [[ "$CID" != *.apps.googleusercontent.com ]]; then
  echo "GOOGLE_IOS_CLIENT_ID does not look like a Google client id: $CID" >&2
  exit 1
fi

REVERSED="com.googleusercontent.apps.${CID%%.apps.googleusercontent.com}"
if [ "$REVERSED" = "com.googleusercontent.apps." ]; then
  echo "refusing to write an empty reversed client id" >&2
  exit 1
fi

N=$(/usr/libexec/PlistBuddy -c "Print :CFBundleURLTypes" "$PLIST" | grep -c "Dict")
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:$N dict" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:$N:CFBundleTypeRole string Editor" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:$N:CFBundleURLSchemes array" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:$N:CFBundleURLSchemes:0 string $REVERSED" "$PLIST"
echo "injected $REVERSED"
