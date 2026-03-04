import 'package:flutter/services.dart';
import '../services/storage_service.dart';

abstract final class Haptics {
  static bool get _enabled {
    try {
      return StorageService.hapticEnabled;
    } catch (_) {
      return false;
    }
  }

  static void light() {
    if (!_enabled) return;
    HapticFeedback.lightImpact();
  }

  static void medium() {
    if (!_enabled) return;
    HapticFeedback.mediumImpact();
  }

  static void heavy() {
    if (!_enabled) return;
    HapticFeedback.heavyImpact();
  }

  static void selection() {
    if (!_enabled) return;
    HapticFeedback.selectionClick();
  }

  /// Ultra-light click for each path step.
  static void pathStep() {
    if (!_enabled) return;
    HapticFeedback.selectionClick();
  }

  /// Double-tap pattern when reaching a waypoint.
  static Future<void> waypointReached() async {
    if (!_enabled) return;
    HapticFeedback.mediumImpact();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    HapticFeedback.lightImpact();
  }

  /// Triple-tap descending pattern for puzzle completion.
  static Future<void> puzzleComplete() async {
    if (!_enabled) return;
    HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    HapticFeedback.mediumImpact();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    HapticFeedback.lightImpact();
  }

  /// Double-tap for hint reveal.
  static Future<void> hintReveal() async {
    if (!_enabled) return;
    HapticFeedback.lightImpact();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    HapticFeedback.selectionClick();
  }

  /// Single heavy buzz for errors.
  static void error() {
    if (!_enabled) return;
    HapticFeedback.heavyImpact();
  }

  /// Light tap for undo.
  static void undo() {
    if (!_enabled) return;
    HapticFeedback.lightImpact();
  }
}
