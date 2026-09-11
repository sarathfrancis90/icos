import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/auth_provider.dart';
import 'widgets/auth_outcome_handler.dart';

class EmailAuthScreen extends ConsumerStatefulWidget {
  const EmailAuthScreen({super.key, this.initialSignUp = true});

  /// When false the form opens in "sign in" mode.
  final bool initialSignUp;

  @override
  ConsumerState<EmailAuthScreen> createState() => _EmailAuthScreenState();
}

class _EmailAuthScreenState extends ConsumerState<EmailAuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  late bool _isSignUp = widget.initialSignUp;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isGuest = ref.watch(isGuestProvider);
    final hasSession = ref.watch(authNotifierProvider).valueOrNull != null;
    final guestUpgrade = hasSession && isGuest;

    listenForAuthFlowMessages(context, ref);

    // Auth screens are always dark; pin the theme so the AppBar/text stay
    // legible when the system theme is light.
    return Theme(
      data: AppTheme.darkTheme,
      child: Scaffold(
        backgroundColor: AppColors.deepBlack,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () =>
                context.canPop() ? context.pop() : context.go('/auth'),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsetsDirectional.all(AppSizes.lg),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _isSignUp ? 'Create Account' : 'Welcome Back',
                    style: AppTheme.darkTheme.textTheme.displayMedium,
                  ),
                  const SizedBox(height: AppSizes.xs),
                  Text(
                    _isSignUp
                        ? (guestUpgrade
                              ? 'Add an email and password to keep your guest '
                                    'progress on every device'
                              : 'Sign up with your email to save progress')
                        : (guestUpgrade
                              ? 'Signing in to an existing account replaces '
                                    'your guest progress on this device'
                              : 'Sign in to continue your streak'),
                    style: AppTheme.darkTheme.textTheme.bodyLarge?.copyWith(
                      color: AppColors.textSecondaryDark,
                    ),
                  ),
                  const SizedBox(height: AppSizes.xl),

                  // Email field
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      hintText: 'you@example.com',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Email is required';
                      }
                      final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                      if (!emailRegex.hasMatch(value.trim())) {
                        return 'Enter a valid email address';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSizes.md),

                  // Password field
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    autofillHints: [
                      _isSignUp
                          ? AutofillHints.newPassword
                          : AutofillHints.password,
                    ],
                    textInputAction: _isSignUp
                        ? TextInputAction.next
                        : TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      hintText: _isSignUp ? 'At least 6 characters' : '',
                      prefixIcon: const Icon(Icons.lock_outlined),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                        ),
                        tooltip: _obscurePassword
                            ? 'Show password'
                            : 'Hide password',
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Password is required';
                      }
                      if (_isSignUp && value.length < 6) {
                        return 'Password must be at least 6 characters';
                      }
                      return null;
                    },
                    onFieldSubmitted: _isSignUp ? null : (_) => _submit(),
                  ),

                  // Confirm password (sign-up only)
                  if (_isSignUp) ...[
                    const SizedBox(height: AppSizes.md),
                    TextFormField(
                      controller: _confirmPasswordController,
                      obscureText: _obscureConfirm,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        labelText: 'Confirm Password',
                        prefixIcon: const Icon(Icons.lock_outlined),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureConfirm
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                          ),
                          tooltip: _obscureConfirm
                              ? 'Show password'
                              : 'Hide password',
                          onPressed: () => setState(
                            () => _obscureConfirm = !_obscureConfirm,
                          ),
                        ),
                      ),
                      validator: (value) {
                        if (value != _passwordController.text) {
                          return 'Passwords do not match';
                        }
                        return null;
                      },
                      onFieldSubmitted: (_) => _submit(),
                    ),
                  ],

                  // Error message
                  if (_errorMessage != null) ...[
                    const SizedBox(height: AppSizes.md),
                    Container(
                      padding: const EdgeInsetsDirectional.all(AppSizes.sm),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                        border: Border.all(
                          color: AppColors.error.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: AppColors.error,
                            size: 20,
                          ),
                          const SizedBox(width: AppSizes.sm),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: AppTheme.darkTheme.textTheme.bodyMedium
                                  ?.copyWith(color: AppColors.error),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: AppSizes.lg),

                  // Submit button
                  Semantics(
                    button: true,
                    label: _isSignUp ? 'Create Account' : 'Sign In',
                    child: GestureDetector(
                      onTap: _isLoading ? null : _submit,
                      child: Container(
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: _isLoading
                              ? null
                              : AppColors.purpleButtonGradient,
                          color: _isLoading ? AppColors.cellBackground : null,
                          borderRadius: BorderRadius.circular(26),
                          boxShadow: _isLoading
                              ? null
                              : const [
                                  BoxShadow(
                                    color: AppColors.purpleGlow,
                                    blurRadius: 12,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                        ),
                        child: Center(
                          child: _isLoading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : Text(
                                  _isSignUp ? 'Create Account' : 'Sign In',
                                  style: AppTheme.darkTheme.textTheme.titleMedium
                                      ?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSizes.lg),

                  // Toggle sign-up / sign-in
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _isSignUp
                            ? 'Already have an account?'
                            : "Don't have an account?",
                        style: AppTheme.darkTheme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondaryDark,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _isSignUp = !_isSignUp;
                            _errorMessage = null;
                            _confirmPasswordController.clear();
                          });
                        },
                        child: Text(
                          _isSignUp ? 'Sign In' : 'Sign Up',
                          style: AppTheme.darkTheme.textTheme.labelLarge
                              ?.copyWith(color: AppColors.purpleLight),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final notifier = ref.read(authNotifierProvider.notifier);

    final outcome = _isSignUp
        ? await notifier.signUpWithEmail(email, password)
        : await notifier.signInWithEmail(email, password);

    if (!mounted) return;

    // Inline error for plain failures; dialogs / navigation for the rest.
    if (outcome is AuthFailure) {
      setState(() {
        _errorMessage = outcome.message;
        _isLoading = false;
      });
      return;
    }

    final done = await handleAuthOutcome(
      context,
      ref,
      outcome,
      emailForExisting: email,
      passwordForExisting: password,
    );
    if (mounted && !done) {
      setState(() => _isLoading = false);
    }
  }
}
