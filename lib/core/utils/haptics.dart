import 'package:flutter/services.dart';
import '../services/storage_service.dart';

abstract final class Haptics {
  static void light() {
    if (!StorageService.hapticEnabled) return;
    HapticFeedback.lightImpact();
  }

  static void medium() {
    if (!StorageService.hapticEnabled) return;
    HapticFeedback.mediumImpact();
  }

  static void heavy() {
    if (!StorageService.hapticEnabled) return;
    HapticFeedback.heavyImpact();
  }

  static void selection() {
    if (!StorageService.hapticEnabled) return;
    HapticFeedback.selectionClick();
  }
}
