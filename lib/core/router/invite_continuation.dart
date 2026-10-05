import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Set to an invite code when an account was just created or signed in while
/// an invite was pending; the router turns it into `/join/<code>`.
class InviteContinuation extends Notifier<String?> {
  @override
  String? build() => null;

  void offer(String code) => state = code;

  void clear() => state = null;
}

final inviteContinuationProvider =
    NotifierProvider<InviteContinuation, String?>(InviteContinuation.new);

/// Navigates [router] to `/join/<code>` whenever [inviteContinuationProvider]
/// is set (once per offer).
void wireInviteContinuation(Ref ref, GoRouter router) {
  ref.listen<String?>(inviteContinuationProvider, (_, code) {
    if (code == null) return;
    ref.read(inviteContinuationProvider.notifier).clear();
    router.go('/join/$code');
  });
}
