import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icos/core/backend/backend_config.dart';
import 'package:icos/core/backend/backend_providers.dart';
import 'package:icos/core/services/session_service.dart';
import 'package:icos/features/auth/data/native_sign_in.dart';
import 'package:icos/features/auth/domain/auth_strategy.dart';

import 'fake_auth_client.dart';

/// Backend config with both Google client ids set (native Google allowed).
final authTestConfig = BackendConfig(
  apiBaseUrl: 'https://fn.example.test',
  dataApiUrl: 'https://data.example.test/rest/v1',
  googleWebClientId: 'web-id',
  googleIosClientId: 'ios-id',
);

/// Backend config without Google client ids (Google falls back to web).
final authTestConfigNoGoogle = BackendConfig(
  apiBaseUrl: 'https://fn.example.test',
  dataApiUrl: 'https://data.example.test/rest/v1',
);

/// Native sheets that hand back fixed tokens and record what was asked.
class FakeNativeSignIn implements NativeSignIn {
  final calls = <String>[];

  /// Thrown instead of returning a token, when set.
  Object? error;

  /// Returned token; null makes the SDK "return no token".
  NativeIdToken? googleToken = const NativeIdToken(idToken: 'google-token');
  NativeIdToken? appleToken = const NativeIdToken(
    idToken: 'apple-token',
    nonce: 'raw-nonce',
  );

  @override
  Future<NativeIdToken?> google({
    required AuthPlatform platform,
    required String? webClientId,
    required String? iosClientId,
  }) async {
    calls.add('google');
    if (error != null) throw error!;
    return googleToken;
  }

  @override
  Future<NativeIdToken?> apple() async {
    calls.add('apple');
    if (error != null) throw error!;
    return appleToken;
  }
}

/// Session gateway backed by a [FakeAuthClient].
class FakeClientGateway implements SessionGateway {
  FakeClientGateway(this.client);
  final FakeAuthClient client;

  @override
  bool get hasSession => client.currentUser != null;

  @override
  Future<void> signInAnonymously() async {
    await client.signInAnonymously();
  }
}

/// Overrides wiring the real auth providers to [client] (and optional
/// [native] sheets and [config]).
List<Override> authClientOverrides(
  FakeAuthClient client, {
  NativeSignIn? native,
  BackendConfig? config,
}) => [
  backendConfigProvider.overrideWith((ref) => config ?? authTestConfigNoGoogle),
  authClientProvider.overrideWithValue(client),
  nativeSignInProvider.overrideWithValue(native ?? FakeNativeSignIn()),
  sessionEnsurerProvider.overrideWithValue(
    SessionEnsurer(gateway: FakeClientGateway(client)),
  ),
];
