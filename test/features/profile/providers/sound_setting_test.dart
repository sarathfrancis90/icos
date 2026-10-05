import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/services/audio_service.dart';
import 'package:icos/core/services/storage_service.dart';
import 'package:icos/features/profile/providers/profile_provider.dart';

import '../../../helpers/storage_test_helpers.dart';

class _Sound implements SoundPlayer {
  _Sound(this.log);
  final List<String> log;

  @override
  Future<void> load(String asset, double volume) async => log.add('load');

  @override
  Future<void> replay() async => log.add('play');

  @override
  Future<void> dispose() async {}
}

void main() {
  late Directory dir;
  setUp(() async => dir = await initTestStorage());
  tearDown(() async => dir.delete(recursive: true));

  test('switching sound on in settings starts preparing the effects', () async {
    await StorageService.setSoundEnabled(false);
    final log = <String>[];
    final audio = AudioService.forTesting(
      playerFactory: (_) => _Sound(log),
      soundEnabled: () => StorageService.soundEnabled,
    );
    await audio.initialize(); // app start with sound off
    expect(log, isEmpty);

    await persistSoundSetting(true, audio: audio);
    await audio.ready;
    expect(StorageService.soundEnabled, isTrue);
    expect(log.where((c) => c == 'load'), hasLength(SoundEffect.values.length));

    await audio.play(SoundEffect.pathStep);
    expect(log, contains('play'), reason: 'the first sound is not dropped');
  });

  test('switching it off prepares nothing', () async {
    final log = <String>[];
    final audio = AudioService.forTesting(
      playerFactory: (_) => _Sound(log),
      soundEnabled: () => StorageService.soundEnabled,
    );
    await persistSoundSetting(false, audio: audio);
    expect(log, isEmpty);
  });
}
