#!/bin/bash
# PostToolUse hook — runs targeted unit tests after Dart file edits
# Triggers on Edit|Write tools for .dart files in lib/ or test/

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only trigger for Dart files
if [[ "$FILE_PATH" != *.dart ]]; then
  exit 0
fi

# Only trigger for lib/ or test/ changes
if [[ "$FILE_PATH" != */lib/* ]] && [[ "$FILE_PATH" != */test/* ]]; then
  exit 0
fi

cd "$CLAUDE_PROJECT_DIR" || exit 0

# Check if flutter project is set up
if [[ ! -f "pubspec.yaml" ]]; then
  exit 0
fi

if ! command -v flutter &> /dev/null; then
  exit 0
fi

# Determine which test to run based on the changed file
COMPONENT=$(basename "$FILE_PATH" .dart)

# Map source files to their test files
TEST_FILE=""

# Direct golden test match
GOLDEN_TEST="test/goldens/${COMPONENT}_test.dart"
if [[ -f "$GOLDEN_TEST" ]]; then
  TEST_FILE="$GOLDEN_TEST"
fi

# Feature-level test match
if [[ "$FILE_PATH" == */features/puzzle/* ]]; then
  # Always run game engine tests for puzzle changes
  TEST_FILE="test/features/puzzle/domain/game_engine_test.dart"
fi

# Check for direct test file match
DIRECT_TEST=$(find test -name "${COMPONENT}_test.dart" 2>/dev/null | head -1)
if [[ -n "$DIRECT_TEST" ]]; then
  TEST_FILE="$DIRECT_TEST"
fi

if [[ -n "$TEST_FILE" ]] && [[ -f "$TEST_FILE" ]]; then
  echo "[Visual] Running tests for $COMPONENT..." >&2
  if flutter test "$TEST_FILE" --no-pub 2>&1 >&2; then
    echo "[Visual] Tests passed for $COMPONENT" >&2
  else
    echo "[Visual] TESTS FAILED for $COMPONENT — check output above" >&2
    exit 2
  fi
fi

exit 0
