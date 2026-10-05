import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_error.dart';
import '../../../core/utils/result.dart';
import '../domain/password_rules.dart';
import '../providers/auth_provider.dart';

/// Shown after a password-recovery link signs the player in: choose a new
/// password, then continue to Home.
class NewPasswordScreen extends ConsumerStatefulWidget {
  const NewPasswordScreen({super.key});

  @override
  ConsumerState<NewPasswordScreen> createState() => _NewPasswordScreenState();
}

class _NewPasswordScreenState extends ConsumerState<NewPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final result = await ref
        .read(authNotifierProvider.notifier)
        .updatePassword(_password.text);
    if (!mounted) return;
    switch (result) {
      case Success():
        final messenger = ScaffoldMessenger.of(context);
        final router = GoRouter.of(context);
        ref.read(passwordRecoveryPendingProvider.notifier).clear();
        messenger.showSnackBar(
          const SnackBar(content: Text(AppStrings.passwordUpdated)),
        );
        router.go('/');
      case Failure(:final error):
        setState(() {
          _saving = false;
          _error = error.userMessage;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.darkTheme;
    return Theme(
      data: theme,
      child: Scaffold(
        backgroundColor: AppColors.deepBlack,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsetsDirectional.all(AppSizes.lg),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      AppStrings.newPasswordTitle,
                      style: theme.textTheme.displayMedium,
                    ),
                  ),
                  const SizedBox(height: AppSizes.xs),
                  Text(
                    AppStrings.newPasswordSubtitle,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: AppColors.textSecondaryDark,
                    ),
                  ),
                  const SizedBox(height: AppSizes.xl),
                  TextFormField(
                    controller: _password,
                    obscureText: _obscure,
                    autofillHints: const [AutofillHints.newPassword],
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: AppStrings.newPasswordLabel,
                      hintText: 'At least 6 characters',
                      prefixIcon: const Icon(Icons.lock_outlined),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                        ),
                        tooltip: _obscure ? 'Show password' : 'Hide password',
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: validateNewPassword,
                  ),
                  const SizedBox(height: AppSizes.md),
                  TextFormField(
                    controller: _confirm,
                    obscureText: _obscure,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _save(),
                    decoration: const InputDecoration(
                      labelText: AppStrings.confirmPasswordLabel,
                      prefixIcon: Icon(Icons.lock_outlined),
                    ),
                    validator: (v) =>
                        validatePasswordConfirmation(v, _password.text),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: AppSizes.md),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _error!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.error,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSizes.lg),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : const Text(AppStrings.savePassword),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
