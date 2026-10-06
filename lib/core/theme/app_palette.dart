import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_colors.dart';

/// Semantic surface and text colours for the app's own (non-Material)
/// widgets, resolved per theme. The dark instance uses exactly the values the
/// dark screens always had; the light instance keeps every text pair at
/// WCAG AA on the light surfaces (see test/accessibility/contrast_test.dart).
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.card,
    required this.elevated,
    required this.inset,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textDisabled,
    required this.accent,
    required this.success,
    required this.gold,
    required this.warning,
    required this.coral,
    required this.info,
    required this.error,
    required this.hint,
    required this.glassFill,
    required this.glassBorder,
    required this.glassText,
    required this.meshBase,
    required this.meshColors,
    required this.particle,
    required this.shadow,
    required this.titleGradient,
  });

  final Brightness brightness;

  /// Screen background (scaffold).
  final Color background;
  final Color surface;
  final Color card;

  /// Raised chips, pills and secondary buttons on a card.
  final Color elevated;

  /// Sunken wells (empty calendar days, disabled controls).
  final Color inset;
  final Color border;

  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textDisabled;

  /// Accent for text, icons and outlines (purple).
  final Color accent;
  final Color success;
  final Color gold;
  final Color warning;
  final Color coral;
  final Color info;
  final Color error;
  final Color hint;

  /// Frosted HUD / glass bars.
  final Color glassFill;
  final Color glassBorder;
  final Color glassText;

  /// Animated background base and its drifting tints.
  final Color meshBase;
  final List<Color> meshColors;

  /// Ambient particles drawn over the background.
  final Color particle;

  /// Drop shadows under raised elements.
  final Color shadow;

  /// Gradient stops for the large gradient titles (each stop keeps 3:1 on
  /// [background]).
  final List<Color> titleGradient;

  bool get isDark => brightness == Brightness.dark;

  /// Status / navigation bar icons that read on [background].
  SystemUiOverlayStyle get overlayStyle => overlayStyleFor(brightness);

  static SystemUiOverlayStyle overlayStyleFor(Brightness brightness) =>
      brightness == Brightness.dark
          ? SystemUiOverlayStyle.light.copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: Colors.transparent,
            )
          : SystemUiOverlayStyle.dark.copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: Colors.transparent,
            );

  static const dark = AppPalette(
    brightness: Brightness.dark,
    background: AppColors.deepBlack,
    surface: AppColors.darkSurface,
    card: AppColors.cardSurface,
    elevated: AppColors.elevatedSurface,
    inset: AppColors.cellBackground,
    border: AppColors.cellBorder,
    textPrimary: AppColors.textPrimaryDark,
    textSecondary: AppColors.textSecondaryDark,
    textTertiary: AppColors.textTertiaryDark,
    textDisabled: AppColors.textDisabledOnElevated,
    accent: AppColors.purpleLight,
    success: AppColors.success,
    gold: AppColors.streakGold,
    warning: AppColors.warning,
    coral: AppColors.coralOrange,
    info: AppColors.electricBlueLight,
    error: AppColors.error,
    hint: AppColors.hintPurple,
    glassFill: AppColors.glassFill,
    glassBorder: AppColors.glassBorder,
    glassText: AppColors.glassText,
    meshBase: AppColors.deepBlack,
    meshColors: [
      Color(0xFF0F1A2E),
      Color(0xFF141028),
      Color(0xFF0A1628),
      Color(0xFF1A0E28),
    ],
    particle: Colors.white,
    shadow: Colors.black,
    titleGradient: [AppColors.purpleLight, AppColors.pathYellowBright],
  );

  static const light = AppPalette(
    brightness: Brightness.light,
    background: AppColors.lightBackground,
    surface: AppColors.lightSurface,
    card: AppColors.lightSurface,
    elevated: AppColors.lightElevated,
    inset: AppColors.lightInset,
    border: AppColors.lightGridLine,
    textPrimary: AppColors.textPrimaryLight,
    textSecondary: AppColors.textSecondaryOnLight,
    textTertiary: AppColors.textTertiaryOnLight,
    textDisabled: AppColors.textSecondaryOnLight,
    accent: AppColors.purpleDeep,
    success: AppColors.successOnLight,
    gold: AppColors.goldOnLight,
    warning: AppColors.warningOnLight,
    coral: AppColors.coralOnLight,
    info: AppColors.infoOnLight,
    error: AppColors.errorOnLight,
    hint: AppColors.hintOnLight,
    glassFill: AppColors.glassFillLight,
    glassBorder: AppColors.glassBorderLight,
    glassText: AppColors.glassTextLight,
    meshBase: AppColors.lightBackground,
    meshColors: AppColors.lightMeshColors,
    particle: AppColors.textSecondaryOnLight,
    shadow: Color(0xFF64748B),
    titleGradient: [AppColors.purpleDeep, AppColors.warningOnLight],
  );

  @override
  AppPalette copyWith() => this;

  /// Theme switches cross-fade through [ThemeData.lerp]; the palette snaps at
  /// the midpoint (its colours are only ever one of the two instances).
  @override
  AppPalette lerp(covariant ThemeExtension<AppPalette>? other, double t) =>
      other is AppPalette && t >= 0.5 ? other : this;
}

extension AppPaletteContext on BuildContext {
  /// The app palette of the ambient theme (picked by brightness when the
  /// theme does not carry one).
  AppPalette get palette {
    final theme = Theme.of(this);
    return theme.extension<AppPalette>() ??
        (theme.brightness == Brightness.dark
            ? AppPalette.dark
            : AppPalette.light);
  }
}
