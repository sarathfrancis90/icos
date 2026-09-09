import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'connectivity_service.g.dart';

bool _isOnline(List<ConnectivityResult> results) =>
    results.any((r) => r != ConnectivityResult.none);

@riverpod
Stream<bool> connectivity(Ref ref) {
  final connectivity = Connectivity();
  return connectivity.onConnectivityChanged.map(_isOnline);
}

/// `true` while the device reports any network interface. Assumes online
/// until the first platform callback so the UI never flashes an offline
/// banner at cold start. Override in tests / the offline banner.
@Riverpod(keepAlive: true)
class ConnectivityNotifier extends _$ConnectivityNotifier {
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  @override
  bool build() {
    final connectivity = Connectivity();
    _subscription = connectivity.onConnectivityChanged.listen((results) {
      state = _isOnline(results);
    });
    connectivity.checkConnectivity().then(
          (results) => state = _isOnline(results),
          onError: (Object _) {},
        );
    ref.onDispose(() => _subscription?.cancel());
    return true;
  }
}
