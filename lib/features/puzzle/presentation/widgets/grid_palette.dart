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

  static GridPalette forMode(ColorblindMode mode) => switch (mode) {
        ColorblindMode.none => standard,
        ColorblindMode.deuteranopia => deuteranopia,
        ColorblindMode.protanopia => protanopia,
        ColorblindMode.tritanopia => tritanopia,
      };
}
