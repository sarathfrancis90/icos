#!/bin/bash
# Stop hook — runs unit tests and integration tests on simulator when Claude finishes.

cd "$CLAUDE_PROJECT_DIR" || exit 0

# Only run if flutter project exists
if [[ ! -f "pubspec.yaml" ]]; then
  exit 0
fi

# Check if any Dart files were modified
if ! git diff --name-only HEAD 2>/dev/null | grep -q '\.dart$'; then
  exit 0
fi

if ! command -v flutter &> /dev/null; then
  exit 0
fi

# Phase 1: Run all unit tests (fast, ~3 seconds)
echo "[Visual Gate] Running unit tests..." >&2
if ! flutter test test/ --no-pub 2>&1 >&2; then
  echo "[Visual Gate] UNIT TESTS FAILED — fix before proceeding" >&2
fi

# Phase 2: Run integration tests on first available simulator
if [[ ! -d "integration_test" ]]; then
  exit 0
fi

# Get device IDs via flutter devices
DEVICES_OUTPUT=$(flutter devices 2>/dev/null)
IOS_DEVICE=$(echo "$DEVICES_OUTPUT" | grep -i 'ios.*simulator' | head -1 | sed -n 's/.*• \([A-F0-9-]*\) .*/\1/p')
ANDROID_DEVICE=$(echo "$DEVICES_OUTPUT" | grep -i 'android.*emulator' | head -1 | sed -n 's/.*• \([^ ]*\) .*/\1/p')

DEVICE_ID=""
PLATFORM=""
if [[ -n "$IOS_DEVICE" ]]; then
  DEVICE_ID="$IOS_DEVICE"
  PLATFORM="iOS"
elif [[ -n "$ANDROID_DEVICE" ]]; then
  DEVICE_ID="$ANDROID_DEVICE"
  PLATFORM="Android"
fi

if [[ -n "$DEVICE_ID" ]]; then
  echo "[Visual Gate] Running integration tests on $PLATFORM ($DEVICE_ID)..." >&2
  if flutter test integration_test/ -d "$DEVICE_ID" --no-pub 2>&1 >&2; then
    echo "[Visual Gate] Integration tests PASSED on $PLATFORM" >&2
  else
    echo "[Visual Gate] INTEGRATION TESTS FAILED on $PLATFORM" >&2
  fi
else
  echo "[Visual Gate] No simulators available — skipping integration tests" >&2
fi

exit 0
