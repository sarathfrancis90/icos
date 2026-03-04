---
inputDocuments:
  - prd.md
  - PLAN.md
date: 2026-03-02
author: Sarathfrancis
type: testing-strategy
scope: visual-validation
---

# Visual Testing Strategy - Icos

**Author:** Sarathfrancis
**Date:** 2026-03-02

## Purpose

Define the automated visual validation approach for Icos to ensure UI correctness, prevent visual regressions, and maintain design consistency across themes, grid sizes, and device configurations.

## Testing Layers

### Layer 1: Golden Tests (Widget-Level)

**Tool:** Flutter's built-in `matchesGoldenFile` + [Alchemist](https://pub.dev/packages/alchemist)
**Runs:** Every PR, every commit via CI
**Speed:** Fast (seconds per test, no device/emulator needed)

**What to cover:**

| Component | Variants | Priority |
|-----------|----------|----------|
| PuzzleGrid | 5x5, 6x6, 6x7, 7x7, 7x8, 8x8 (empty, partial path, completed) | Critical |
| PathRenderer | Active path, waypoint hit, wall collision, backtrack state | Critical |
| WaypointCircle | Default, active, completed, colorblind mode | Critical |
| ShareCard | Each grid size, light/dark theme | High |
| LeaderboardTile | 1 member, 10 members, 50 members, solved/unsolved states | High |
| StatsScreen | Empty stats, populated stats, streak display | High |
| GroupCard | Active group, empty group, full group (50/50) | Medium |
| HomeScreen | Daily puzzle card, streak counter, group activity | Medium |
| CelebrationAnimation | First frame capture (static golden) | Medium |
| NavigationBar | All 4 tabs in selected/unselected state | Low |

**Theme matrix — each component tested in:**
- Light mode
- Dark mode
- Colorblind mode (patterns/textures enabled)
- Reduced motion mode (animations disabled)

**Example test structure:**

```dart
// test/goldens/puzzle_grid_test.dart
import 'package:alchemist/alchemist.dart';

goldenTest(
  'PuzzleGrid renders all sizes correctly',
  fileName: 'puzzle_grid_sizes',
  builder: () => GoldenTestGroup(
    children: [
      for (final size in [5, 6, 7, 8])
        GoldenTestScenario(
          name: '${size}x$size_empty',
          child: PuzzleGrid(
            gridSize: size,
            waypoints: mockWaypoints[size]!,
            path: [],
          ),
        ),
    ],
  ),
);

goldenTest(
  'PuzzleGrid themes',
  fileName: 'puzzle_grid_themes',
  builder: () => GoldenTestGroup(
    children: [
      GoldenTestScenario(
        name: 'light',
        child: Theme(data: lightTheme, child: PuzzleGrid(...)),
      ),
      GoldenTestScenario(
        name: 'dark',
        child: Theme(data: darkTheme, child: PuzzleGrid(...)),
      ),
      GoldenTestScenario(
        name: 'colorblind',
        child: Theme(data: colorblindTheme, child: PuzzleGrid(...)),
      ),
    ],
  ),
);
```

**Golden file storage:** `test/goldens/` directory, committed to git. Updated via `flutter test --update-goldens`.

### Layer 2: Screen-Level Golden Tests

**Tool:** Flutter widget tests with `matchesGoldenFile`
**Runs:** Every PR via CI
**Speed:** Fast (mocked providers, no network)

**Full screens to capture:**

| Screen | States | Mock Data |
|--------|--------|-----------|
| HomeScreen | Default, with streak, with group activity, offline indicator | MockPuzzleProvider, MockUserProvider |
| PuzzleScreen | Empty grid, mid-solve, completed, hint used | MockPuzzleState |
| GroupListScreen | No groups, 1 group, 5 groups | MockGroupProvider |
| GroupDetailScreen | Leaderboard with 3/10/50 members, all solved, partially solved | MockLeaderboardProvider |
| StatsScreen | New user (0 puzzles), active user (50+ puzzles) | MockStatsProvider |
| ProfileScreen | Anonymous user, registered user | MockAuthProvider |
| SettingsScreen | Default settings, all toggles changed | MockSettingsProvider |
| ShareCardPreview | Each grid size, light + dark | MockShareData |

**Each screen tested at device sizes:**
- iPhone SE (375x667) — small
- iPhone 15 (393x852) — standard
- Pixel 7 (412x915) — Android standard
- iPad Mini (744x1133) — tablet (layout only)

### Layer 3: Integration Tests with Screenshots

**Tool:** `integration_test` package + `binding.takeScreenshot()`
**Runs:** Nightly CI, pre-release
**Speed:** Slow (requires emulator/simulator)

**Flows to capture:**

1. **First Launch Flow**
   - App open → home screen → tap play → puzzle grid → solve → celebration → result screen
   - Screenshots at each step

2. **Group Join Flow**
   - Deep link open → group preview → join → leaderboard visible
   - Screenshots at each step

3. **Offline Play Flow**
   - Enable airplane mode → open app → solve cached puzzle → result queued
   - Screenshots showing offline indicator

4. **Share Flow**
   - Complete puzzle → tap share → share card preview → native share sheet
   - Screenshot of share card

**Example:**

