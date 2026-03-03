import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'connectivity_service.g.dart';

@riverpod
Stream<bool> connectivity(Ref ref) {
  final connectivity = Connectivity();
  return connectivity.onConnectivityChanged.map((results) {
    return results.any(
      (r) => r != ConnectivityResult.none,
    );
  });
}

@riverpod
class ConnectivityNotifier extends _$ConnectivityNotifier {
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  @override
  bool build() {
    _subscription = Connectivity().onConnectivityChanged.listen((results) {
      state = results.any((r) => r != ConnectivityResult.none);
    });
    ref.onDispose(() => _subscription?.cancel());
    return true; // assume online initially
  }
}
