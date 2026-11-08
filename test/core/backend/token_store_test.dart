import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/backend/token_store.dart';
import 'package:icos/core/services/app_logger.dart';
import 'package:mocktail/mocktail.dart';

class _MockStorage extends Mock implements FlutterSecureStorage {}

void main() {
  late List<Map<String, Object?>> logged;

  setUp(() {
    logged = [];
    AppLogger.testSink = logged.add;
  });
  tearDown(() => AppLogger.testSink = null);

  test(
    'a failing keychain read means "nothing stored" and is logged',
    () async {
      final storage = _MockStorage();
      when(
        () => storage.read(key: any(named: 'key')),
      ).thenThrow(PlatformException(code: 'Unexpected', message: 'keychain'));
      final store = SecureTokenStore(storage);

      expect(await store.readSessionToken(), isNull);
      expect(await store.cachedJwt(), isNull);
      expect(await store.jwtExpiry(), isNull);
      expect(await store.readUserJson(), isNull);

      expect(logged, hasLength(4));
      expect(logged.first['level'], 'warn');
      expect(logged.first['message'], 'secure storage read failed');
      expect(logged.first['data'], {'key': 'icos.session_token'});
    },
  );

  test('a successful read returns the stored value', () async {
    final storage = _MockStorage();
    when(
      () => storage.read(key: any(named: 'key')),
    ).thenAnswer((_) async => 'tok');
    expect(await SecureTokenStore(storage).readSessionToken(), 'tok');
    expect(logged, isEmpty);
  });
}
