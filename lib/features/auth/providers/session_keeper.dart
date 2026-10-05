import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;

import '../../../core/services/connectivity_service.dart';
import '../../../core/services/session_service.dart';
import 'auth_provider.dart';

part 'session_keeper.g.dart';

/// Keeps the app from staying session-less: re-creates the guest session when
/// connectivity returns and when the SDK reports the session was lost.
/// Instantiated once at app start. App resume and the sync queue call
/// [ensure] too.
@Riverpod(keepAlive: true)
class SessionKeeper extends _$SessionKeeper {
  @override
  void build() {
    ref.listen(connectivityNotifierProvider, (prev, next) {
      if (next && prev == false) ensure();
    });
    ref.listen(authStateChangesProvider, (prev, next) {
      if (next.valueOrNull?.event == AuthChangeEvent.signedOut) ensure();
    });
  }

  Future<bool> ensure() => ref.read(sessionEnsurerProvider).ensureSession();
}
