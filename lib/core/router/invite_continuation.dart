import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// How the join screen was reached, passed as the route's `extra`.
enum JoinEntry {
  /// A link or an in-app path the player chose: join straight away.
  link,

  /// A stored invite resumed after sign-in: the player may have changed their
  /// mind, so the screen asks before joining.
  resumedInvite,
}

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
  void go(String code) {
    ref.read(inviteContinuationProvider.notifier).clear();
    router.go('/join/$code', extra: JoinEntry.resumedInvite);
  }

  ref.listen<String?>(inviteContinuationProvider, (_, code) {
    if (code != null) go(code);
  });
  // An offer made before the router existed (the linked event of a cold start
  // from the auth callback) is not replayed by `listen`: take it now.
  final waiting = ref.read(inviteContinuationProvider);
  // (Providers may not modify other providers while building: defer.)
  if (waiting != null) Future.microtask(() => go(waiting));
}
