import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../providers/auth_provider.dart';

/// Shows one-shot messages from [authFlowMessageProvider] (deep-link
/// callbacks etc.) as SnackBars, and turns an identity conflict reported by
/// the deep-link flow into the same "sign in instead" dialog the synchronous
/// flows get. Call from `build`.
void listenForAuthFlowMessages(BuildContext context, WidgetRef ref) {
  ref.listen<String?>(authFlowMessageProvider, (_, message) {
    if (message == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
    ref.read(authFlowMessageProvider.notifier).clear();
  });

  ref.listen<OAuthKind?>(authIdentityConflictProvider, (previous, provider) {
    // The provider may legitimately be null (we could not tell which one it
    // was), so fire on any transition into a set state.
    if (previous == provider) return;
    final conflict = ref.read(authIdentityConflictProvider);
    if (previous != null && conflict == null) return;
    ref.read(authIdentityConflictProvider.notifier).clear();
    unawaited(_offerExistingAccount(
      context,
      ref,
      email: null,
      password: null,
      provider: provider,
    ));
  });
}

/// Common handling for [AuthOutcome]s. Returns true when the flow finished
/// (navigated away), false when the user should stay on the screen.
Future<bool> handleAuthOutcome(
  BuildContext context,
  WidgetRef ref,
  AuthOutcome outcome, {
  String? emailForExisting,
  String? passwordForExisting,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  switch (outcome) {
    case AuthSuccess(:final isNewAccount):
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            isNewAccount
                ? 'Account created. Your progress is saved.'
                : 'Signed in.',
          ),
        ),
      );
      context.go('/');
      return true;

    case AuthRedirected():
      // The browser is open; the deep link will finish the flow.
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Continue in your browser to finish signing in.'),
        ),
      );
      return false;

    case AuthEmailConfirmationRequired(:final email, :final fromSignUp):
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Check your inbox'),
          content: Text(
            'We sent a confirmation link to $email. Open it to finish '
            'creating your account. Your progress stays on this device '
            'in the meantime.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                ref
                    .read(authNotifierProvider.notifier)
                    .resendConfirmation(email, fromSignUp: fromSignUp);
                Navigator.of(context).pop();
              },
              child: const Text('Resend'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (context.mounted) context.go('/');
      return true;

    case AuthIdentityExists(:final email, :final provider):
      return _offerExistingAccount(
        context,
        ref,
        email: email ?? emailForExisting,
        password: passwordForExisting,
        provider: provider,
      );

    case AuthCancelled():
      return false;

    case AuthFailure(:final message):
      messenger.showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.error,
        ),
      );
      return false;
  }
}

Future<bool> _offerExistingAccount(
  BuildContext context,
  WidgetRef ref, {
  required String? email,
  required String? password,
  required OAuthKind? provider,
}) async {
  final label = email ??
      switch (provider) {
        OAuthKind.google => 'that Google account',
        OAuthKind.apple => 'that Apple account',
        null => 'that account',
      };
  final proceed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Account already exists'),
      content: Text(
        'An account for $label already exists.\n\n'
        'You can sign in to it instead, but your guest progress on this '
        'device (streak, solves) will NOT be carried over.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Sign in anyway'),
        ),
      ],
    ),
  );
  if (proceed != true || !context.mounted) return false;

  final notifier = ref.read(authNotifierProvider.notifier);
  final AuthOutcome outcome;
  if (provider != null) {
    outcome = await notifier.signInToExistingWithOAuth(provider);
  } else if (email != null && password != null) {
    outcome = await notifier.signInWithEmail(email, password);
  } else {
    // Email known but no password: bounce to the sign-in form.
    if (context.mounted) context.push('/auth/email?mode=signin');
    return false;
  }
  if (!context.mounted) return false;
  return handleAuthOutcome(context, ref, outcome);
}