```dart
// integration_test/puzzle_flow_test.dart
void main() {
  testWidgets('complete puzzle flow captures all states', (tester) async {
    app.main();
    await tester.pumpAndSettle();
    await binding.takeScreenshot('01_home_screen');

    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('02_puzzle_empty');

    // Simulate path drawing
    await simulatePath(tester, mockSolution.sublist(0, 5));
    await binding.takeScreenshot('03_puzzle_mid_solve');

    await simulatePath(tester, mockSolution);
    await tester.pumpAndSettle();
    await binding.takeScreenshot('04_puzzle_complete');

    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('05_share_card');
  });
}
```

### Layer 4: Device Testing (Pre-Release)

**Tool:** [Maestro](https://maestro.mobile.dev/) or Firebase Test Lab
**Runs:** Pre-release only
**Speed:** Very slow (real device farm)

**Purpose:** Validate rendering on actual hardware across screen densities, OS versions, and device manufacturers.

**Maestro flow example:**

```yaml
appId: com.icos.app
---
- launchApp
- takeScreenshot: 01_launch
- assertVisible: "Today's Puzzle"
- tapOn: "Play"
- takeScreenshot: 02_puzzle
- assertVisible:
    id: "puzzle_grid"
```

## CI Pipeline Integration

### GitHub Actions Workflow

```yaml
name: Visual Tests
on:
  pull_request:
    paths: ['lib/**', 'test/**']

jobs:
  golden-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.x'

      - name: Run golden tests
        run: flutter test test/goldens/ --tags golden

      - name: Upload failure diffs
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: golden-failures
          path: test/failures/

  integration-screenshots:
    runs-on: macos-latest
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
      - name: Start iOS Simulator
        run: |
          xcrun simctl boot "iPhone 15"
      - name: Run integration tests
        run: |
          flutter test integration_test/ --screenshots
      - uses: actions/upload-artifact@v4
        with:
          name: integration-screenshots
          path: integration_test/screenshots/
```

## Claude Code Hooks for Development

### Automated Golden Test Validation

Hook triggers after every Dart file edit to run relevant golden tests.

**File: `.claude/settings.json`**

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/visual-validate.sh"
          }
        ]
      }
    ]
  }
}
```

**File: `.claude/hooks/visual-validate.sh`**

```bash
#!/bin/bash
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only trigger for Dart files in lib/ or test/
if [[ "$FILE_PATH" != *.dart ]]; then
  exit 0
fi

if [[ "$FILE_PATH" != */lib/* ]] && [[ "$FILE_PATH" != */test/* ]]; then
  exit 0
fi

cd "$CLAUDE_PROJECT_DIR" || exit 0

# Extract component name from file path for targeted golden test
COMPONENT=$(basename "$FILE_PATH" .dart)
GOLDEN_TEST="test/goldens/${COMPONENT}_test.dart"

if [[ -f "$GOLDEN_TEST" ]]; then
  echo "Running golden tests for $COMPONENT..." >&2
  if flutter test "$GOLDEN_TEST" 2>&1; then
    echo "Golden tests passed for $COMPONENT" >&2
  else
    echo "VISUAL REGRESSION DETECTED in $COMPONENT — review golden diffs" >&2
    exit 2
  fi
fi

exit 0
```

### Story Completion Visual Gate

Hook triggers when Claude finishes a response, checking if golden tests pass.

**Added to `.claude/settings.json`:**

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/visual-gate.sh"
          }
        ]
      }
    ]
  }
}
```

**File: `.claude/hooks/visual-gate.sh`**

```bash
#!/bin/bash
cd "$CLAUDE_PROJECT_DIR" || exit 0

# Only run if golden test files exist
if ! ls test/goldens/*_test.dart 1>/dev/null 2>&1; then
  exit 0
fi

# Run all golden tests
if flutter test test/goldens/ --tags golden 2>&1; then
  echo "All visual golden tests pass" >&2
else
  echo "Visual regression detected — golden tests failed" >&2
  # Don't block, just warn (exit 0 with message)
fi

exit 0
```

## Directory Structure

```
test/
  goldens/                        # Golden test files
    puzzle_grid_test.dart
    share_card_test.dart
    leaderboard_test.dart
    home_screen_test.dart
    ...
  goldens/                        # Reference golden images (auto-generated)
    puzzle_grid_sizes.png
    puzzle_grid_themes.png
    share_card_light.png
    share_card_dark.png
    ...
  failures/                       # Failed diff images (gitignored)
integration_test/
  puzzle_flow_test.dart
  group_flow_test.dart
  screenshots/                    # Integration test screenshots (gitignored)
.maestro/
  flows/
    smoke_test.yaml
    puzzle_complete.yaml
.claude/
  hooks/
    visual-validate.sh            # Post-edit golden test runner
    visual-gate.sh                # Stop-event visual gate
  settings.json                   # Hook configuration
```

## Definition of Done — Visual Testing

For every UI component or screen implemented:

- [ ] Golden test written covering all visual states
- [ ] Golden test covers light, dark, and colorblind themes
- [ ] Golden reference images committed to `test/goldens/`
- [ ] All existing golden tests pass (no regressions)
- [ ] Integration test screenshot added for new user flows
- [ ] Claude Code hook validates changes on edit

## Updating Golden Files

When intentional visual changes are made:

```bash
# Update all golden files
flutter test --update-goldens

# Update specific component
flutter test test/goldens/puzzle_grid_test.dart --update-goldens

# Review changes
git diff --stat test/goldens/
```

Golden file updates must be reviewed in PR — reviewer confirms the visual change is intentional.
