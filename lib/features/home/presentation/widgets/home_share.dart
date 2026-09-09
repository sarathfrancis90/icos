import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/services/analytics_service.dart';
import '../../../../core/services/app_logger.dart';
import '../../../puzzle/data/submission_result.dart';
import '../../../sharing/domain/share_card_generator.dart';
import '../../../sharing/presentation/share_card_widget.dart';

/// Shares today's stored result from Home: renders the spoiler-free card in
/// an invisible overlay entry, captures it as PNG and hands it to the OS
/// share sheet (text-only fallback).
Future<void> shareResultFromHome(
  BuildContext context, {
  required SubmissionResult result,
  required int gridSize,
  required String difficulty,
  required int parTimeSeconds,
  required List<List<int>> walls,
  int? streak,
}) async {
  final underPar = result.timeSeconds <= parTimeSeconds;
  final text = ShareCardGenerator.buildShareText(
    timeSeconds: result.timeSeconds,
    hintsUsed: result.hintsUsed,
    gridSize: gridSize,
    difficulty: difficulty,
    underPar: underPar,
    dateLabel: result.date,
    streak: streak,
  );

  final key = GlobalKey();
  final overlay = Overlay.maybeOf(context);
  OverlayEntry? entry;
  if (overlay != null) {
    entry = OverlayEntry(
      builder: (_) => Positioned(
        left: -2000,
        top: 0,
        child: Material(
          type: MaterialType.transparency,
          child: ShareCardWidget(
            repaintKey: key,
            gridSize: gridSize,
            difficulty: difficulty,
            timeSeconds: result.timeSeconds,
            hintsUsed: result.hintsUsed,
            parTimeSeconds: parTimeSeconds,
            dateLabel: result.date,
            streak: streak,
            pathVisualization: PathBlocksVisualization(
              gridSize: gridSize,
              path: result.path,
              walls: walls,
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    // Give the entry a frame to lay out and paint.
    await WidgetsBinding.instance.endOfFrame;
  }

  try {
    final bytes =
        entry == null ? null : await ShareCardGenerator.captureFromWidget(key);
    if (bytes != null) {
      final name = 'icos-${result.date}.png';
      await Share.shareXFiles(
        [XFile.fromData(bytes, mimeType: 'image/png', name: name)],
        text: text,
        fileNameOverrides: [name],
      );
    } else {
      await Share.share(text);
    }
    await AnalyticsService.logEvent(AnalyticsEvents.shareResult, {
      'image': bytes != null,
      'from': 'home',
    });
  } catch (e, st) {
    AppLogger.warn('share from home failed', error: e, st: st);
    try {
      await Share.share(text);
    } catch (_) {}
  } finally {
    entry?.remove();
  }
}
