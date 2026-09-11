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

  /// Visited / filled cell (warm tint under the line)
  static const filledCellLight = Color(0xFF3A2A12);
  static const filledCellDark = Color(0xFF241A0C);

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

  // ─── Path line (amber ramp, matches the app icon) ───────────────────
  /// Bright cap drawn at the head of the line.
  static const pathHead = pathYellowBright;
  /// Cap drawn at waypoint 1, the start of the line.
  static const pathStartCap = pathOrangeDeep;
  /// Soft bloom under the stroke.
  static const pathGlowSoft = Color(0x33FF9100);

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
  // Okabe–Ito based. Each mode pairs a path hue with a contrasting
  // waypoint hue that stays distinguishable under that deficiency; pattern
  // overlays (hatching / rings) are added on top so colour is never the
  // only cue.
  static const deuteranopiaPath = Color(0xFF0072B2);
  static const deuteranopiaWaypoint = Color(0xFFE69F00);
  static const protanopiaPath = Color(0xFF56B4E9);
  static const protanopiaWaypoint = Color(0xFFD55E00);
  static const tritanopiaPath = Color(0xFF009E73);
  static const tritanopiaWaypoint = Color(0xFFCC79A7);

  /// Deuteranopia: blue path, orange waypoints.
  static const cbDeutPathGradient = [
    Color(0xFF003F6B),
    Color(0xFF00568A),
    deuteranopiaPath,
    Color(0xFF3399DD),
    Color(0xFF66B8EE),
  ];
  static const cbDeutHeadHighlight = Color(0xFFBFE4FF);
  static const cbDeutGlow = Color(0x600072B2);
  static const cbDeutWaypointFill = deuteranopiaWaypoint;
  static const cbDeutWaypointStart = Color(0xFFB87A00);
  static const cbDeutFilledDark = Color(0xFF0F2A44);
  static const cbDeutFilledLight = Color(0xFF16406A);

  /// Protanopia: sky-blue path, yellow waypoints.
  static const cbProtPathGradient = [
    Color(0xFF1B5E8C),
    Color(0xFF2F7FB5),
    protanopiaPath,
    Color(0xFF7FC8F0),
    Color(0xFFA8DDF7),
  ];
  static const cbProtHeadHighlight = Color(0xFFDDF2FC);
  static const cbProtGlow = Color(0x6056B4E9);
  static const cbProtWaypointFill = Color(0xFFF0E442);
  static const cbProtWaypointStart = Color(0xFFC9BC1E);
  static const cbProtFilledDark = Color(0xFF12344A);
  static const cbProtFilledLight = Color(0xFF1B4F6E);

  /// Tritanopia: red path, teal waypoints.
  static const cbTritPathGradient = [
    Color(0xFF7A1414),
    Color(0xFFA11E1E),
    Color(0xFFD62828),
    Color(0xFFE85D5D),
    Color(0xFFF28C8C),
  ];
  static const cbTritHeadHighlight = Color(0xFFFFD1D1);
  static const cbTritGlow = Color(0x60D62828);
  static const cbTritWaypointFill = tritanopiaPath;
  static const cbTritWaypointStart = Color(0xFF006B4E);
  static const cbTritFilledDark = Color(0xFF3A1414);
  static const cbTritFilledLight = Color(0xFF5A1E1E);

  /// Highlight for the "wrong cell" hint (backtrack to here).
  static const wrongCell = Color(0xFFEF4444);
  static const wrongCellTritanopia = Color(0xFFCC79A7);

  /// Pattern overlay stroke used in colorblind modes.
  static const patternOverlay = Color(0x59FFFFFF);

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
