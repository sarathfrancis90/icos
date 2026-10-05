import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_sizes.dart';

/// Leaves the current screen: pops when there is somewhere to go back to,
/// otherwise (a deep link replaced the stack) goes to [fallback].
void leaveScreen(BuildContext context, String fallback) {
  final navigator = Navigator.of(context);
  if (navigator.canPop()) {
    navigator.pop();
  } else {
    GoRouter.of(context).go(fallback);
  }
}

/// `AppBar.leading` for screens reachable by deep link.
///
/// Returns `null` (so the AppBar shows its normal back button) when the
/// screen sits on top of another route. When the stack holds only this
/// screen there is nothing to pop, so a close control that goes to
/// [fallback] is offered instead; [label] names the destination for screen
/// readers.
Widget? deepLinkLeading(
  BuildContext context, {
  required String fallback,
  required String label,
  VoidCallback? onExit,
}) {
  if (Navigator.of(context).canPop()) return null;
  return IconButton(
    key: const Key('deep_link_exit'),
    icon: const Icon(Icons.close_rounded),
    tooltip: label,
    constraints: const BoxConstraints(
      minWidth: AppSizes.minTouchTarget,
      minHeight: AppSizes.minTouchTarget,
    ),
    onPressed: () {
      onExit?.call();
      GoRouter.of(context).go(fallback);
    },
  );
}
