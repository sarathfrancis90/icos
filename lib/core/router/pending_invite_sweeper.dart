import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../features/groups/domain/pending_invite.dart';

/// Clears a stored invite that has outlived the visit it was saved for.
///
/// On app start only an invite older than [PendingInvite.startKeepFor] goes
/// (a cold start from the auth callback must still find its invite); on
/// resume the route rule below applies.
///
/// The invite bridges the detour through sign-up (browser or email link). On
/// app start and on every resume it is dropped unless the player is on the
/// join screen for that code or on an auth screen opened from it, so an invite
/// left behind (app killed, back at the root of a cold-start link, `go()`
/// elsewhere) cannot turn a later sign-in into a surprise join.
class PendingInviteSweeper extends StatefulWidget {
  const PendingInviteSweeper({
    required this.router,
    required this.child,
    super.key,
  });

  final GoRouter router;
  final Widget child;

  @override
  State<PendingInviteSweeper> createState() => _PendingInviteSweeperState();
}

class _PendingInviteSweeperState extends State<PendingInviteSweeper>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) PendingInvite.clearStaleOnStart();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _sweep();
  }

  void _sweep() {
    if (!mounted) return;
    final config = widget.router.routerDelegate.currentConfiguration;
    // A pushed route (the auth screen opened from the join screen) carries its
    // own full location; `config.uri` stays that of the base route.
    final top = config.isEmpty ? null : config.last;
    final configured = top is ImperativeRouteMatch
        ? top.matches.uri
        : config.uri;
    // Before the first route is parsed the configuration is empty; the
    // route information provider already holds the launch location.
    final location = configured.path.isEmpty
        ? widget.router.routeInformationProvider.value.uri
        : configured;
    PendingInvite.clearUnlessActive(location);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
