import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../providers/colorblind_mode_provider.dart';

/// Colours used by the grid painter and [PathRenderer], resolved per
/// [ColorblindMode]. Pattern overlays ([patterns]) are enabled whenever a
/// colorblind mode is active so colour is never the only cue.
class GridPalette {
  const GridPalette({
    required this.mode,
    required this.pathGradient,
    required this.pathHead,
    required this.pathStart,
    required this.pathGlow,
    required this.filledCellDark,
    required this.filledCellLight,
    required this.filledCellBorder,
    required this.waypointFill,
    required this.waypointBorder,
    required this.waypointText,
    required this.waypointStartFill,
    required this.waypointStartBorder,
    required this.waypointStartText,
    required this.hint,
    required this.wrongCell,
    this.patternOverlay = AppColors.patternOverlay,
    this.brightness = Brightness.dark,
    this.cellBackground = AppColors.cellBackground,
    this.cellHighlight = AppColors.cellHighlight,
    this.cellShadow = AppColors.cellShadow,
    this.cellBorder = AppColors.cellBorder,
    this.cellBorderAlpha = 0.3,
    this.wallFill = AppColors.wallFill,
    this.wallBorder = AppColors.wallBorder,
    this.wallCross = AppColors.wallCross,
    this.wallShadow = Colors.black,
    this.entryGlow = Colors.white,
    this.ripple = Colors.white,
    this.burst = AppColors.streakGold,
    this.dimUnvisitedWaypoints = true,
    this.waypointStartBorderAlpha = 0.5,
  });

  final ColorblindMode mode;

  /// Stroke gradient, ordered start -> head.
  final List<Color> pathGradient;

  /// Cap at the head of the line (the cell the player is "holding").
  final Color pathHead;

  /// Cap at waypoint 1, where the line begins.
  final Color pathStart;

  /// Soft bloom drawn under the stroke.
  final Color pathGlow;

  final Color filledCellDark;
  final Color filledCellLight;
  final Color filledCellBorder;

  final Color waypointFill;
  final Color waypointBorder;
  final Color waypointText;
  final Color waypointStartFill;
  final Color waypointStartBorder;
  final Color waypointStartText;

  final Color hint;
  final Color wrongCell;
  final Color patternOverlay;

  /// The theme this palette is drawn for.
  final Brightness brightness;

  // Board: sunken empty cells, raised walls and one-off effects.
  final Color cellBackground;
  final Color cellHighlight;
  final Color cellShadow;
  final Color cellBorder;
  final double cellBorderAlpha;
  final Color wallFill;
  final Color wallBorder;
  final Color wallCross;
  final Color wallShadow;

  /// Ring flashed on a cell as the line enters it.
  final Color entryGlow;

  /// Completion ripple across the board.
  final Color ripple;

  /// Ring and dots when the line reaches a waypoint.
  final Color burst;

  /// Draw waypoints the line has not reached yet slightly translucent. The
  /// light board keeps them opaque so the discs and numerals hold contrast.
  final bool dimUnvisitedWaypoints;

  /// Opacity of the start ring; the light board draws it solid so it reads
  /// against the dark disc.
  final double waypointStartBorderAlpha;

  /// Draw hatching on filled cells, rings on waypoints and ticks along the line.
  bool get patterns => mode.isActive;

  /// Amber ramp, the same colours as the app icon.
  static const GridPalette standard = GridPalette(
    mode: ColorblindMode.none,
    pathGradient: AppColors.pathGradientColors,
    pathHead: AppColors.pathHead,
    pathStart: AppColors.pathStartCap,
    pathGlow: AppColors.pathGlowSoft,
    filledCellDark: AppColors.filledCellDark,
    filledCellLight: AppColors.filledCellLight,
    filledCellBorder: AppColors.pathAmber,
    waypointFill: AppColors.waypointFill,
    waypointBorder: AppColors.waypointBorder,
    waypointText: AppColors.waypointText,
    waypointStartFill: AppColors.waypointStartFill,
    waypointStartBorder: AppColors.waypointStartBorder,
    waypointStartText: AppColors.waypointText,
    hint: AppColors.hintPurple,
    wrongCell: AppColors.wrongCell,
  );

  static const GridPalette deuteranopia = GridPalette(
    mode: ColorblindMode.deuteranopia,
    pathGradient: AppColors.cbDeutPathGradient,
    pathHead: Color(0xFF9ED2F5),
    pathStart: Color(0xFF003F6B),
    pathGlow: Color(0x330072B2),
    filledCellDark: AppColors.cbDeutFilledDark,
    filledCellLight: AppColors.cbDeutFilledLight,
    filledCellBorder: AppColors.deuteranopiaPath,
    waypointFill: AppColors.cbDeutWaypointFill,
    waypointBorder: Color(0xFFFFD27F),
    waypointText: Color(0xFF1A1A1A),
    waypointStartFill: AppColors.cbDeutWaypointStart,
    waypointStartBorder: Color(0xFFE69F00),
    waypointStartText: Colors.white,
    hint: Colors.white,
    wrongCell: AppColors.wrongCell,
  );

