import 'package:flutter/material.dart';

abstract final class AppColors {
  // Primary Dark Theme (Dark Immersive)
  static const deepNavy = Color(0xFF0A1628);
  static const darkNavy = Color(0xFF0F1D30);
  static const mediumNavy = Color(0xFF162238);
  static const electricBlue = Color(0xFF3B82F6);
  static const electricBlueDim = Color(0xFF2563EB);
  static const coralOrange = Color(0xFFFF6B35);
  static const coralOrangeLight = Color(0xFFFF8F5E);

  // Path & Grid
  static const pathFill = electricBlue;
  static const waypointFill = coralOrange;
  static const wallFill = Color(0xFF1E293B);
  static const gridLine = Color(0xFF1E3A5F);
  static const gridLineLight = Color(0xFFE2E8F0);
  static const emptyCell = Colors.transparent;
  static const filledCell = Color(0xFF1E3A5F);

  // UI Accents
  static const success = Color(0xFF22C55E);
  static const warning = Color(0xFFF59E0B);
  static const error = Color(0xFFEF4444);
  static const streakGold = Color(0xFFFFD700);
  static const hintPurple = Color(0xFF8B5CF6);

  // Light Theme
  static const lightBackground = Color(0xFFF8FAFC);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightOnBackground = Color(0xFF0F172A);
  static const lightOnSurface = Color(0xFF1E293B);
  static const lightGridLine = Color(0xFFCBD5E1);
  static const lightFilledCell = Color(0xFFDBEAFE);

  // Text
  static const textPrimaryDark = Color(0xFFF1F5F9);
  static const textSecondaryDark = Color(0xFF94A3B8);
  static const textPrimaryLight = Color(0xFF0F172A);
  static const textSecondaryLight = Color(0xFF64748B);

  // Colorblind Palettes
  static const deuteranopiaPath = Color(0xFF0072B2);
  static const deuteranopiaWaypoint = Color(0xFFE69F00);
  static const protanopiaPath = Color(0xFF56B4E9);
  static const protanopiaWaypoint = Color(0xFFD55E00);
  static const tritanopiaPath = Color(0xFF009E73);
  static const tritanopiaWaypoint = Color(0xFFCC79A7);
}
