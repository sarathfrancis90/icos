import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../../core/utils/date_utils.dart';

class ShareCardGenerator {
  /// Generate a share card image from a GlobalKey pointing to a RepaintBoundary.
  static Future<Uint8List?> captureFromWidget(GlobalKey key) async {
    try {
      final boundary =
          key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  /// Build share text for the puzzle result with emoji grid.
  static String buildShareText({
    required int timeSeconds,
    required int hintsUsed,
    required int gridSize,
    required String difficulty,
    required bool underPar,
    List<List<bool>>? gridFilled,
    String? dateLabel,
    int? streak,
  }) {
    final label = dateLabel ?? AppDateUtils.todayUtc();
    final timeStr = AppDateUtils.formatTime(timeSeconds);
    final hintStr = hintsUsed == 0 ? 'No hints' : '$hintsUsed hint${hintsUsed > 1 ? 's' : ''}';

    final buffer = StringBuffer()
      ..writeln('Icos $label')
      ..writeln('${gridSize}x$gridSize ${difficulty[0].toUpperCase()}${difficulty.substring(1)}')
      ..writeln('$timeStr · $hintStr')
      ..writeln(underPar ? '⭐ Under Par!' : '✅ Solved!');
    if (streak != null && streak > 0) {
      buffer.writeln('🔥 $streak day streak');
    }

    // Emoji grid representation
    if (gridFilled != null) {
      buffer.writeln();
      for (final row in gridFilled) {
        for (final cell in row) {
          buffer.write(cell ? '🟧' : '⬛');
        }
        buffer.writeln();
      }
    }

    return buffer.toString();
  }
}
