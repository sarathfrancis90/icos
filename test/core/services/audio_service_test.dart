import 'dart:async';
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
  Future<void> replay() async {
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
    await audio.ready;
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
    await audio.ready;
    enabled = false;
    await audio.play(SoundEffect.pathStep);
    expect(calls.where((c) => c.startsWith('play')), isEmpty);
  });

  test('playback failures are swallowed and logged at most once', () async {
    final audio = service(failPlay: true);
    await audio.initialize();
    await audio.ready;
    for (var i = 0; i < 50; i++) {
      await audio.play(SoundEffect.pathStep);
    }
    expect(logged.length, lessThanOrEqualTo(1));
    if (logged.isNotEmpty) expect(logged.single['level'], 'debug');
  });

  test('a sound that cannot be loaded is skipped quietly', () async {
    final audio = service(failLoad: true);
    await audio.initialize();
    await audio.ready;
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

  test('initialize does not wait for a player that never prepares', () async {
    final never = Completer<void>();
    final audio = AudioService.forTesting(
      playerFactory: (asset) => _HangingSound(never.future),
      soundEnabled: () => true,
    );
    // Startup awaits (or unawaits) this: it must return at once.
    await audio.initialize().timeout(const Duration(seconds: 1));
  });

  test('sound off prepares nothing', () async {
    enabled = false;
    final audio = service();
    await audio.initialize();
    await audio.ready;
    await audio.play(SoundEffect.pathStep);
    expect(calls, isEmpty);
  });

  test(
    'a play request before preparation finishes is a silent no-op',
    () async {
      final gate = Completer<void>();
      final played = <String>[];
      final audio = AudioService.forTesting(
        playerFactory: (asset) => _HangingSound(gate.future, played: played),
        soundEnabled: () => true,
      );
      await audio.initialize();
      await audio.play(SoundEffect.pathStep); // not ready yet
      gate.complete();
      await audio.ready;
      expect(played, isEmpty, reason: 'early requests are dropped, not queued');
      await audio.play(SoundEffect.pathStep);
      expect(played, hasLength(1));
    },
  );

  test('replaying a short sound is stop then resume, never seek', () async {
    final engine = _FakeEngine();
    final sound = AudioplayersSound(engine);
    await sound.load('sounds/a.wav', 0.3);
    await sound.replay();
    await sound.replay();
    expect(engine.calls, [
      'prepare sounds/a.wav',
      'stop',
      'resume',
      'stop',
      'resume',
    ]);
  });
}

class _HangingSound implements SoundPlayer {
  _HangingSound(this.gate, {this.played});

  final Future<void> gate;
  final List<String>? played;

  @override
  Future<void> load(String asset, double volume) => gate;

  @override
  Future<void> replay() async => played?.add('play');

  @override
  Future<void> dispose() async {}
}

class _FakeEngine implements ShortSoundEngine {
  final calls = <String>[];

  @override
  Future<void> prepare(String asset, double volume) async =>
      calls.add('prepare $asset');

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<void> resume() async => calls.add('resume');

  @override
  Future<void> dispose() async {}
}
