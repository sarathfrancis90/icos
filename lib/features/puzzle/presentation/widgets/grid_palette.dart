import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../providers/colorblind_mode_provider.dart';

/// Colours used by the grid painter and snake renderer, resolved per
/// [ColorblindMode]. Pattern overlays ([patterns]) are enabled whenever a
/// colorblind mode is active so colour is never the only cue.
class GridPalette {
  const GridPalette({
    required this.mode,
    required this.snakeGradientColors,
    required this.snakeHeadHighlight,
    required this.snakeHeadBright,
    required this.snakeBodyStart,
    required this.snakeBodyMid,
    required this.snakeBodyEnd,
    required this.snakeGlowOuter,
    required this.snakeGlowInner,
    required this.snakeSegmentHighlight,
    required this.snakeSegmentShadow,
    required this.snakeBellyHighlight,
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
    this.snakeEye = AppColors.snakeEye,
    this.snakePupil = AppColors.snakePupil,
    this.snakeTongue = AppColors.snakeTongue,
    this.patternOverlay = AppColors.patternOverlay,
  });

  final ColorblindMode mode;

  final List<Color> snakeGradientColors;
  final Color snakeHeadHighlight;
  final Color snakeHeadBright;
  final Color snakeBodyStart;
  final Color snakeBodyMid;
  final Color snakeBodyEnd;
  final Color snakeGlowOuter;
  final Color snakeGlowInner;
  final Color snakeSegmentHighlight;
  final Color snakeSegmentShadow;
  final Color snakeBellyHighlight;
  final Color snakeEye;
  final Color snakePupil;
  final Color snakeTongue;

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

  /// Draw hatching on filled cells and rings on waypoints.
  bool get patterns => mode.isActive;

  static const GridPalette standard = GridPalette(
    mode: ColorblindMode.none,
    snakeGradientColors: AppColors.snakeGradientColors,
    snakeHeadHighlight: AppColors.snakeHeadHighlight,
    snakeHeadBright: AppColors.snakeHeadBright,
    snakeBodyStart: AppColors.snakeBodyStart,
    snakeBodyMid: AppColors.snakeBodyMid,
    snakeBodyEnd: AppColors.snakeBodyEnd,
    snakeGlowOuter: AppColors.snakeGlowOuter,
    snakeGlowInner: AppColors.snakeGlowInner,
    snakeSegmentHighlight: AppColors.snakeSegmentHighlight,
    snakeSegmentShadow: AppColors.snakeSegmentShadow,
    snakeBellyHighlight: AppColors.snakeBellyHighlight,
    filledCellDark: AppColors.filledCellDark,
    filledCellLight: AppColors.filledCellLight,
    filledCellBorder: AppColors.pathAmber,
    waypointFill: AppColors.waypointFill,
    waypointBorder: AppColors.waypointBorder,
    waypointText: AppColors.waypointText,
    waypointStartFill: AppColors.waypointStartFill,
    waypointStartBorder: AppColors.waypointStartBorder,
    waypointStartText: Colors.white,
    hint: AppColors.hintPurple,
    wrongCell: AppColors.wrongCell,
  );

  static const GridPalette deuteranopia = GridPalette(
    mode: ColorblindMode.deuteranopia,
    snakeGradientColors: AppColors.cbDeutSnakeGradient,
    snakeHeadHighlight: AppColors.cbDeutHeadHighlight,
    snakeHeadBright: Color(0xFF66B8EE),
    snakeBodyStart: Color(0xFF3399DD),
    snakeBodyMid: AppColors.deuteranopiaPath,
    snakeBodyEnd: Color(0xFF003F6B),
    snakeGlowOuter: Color(0x400072B2),
    snakeGlowInner: AppColors.cbDeutGlow,
    snakeSegmentHighlight: Color(0xFFCCE9FF),
    snakeSegmentShadow: Color(0xFF002A4A),
    snakeBellyHighlight: Color(0xFF8FD3FF),
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
    snakeGradientColors: AppColors.cbProtSnakeGradient,
    snakeHeadHighlight: AppColors.cbProtHeadHighlight,
    snakeHeadBright: Color(0xFFA8DDF7),
    snakeBodyStart: Color(0xFF7FC8F0),
    snakeBodyMid: AppColors.protanopiaPath,
    snakeBodyEnd: Color(0xFF1B5E8C),
    snakeGlowOuter: Color(0x4056B4E9),
    snakeGlowInner: AppColors.cbProtGlow,
    snakeSegmentHighlight: Color(0xFFE6F6FD),
    snakeSegmentShadow: Color(0xFF123F5E),
    snakeBellyHighlight: Color(0xFFBFE8FA),
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
    snakeGradientColors: AppColors.cbTritSnakeGradient,
    snakeHeadHighlight: AppColors.cbTritHeadHighlight,
    snakeHeadBright: Color(0xFFF28C8C),
    snakeBodyStart: Color(0xFFE85D5D),
    snakeBodyMid: Color(0xFFD62828),
    snakeBodyEnd: Color(0xFF7A1414),
    snakeGlowOuter: Color(0x40D62828),
    snakeGlowInner: AppColors.cbTritGlow,
    snakeSegmentHighlight: Color(0xFFFFE0E0),
    snakeSegmentShadow: Color(0xFF4A0C0C),
    snakeBellyHighlight: Color(0xFFFFB3B3),
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
