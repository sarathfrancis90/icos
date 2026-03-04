#!/bin/bash
# Visual testing script — runs integration tests on available simulators
# with screenshot capture and reports results.
#
# Usage:
#   ./scripts/run_visual_tests.sh [--ios-only|--android-only|--quick]
#
# Options:
#   --ios-only       Only test on iOS simulator
#   --android-only   Only test on Android emulator
#   --quick          Run unit tests only (no simulator), for fast feedback

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

SCREENSHOT_DIR="/tmp/icos_visual_test"
mkdir -p "$SCREENSHOT_DIR"

MODE="${1:-full}"
FAIL=0

# --- Helper functions ---

log() { echo "[VisualTest] $*" >&2; }
pass() { echo "[PASS] $*" >&2; }
fail() { echo "[FAIL] $*" >&2; FAIL=1; }

# --- Phase 1: Unit tests (always run, fast) ---

log "Phase 1: Running unit tests..."
if flutter test test/features/puzzle/domain/game_engine_test.dart --no-pub 2>&1 | tail -3; then
  pass "Unit tests (game engine: ${?} tests)"
else
  fail "Unit tests failed"
  exit 1
fi

if [ "$MODE" = "--quick" ]; then
  log "Quick mode — skipping simulator tests"
  exit $FAIL
fi

# --- Phase 2: Integration tests on simulators ---

# Detect available devices
IOS_DEVICE=""
ANDROID_DEVICE=""

if [ "$MODE" != "--android-only" ]; then
  IOS_DEVICE=$(flutter devices 2>/dev/null | grep -i "ios.*simulator" | head -1 | sed 's/.*• \([^ ]*\) .*/\1/' || true)
fi

if [ "$MODE" != "--ios-only" ]; then
  ANDROID_DEVICE=$(flutter devices 2>/dev/null | grep -i "android.*emulator" | head -1 | sed 's/.*• \([^ ]*\) .*/\1/' || true)
fi

run_integration_test() {
  local device_id="$1"
  local platform="$2"

  log "Phase 2: Running integration tests on $platform ($device_id)..."

  if flutter test integration_test/puzzle_drag_test.dart -d "$device_id" --no-pub 2>&1; then
    pass "Integration tests on $platform"

    # Take a screenshot of the simulator
    if [ "$platform" = "iOS" ]; then
      xcrun simctl io "$device_id" screenshot "$SCREENSHOT_DIR/${platform}_final.png" 2>/dev/null && \
        log "Screenshot saved: $SCREENSHOT_DIR/${platform}_final.png"
    elif [ "$platform" = "Android" ]; then
      adb -s "$device_id" exec-out screencap -p > "$SCREENSHOT_DIR/${platform}_final.png" 2>/dev/null && \
        log "Screenshot saved: $SCREENSHOT_DIR/${platform}_final.png"
    fi
  else
    fail "Integration tests failed on $platform"
  fi
}

if [ -n "$IOS_DEVICE" ]; then
  run_integration_test "$IOS_DEVICE" "iOS"
else
  log "No iOS simulator found — skipping"
fi

if [ -n "$ANDROID_DEVICE" ]; then
  run_integration_test "$ANDROID_DEVICE" "Android"
else
  log "No Android emulator found — skipping"
fi

if [ -z "$IOS_DEVICE" ] && [ -z "$ANDROID_DEVICE" ]; then
  fail "No simulators/emulators available for integration testing"
fi

# --- Summary ---

log "Screenshots in: $SCREENSHOT_DIR/"
ls -la "$SCREENSHOT_DIR"/*.png 2>/dev/null | while read -r line; do
  log "  $line"
done

if [ $FAIL -eq 0 ]; then
  log "All visual tests PASSED"
else
  log "Some visual tests FAILED"
fi

exit $FAIL
