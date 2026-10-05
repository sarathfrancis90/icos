import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import 'app_logger.dart';
import 'storage_service.dart';

/// Sound effect identifiers.
enum SoundEffect {
  pathStep,
  waypointReached,
  hintReveal,
  completion,
  buttonTap,
  undo,
  invalidMove,
}

/// One preloaded short sound. Abstracted so [AudioService] can be tested
/// without a platform audio engine.
abstract interface class SoundPlayer {
  /// Loads [asset] (a path under `assets/`) once, at [volume].
  Future<void> load(String asset, double volume);

  /// Plays the loaded sound from the start (restarting it if still playing).
  Future<void> replay();

  Future<void> dispose();
}

/// The few engine calls a short sound needs. Deliberately has no `seek`: on
/// Android a low-latency (SoundPool) player never reports seek completion, so
/// `AudioPlayer.seek` would wait out its 30 s timeout and the sound would
/// never play.
abstract interface class ShortSoundEngine {
  Future<void> prepare(String asset, double volume);
  Future<void> stop();
  Future<void> resume();
  Future<void> dispose();
}

/// [ShortSoundEngine] backed by audioplayers in low-latency mode.
class AudioplayersEngine implements ShortSoundEngine {
  AudioplayersEngine() : _player = AudioPlayer();

  final AudioPlayer _player;

  @override
  Future<void> prepare(String asset, double volume) async {
    await _player.setPlayerMode(PlayerMode.lowLatency);
    await _player.setReleaseMode(ReleaseMode.stop);
    await _player.setVolume(volume);
    await _player.setSource(AssetSource(asset));
  }

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> resume() => _player.resume();

  @override
  Future<void> dispose() => _player.dispose();
}

/// [SoundPlayer] over a [ShortSoundEngine]: replays by `stop()` then
/// `resume()`, which restarts a short source from the start on iOS and
/// Android without seeking.
class AudioplayersSound implements SoundPlayer {
  AudioplayersSound([ShortSoundEngine? engine])
    : _engine = engine ?? AudioplayersEngine();

  final ShortSoundEngine _engine;

  @override
  Future<void> load(String asset, double volume) =>
      _engine.prepare(asset, volume);

  @override
  Future<void> replay() async {
    await _engine.stop();
    await _engine.resume();
  }

  @override
  Future<void> dispose() => _engine.dispose();
}

/// Manages sound effects for game interactions.
///
/// Respects [StorageService.soundEnabled]. Each effect is loaded once on
/// [initialize] and reused for every play. Sound is a nicety: a sound that
/// fails to load or play is skipped silently (one debug log per session, never
/// one per move).
class AudioService {
  AudioService._()
    : _playerFactory = ((_) => AudioplayersSound()),
      _soundEnabled = _storageSoundEnabled;

  /// A service with an injected player and settings, for tests.
  AudioService.forTesting({
    required SoundPlayer Function(String asset) playerFactory,
    required bool Function() soundEnabled,
  }) : _playerFactory = playerFactory,
       _soundEnabled = soundEnabled;

  static final instance = AudioService._();

  final SoundPlayer Function(String asset) _playerFactory;
  final bool Function() _soundEnabled;

  /// Effects that loaded and can be played.
  final Map<SoundEffect, SoundPlayer> _players = {};
  bool _started = false;
  bool _loggedFailure = false;
  Future<void>? _preparing;

  /// Completes when background preparation has finished (for tests).
  Future<void> get ready => _preparing ?? Future<void>.value();

  /// Sound configuration: volume levels per effect.
  static const _volumes = {
    SoundEffect.pathStep: 0.3,
    SoundEffect.waypointReached: 0.5,
    SoundEffect.hintReveal: 0.4,
    SoundEffect.completion: 0.6,
    SoundEffect.buttonTap: 0.2,
    SoundEffect.undo: 0.25,
    SoundEffect.invalidMove: 0.35,
  };

  /// Asset paths (relative to `assets/`) for each sound effect. WAV, because
  /// iOS's AVPlayer cannot decode Ogg Vorbis.
  static const _assets = {
    SoundEffect.pathStep: 'sounds/path_step.wav',
    SoundEffect.waypointReached: 'sounds/chomp.wav',
    SoundEffect.hintReveal: 'sounds/hint.wav',
    SoundEffect.completion: 'sounds/victory.wav',
    SoundEffect.buttonTap: 'sounds/button_tap.wav',
    SoundEffect.undo: 'sounds/undo.wav',
    SoundEffect.invalidMove: 'sounds/invalid_move.wav',
  };

  /// All sound asset paths, relative to `assets/`.
  static Iterable<String> get assetPaths => _assets.values;

  /// Starts preparing the sound effects in the background and returns
  /// immediately; never throws and never blocks startup. Does nothing while
  /// the sound setting is off (preparation then happens on the first play
  /// after it is switched on).
  Future<void> initialize() async {
    if (_started || !_soundEnabled()) return;
    _started = true;
    _preparing = _prepareAll();
  }

  Future<void> _prepareAll() async {
    await Future.wait([
      for (final effect in SoundEffect.values) _prepare(effect),
    ]);
  }

  Future<void> _prepare(SoundEffect effect) async {
    final asset = _assets[effect]!;
    SoundPlayer? player;
    try {
      player = _playerFactory(asset);
      await player
          .load(asset, _volumes[effect] ?? 0.3)
          .timeout(const Duration(seconds: 5));
      _players[effect] = player;
    } catch (e) {
      _logOnce('sound could not be loaded', e);
      try {
        await player?.dispose();
      } catch (_) {}
    }
  }

  /// Play a sound effect if sound is enabled and it is ready. A request that
  /// arrives before preparation has finished is silently dropped (never
  /// queued).
  Future<void> play(SoundEffect effect) async {
    if (!_soundEnabled()) return;
    if (!_started) {
      unawaited(initialize());
      return;
    }
    final player = _players[effect];
    if (player == null) return;
    try {
      await player.replay();
    } catch (e) {
      _logOnce('sound playback failed', e);
    }
  }

  void _logOnce(String message, Object error) {
    if (_loggedFailure) return;
    _loggedFailure = true;
    AppLogger.debug('$message (further sound errors are not logged)',
        error: error);
  }

  static bool _storageSoundEnabled() {
    try {
      return StorageService.soundEnabled;
    } catch (_) {
      return false;
    }
  }

  /// Dispose all players.
  Future<void> dispose() async {
    for (final player in _players.values) {
      await player.dispose();
    }
    _players.clear();
    _started = false;
    _preparing = null;
  }
}
