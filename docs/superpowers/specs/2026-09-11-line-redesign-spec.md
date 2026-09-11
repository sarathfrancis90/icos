# Icos: line redesign + path interaction overhaul

Date: 2026-09-11
Status: approved by the user for fully autonomous execution ("plan, spec, implement,
review, test, validate, visual full validation ... then push the new bundles").

## 1. Why

Two problems with the current puzzle surface.

**Interaction.** Tapping a cell already in the path does nothing unless it happens to be
the second-to-last cell, which then undoes one step. Players expect to tap anywhere on the
line and have it retract to that point. The engine already has `backtrackToCell`; it is
simply never reached from a tap. The same applies to dragging backwards: only a single
step is honoured, so dragging back over four cells leaves the path unchanged.

**Theme.** The path is drawn as a cartoon snake: eyes, blinking, a flicking tongue, scale
shading, a swallowing bulge, and a lunge animation on invalid moves. It fights the product.
The app is called Icos after Hamilton's 1857 Icosian game, the tagline is "One line. Every
cell.", and the icon is a clean amber line through a grid. The snake reads as a different,
cheaper game, adds ~900 lines of animation code, and makes the board noisy at 7x7 and 8x8
where legibility matters most.

## 2. Design direction

Genre reference points: LinkedIn Zip (indigo, flat, the line is the only ornament), and
the general rule for daily logic puzzles that the UI must be readable and unintrusive.
We deliberately do **not** copy Zip's indigo; our icon is amber-on-navy and that is the
identity we already ship on both stores.

Principles:

1. **The line is the hero.** One continuous stroke, uniform width, round caps and round
   joins. No faces, no texture, no per-segment ornament.
2. **Colour carries direction, not decoration.** A single gradient runs start to head using
   the existing `AppColors.pathGradientColors` (deep orange -> amber -> bright yellow), the
   same ramp as the app icon. Progress is legible at a glance: dark at the start, bright at
   the head.
3. **Calm motion.** Segments draw in over ~110 ms. Waypoints pop when reached. Completion
   ripples once. Everything else is removed.
4. **Legibility first.** Line width is 0.44 x cell, so the underlying grid, walls and
   waypoint numbers stay visible at 8x8.
5. **Accessibility is not an afterthought.** Every colour stays routed through
   `GridPalette` so the three colourblind palettes and their pattern overlays keep working.

## 3. Interaction changes

| Gesture | Before | After |
|---|---|---|
| Tap empty adjacent cell | extend | unchanged |
| Tap any cell already in the path | nothing (unless second-to-last) | **retract to that cell** |
| Tap the head | nothing | nothing (no-op, avoids accidental clears) |
| Tap waypoint 1 when path is only waypoint 1 | nothing | nothing |
| Drag over a visited cell | single-step undo only | **retract to that cell** |
| Drag over empty adjacent cell | extend | unchanged |
| Invalid move | snake lunges | brief red flash on the rejected cell |

Retraction always goes through `GameEngine.backtrackToCell`, which already recomputes the
grid state and the current waypoint index. It counts as one undo for scoring, matching the
existing `undo()` behaviour, so leaderboards stay comparable.

## 4. Code plan

### 4.1 Domain / state
- `GameEngine.handleCellTap`: if the cell is in the path and is not the head, return
  `backtrackToCell`; otherwise `addToPath`. Increment `undosUsed` on retraction.
- `GameEngine.handleCellDrag` (new): same retract-or-extend rule, used by the drag handler
  so tap and drag share one code path.
- `GameNotifier.handleCellTap` / `handleCellDrag`: delegate to the engine, keep the
  existing hint-clear, autosave, timer-start and completion checks.

### 4.2 Rendering
- Delete `snake_renderer.dart`; add `path_renderer.dart` exposing `PathRenderer` with the
  same call shape (`paint(canvas, cells, headProgress)`) minus all creature state.
  Draw order: soft outer glow -> main stroke with gradient -> head cap -> start cap.
- `GridPalette`: rename `snake*` fields to `path*`; drop `snakeEye`, `snakePupil`,
  `snakeTongue`, `snakeSegmentHighlight`, `snakeSegmentShadow`, `snakeBellyHighlight`.
- `AppColors`: drop the snake colour block; keep `pathGradientColors` as the source of
  truth and add `pathGlow`, `pathHead`, `pathStart`.
- `puzzle_grid.dart`: remove the idle-blink, tongue, eating and invalid-lunge controllers
  and their timers; add a short invalid-flash controller. Keep segment draw-in, glow
  breathing, waypoint burst, hint pulse and completion ripple.

### 4.3 Naming and copy
Remove the word "snake" from `lib/`, including the colorblind palette builders and the
analytics event payloads. Onboarding copy is already line-based.

### 4.4 Audio
`SoundEffect.slither` is dropped (it only existed for the creature). `waypointReached`,
`pathStep`, `undo`, `invalidMove`, `completion`, `hint` and `buttonTap` are unchanged.

## 5. Testing and validation

1. `flutter analyze` clean, full `flutter test` green (551 before, 575 after).
2. New unit tests: tap-retracts-to-cell, tap-on-head-is-noop, drag-retracts-multiple,
   retraction recomputes the waypoint index, retraction counts one undo.
3. Golden-free visual validation: Maestro flows on iPhone 6.9", iPad 13" and Android,
   solving the live daily puzzle end to end and capturing every screen.
4. Colourblind validation: capture the puzzle screen in all three palettes.
5. Re-shoot App Store and Play screenshots from the new build; re-upload to App Store
   Connect; rebuild the signed AAB for Play.

`test/visual/capture_puzzle_grid.dart` renders the grid to PNGs in `build/visual/`
(four stages of the line, all four palettes, mid-flash). It is deliberately not named
`*_test.dart`, so `flutter test` and CI skip it: rendering differs between machines, so
it is an eyeballing tool, not a gate.

## 6. Found during review

Four things the review turned up that the plan above had not anticipated.

**The painter froze every animation it read as a number.** `_GridPainter` is rebuilt only
when the widget rebuilds, but `repaint` fires on every animation tick and reuses the same
instance. Five values (glow breath, hint pulse, waypoint burst, completion ripple, and the
new flash) were captured as plain numbers and so held whatever they had at the last
rebuild. They are now read through closures, the way the per-index getters already were.
This is why the flash appeared to be dead code even after it was wired up.

**Every tap reported a drag it never made.** A tap cancels the pan recognizer, and
`onPanCancel` called `onDragEnd` unguarded. The grid now tracks whether a gesture actually
started.

**A backwards sweep was charged one undo per cell.** Tapping the fourth cell back cost one
undo; dragging over the same four cost four. `handleCellTap` takes `countUndo`, and the
notifier charges once per gesture between `beginDrag` and `endDrag`.

**The grid kept its own copy of the rules.** It re-derived adjacency and walls, which
silently disagreed with the engine about revisits, "the first cell must be waypoint 1" and
waypoint ordering. It now asks `GameEngine.canMoveToCell`.

Also: a drag could not start a puzzle (now it can), retraction played the step sound
(it plays undo), and reduced motion dropped the invalid cue entirely (it now holds the cue
steady and clears it).

## 7. Out of scope

Dead-end highlighting, auto-fill of forced corridors, and a global leaderboard. They are
good ideas but each changes difficulty balance and needs its own design pass.
