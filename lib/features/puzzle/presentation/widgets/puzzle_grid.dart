import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/services/audio_service.dart';
import '../../../../core/utils/haptics.dart';
import '../../../../core/utils/motion.dart';
import '../../domain/game_engine.dart';
import '../../domain/models/game_state.dart';
import '../../domain/models/puzzle.dart';
import 'grid_palette.dart';
import 'path_renderer.dart';

class PuzzleGrid extends StatefulWidget {
  const PuzzleGrid({
    required this.gameState,
    required this.onCellTap,
    required this.onCellDrag,
    this.onDragStart,
    this.onDragEnd,
    this.onInvalidMove,
    this.palette = GridPalette.standard,
    this.wrongCell,
    this.readOnly = false,
    super.key,
  });

  final GameState gameState;
  final void Function(int row, int col) onCellTap;
  final void Function(int row, int col) onCellDrag;

  /// Drag gesture boundaries. The owner uses them to charge one undo for a
  /// backwards sweep rather than one per cell crossed.
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;

  final void Function(int row, int col)? onInvalidMove;

  /// Colours (standard or colorblind palette with pattern overlays).
  final GridPalette palette;

  /// Cell where the path diverged from the solution (wrong-cell hint).
  final GridPosition? wrongCell;

  /// Replay of a finished puzzle: input is ignored.
  final bool readOnly;

  @override
  State<PuzzleGrid> createState() => _PuzzleGridState();
}

/// What a touch on a cell resolves to.
enum _GridAction { extend, retract, noop, reject }

class _PuzzleGridState extends State<PuzzleGrid> with TickerProviderStateMixin {
  // ─── Path segment animation (Phase 1) ────────────────────────────
  int _previousPathLength = 0;
  final Map<int, AnimationController> _segmentControllers = {};

  // ─── Glow breath (Phase 1) ───────────────────────────────────────
  late final AnimationController _glowBreathController;

  // ─── Cell entry bounce (Phase 2) ─────────────────────────────────
  final Map<String, AnimationController> _cellEntryControllers = {};

  // ─── Hint pulse (Phase 3) ────────────────────────────────────────
  AnimationController? _hintPulseController;

  // ─── Waypoint burst (Phase 4) ────────────────────────────────────
  int _previousWaypointIndex = 0;
  AnimationController? _waypointBurstController;
  Offset? _waypointBurstCenter;

  // ─── Completion ripple (Phase 5) ─────────────────────────────────
  AnimationController? _completionRippleController;
  bool _hasTriggeredCompletion = false;

  // ─── Invalid-move feedback ─────────────────────────────────────
  /// Short flash on a cell the player tried to move to illegally.
  AnimationController? _invalidFlashController;
  GridPosition? _invalidCell;

  /// Clears the flash when motion is reduced and there is no controller.
  Timer? _invalidFlashTimer;

  /// A drag gesture has been started and not yet ended.
  bool _dragging = false;

  /// Rule oracle. Pure and cheap to build: it only wraps the puzzle, and keeps
  /// the grid from re-deriving adjacency and waypoint-order rules of its own.
  late GameEngine _engine;

  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();

    _engine = GameEngine(widget.gameState.puzzle);
    _previousPathLength = widget.gameState.path.length;
    _previousWaypointIndex = widget.gameState.currentWaypointIndex;

