import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/router/deep_link.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/content_width.dart';
import '../../../shared/widgets/legal_consent_text.dart';
import '../domain/auth_strategy.dart';
import '../providers/auth_provider.dart';
import 'widgets/auth_outcome_handler.dart';

class AuthScreen extends ConsumerWidget {
  const AuthScreen({super.key, this.nextLocation, this.signIn = false});

  /// Opened from a "Sign in" link: returning players, so the copy and the
  /// email form lean to signing in. Google and Apple work in either mode.
  final bool signIn;

  /// Where to go once signed in, e.g. the invite a guest was joining. Only a
  /// whitelisted deep link is honoured (see [sanitizeJoinLink]).
  final String? nextLocation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);
    final isGuest = ref.watch(isGuestProvider);
    final hasSession = authState.valueOrNull != null;
    final platform = AuthNotifier.platform;
    final showApple = AuthStrategy.showAppleButton(platform);
    final next = sanitizeJoinLink(nextLocation);
    Future<void> googleSignIn() async {
      final outcome = await ref
          .read(authNotifierProvider.notifier)
          .signInWithGoogle();
      if (context.mounted) {
        await handleAuthOutcome(context, ref, outcome, nextLocation: next);
      }
    }

    String emailRoute({bool signIn = false}) => Uri(
      path: '/auth/email',
      queryParameters: {
        if (signIn) 'mode': 'signin',
        'from': ?next,
      },
    ).toString();

    listenForAuthFlowMessages(context, ref);

    final title = signIn
        ? AppStrings.welcomeBack
        : hasSession && isGuest
        ? 'Save your progress'
        : AppStrings.appName;
    final subtitle = signIn
        ? AppStrings.signInSubtitle
        : hasSession && isGuest
        ? 'Create an account to keep your streak and join groups, or sign in '
              'to one you already have. Your guest progress comes with you.'
        : AppStrings.appTagline;

    return Scaffold(
      backgroundColor: context.palette.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
          tooltip: 'Close',
        ),
      ),
      body: SafeArea(
        // Scrolls when the content outgrows the screen (small phones, large
        // text); otherwise the Spacers keep the original centred layout.
        child: ContentWidth(child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsetsDirectional.all(AppSizes.lg),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - AppSizes.lg * 2,
              ),
              child: IntrinsicHeight(
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
                      shaderCallback: (bounds) => LinearGradient(
                        colors: context.palette.titleGradient,
                      ).createShader(bounds),
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.displayLarge
                            ?.copyWith(color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: AppSizes.xs),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: AppTheme.textThemeOf(context).bodyLarge?.copyWith(
                        color: context.palette.textSecondary,
                      ),
                    ),
                    const Spacer(),

                    if (authState.isLoading)
                      CircularProgressIndicator(
                        color: context.palette.accent,
                      )
                    else ...[
                      // Google sign in
                      // excludeSemantics: the label here replaces the child's
                      // own text, which would otherwise be read a second time.
                      Semantics(
                        button: true,
                        excludeSemantics: true,
                        label: AppStrings.signInWithGoogle,
                        onTap: googleSignIn,
                        child: GestureDetector(
                          onTap: googleSignIn,
                          child: Container(
                            width: double.infinity,
                            constraints: const BoxConstraints(minHeight: 52),
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
                                Icon(
                                  Icons.g_mobiledata_rounded,
                                  color: Colors.white,
                                  size: 24,
                                ),
                                SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    AppStrings.signInWithGoogle,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSizes.sm),

                      // Apple sign in (iOS native, Android via the web flow). Same size
                      // as Google, directly under it: Apple's branding rules forbid
                      // making it less prominent.
                      if (showApple) ...[
                        // The package fixes the button's height, and its label
                        // is sized from that height, so it would clip at large
                        // text sizes. Apple's own button does not follow
                        // Dynamic Type either; keep the label at its design
                        // size and let everything around it scale.
                        MediaQuery.withNoTextScaling(
                          child: SignInWithAppleButton(
                            text: AppStrings.signInWithApple,
                            height: 52,
                            // Apple HIG: white on dark backgrounds, black on light.
                            style: context.palette.isDark
                                ? SignInWithAppleButtonStyle.white
                                : SignInWithAppleButtonStyle.black,
                            borderRadius: BorderRadius.circular(26),
                            onPressed: () async {
                              final outcome = await ref
                                  .read(authNotifierProvider.notifier)
                                  .signInWithApple();
                              if (context.mounted) {
                                await handleAuthOutcome(
                                  context,
                                  ref,
                                  outcome,
                                  nextLocation: next,
                                );
                              }
                            },
                          ),
                        ),
                        const SizedBox(height: AppSizes.sm),
                      ],

                      // Email: creates an account, or signs in to an existing one.
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => context.push(emailRoute(signIn: signIn)),
                          icon: const Icon(Icons.email_outlined),
                          label: Text(
                            signIn
                                ? AppStrings.signInWithEmail
                                : AppStrings.signUpWithEmail,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSizes.md),

                      // Returning players had no way in: every route on this screen
                      // read as "create an account", and the email form opened in
                      // sign-up mode.
                      if (!signIn)
                      Semantics(
                        button: true,
                        excludeSemantics: true,
                        label: AppStrings.alreadyHaveAccount,
                        onTap: () => context.push(emailRoute(signIn: true)),
                        child: TextButton(
                          onPressed: () =>
                              context.push(emailRoute(signIn: true)),
                          child: Text.rich(
                            TextSpan(
                              text: 'Already have an account?  ',
                              style: AppTheme.textThemeOf(context).bodyMedium
                                  ?.copyWith(
                                    color: context.palette.textSecondary,
                                  ),
                              children: [
                                TextSpan(
                                  text: AppStrings.signIn,
                                  style: AppTheme
                                      .darkTheme
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: context.palette.accent,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSizes.sm),

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
                          style: AppTheme.textThemeOf(context).bodyMedium
                              ?.copyWith(color: context.palette.textSecondary),
                        ),
                      ),
                      const SizedBox(height: AppSizes.sm),
                      const LegalConsentText(),
                    ],
                    const SizedBox(height: AppSizes.xl),
                  ],
                ),
              ),
            ),
          ),
        )),
      ),
    );
  }
}
