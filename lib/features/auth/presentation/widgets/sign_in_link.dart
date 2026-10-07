import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_strings.dart';

/// Route to the email form opened in sign-in mode, optionally carrying a
/// `/join/<code>` continuation through `from`.
String signInRoute({String? from}) => Uri(
  path: '/auth/email',
  queryParameters: {'mode': 'signin', 'from': ?from},
).toString();

/// Secondary "Sign in" action for guest cards, for a returning player who
/// already has an account (for example on a new phone).
class SignInLink extends StatelessWidget {
  const SignInLink({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Semantics(
        button: true,
        label: AppStrings.signInExistingAccount,
        excludeSemantics: true,
        onTap: onPressed,
        child: TextButton(
          key: const Key('sign_in_link'),
          onPressed: onPressed,
          style: TextButton.styleFrom(
            minimumSize: const Size.fromHeight(AppSizes.minTouchTarget),
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: AppSizes.md,
            ),
          ),
          child: const Text(AppStrings.signInLink, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}
