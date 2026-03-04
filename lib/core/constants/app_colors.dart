import 'package:flutter/material.dart';

abstract final class AppColors {
  // ─── Background Layers ───────────────────────────────────────────
  static const deepBlack = Color(0xFF0A0E14);
  static const darkSurface = Color(0xFF141A24);
  static const cardSurface = Color(0xFF1A2232);
  static const elevatedSurface = Color(0xFF1F2A3C);

  // Legacy aliases used across the app
  static const deepNavy = deepBlack;
  static const darkNavy = darkSurface;
  static const mediumNavy = cardSurface;

  // ─── Grid & Cell Colors ──────────────────────────────────────────
  /// 3D-embossed empty cell (dark inset look)
  static const cellBackground = Color(0xFF1C2535);
  static const cellHighlight = Color(0xFF243045); // top-left light edge
  static const cellShadow = Color(0xFF0D1219); // bottom-right shadow edge
  static const cellBorder = Color(0xFF2A3548);

  /// Visited / filled cell (snake trail green tint)
  static const filledCellLight = Color(0xFF1B4332);
  static const filledCellDark = Color(0xFF14291E);

  // Grid lines (subtle)
  static const gridLine = Color(0xFF1E2D42);
  static const gridLineLight = Color(0xFFE2E8F0);

  // ─── Path Gradient (Orange → Yellow) ─────────────────────────────
  static const pathOrangeDeep = Color(0xFFE65100);
  static const pathOrange = Color(0xFFFF6D00);
  static const pathAmber = Color(0xFFFF9100);
  static const pathYellow = Color(0xFFFFBF00);
  static const pathYellowBright = Color(0xFFFFD740);
  static const pathGlow = Color(0x40FF9100);

  /// The gradient stops for the tube path
  static const pathGradientColors = [
    pathOrangeDeep,
    pathOrange,
    pathAmber,
    pathYellow,
    pathYellowBright,
  ];

  // ─── Waypoints ───────────────────────────────────────────────────
  static const waypointFill = Color(0xFFFFFFFF);
  static const waypointBorder = Color(0xFFE0E0E0);
  static const waypointText = Color(0xFF1A1A1A);
  static const waypointStartFill = Color(0xFF8D6E63); // bronze/brown for wp 1
  static const waypointStartBorder = Color(0xFFA1887F);

  // ─── Walls ───────────────────────────────────────────────────────
  static const wallFill = Color(0xFF2E3A50);
  static const wallBorder = Color(0xFF4E5E78);
  static const wallCross = Color(0xFF8090A8);

  // ─── Purple Accent (Buttons) ─────────────────────────────────────
  static const purpleLight = Color(0xFFB388FF);
  static const purplePrimary = Color(0xFF9C27B0);
  static const purpleDeep = Color(0xFF7B1FA2);
  static const purpleDark = Color(0xFF6A1B9A);
  static const purpleGradientStart = Color(0xFFAB47BC);
  static const purpleGradientEnd = Color(0xFF7B1FA2);

  // ─── Primary Accent ──────────────────────────────────────────────
  static const electricBlue = Color(0xFF3B82F6);
  static const electricBlueDim = Color(0xFF2563EB);

  // ─── UI Accent Colors ────────────────────────────────────────────
  static const success = Color(0xFF22C55E);
  static const successDim = Color(0xFF16A34A);
  static const warning = Color(0xFFF59E0B);
  static const error = Color(0xFFEF4444);
  static const streakGold = Color(0xFFFFD700);
  static const hintPurple = Color(0xFF8B5CF6);
  static const coralOrange = Color(0xFFFF6B35);
  static const coralOrangeLight = Color(0xFFFF8F5E);

