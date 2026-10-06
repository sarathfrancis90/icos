import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../providers/colorblind_mode_provider.dart';
import 'grid_palette.dart';

/// Puzzle-screen colours (board, celebration) for the ambient theme. The
/// board itself is a [GridPalette] per colorblind mode; this extension picks
/// the light or dark set so a theme switch re-themes the grid live.
@immutable
class PuzzlePalette extends ThemeExtension<PuzzlePalette> {
  const PuzzlePalette({
    required this.brightness,
    required this.confetti,
    required this.sparks,
    required this.scrimTop,
    required this.scrimBottom,
  });

  final Brightness brightness;

  /// Confetti pieces in the celebration burst (all read on the theme's
  /// background).
  final List<Color> confetti;

  /// Small sparks around the result card.
  final List<Color> sparks;

  /// Scrim behind the result card, top to bottom.
  final Color scrimTop;
  final Color scrimBottom;

  /// The board palette for [mode].
  GridPalette grid(ColorblindMode mode) =>
      GridPalette.forMode(mode, brightness: brightness);

  static const dark = PuzzlePalette(
    brightness: Brightness.dark,
    confetti: [
      AppColors.pathYellowBright,
      AppColors.pathOrange,
      AppColors.purpleLight,
      AppColors.success,
      AppColors.streakGold,
      Colors.white,
      AppColors.pathAmber,
    ],
    sparks: [
      AppColors.pathYellowBright,
      AppColors.pathOrange,
      AppColors.purpleLight,
      AppColors.streakGold,
      AppColors.pathAmber,
    ],
    scrimTop: Color(0x26FF6D00),
    scrimBottom: Color(0xD9000000),
  );

  static const light = PuzzlePalette(
    brightness: Brightness.light,
    confetti: [
      Color(0xFFC2410C),
      Color(0xFFD97706),
      AppColors.purpleDeep,
      AppColors.successOnLight,
      AppColors.goldOnLight,
      AppColors.infoOnLight,
      Color(0xFFB45309),
    ],
    sparks: [
      Color(0xFFC2410C),
      Color(0xFFD97706),
      AppColors.purpleDeep,
      AppColors.goldOnLight,
      Color(0xFFB45309),
    ],
    scrimTop: Color(0x1FFF6D00),
    scrimBottom: Color(0xE6F8FAFC),
  );

  @override
  PuzzlePalette copyWith() => this;

  @override
  PuzzlePalette lerp(covariant ThemeExtension<PuzzlePalette>? other, double t) =>
      other is PuzzlePalette && t >= 0.5 ? other : this;
}

extension PuzzlePaletteContext on BuildContext {
  PuzzlePalette get puzzlePalette {
    final theme = Theme.of(this);
    return theme.extension<PuzzlePalette>() ??
        (theme.brightness == Brightness.dark
            ? PuzzlePalette.dark
            : PuzzlePalette.light);
  }
}
