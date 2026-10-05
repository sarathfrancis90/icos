import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/services/app_logger.dart';
import 'package:icos/core/services/audio_service.dart';

class _FakeSound implements SoundPlayer {
  _FakeSound(
    this.asset,
    this.log, {
    this.failLoad = false,
    this.failPlay = false,
  });

  final String asset;
  final List<String> log;
  final bool failLoad;
  final bool failPlay;

  @override
  Future<void> load(String asset, double volume) async {
    log.add('load $asset');
    if (failLoad) throw Exception('Failed to set source');
  }

  @override
  Future<void> play() async {
    log.add('play $asset');
    if (failPlay) throw Exception('DarwinAudioError');
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  late List<String> calls;
  late List<Map<String, Object?>> logged;
  var enabled = true;

  AudioService service({bool failLoad = false, bool failPlay = false}) =>
      AudioService.forTesting(
        playerFactory: (asset) =>
            _FakeSound(asset, calls, failLoad: failLoad, failPlay: failPlay),
        soundEnabled: () => enabled,
      );

  setUp(() {
    calls = [];
    logged = [];
    enabled = true;
    AppLogger.testSink = logged.add;
  });
  tearDown(() => AppLogger.testSink = null);

  test(
    'every bundled sound asset exists and is in a format iOS can decode',
    () {
      for (final path in AudioService.assetPaths) {
        expect(
          path,
          isNot(endsWith('.ogg')),
          reason: 'AVPlayer cannot decode Ogg Vorbis (iOS)',
        );
        expect(File('assets/$path').existsSync(), isTrue, reason: path);
      }
    },
  );

  test('preloads each sound once and reuses it', () async {
    final audio = service();
    await audio.initialize();
    await audio.initialize();
    final loads = calls.where((c) => c.startsWith('load')).length;
    expect(loads, SoundEffect.values.length);

    await audio.play(SoundEffect.pathStep);
    await audio.play(SoundEffect.pathStep);
    expect(
      calls.where((c) => c.startsWith('load')).length,
      loads,
      reason: 'playing must not reload the source',
    );
    expect(calls.where((c) => c.startsWith('play')).length, 2);
  });

  test('respects the sound setting', () async {
    final audio = service();
    await audio.initialize();
    enabled = false;
    await audio.play(SoundEffect.pathStep);
    expect(calls.where((c) => c.startsWith('play')), isEmpty);
  });

  test('playback failures are swallowed and logged at most once', () async {
    final audio = service(failPlay: true);
    await audio.initialize();
    for (var i = 0; i < 50; i++) {
      await audio.play(SoundEffect.pathStep);
    }
    expect(logged.length, lessThanOrEqualTo(1));
    if (logged.isNotEmpty) expect(logged.single['level'], 'debug');
  });

  test('a sound that cannot be loaded is skipped quietly', () async {
    final audio = service(failLoad: true);
    await audio.initialize();
    for (var i = 0; i < 50; i++) {
      await audio.play(SoundEffect.pathStep);
    }
    expect(
      calls.where((c) => c.startsWith('play')),
      isEmpty,
      reason: 'no point retrying a source that failed to load',
    );
    expect(logged.length, lessThanOrEqualTo(1));
  });
}