  // ─── Snake Colors (Neon Green palette) ──────────────────────────────
  static const snakeHeadHighlight = Color(0xFF7DFFB3); // mint-white specular
  static const snakeHeadBright = Color(0xFF39FF7F); // electric neon head
  static const snakeBodyStart = Color(0xFF22FF6E); // bright near head
  static const snakeBodyMid = Color(0xFF00E650); // strong green
  static const snakeBodyDark = Color(0xFF00B341); // deep emerald
  static const snakeBodyEnd = Color(0xFF007A2D); // dark forest tail
  static const snakeSegmentHighlight = Color(0xFFB3FFD6); // top-left specular
  static const snakeSegmentShadow = Color(0xFF005C22); // bottom-right shadow
  static const snakeEye = Color(0xFFF0FFF4); // green-tinted sclera
  static const snakePupil = Color(0xFF0A1628); // matches background
  static const snakeTongue = Color(0xFFFF4757); // coral-red contrast
  static const snakeGlowOuter = Color(0x4000FF55); // outer neon bloom
  static const snakeGlowInner = Color(0x6039FF7F); // inner glow halo
  static const snakeBellyHighlight = Color(0xFF66FFB3); // underside stripe
  static const snakeScaleHighlight = Color(0x30FFFFFF);
  // Legacy alias
  static const snakeGlow = snakeGlowOuter;

  static const snakeGradientColors = [
    snakeBodyEnd, // tail
    snakeBodyDark,
    snakeBodyMid,
    snakeBodyStart,
    snakeHeadBright, // head
  ];

  // ─── Glow & Effects ──────────────────────────────────────────────
  static const pathGlowOrange = Color(0x60FF9100);
  static const pathGlowYellow = Color(0x60FFD740);
  static const purpleGlow = Color(0x409C27B0);
  static const goldGlow = Color(0x40FFD700);
  static const celebrationBurst = Color(0xFFFF6D00);

  // ─── Info Bar / Glass ────────────────────────────────────────────
  static const glassFill = Color(0x33FFFFFF);
  static const glassBorder = Color(0x22FFFFFF);
  static const glassText = Color(0xCCFFFFFF);

  // ─── Text ────────────────────────────────────────────────────────
  static const textPrimaryDark = Color(0xFFF1F5F9);
  static const textSecondaryDark = Color(0xFF8899AA);
  static const textTertiaryDark = Color(0xFF7A8B9D);
  static const textPrimaryLight = Color(0xFF0F172A);
  static const textSecondaryLight = Color(0xFF64748B);

  // ─── Bottom Navigation ───────────────────────────────────────────
  static const navBarBackground = Color(0xFF111822);
  static const navBarSelected = purpleLight;
  static const navBarUnselected = Color(0xFF5A6B7D);

  // ─── Light Theme (kept for accessibility / settings) ─────────────
  static const lightBackground = Color(0xFFF8FAFC);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightOnBackground = Color(0xFF0F172A);
  static const lightOnSurface = Color(0xFF1E293B);
  static const lightGridLine = Color(0xFFCBD5E1);
  static const lightFilledCell = Color(0xFFDBEAFE);

  // ─── Colorblind Palettes ─────────────────────────────────────────
  static const deuteranopiaPath = Color(0xFF0072B2);
  static const deuteranopiaWaypoint = Color(0xFFE69F00);
  static const protanopiaPath = Color(0xFF56B4E9);
  static const protanopiaWaypoint = Color(0xFFD55E00);
  static const tritanopiaPath = Color(0xFF009E73);
  static const tritanopiaWaypoint = Color(0xFFCC79A7);

  // ─── Convenience gradients ───────────────────────────────────────
  static const purpleButtonGradient = LinearGradient(
    colors: [purpleGradientStart, purpleGradientEnd],
  );

  static const pathTubeGradient = LinearGradient(
    colors: [pathOrangeDeep, pathOrange, pathAmber, pathYellow, pathYellowBright],
  );

  // Legacy aliases
  static const pathFill = pathOrange;
  static const emptyCell = Colors.transparent;
  static const filledCell = filledCellLight;
}