  static const GridPalette protanopia = GridPalette(
    mode: ColorblindMode.protanopia,
    pathGradient: AppColors.cbProtPathGradient,
    pathHead: Color(0xFFCDECFB),
    pathStart: Color(0xFF1B5E8C),
    pathGlow: Color(0x3356B4E9),
    filledCellDark: AppColors.cbProtFilledDark,
    filledCellLight: AppColors.cbProtFilledLight,
    filledCellBorder: AppColors.protanopiaPath,
    waypointFill: AppColors.cbProtWaypointFill,
    waypointBorder: Color(0xFFFFF59D),
    waypointText: Color(0xFF1A1A1A),
    waypointStartFill: AppColors.cbProtWaypointStart,
    waypointStartBorder: Color(0xFFF0E442),
    waypointStartText: Color(0xFF1A1A1A),
    hint: Colors.white,
    wrongCell: AppColors.wrongCell,
  );

  static const GridPalette tritanopia = GridPalette(
    mode: ColorblindMode.tritanopia,
    pathGradient: AppColors.cbTritPathGradient,
    pathHead: Color(0xFFFFB3B3),
    pathStart: Color(0xFF7A1414),
    pathGlow: Color(0x33D62828),
    filledCellDark: AppColors.cbTritFilledDark,
    filledCellLight: AppColors.cbTritFilledLight,
    filledCellBorder: Color(0xFFD62828),
    waypointFill: AppColors.cbTritWaypointFill,
    waypointBorder: Color(0xFF66D9B8),
    waypointText: Color(0xFF062A20),
    waypointStartFill: AppColors.cbTritWaypointStart,
    waypointStartBorder: Color(0xFF009E73),
    waypointStartText: Colors.white,
    hint: Colors.white,
    wrongCell: AppColors.wrongCellTritanopia,
  );

  // ─── Light board ─────────────────────────────────────────────────
  // Same hues as the dark palettes, darkened so the line and the waypoint
  // discs keep 3:1 on the pale cells and numerals keep 4.5:1 on their discs.

  static const GridPalette standardLight = GridPalette(
    mode: ColorblindMode.none,
    brightness: Brightness.light,
    pathGradient: AppColors.lightPathGradientColors,
    pathHead: Color(0xFFB45309),
    pathStart: Color(0xFF9A3412),
    pathGlow: Color(0x33D97706),
    filledCellDark: AppColors.lightFilledCellStart,
    filledCellLight: AppColors.lightFilledCellEnd,
    filledCellBorder: Color(0xFFB45309),
    waypointFill: AppColors.lightWaypointFill,
    waypointBorder: AppColors.lightWaypointBorder,
    waypointText: AppColors.lightWaypointText,
    waypointStartFill: AppColors.lightWaypointFill,
    waypointStartBorder: AppColors.lightWaypointStartBorder,
    waypointStartText: AppColors.lightWaypointText,
    hint: AppColors.hintOnLight,
    wrongCell: Color(0xFFDC2626),
    patternOverlay: Color(0x4D0F172A),
    cellBackground: AppColors.lightCellBackground,
    cellHighlight: AppColors.lightCellHighlight,
    cellShadow: AppColors.lightCellShadow,
    cellBorder: AppColors.lightCellBorder,
    cellBorderAlpha: 0.6,
    wallFill: AppColors.lightWallFill,
    wallBorder: AppColors.lightWallBorder,
    wallCross: AppColors.lightWallCross,
    wallShadow: Color(0xFF64748B),
    entryGlow: Color(0xFFD97706),
    ripple: Color(0xFFD97706),
    burst: AppColors.goldOnLight,
    dimUnvisitedWaypoints: false,
    waypointStartBorderAlpha: 1,
  );

  static const GridPalette deuteranopiaLight = GridPalette(
    mode: ColorblindMode.deuteranopia,
    brightness: Brightness.light,
    pathGradient: [
      Color(0xFF003F6B),
      Color(0xFF00568A),
      Color(0xFF005A8C),
      Color(0xFF0369A1),
      Color(0xFF0369A1),
    ],
    pathHead: Color(0xFF0369A1),
    pathStart: Color(0xFF003F6B),
    pathGlow: Color(0x330072B2),
    filledCellDark: Color(0xFFE0F2FE),
    filledCellLight: Color(0xFFBAE6FD),
    filledCellBorder: AppColors.deuteranopiaPath,
    waypointFill: Color(0xFF8A5300),
    waypointBorder: Color(0xFF5C3700),
    waypointText: Colors.white,
    waypointStartFill: Color(0xFF7A4A00),
    waypointStartBorder: Color(0xFFE69F00),
    waypointStartText: Colors.white,
    hint: Color(0xFF1E293B),
    wrongCell: Color(0xFFDC2626),
    patternOverlay: Color(0x4D0F172A),
    cellBackground: AppColors.lightCellBackground,
    cellHighlight: AppColors.lightCellHighlight,
    cellShadow: AppColors.lightCellShadow,
    cellBorder: AppColors.lightCellBorder,
    cellBorderAlpha: 0.6,
    wallFill: AppColors.lightWallFill,
    wallBorder: AppColors.lightWallBorder,
    wallCross: AppColors.lightWallCross,
    wallShadow: Color(0xFF64748B),
    entryGlow: Color(0xFF0072B2),
    ripple: Color(0xFF0072B2),
    burst: Color(0xFF8A5300),
    dimUnvisitedWaypoints: false,
    waypointStartBorderAlpha: 1,
  );

