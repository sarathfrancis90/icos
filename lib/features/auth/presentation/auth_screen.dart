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
      backgroundColor: AppColors.deepBlack,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsetsDirectional.all(AppSizes.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              // Logo with gradient
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.purpleGradientStart, AppColors.purpleGradientEnd],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.purpleGlow,
                      blurRadius: 24,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.route_rounded,
                  size: 50,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: AppSizes.lg),
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [AppColors.purpleLight, AppColors.pathYellowBright],
                ).createShader(bounds),
                child: Text(
                  AppStrings.appName,
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(
                        color: Colors.white,
                      ),
                ),
              ),
              const SizedBox(height: AppSizes.xs),
              Text(
                AppStrings.appTagline,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.textSecondaryDark,
                    ),
              ),
              const Spacer(),

              if (authState.isLoading)
                const CircularProgressIndicator(color: AppColors.purpleLight)
              else ...[
                // Google sign in
                GestureDetector(
                  onTap: () {
                    ref
                        .read(authNotifierProvider.notifier)
                        .signInWithGoogle();
                  },
                  child: Container(
                    width: double.infinity,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: AppColors.purpleButtonGradient,
                      borderRadius: BorderRadius.circular(26),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.purpleGlow,
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.g_mobiledata_rounded, color: Colors.white, size: 24),
                        SizedBox(width: 8),
                        Text(
                          AppStrings.signInWithGoogle,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSizes.sm),

                // Apple sign in
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
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                    ),
                  ),
                ),
                const SizedBox(height: AppSizes.sm),

                // Email sign in
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
                          color: AppColors.textSecondaryDark,
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
