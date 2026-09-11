import 'package:audioplayers/audioplayers.dart';

import '../services/storage_service.dart';

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

/// Manages sound effects for game interactions.
///
/// Respects [StorageService.soundEnabled] setting.
/// Pre-loads all sounds on [initialize] for zero-latency playback.
class AudioService {
  AudioService._();
  static final instance = AudioService._();

  final Map<SoundEffect, AudioPlayer> _players = {};
  bool _initialized = false;

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

  /// Asset paths for each sound effect.
  static const _assets = {
    SoundEffect.pathStep: 'sounds/path_step.ogg',
    SoundEffect.waypointReached: 'sounds/chomp.ogg',
    SoundEffect.hintReveal: 'sounds/hint.ogg',
    SoundEffect.completion: 'sounds/victory.ogg',
    SoundEffect.buttonTap: 'sounds/button_tap.ogg',
    SoundEffect.undo: 'sounds/undo.ogg',
    SoundEffect.invalidMove: 'sounds/invalid_move.ogg',
  };

  /// Pre-load all sound effects for instant playback.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    for (final effect in SoundEffect.values) {
      final player = AudioPlayer();
      player.setReleaseMode(ReleaseMode.stop);
      _players[effect] = player;
    }
  }

  /// Play a sound effect if sound is enabled and assets exist.
  Future<void> play(SoundEffect effect) async {
    if (!_soundEnabled) return;
    if (!_initialized) return;

    final player = _players[effect];
    if (player == null) return;

    final volume = _volumes[effect] ?? 0.3;
    final asset = _assets[effect];
    if (asset == null) return;

    try {
      await player.setVolume(volume);
      await player.play(AssetSource(asset));
    } catch (_) {
      // Silently fail — missing sound files shouldn't crash the app
    }
  }

  bool get _soundEnabled {
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
