import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_strings.dart';
import 'group_ui.dart';

/// Gate shown to anonymous users on social features. The primary CTA routes
/// to `/auth` where the guest session is upgraded to a full account.
class AccountRequiredCard extends StatelessWidget {
  const AccountRequiredCard({
    this.message =
        'Groups are tied to an account so your friends can find you. '
        'Create a free account to create or join groups — your streak and '
        'stats come with you.',
    this.onCreateAccount,
    super.key,
  });

  static const ctaLabel = 'Create an account';

  final String message;

  /// Defaults to navigating to `/auth`.
  final VoidCallback? onCreateAccount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = GroupSurface.of(context);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Container(
          padding: const EdgeInsetsDirectional.all(AppSizes.lg),
          decoration: surface.decoration(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      AppColors.purpleLight.withValues(alpha: 0.2),
                      AppColors.purpleDeep.withValues(alpha: 0.03),
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.lock_person_rounded,
                  size: 36,
                  color: AppColors.purpleLight,
                ),
              ),
              const SizedBox(height: AppSizes.md),
              Text(
                AppStrings.accountRequired,
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSizes.sm),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: secondaryTextColor(context),
                ),
              ),
              const SizedBox(height: AppSizes.lg),
              SizedBox(
                width: double.infinity,
                height: AppSizes.minTouchTarget + 4,
                child: Semantics(
                  button: true,
                  label: ctaLabel,
                  child: FilledButton.icon(
                    key: const Key('account_required_cta'),
                    onPressed: onCreateAccount ?? () => context.push('/auth'),
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: const Text(ctaLabel),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
