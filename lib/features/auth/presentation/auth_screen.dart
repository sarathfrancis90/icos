import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../providers/auth_provider.dart';

class AuthScreen extends ConsumerWidget {
  const AuthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsetsDirectional.all(AppSizes.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              // Logo/Title
              const Icon(
                Icons.route_rounded,
                size: 80,
                color: AppColors.electricBlue,
              ),
              const SizedBox(height: AppSizes.md),
              Text(
                AppStrings.appName,
                style: Theme.of(context).textTheme.displayLarge,
              ),
              const SizedBox(height: AppSizes.xs),
              Text(
                AppStrings.appTagline,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.6),
                    ),
              ),
              const Spacer(),

              if (authState.isLoading)
                const CircularProgressIndicator()
              else ...[
                // Sign in options
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      ref
                          .read(authNotifierProvider.notifier)
                          .signInWithGoogle();
                    },
                    icon: const Icon(Icons.g_mobiledata_rounded),
                    label: const Text(AppStrings.signInWithGoogle),
                  ),
                ),
                const SizedBox(height: AppSizes.sm),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      ref
                          .read(authNotifierProvider.notifier)
                          .signInWithApple();
                    },
                    icon: const Icon(Icons.apple_rounded),
                    label: const Text(AppStrings.signInWithApple),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          Theme.of(context).brightness == Brightness.dark
                              ? Colors.white
                              : Colors.black,
                      foregroundColor:
                          Theme.of(context).brightness == Brightness.dark
                              ? Colors.black
                              : Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: AppSizes.sm),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      // TODO: email sign in
                    },
                    icon: const Icon(Icons.email_outlined),
                    label: const Text(AppStrings.signInWithEmail),
                  ),
                ),
                const SizedBox(height: AppSizes.lg),
                TextButton(
                  onPressed: () {
                    ref
                        .read(authNotifierProvider.notifier)
                        .signInAnonymously();
                    context.go('/');
                  },
                  child: Text(
                    AppStrings.continueAsGuest,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.6),
                        ),
                  ),
                ),
              ],
              const SizedBox(height: AppSizes.xl),
            ],
          ),
        ),
      ),
    );
  }
}
