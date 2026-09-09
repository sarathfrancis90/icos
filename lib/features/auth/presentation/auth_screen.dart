import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../domain/auth_strategy.dart';
import '../providers/auth_provider.dart';
import 'widgets/auth_outcome_handler.dart';

class AuthScreen extends ConsumerWidget {
  const AuthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);
    final isGuest = ref.watch(isGuestProvider);
    final hasSession = authState.valueOrNull != null;
    final platform = AuthNotifier.platform;
    final showApple = AuthStrategy.showAppleButton(platform);

    listenForAuthFlowMessages(context, ref);

    final title = hasSession && isGuest
        ? 'Save your progress'
        : AppStrings.appName;
    final subtitle = hasSession && isGuest
        ? 'Create an account to keep your streak and join groups. '
            'Your guest progress comes with you.'
        : AppStrings.appTagline;

    return Scaffold(
      backgroundColor: AppColors.deepBlack,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/'),
          tooltip: 'Close',
        ),
      ),
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
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.purpleGradientStart,
                      AppColors.purpleGradientEnd,
                    ],
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
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(
                        color: Colors.white,
                      ),
                ),
              ),
              const SizedBox(height: AppSizes.xs),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.textSecondaryDark,
                    ),
              ),
              const Spacer(),

              if (authState.isLoading)
                const CircularProgressIndicator(color: AppColors.purpleLight)
              else ...[
                // Google sign in
                Semantics(
                  button: true,
                  label: AppStrings.signInWithGoogle,
                  child: GestureDetector(
                    onTap: () async {
                      final outcome = await ref
                          .read(authNotifierProvider.notifier)
                          .signInWithGoogle();
                      if (context.mounted) {
                        await handleAuthOutcome(context, ref, outcome);
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: AppColors.purpleButtonGradient,
                        borderRadius: BorderRadius.circular(26),
                        boxShadow: const [
                          BoxShadow(
                            color: AppColors.purpleGlow,
                            blurRadius: 12,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.g_mobiledata_rounded,
                              color: Colors.white, size: 24),
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
                ),
                const SizedBox(height: AppSizes.sm),

                // Apple sign in (iOS only — Apple HIG-compliant button)
                if (showApple) ...[
                  SignInWithAppleButton(
                    text: AppStrings.signInWithApple,
                    height: 52,
                    style: SignInWithAppleButtonStyle.white,
                    borderRadius: BorderRadius.circular(26),
                    onPressed: () async {
                      final outcome = await ref
                          .read(authNotifierProvider.notifier)
                          .signInWithApple();
                      if (context.mounted) {
                        await handleAuthOutcome(context, ref, outcome);
                      }
                    },
                  ),
                  const SizedBox(height: AppSizes.sm),
                ],

                // Email sign in
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => context.push('/auth/email'),
                    icon: const Icon(Icons.email_outlined),
                    label: const Text(AppStrings.signInWithEmail),
                  ),
                ),
                const SizedBox(height: AppSizes.lg),

                TextButton(
                  onPressed: () async {
                    if (!hasSession) {
                      await ref
                          .read(authNotifierProvider.notifier)
                          .signInAnonymously();
                    }
                    if (context.mounted) context.go('/');
                  },
                  child: Text(
                    hasSession && isGuest
                        ? 'Not now'
                        : AppStrings.continueAsGuest,
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