    _glowBreathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: AppSizes.glowBreathCycleMs),
    );

    // Init hint pulse if needed
    if (widget.gameState.hintCell != null) {
      _startHintPulse();
    }

  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MotionUtils.shouldReduceMotion(context);
    // Under reduced motion the glow is a constant, so leaving the controller
    // stopped also stops the grid repainting every frame.
    if (_reduceMotion) {
      _glowBreathController.stop();
    } else if (!_glowBreathController.isAnimating) {
      _glowBreathController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant PuzzleGrid oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.gameState.puzzle != oldWidget.gameState.puzzle) {
      _engine = GameEngine(widget.gameState.puzzle);
    }

    final newLen = widget.gameState.path.length;
    final oldLen = _previousPathLength;

    // ── Phase 1: New path segments ──────────────────────────────
    if (newLen > oldLen && !_reduceMotion) {
      for (int i = oldLen; i < newLen; i++) {
        _animateNewSegment(i);
      }
    }

    // Clean up controllers for removed segments (undo/backtrack)
    if (newLen < oldLen) {
      final keysToRemove = <int>[];
      for (final key in _segmentControllers.keys) {
        if (key >= newLen) keysToRemove.add(key);
      }
      for (final key in keysToRemove) {
        _segmentControllers[key]?.dispose();
        _segmentControllers.remove(key);
      }

      // Clean up cell entry controllers for removed cells
      final cellKeysToRemove = <String>[];
      for (final cellKey in _cellEntryControllers.keys) {
        final parts = cellKey.split(',');
        final r = int.parse(parts[0]);
        final c = int.parse(parts[1]);
        final stillInPath =
            widget.gameState.path.any((p) => p.row == r && p.col == c);
        if (!stillInPath) cellKeysToRemove.add(cellKey);
      }
      for (final key in cellKeysToRemove) {
        _cellEntryControllers[key]?.dispose();
        _cellEntryControllers.remove(key);
      }
    }

    // ── Phase 2: Cell entry bounce for new cells ────────────────
    if (newLen > oldLen && !_reduceMotion) {
      for (int i = oldLen; i < newLen; i++) {
        final pos = widget.gameState.path[i];
        _animateCellEntry(pos.row, pos.col);
      }
    }

    _previousPathLength = newLen;

    // ── Phase 3: Hint pulse ─────────────────────────────────────
    final hadHint =
        oldWidget.gameState.hintCell != null || oldWidget.wrongCell != null;
    final hasHint = widget.gameState.hintCell != null || widget.wrongCell != null;
    if (hasHint && !hadHint) {
      _startHintPulse();
    } else if (!hasHint && hadHint) {
      _stopHintPulse();
    }

    // ── Phase 4: Waypoint reached ──────────────────────────────
    final newWpIdx = widget.gameState.currentWaypointIndex;
    if (newWpIdx > _previousWaypointIndex && !_reduceMotion) {
      _triggerWaypointBurst();
      AudioService.instance.play(SoundEffect.waypointReached);
    }
    _previousWaypointIndex = newWpIdx;

    // ── Phase 5: Grid completion ────────────────────────────────
    if (widget.gameState.status == GameStatus.completed &&
        oldWidget.gameState.status != GameStatus.completed &&
        !_hasTriggeredCompletion) {
      _hasTriggeredCompletion = true;
      _triggerCompletionRipple();
    }
  }

  // ── Phase 1: Segment animation ──────────────────────────────────

  void _animateNewSegment(int segmentIndex) {
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: AppSizes.pathDrawMs),
    );
    _segmentControllers[segmentIndex] = controller;
    controller.forward().then((_) {
      // Keep controller at 1.0 — don't dispose until segment is removed
    });
  }

  double _getSegmentProgress(int index) {
    if (_reduceMotion) return 1.0;
    final controller = _segmentControllers[index];
    if (controller == null) return 1.0;
    return Curves.easeOut.transform(controller.value);
  }

  double _getGlowBreathValue() {
    if (_reduceMotion) return 0.5;
    return _glowBreathController.value;
  }

  // ── Phase 2: Cell entry animation ───────────────────────────────

  void _animateCellEntry(int row, int col) {
    final key = '$row,$col';
    if (_cellEntryControllers.containsKey(key)) return;

    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: AppSizes.cellEntryBounceMs),
    );
    _cellEntryControllers[key] = controller;
    controller.forward();
  }

  double _getCellEntryScale(int row, int col) {
    if (_reduceMotion) return 1.0;
    final key = '$row,$col';
    final controller = _cellEntryControllers[key];
    if (controller == null) return 1.0;
    // Elastic bounce: 1.0 → 1.08 → 1.0
    final t = Curves.elasticOut.transform(controller.value);
    return 1.0 + (0.08 * (1.0 - t).abs() * (t < 0.5 ? 1 : 0));
  }

  double _getCellEntryGlow(int row, int col) {
    if (_reduceMotion) return 0.0;
    final key = '$row,$col';
    final controller = _cellEntryControllers[key];
    if (controller == null) return 0.0;
    // Flash glow: 0.3 → 0.0
    return 0.3 * (1.0 - controller.value);
  }

  // ── Phase 3: Hint pulse ─────────────────────────────────────────

  void _startHintPulse() {
    if (_reduceMotion) return;
    _hintPulseController?.dispose();
    _hintPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: AppSizes.hintPulseCycleMs),
    )..repeat(reverse: true);
  }

  void _stopHintPulse() {
    _hintPulseController?.dispose();
    _hintPulseController = null;
  }

  double _getHintPulseValue() {
    if (_reduceMotion) return 0.0;
    return _hintPulseController?.value ?? 0.0;
  }

  // ── Phase 4: Waypoint burst ─────────────────────────────────────

  void _triggerWaypointBurst() {
    Haptics.waypointReached();

    // Find the waypoint that was just reached
    final wpIdx = widget.gameState.currentWaypointIndex;
    final waypoints = widget.gameState.puzzle.waypoints;
    if (wpIdx <= 0 || wpIdx > waypoints.length) return;

    // The waypoint order that was just reached
    final reachedWp = waypoints.firstWhere(
      (w) => w.order == wpIdx,
      orElse: () => waypoints.first,
    );

    // We'll compute the actual pixel center in the painter using row/col
    _waypointBurstCenter = Offset(
      reachedWp.col.toDouble(),
      reachedWp.row.toDouble(),
    );

    _waypointBurstController?.dispose();
    _waypointBurstController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: AppSizes.waypointBurstMs),
    )..forward();
  }

  double _getWaypointBurstProgress() {
    if (_reduceMotion) return -1.0;
    final controller = _waypointBurstController;
    if (controller == null || !controller.isAnimating) return -1.0;
    return controller.value;
  }

  // ── Phase 5: Completion ripple ──────────────────────────────────

  void _triggerCompletionRipple() {
    if (_reduceMotion) return;
    Haptics.puzzleComplete();

    _completionRippleController?.dispose();
    _completionRippleController = AnimationController(
      vsync: this,
      duration:
          const Duration(milliseconds: AppSizes.completionRippleMs + 200),
    )..forward();
  }

  double _getCompletionRippleProgress() {
    if (_reduceMotion) return -1.0;
    final controller = _completionRippleController;
    if (controller == null) return -1.0;
    return controller.value;
  }

  // ── Invalid-move feedback ─────────────────────────────────────────

  /// Flash the cell the player tried to enter illegally.
  ///
  /// Under reduced motion the same cell is marked, but it is held steady and
  /// then cleared instead of fading in and out: the cue stays, the animation
  /// goes.
  void triggerInvalidFlash(int row, int col) {
    _invalidFlashTimer?.cancel();
    _invalidFlashController?.dispose();
    _invalidFlashController = null;

    if (_reduceMotion) {
      setState(() => _invalidCell = GridPosition(row: row, col: col));
      _invalidFlashTimer = Timer(
        const Duration(milliseconds: AppSizes.invalidFlashStaticMs),
        () {
          if (!mounted) return;
          setState(() => _invalidCell = null);
        },
      );
      return;
    }

    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: AppSizes.invalidFlashMs),
    );
    setState(() {
      _invalidCell = GridPosition(row: row, col: col);
      _invalidFlashController = controller;
    });
    controller.forward().then((_) {
      if (!mounted) return null;
      return controller.reverse().then((_) {
        if (!mounted) return;
        setState(() => _invalidCell = null);
      });
    });
  }

  /// 0..1 intensity of the invalid-move cue. Full strength with no controller
  /// so the reduced-motion cue is visible.
  double _getInvalidFlashProgress() {
    if (_invalidCell == null) return 0.0;
    return _invalidFlashController?.value ?? 1.0;
  }

  /// Width of the square grid.
  ///
  /// Phones are always narrower than [AppSizes.gridMaxWidth], so the cap only
  /// affects tablets. The height term stops the grid from crowding the timer
  /// bar and controls on short/wide windows.
  double get _gridWidth {
    final media = MediaQuery.of(context).size;
    final cap = math.min(
      AppSizes.gridMaxWidth,
      media.height * AppSizes.gridMaxHeightFraction,
    );
    return (media.width - AppSizes.gridPadding * 2).clamp(0.0, cap);
  }

  double get cellSize {
    final size = widget.gameState.puzzle.gridSize;
    return _gridWidth / size;
  }

  @override
  void dispose() {

    _glowBreathController.dispose();
    _hintPulseController?.dispose();
    _waypointBurstController?.dispose();
    _completionRippleController?.dispose();
    _invalidFlashController?.dispose();
    _invalidFlashTimer?.cancel();
    for (final c in _segmentControllers.values) {
      c.dispose();
    }
    for (final c in _cellEntryControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.gameState.puzzle.gridSize;
    final gridWidth = _gridWidth;
    final cellSize = gridWidth / size;

    // Merge all animation listenables for repaint
    final listenables = <Listenable>[
      _glowBreathController,
      ?_hintPulseController,
      ?_waypointBurstController,
      ?_completionRippleController,
      ?_invalidFlashController,
      ..._segmentControllers.values,
      ..._cellEntryControllers.values,
    ];

    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSizes.gridPadding,
      ),
      child: Center(
        child: SizedBox(
          width: gridWidth,
          height: gridWidth,
          child: GestureDetector(
            onPanStart: (details) {
              if (widget.readOnly) return;
              _dragging = true;
              widget.onDragStart?.call();
              // The press that starts a drag never reaches the per-cell tap
              // targets, so treat it as the gesture's first move.
              _dragAt(details.localPosition, size, cellSize);
            },
            onPanUpdate: (details) {
              if (widget.readOnly) return;
              _dragAt(details.localPosition, size, cellSize);
            },
            // A plain tap also cancels the pan recognizer, so end the gesture
            // only if one actually started. Otherwise every tap would report a
            // drag it never made.
            onPanEnd: (_) => _endDrag(),
            onPanCancel: _endDrag,
            child: CustomPaint(
              painter: _GridPainter(
                gameState: widget.gameState,
                cellSize: cellSize,
                palette: widget.palette,
                wrongCell: widget.wrongCell,
                segmentProgressGetter: _getSegmentProgress,
                glowBreathValueGetter: _getGlowBreathValue,
                cellEntryScaleGetter: _getCellEntryScale,
                cellEntryGlowGetter: _getCellEntryGlow,
                hintPulseValueGetter: _getHintPulseValue,
                waypointBurstProgressGetter: _getWaypointBurstProgress,
                waypointBurstGridPos: _waypointBurstCenter,
                completionRippleProgressGetter: _getCompletionRippleProgress,
                invalidCell: _invalidCell,
                invalidFlashProgressGetter: _getInvalidFlashProgress,
                repaintNotifier: listenables.isNotEmpty
                    ? Listenable.merge(listenables)
                    : null,
              ),
              child: _buildTapTargets(size, cellSize),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTapTargets(int size, double cellSize) {
    return Stack(
      children: [
        for (int row = 0; row < size; row++)
          for (int col = 0; col < size; col++)
            Positioned(
              left: col * cellSize,
              top: row * cellSize,
              width: cellSize,
              height: cellSize,
              child: GestureDetector(
                onTap: () => _handleCellTap(row, col),
                behavior: HitTestBehavior.opaque,
                child: Semantics(
                  label: _cellSemanticLabel(row, col),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
      ],
    );
  }

  void _endDrag() {
    if (!_dragging) return;
    _dragging = false;
    widget.onDragEnd?.call();
  }

  /// Maps a pointer position to a cell and forwards it as a drag move.
  void _dragAt(Offset localPos, int size, double cellSize) {
    final row = (localPos.dy / cellSize).floor();
    final col = (localPos.dx / cellSize).floor();
    if (row < 0 || row >= size || col < 0 || col >= size) return;
    _handleCellDrag(row, col);
  }

  /// What touching [row], [col] means right now.
  ///
  /// Legality of an extension is decided by [GameEngine.canMoveToCell], which
  /// already covers bounds, walls, adjacency, revisits, the "first cell must be
  /// waypoint 1" rule and waypoint ordering. Asking it keeps one rulebook
  /// between what the grid accepts and what the engine will actually apply.
  _GridAction _classify(int row, int col) {
    final path = widget.gameState.path;
    final index = path.indexWhere((p) => p.row == row && p.col == col);
    if (index >= 0) {
      return index == path.length - 1 ? _GridAction.noop : _GridAction.retract;
    }
    return _engine.canMoveToCell(widget.gameState, row, col)
        ? _GridAction.extend
        : _GridAction.reject;
  }

  void _handleCellTap(int row, int col) {
    if (widget.readOnly) return;
    switch (_classify(row, col)) {
      // Tapping the head is deliberately inert: a stray tap there must not
      // clear progress.
      case _GridAction.noop:
        return;
      case _GridAction.reject:
        _rejectMove(row, col);
      case _GridAction.retract:
        _retractFeedback();
        widget.onCellTap(row, col);
      case _GridAction.extend:
        _stepFeedback();
        widget.onCellTap(row, col);
    }
  }

  void _handleCellDrag(int row, int col) {
    if (widget.readOnly) return;
    switch (_classify(row, col)) {
      // A finger crossing the board passes over plenty of cells it cannot
      // enter. Flashing and buzzing at each one would be constant noise, so a
      // rejected drag is silent; only a rejected tap gets feedback.
      case _GridAction.noop:
      case _GridAction.reject:
        return;
      case _GridAction.retract:
        _retractFeedback();
        widget.onCellDrag(row, col);
      case _GridAction.extend:
        _stepFeedback();
        widget.onCellDrag(row, col);
    }
  }

  void _stepFeedback() {
    Haptics.pathStep();
    AudioService.instance.play(SoundEffect.pathStep);
  }

  /// Retraction is an undo, so it sounds like the undo button rather than like
  /// laying down another cell.
  void _retractFeedback() {
    Haptics.undo();
    AudioService.instance.play(SoundEffect.undo);
  }

  /// Shared feedback for a move the rules do not allow.
  void _rejectMove(int row, int col) {
    triggerInvalidFlash(row, col);
    Haptics.error();
    AudioService.instance.play(SoundEffect.invalidMove);
    widget.onInvalidMove?.call(row, col);
  }

  String _cellSemanticLabel(int row, int col) {
    final cellState = widget.gameState.grid[row][col];
    final stateLabel = switch (cellState) {
      CellState.empty => 'empty',
      CellState.filled => 'filled',
      CellState.waypoint => _waypointLabel(row, col),
      CellState.wall => 'wall',
    };
    return 'Row ${row + 1}, Column ${col + 1}, $stateLabel';
  }

  String _waypointLabel(int row, int col) {
    for (final wp in widget.gameState.puzzle.waypoints) {
      if (wp.row == row && wp.col == col) {
        return 'waypoint ${wp.order}';
      }
    }
    return 'waypoint';
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter({
    required this.gameState,
    required this.cellSize,
    required this.palette,
    this.wrongCell,
    required this.segmentProgressGetter,
    required this.glowBreathValueGetter,
    required this.cellEntryScaleGetter,
    required this.cellEntryGlowGetter,
    required this.hintPulseValueGetter,
    required this.waypointBurstProgressGetter,
    this.waypointBurstGridPos,
    required this.completionRippleProgressGetter,
    required this.invalidCell,
    required this.invalidFlashProgressGetter,
    Listenable? repaintNotifier,
  }) : super(repaint: repaintNotifier);

  final GameState gameState;
  final double cellSize;
  final GridPalette palette;
  final GridPosition? wrongCell;
  final double Function(int index) segmentProgressGetter;
  /// Animated values are read through closures rather than captured as
  /// numbers. The painter is only rebuilt when the widget rebuilds, but
  /// [repaint] fires on every animation tick and reuses the same painter
  /// instance, so a captured number would be stale for the whole animation.
  final double Function() glowBreathValueGetter;
  final double Function(int row, int col) cellEntryScaleGetter;
  final double Function(int row, int col) cellEntryGlowGetter;
  final double Function() hintPulseValueGetter;
  final double Function() waypointBurstProgressGetter;
  final Offset? waypointBurstGridPos;
  final double Function() completionRippleProgressGetter;
  final GridPosition? invalidCell;
  final double Function() invalidFlashProgressGetter;

  double get glowBreathValue => glowBreathValueGetter();
  double get hintPulseValue => hintPulseValueGetter();
  double get waypointBurstProgress => waypointBurstProgressGetter();
  double get completionRippleProgress => completionRippleProgressGetter();
  double get invalidFlashProgress => invalidFlashProgressGetter();

  // Cell geometry constants
  static const double _cellInset = 2.0;
  static const double _cellRadius = 8.0;

  @override
  void paint(Canvas canvas, Size size) {
    final gridSize = gameState.puzzle.gridSize;

    // Draw all cells (3D embossed)
    for (int row = 0; row < gridSize; row++) {
      for (int col = 0; col < gridSize; col++) {
        _drawEmbossedCell(canvas, row, col);
      }
    }

    // Draw hint cell highlight
    _drawHintCell(canvas);
    _drawWrongCell(canvas);

    // Draw the player line
    _drawLine(canvas);

    // Draw waypoints on top
    for (int row = 0; row < gridSize; row++) {
      for (int col = 0; col < gridSize; col++) {
        if (gameState.grid[row][col] == CellState.waypoint) {
          _drawWaypoint(canvas, row, col);
        }
      }
    }

    // Draw waypoint burst effect (Phase 4)
    if (waypointBurstProgress >= 0 && waypointBurstGridPos != null) {
      _drawWaypointBurst(canvas);
    }

    // Draw completion ripple (Phase 5)
    if (completionRippleProgress >= 0) {
      _drawCompletionRipple(canvas, size);
    }

    // Rejected move, drawn last so it is legible over the line and waypoints.
    _drawInvalidFlash(canvas);
  }

  /// Brief red wash and outline on a cell the player could not move to.
  void _drawInvalidFlash(Canvas canvas) {
    final cell = invalidCell;
    if (cell == null || invalidFlashProgress <= 0.0) return;

    final t = invalidFlashProgress.clamp(0.0, 1.0);
    final rect = Rect.fromLTWH(
      cell.col * cellSize + _cellInset,
      cell.row * cellSize + _cellInset,
      cellSize - _cellInset * 2,
      cellSize - _cellInset * 2,
    );
    final rrect =
        RRect.fromRectAndRadius(rect, const Radius.circular(_cellRadius));
    final color = palette.wrongCell;

    canvas.drawRRect(
      rrect,
      Paint()
        ..color = color.withValues(alpha: 0.34 * t)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, cellSize * 0.14),
    );
    canvas.drawRRect(rrect, Paint()..color = color.withValues(alpha: 0.30 * t));
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = color.withValues(alpha: 0.95 * t)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2.0, cellSize * 0.05),
    );
  }

  /// Draws a 3D embossed/inset cell matching the reference design.
  void _drawEmbossedCell(Canvas canvas, int row, int col) {
    final cellState = gameState.grid[row][col];
    final rect = Rect.fromLTWH(
      col * cellSize + _cellInset,
      row * cellSize + _cellInset,
      cellSize - _cellInset * 2,
      cellSize - _cellInset * 2,
    );
    final rrect =
        RRect.fromRectAndRadius(rect, const Radius.circular(_cellRadius));

    final isInPath = gameState.path.any((p) => p.row == row && p.col == col);

    if (cellState == CellState.wall) {
      _drawWallCell(canvas, rect, rrect);
      return;
    }

    if (isInPath && cellState != CellState.waypoint) {
      _drawVisitedCell(canvas, rect, rrect, row, col);
    } else {
      _drawInsetCell(canvas, rect, rrect);
    }
  }

  /// Draws a wall cell — raised block with bold cross pattern.
  void _drawWallCell(Canvas canvas, Rect rect, RRect rrect) {
    // Outer shadow for raised 3D look
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0);
    canvas.drawRRect(
      rrect.shift(const Offset(1.5, 1.5)),
      shadowPaint,
    );

    // Fill — darker than empty cells for a "solid block" feel
    final fillPaint = Paint()..color = AppColors.wallFill;
    canvas.drawRRect(rrect, fillPaint);

    // Border — bright enough to see the cell outline clearly
    final borderPaint = Paint()
      ..color = AppColors.wallBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(rrect, borderPaint);

    // Bold diagonal cross (X) — high-contrast lines
    canvas.save();
    canvas.clipRRect(rrect);
    final crossPaint = Paint()
      ..color = AppColors.wallCross
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final inset = cellSize * 0.22;
    canvas.drawLine(
      Offset(rect.left + inset, rect.top + inset),
      Offset(rect.right - inset, rect.bottom - inset),
      crossPaint,
    );
    canvas.drawLine(
      Offset(rect.right - inset, rect.top + inset),
      Offset(rect.left + inset, rect.bottom - inset),
      crossPaint,
    );
    canvas.restore();
  }

  /// Draws the 3D inset empty cell (dark sunken look).
  void _drawInsetCell(Canvas canvas, Rect rect, RRect rrect) {
    final shadowPaint = Paint()
      ..color = AppColors.cellShadow
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
    canvas.drawRRect(
      rrect.shift(const Offset(1.0, 1.0)),
      shadowPaint,
    );

    final highlightPaint = Paint()
      ..color = AppColors.cellHighlight.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.5);
    canvas.drawRRect(
      rrect.shift(const Offset(-0.5, -0.5)),
      highlightPaint,
    );

    final fillPaint = Paint()..color = AppColors.cellBackground;
    canvas.drawRRect(rrect, fillPaint);

    final borderPaint = Paint()
      ..color = AppColors.cellBorder.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    canvas.drawRRect(rrect, borderPaint);
  }

  /// Draws a visited cell with warm amber tint + Phase 2 entry effects.
  void _drawVisitedCell(
      Canvas canvas, Rect rect, RRect rrect, int row, int col) {
    final pathIndex =
        gameState.path.indexWhere((p) => p.row == row && p.col == col);
    final progress = gameState.path.length > 1
        ? pathIndex / (gameState.path.length - 1)
        : 0.0;

    final baseColor = Color.lerp(
      palette.filledCellDark,
      palette.filledCellLight,
      progress,
    )!;

    // Phase 2: Cell entry scale effect
    final scale = cellEntryScaleGetter(row, col);
    final entryGlow = cellEntryGlowGetter(row, col);

    if (scale != 1.0) {
      canvas.save();
      final center = rect.center;
      canvas.translate(center.dx, center.dy);
      canvas.scale(scale);
      canvas.translate(-center.dx, -center.dy);
    }

    final fillPaint = Paint()..color = baseColor;
    canvas.drawRRect(rrect, fillPaint);

    // Phase 2: White glow ring flash on entry
    if (entryGlow > 0) {
      final glowPaint = Paint()
        ..color = Colors.white.withValues(alpha: entryGlow)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawRRect(rrect, glowPaint);
    }

    final borderPaint = Paint()
      ..color = palette.filledCellBorder.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    canvas.drawRRect(rrect, borderPaint);

    if (palette.patterns) _drawHatch(canvas, rect, rrect);

    if (scale != 1.0) {
      canvas.restore();
    }
  }

  /// Colorblind pattern: diagonal hatching clipped to the cell.
  void _drawHatch(Canvas canvas, Rect rect, RRect rrect) {
    final paint = Paint()
      ..color = palette.patternOverlay
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    canvas.save();
    canvas.clipRRect(rrect);
    final step = (cellSize / 5).clamp(4.0, 12.0);
    for (var d = -rect.height; d < rect.width; d += step) {
      canvas.drawLine(
        Offset(rect.left + d, rect.bottom),
        Offset(rect.left + d + rect.height, rect.top),
        paint,
      );
    }
    canvas.restore();
  }

  /// Draws the player's line using [PathRenderer].
  void _drawLine(Canvas canvas) {
    if (gameState.path.isEmpty) return;

    final points = <Offset>[];
    for (final p in gameState.path) {
      points.add(Offset(
        p.col * cellSize + cellSize / 2,
        p.row * cellSize + cellSize / 2,
      ));
    }

    final renderer = PathRenderer(
      cellSize: cellSize,
      palette: palette,
      glowBreathValue: glowBreathValue,
    );

    renderer.paint(canvas, points, segmentProgressGetter);
  }

  /// Draws a waypoint circle with number.
  void _drawWaypoint(Canvas canvas, int row, int col) {
    Waypoint? wp;
    for (final w in gameState.puzzle.waypoints) {
      if (w.row == row && w.col == col) {
        wp = w;
        break;
      }
    }
    if (wp == null) return;

    final isVisited = gameState.path.any((p) => p.row == row && p.col == col);
    final isStart = wp.order == 1;
    final center = Offset(
      col * cellSize + cellSize / 2,
      row * cellSize + cellSize / 2,
    );
    final radius = cellSize * 0.34;

    // Phase 4: waypoint scale bounce when burst is active and this is the target
    double wpScale = 1.0;
    if (waypointBurstProgress >= 0 &&
        waypointBurstGridPos != null &&
        waypointBurstGridPos!.dx.round() == col &&
        waypointBurstGridPos!.dy.round() == row) {
      // Scale 1.0 → 1.15 → 1.0 over first half of burst
      final t = (waypointBurstProgress * 2).clamp(0.0, 1.0);
      wpScale = 1.0 + 0.15 * math.sin(t * math.pi);
    }

    if (isVisited) {
      final glowColor = isStart ? palette.waypointStartFill : palette.waypointFill;
      final glowPaint = Paint()
        ..color = glowColor.withValues(alpha: 0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawCircle(center, radius * wpScale + 4, glowPaint);
    }

    Color fillColor;
    if (isStart) {
      fillColor = isVisited
          ? palette.waypointStartFill
          : palette.waypointStartFill.withValues(alpha: 0.7);
    } else {
      fillColor = isVisited
          ? palette.waypointFill
          : palette.waypointFill.withValues(alpha: 0.8);
    }

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawCircle(
        center + const Offset(0, 1), radius * wpScale, shadowPaint);

    final circlePaint = Paint()..color = fillColor;
    canvas.drawCircle(center, radius * wpScale, circlePaint);

    final borderPaint = Paint()
      ..color = isStart
          ? palette.waypointStartBorder.withValues(alpha: 0.5)
          : palette.waypointBorder.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, radius * wpScale, borderPaint);

    // Colorblind pattern: inner ring so waypoints read by shape too.
    if (palette.patterns) {
      final ringPaint = Paint()
        ..color = (isStart ? palette.waypointStartText : palette.waypointText)
            .withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(center, radius * wpScale * 0.78, ringPaint);
    }

    final textColor = isStart ? palette.waypointStartText : palette.waypointText;
    final textPainter = TextPainter(
      text: TextSpan(
        text: '${wp.order}',
        style: TextStyle(
          color: textColor,
          fontSize: cellSize * 0.28 * wpScale,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset(
        center.dx - textPainter.width / 2,
        center.dy - textPainter.height / 2,
      ),
    );
  }

  /// Draws the hint cell highlight with Phase 3 pulsing.
  void _drawHintCell(Canvas canvas) {
    final hint = gameState.hintCell;
    if (hint == null) return;

    final center = Offset(
      hint.col * cellSize + cellSize / 2,
      hint.row * cellSize + cellSize / 2,
    );
    final radius = cellSize * 0.35;

    // Phase 3: Pulsing glow
    final pulseScale = 1.0 + hintPulseValue * 0.15;
    final pulseAlpha = 0.15 + hintPulseValue * 0.15;
    final pulseBlur = 8.0 + hintPulseValue * 6.0;

    final glowPaint = Paint()
      ..color = palette.hint.withValues(alpha: pulseAlpha)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, pulseBlur);
    canvas.drawCircle(center, (radius + 8) * pulseScale, glowPaint);

    final circlePaint = Paint()..color = palette.hint.withValues(alpha: 0.5);
    canvas.drawCircle(center, radius, circlePaint);

    final borderPaint = Paint()
      ..color = palette.hint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawCircle(center, radius, borderPaint);
  }

  /// Wrong-cell hint: reddish pulsing frame + cross on the divergent cell.
  void _drawWrongCell(Canvas canvas) {
    final cell = wrongCell;
    if (cell == null) return;

    final rect = Rect.fromLTWH(
      cell.col * cellSize + _cellInset,
      cell.row * cellSize + _cellInset,
      cellSize - _cellInset * 2,
      cellSize - _cellInset * 2,
    );
    final rrect =
        RRect.fromRectAndRadius(rect, const Radius.circular(_cellRadius));
    final pulseAlpha = 0.25 + hintPulseValue * 0.2;

    canvas.drawRRect(
      rrect,
      Paint()
        ..color = palette.wrongCell.withValues(alpha: pulseAlpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawRRect(
      rrect,
      Paint()..color = palette.wrongCell.withValues(alpha: 0.35),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = palette.wrongCell
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    final inset = cellSize * 0.32;
    final crossPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      rect.topLeft + Offset(inset, inset),
      rect.bottomRight - Offset(inset, inset),
      crossPaint,
    );
    canvas.drawLine(
      rect.topRight + Offset(-inset, inset),
      rect.bottomLeft + Offset(inset, -inset),
      crossPaint,
    );
  }

  /// Phase 4: Waypoint burst — expanding gold ring + particle dots.
  void _drawWaypointBurst(Canvas canvas) {
    if (waypointBurstGridPos == null || waypointBurstProgress < 0) return;

    final center = Offset(
      waypointBurstGridPos!.dx * cellSize + cellSize / 2,
      waypointBurstGridPos!.dy * cellSize + cellSize / 2,
    );

    final t = waypointBurstProgress;
    final maxRadius = cellSize * 0.8;
    final ringRadius = maxRadius * Curves.easeOut.transform(t);
    final ringAlpha = (1.0 - t) * 0.6;

    // Expanding gold ring
    final ringPaint = Paint()
      ..color = AppColors.streakGold.withValues(alpha: ringAlpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5 * (1.0 - t)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 * t);
    canvas.drawCircle(center, ringRadius, ringPaint);

    // 4 radiating particle dots
    for (int i = 0; i < 4; i++) {
      final angle = (i * math.pi / 2) + (math.pi / 4);
      final particleRadius = ringRadius * 0.9;
      final px = center.dx + math.cos(angle) * particleRadius;
      final py = center.dy + math.sin(angle) * particleRadius;
      final dotPaint = Paint()
        ..color = AppColors.streakGold.withValues(alpha: ringAlpha * 0.8);
      canvas.drawCircle(Offset(px, py), 2.5 * (1.0 - t), dotPaint);
    }
  }

  /// Phase 5: Grid completion ripple — white ring expands from center.
  void _drawCompletionRipple(Canvas canvas, Size size) {
    if (completionRippleProgress < 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width * 0.8;
    final t = Curves.easeOut.transform(completionRippleProgress);
    final rippleRadius = maxRadius * t;
    final rippleAlpha = (1.0 - t) * 0.4;

    final ripplePaint = Paint()
      ..color = Colors.white.withValues(alpha: rippleAlpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0 * (1.0 - t)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 + 8 * t);
    canvas.drawCircle(center, rippleRadius, ripplePaint);

    // Inner brighter ring
    final innerPaint = Paint()
      ..color = Colors.white.withValues(alpha: rippleAlpha * 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 * (1.0 - t);
    canvas.drawCircle(center, rippleRadius * 0.95, innerPaint);
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) {
    // Animation ticks arrive through `repaint`; this only has to catch state
    // the widget rebuilt for.
    return oldDelegate.gameState != gameState ||
        oldDelegate.palette != palette ||
        oldDelegate.wrongCell != wrongCell ||
        oldDelegate.cellSize != cellSize ||
        oldDelegate.invalidCell != invalidCell ||
        oldDelegate.waypointBurstGridPos != waypointBurstGridPos;
  }
}
