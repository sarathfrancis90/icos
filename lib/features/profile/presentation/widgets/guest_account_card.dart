import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';

/// Profile card nudging a guest to create an account.
class GuestAccountCard extends StatelessWidget {
  const GuestAccountCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.all(AppSizes.md),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.purpleGradientStart.withValues(alpha: 0.25),
            AppColors.purpleGradientEnd.withValues(alpha: 0.15),
          ],
        ),
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        border: Border.all(color: AppColors.purpleLight.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.person_outline_rounded,
                color: AppColors.purpleLight,
              ),
              const SizedBox(width: AppSizes.sm),
              Expanded(
                child: Text(
                  'Guest account',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.sm),
          Text(
            'Create an account to keep your progress across devices, join '
            'groups and never lose your streak. Guest data is removed after '
            '${AppSizes.anonymousPurgeDays} days of inactivity.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).brightness == Brightness.dark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSizes.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => context.push('/auth'),
              child: const Text('Create account'),
            ),
          ),
        ],
      ),
    );
  }
}
