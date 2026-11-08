import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'api_client.dart';
import 'auth_client.dart';
import 'backend_config.dart';
import 'data_api.dart';
import 'token_store.dart';

part 'backend_providers.g.dart';

/// Backend hosts for this launch. `main()` must await
/// `container.read(backendConfigProvider.future)` before anything reads the
/// providers below (they use `requireValue`).
@Riverpod(keepAlive: true)
Future<BackendConfig> backendConfig(Ref ref) => BackendConfig.load();

/// Shared HTTP client for the backend layer.
@Riverpod(keepAlive: true)
http.Client backendHttpClient(Ref ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
}

@Riverpod(keepAlive: true)
TokenStore tokenStore(Ref ref) => SecureTokenStore();

@Riverpod(keepAlive: true)
AuthClient authClient(Ref ref) {
  final client = AuthClient(
    ref.watch(backendHttpClientProvider),
    ref.watch(backendConfigProvider).requireValue,
    ref.watch(tokenStoreProvider),
  );
  ref.onDispose(client.dispose);
  return client;
}

@Riverpod(keepAlive: true)
DataApi dataApi(Ref ref) {
  final api = DataApi(
    ref.watch(backendConfigProvider).requireValue,
    ref.watch(authClientProvider),
    httpClient: ref.watch(backendHttpClientProvider),
  );
  // DataApi.dispose closes the shared client too; only release the isolate.
  ref.onDispose(api.client.dispose);
  return api;
}

@Riverpod(keepAlive: true)
ApiClient apiClient(Ref ref) => ApiClient(
  ref.watch(backendHttpClientProvider),
  ref.watch(backendConfigProvider).requireValue,
  ref.watch(tokenStoreProvider),
);