  static const GridPalette protanopiaLight = GridPalette(
    mode: ColorblindMode.protanopia,
    brightness: Brightness.light,
    pathGradient: [
      Color(0xFF0B4F7A),
      Color(0xFF1B5E8C),
      Color(0xFF075985),
      Color(0xFF0369A1),
      Color(0xFF0369A1),
    ],
    pathHead: Color(0xFF0369A1),
    pathStart: Color(0xFF0B4F7A),
    pathGlow: Color(0x3356B4E9),
    filledCellDark: Color(0xFFE0F2FE),
    filledCellLight: Color(0xFFBAE6FD),
    filledCellBorder: Color(0xFF0369A1),
    waypointFill: Color(0xFF6B5E00),
    waypointBorder: Color(0xFF453C00),
    waypointText: Colors.white,
    waypointStartFill: Color(0xFF5C5000),
    waypointStartBorder: Color(0xFFC9BC1E),
    waypointStartText: Colors.white,
    hint: Color(0xFF1E293B),
    wrongCell: Color(0xFFDC2626),
    patternOverlay: Color(0x4D0F172A),
    cellBackground: AppColors.lightCellBackground,
    cellHighlight: AppColors.lightCellHighlight,
    cellShadow: AppColors.lightCellShadow,
    cellBorder: AppColors.lightCellBorder,
    cellBorderAlpha: 0.6,
    wallFill: AppColors.lightWallFill,
    wallBorder: AppColors.lightWallBorder,
    wallCross: AppColors.lightWallCross,
    wallShadow: Color(0xFF64748B),
    entryGlow: Color(0xFF0369A1),
    ripple: Color(0xFF0369A1),
    burst: Color(0xFF6B5E00),
    dimUnvisitedWaypoints: false,
    waypointStartBorderAlpha: 1,
  );

  static const GridPalette tritanopiaLight = GridPalette(
    mode: ColorblindMode.tritanopia,
    brightness: Brightness.light,
    pathGradient: [
      Color(0xFF7A1414),
      Color(0xFFA11E1E),
      Color(0xFFB91C1C),
      Color(0xFFB91C1C),
      Color(0xFFB91C1C),
    ],
    pathHead: Color(0xFFB91C1C),
    pathStart: Color(0xFF7A1414),
    pathGlow: Color(0x33D62828),
    filledCellDark: Color(0xFFFEF2F2),
    filledCellLight: Color(0xFFFEE2E2),
    filledCellBorder: Color(0xFFB91C1C),
    waypointFill: Color(0xFF006B4E),
    waypointBorder: Color(0xFF004D38),
    waypointText: Colors.white,
    waypointStartFill: Color(0xFF004D38),
    waypointStartBorder: Color(0xFF34D399),
    waypointStartText: Colors.white,
    hint: Color(0xFF1E293B),
    wrongCell: Color(0xFFA0457A),
    patternOverlay: Color(0x4D0F172A),
    cellBackground: AppColors.lightCellBackground,
    cellHighlight: AppColors.lightCellHighlight,
    cellShadow: AppColors.lightCellShadow,
    cellBorder: AppColors.lightCellBorder,
    cellBorderAlpha: 0.6,
    wallFill: AppColors.lightWallFill,
    wallBorder: AppColors.lightWallBorder,
    wallCross: AppColors.lightWallCross,
    wallShadow: Color(0xFF64748B),
    entryGlow: Color(0xFFB91C1C),
    ripple: Color(0xFFB91C1C),
    burst: Color(0xFF006B4E),
    dimUnvisitedWaypoints: false,
    waypointStartBorderAlpha: 1,
  );

  /// The palette for [mode] on a board drawn in [brightness].
  static GridPalette forMode(
    ColorblindMode mode, {
    Brightness brightness = Brightness.dark,
  }) => brightness == Brightness.dark
      ? switch (mode) {
          ColorblindMode.none => standard,
          ColorblindMode.deuteranopia => deuteranopia,
          ColorblindMode.protanopia => protanopia,
          ColorblindMode.tritanopia => tritanopia,
        }
      : switch (mode) {
          ColorblindMode.none => standardLight,
          ColorblindMode.deuteranopia => deuteranopiaLight,
          ColorblindMode.protanopia => protanopiaLight,
          ColorblindMode.tritanopia => tritanopiaLight,
        };
}
