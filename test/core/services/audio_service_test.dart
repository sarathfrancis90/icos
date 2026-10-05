import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
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
      reason:
          'a failed source is not retried on every move (retries are spaced)',
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

  group('effect players (the audioplayers engine)', () {
    test('are created with position updates disabled', () async {
      final fake = _FakeEffectPlayer();
      final engine = AudioplayersEngine(playerFactory: () => fake);
      expect(
        fake.calls.first,
        'disablePositionUpdates',
        reason:
            'SoundPool never reports completion on Android, so a position '
            'updater would poll the platform every frame after each sound',
      );
      await engine.prepare('sounds/a.wav', 0.3);
      expect(
        fake.calls.where((c) => c == 'disablePositionUpdates'),
        hasLength(1),
      );
    });

    test(
      'are configured in order, and set no audio context themselves',
      () async {
        final fake = _FakeEffectPlayer();
        final engine = AudioplayersEngine(playerFactory: () => fake);
        await engine.prepare('sounds/a.wav', 0.3);
        expect(fake.calls, [
          'disablePositionUpdates',
          'setPlayerMode PlayerMode.lowLatency',
          'setReleaseMode ReleaseMode.stop',
          'setVolume 0.3',
          'setSource sounds/a.wav',
        ]);
      },
    );
  });

  group('audio context', () {
    test('is applied once, globally, for the service lifetime', () async {
      final applied = <AudioContext>[];
      final audio = AudioService.forTesting(
        playerFactory: (asset) => _FakeSound(asset, calls),
        soundEnabled: () => true,
        applyAudioContext: (c) async => applied.add(c),
      );
      await audio.initialize();
      await audio.ready;
      for (var i = 0; i < 20; i++) {
        await audio.play(SoundEffect.pathStep);
      }
      await audio.dispose();
      await audio.initialize();
      await audio.ready;
      expect(applied, hasLength(1));
      expect(calls.indexOf('load sounds/path_step.wav'), greaterThan(-1));
    });

    test('Android: game / sonification, no audio focus, nothing forced', () {
      final a = AudioService.effectContext().android;
      expect(a.audioFocus, AndroidAudioFocus.none);
      expect(a.usageType, AndroidUsageType.game);
      expect(a.contentType, AndroidContentType.sonification);
      expect(a.isSpeakerphoneOn, isFalse);
      expect(a.audioMode, AndroidAudioMode.normal);
      expect(a.stayAwake, isFalse);
    });

    test('iOS: ambient with no options (mixes, follows the silent switch)', () {
      final i = AudioService.effectContext().iOS;
      expect(i.category, AVAudioSessionCategory.ambient);
      expect(i.options, isEmpty);
    });
  });

  group('turning sound on', () {
    test(
      'starts preparing at once, so the first sound is not dropped',
      () async {
        enabled = false;
        final audio = service();
        await audio.initialize(); // app start with sound off
        expect(calls, isEmpty);

        enabled = true;
        audio.soundSettingChanged();
        await audio.ready;
        expect(
          calls.where((c) => c.startsWith('load')),
          hasLength(SoundEffect.values.length),
        );

        await audio.play(SoundEffect.pathStep);
        expect(calls.where((c) => c.startsWith('play')), hasLength(1));
      },
    );

    test(
      'does nothing while the setting is still off, and is idempotent',
      () async {
        enabled = false;
        final audio = service();
        await audio.initialize();
        audio.soundSettingChanged();
        expect(calls, isEmpty);

        enabled = true;
        audio.soundSettingChanged();
        audio.soundSettingChanged();
        await audio.ready;
        expect(
          calls.where((c) => c.startsWith('load')),
          hasLength(SoundEffect.values.length),
          reason: 'one preparation, however often the switch is flipped',
        );
      },
    );
  });

  group('a sound that timed out while preparing', () {
    test(
      'is prepared again on a later play instead of staying silent',
      () async {
        var now = DateTime(2026, 10, 5, 12);
        var failFirst = true;
        final log = <String>[];
        final audio = AudioService.forTesting(
          playerFactory: (asset) {
            final hang = failFirst;
            return _FlakySound(asset, log, hang: () => hang);
          },
          soundEnabled: () => true,
          now: () => now,
          prepareTimeout: const Duration(milliseconds: 20),
        );
        await audio.initialize();
        await audio.ready;
        expect(log.where((c) => c.startsWith('play')), isEmpty);
        await audio.play(SoundEffect.pathStep); // not ready: dropped
        expect(log.where((c) => c.startsWith('play')), isEmpty);

        failFirst = false;
        // Too soon after the failure: no retry storm.
        await audio.play(SoundEffect.pathStep);
        await audio.ready;
        expect(log.where((c) => c.startsWith('loaded')), isEmpty);

        now = now.add(const Duration(seconds: 30));
        await audio.play(SoundEffect.pathStep); // triggers the retry
        await audio.ready;
        await audio.play(SoundEffect.pathStep);
        expect(log.where((c) => c.startsWith('play')), hasLength(1));
      },
    );

    test('gives up after a few attempts', () async {
      var now = DateTime(2026, 10, 5, 12);
      final log = <String>[];
      final audio = AudioService.forTesting(
        playerFactory: (asset) => _FlakySound(asset, log, hang: () => true),
        soundEnabled: () => true,
        now: () => now,
        prepareTimeout: const Duration(milliseconds: 5),
      );
      await audio.initialize();
      await audio.ready;
      for (var i = 0; i < 10; i++) {
        now = now.add(const Duration(minutes: 1));
        await audio.play(SoundEffect.pathStep);
        await audio.ready;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      // 1 initial + at most 2 retries of that effect's load.
      expect(
        log.where((c) => c == 'load sounds/path_step.wav'),
        hasLength(lessThanOrEqualTo(3)),
      );
    });
  });

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

class _FlakySound implements SoundPlayer {
  _FlakySound(this.asset, this.log, {required this.hang});

  final String asset;
  final List<String> log;
  final bool Function() hang;

  @override
  Future<void> load(String asset, double volume) async {
    log.add('load $asset');
    if (hang()) await Completer<void>().future; // never finishes
    log.add('loaded $asset');
  }

  @override
  Future<void> replay() async => log.add('play $asset');

  @override
  Future<void> dispose() async {}
}

class _FakeEffectPlayer implements EffectPlayer {
  final calls = <String>[];

  @override
  void disablePositionUpdates() => calls.add('disablePositionUpdates');

  @override
  @override
  Future<void> setPlayerMode(PlayerMode mode) async =>
      calls.add('setPlayerMode $mode');

  @override
  Future<void> setReleaseMode(ReleaseMode mode) async =>
      calls.add('setReleaseMode $mode');

  @override
  Future<void> setVolume(double volume) async => calls.add('setVolume $volume');

  @override
  Future<void> setSource(String asset) async => calls.add('setSource $asset');

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<void> resume() async => calls.add('resume');

  @override
  Future<void> dispose() async => calls.add('dispose');
}
