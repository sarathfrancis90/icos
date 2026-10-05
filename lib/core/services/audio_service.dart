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

  /// Plays the loaded sound from the start.
  Future<void> play();

  Future<void> dispose();
}

/// [SoundPlayer] backed by audioplayers in low-latency mode.
class AudioplayersSound implements SoundPlayer {
  AudioplayersSound() : _player = AudioPlayer();

  final AudioPlayer _player;

  @override
  Future<void> load(String asset, double volume) async {
    await _player.setPlayerMode(PlayerMode.lowLatency);
    await _player.setReleaseMode(ReleaseMode.stop);
    await _player.setVolume(volume);
    await _player.setSource(AssetSource(asset));
  }

  @override
  Future<void> play() async {
    await _player.seek(Duration.zero);
    await _player.resume();
  }

  @override
  Future<void> dispose() => _player.dispose();
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
  bool _initialized = false;
  bool _loggedFailure = false;

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

  /// Pre-load all sound effects for instant playback.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    for (final effect in SoundEffect.values) {
      final player = _playerFactory(_assets[effect]!);
      try {
        await player.load(_assets[effect]!, _volumes[effect] ?? 0.3);
        _players[effect] = player;
      } catch (e) {
        _logOnce('sound could not be loaded', e);
        try {
          await player.dispose();
        } catch (_) {}
      }
    }
  }

  /// Play a sound effect if sound is enabled and it loaded.
  Future<void> play(SoundEffect effect) async {
    if (!_soundEnabled()) return;
    final player = _players[effect];
    if (player == null) return;
    try {
      await player.play();
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
    _initialized = false;
  }
}
