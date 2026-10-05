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

/// The slice of audioplayers' `AudioPlayer` that [AudioplayersEngine] uses,
/// so the configuration it applies can be tested without a platform engine.
abstract interface class EffectPlayer {
  /// Stops the per-frame position polling audioplayers starts by default.
  void disablePositionUpdates();
  Future<void> setAudioContext(AudioContext context);
  Future<void> setPlayerMode(PlayerMode mode);
  Future<void> setReleaseMode(ReleaseMode mode);
  Future<void> setVolume(double volume);
  Future<void> setSource(String asset);
  Future<void> stop();
  Future<void> resume();
  Future<void> dispose();
}

class _AudioPlayerEffect implements EffectPlayer {
  _AudioPlayerEffect() : _player = AudioPlayer();

  final AudioPlayer _player;

  @override
  void disablePositionUpdates() => _player.positionUpdater = null;

  @override
  Future<void> setAudioContext(AudioContext context) =>
      _player.setAudioContext(context);

  @override
  Future<void> setPlayerMode(PlayerMode mode) => _player.setPlayerMode(mode);

  @override
  Future<void> setReleaseMode(ReleaseMode mode) => _player.setReleaseMode(mode);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> setSource(String asset) => _player.setSource(AssetSource(asset));

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> resume() => _player.resume();

  @override
  Future<void> dispose() => _player.dispose();
}

/// [ShortSoundEngine] backed by audioplayers in low-latency mode.
class AudioplayersEngine implements ShortSoundEngine {
  AudioplayersEngine({EffectPlayer Function()? playerFactory})
    : _player = (playerFactory ?? _AudioPlayerEffect.new)()
        // Effects never need position updates, and on Android a SoundPool
        // player never reports completion, so the default updater would keep
        // scheduling a frame callback and a platform call after every sound.
        ..disablePositionUpdates();

  final EffectPlayer _player;

  /// How effects take part in the device's audio: mixed with whatever else is
  /// playing, never holding audio focus.
  ///
  /// audioplayers' default context requests AUDIOFOCUS_GAIN before each play
  /// and abandons it after each stop on Android. That pauses other apps' music
  /// on every move, and a refused request is ignored by the plugin
  /// (WrappedPlayer / FocusManager.handleFocusResult has no branch for
  /// AUDIOFOCUS_REQUEST_FAILED), so the sound is silently dropped. iOS gets
  /// the playback category with `mixWithOthers` for the same reason.
  static AudioContext effectContext() => AudioContext(
    android: const AudioContextAndroid(
      usageType: AndroidUsageType.game,
      contentType: AndroidContentType.sonification,
      audioFocus: AndroidAudioFocus.none,
    ),
    iOS: AudioContextIOS(
      category: AVAudioSessionCategory.playback,
      options: const {AVAudioSessionOptions.mixWithOthers},
    ),
  );

  @override
  Future<void> prepare(String asset, double volume) async {
    // The context first: it is read when the platform player is created.
    await _player.setAudioContext(effectContext());
    await _player.setPlayerMode(PlayerMode.lowLatency);
    await _player.setReleaseMode(ReleaseMode.stop);
    await _player.setVolume(volume);
    await _player.setSource(asset);
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
      _soundEnabled = _storageSoundEnabled,
      _now = DateTime.now,
      _prepareTimeout = const Duration(seconds: 15);

  /// A service with an injected player and settings, for tests.
  AudioService.forTesting({
    required SoundPlayer Function(String asset) playerFactory,
    required bool Function() soundEnabled,
    DateTime Function()? now,
    Duration prepareTimeout = const Duration(seconds: 15),
  }) : _playerFactory = playerFactory,
       _soundEnabled = soundEnabled,
       _now = now ?? DateTime.now,
       _prepareTimeout = prepareTimeout;

  static final instance = AudioService._();

  final SoundPlayer Function(String asset) _playerFactory;
  final bool Function() _soundEnabled;
  final DateTime Function() _now;
  final Duration _prepareTimeout;

  /// A sound that failed to prepare (a slow first start can outlast the
  /// timeout) is tried again on a later play: at most this many attempts, no
  /// closer together than [_retryAfter].
  static const _maxPrepareAttempts = 3;
  static const _retryAfter = Duration(seconds: 10);
  final Map<SoundEffect, int> _attempts = {};
  final Map<SoundEffect, DateTime> _lastAttempt = {};
  final Set<SoundEffect> _inFlight = {};

  /// Effects that loaded and can be played.
  final Map<SoundEffect, SoundPlayer> _players = {};
  bool _started = false;
  bool _deferred = false;
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
  /// the sound setting is off (preparation then starts when it is switched on).
  Future<void> initialize() async {
    if (_started) return;
    if (!_soundEnabled()) {
      // Prepared when the setting is switched on (see [soundSettingChanged]),
      // or at the latest on the first play after that.
      _deferred = true;
      return;
    }
    _started = true;
    _preparing = _prepareAll();
  }

  /// Call after the sound setting changed: switching it on starts preparing
  /// right away, so the first sound after the switch is not the one that is
  /// dropped while the effects load.
  void soundSettingChanged() {
    if (_soundEnabled() && !_started) {
      _deferred = false;
      unawaited(initialize());
    }
  }

  Future<void> _prepareAll() async {
    await Future.wait([
      for (final effect in SoundEffect.values) _prepare(effect),
    ]);
  }

  Future<void> _prepare(SoundEffect effect) async {
    if (!_inFlight.add(effect)) return;
    _attempts[effect] = (_attempts[effect] ?? 0) + 1;
    _lastAttempt[effect] = _now();
    final asset = _assets[effect]!;
    SoundPlayer? player;
    try {
      player = _playerFactory(asset);
      await player
          .load(asset, _volumes[effect] ?? 0.3)
          .timeout(_prepareTimeout);
      _players[effect] = player;
    } catch (e) {
      _logOnce('sound could not be loaded', e);
      try {
        await player?.dispose();
      } catch (_) {}
    } finally {
      _inFlight.remove(effect);
    }
  }

  /// Tries a failed effect again, when it is due.
  void _retryIfDue(SoundEffect effect) {
    if (_inFlight.contains(effect)) return;
    if ((_attempts[effect] ?? 0) >= _maxPrepareAttempts) return;
    final last = _lastAttempt[effect];
    if (last != null && _now().difference(last) < _retryAfter) return;
    _preparing = _prepare(effect);
  }

  /// Play a sound effect if sound is enabled and it is ready. A request that
  /// arrives before preparation has finished is silently dropped (never
  /// queued).
  Future<void> play(SoundEffect effect) async {
    if (!_soundEnabled()) return;
    if (!_started) {
      if (_deferred) {
        _deferred = false;
        unawaited(initialize());
      }
      return;
    }
    final player = _players[effect];
    if (player == null) {
      _retryIfDue(effect);
      return;
    }
    try {
      await player.replay();
    } catch (e) {
      _logOnce('sound playback failed', e);
    }
  }

  void _logOnce(String message, Object error) {
    if (_loggedFailure) return;
    _loggedFailure = true;
    AppLogger.debug(
      '$message (further sound errors are not logged)',
      error: error,
    );
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
    _attempts.clear();
    _lastAttempt.clear();
    _started = false;
    _preparing = null;
  }
}
