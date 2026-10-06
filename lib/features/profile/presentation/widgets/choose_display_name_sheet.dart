import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/services/app_logger.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/utils/app_error.dart';
import '../../../../core/utils/result.dart';
import '../../../../core/utils/text_sanitizer.dart';
import '../../domain/display_name_suggestion.dart';
import '../../providers/profile_provider.dart';

/// After the first sign-in or link completes for an account: asks the player
/// to choose a display name, prefilled with a sensible default (the current
/// name if they already chose one, else the provider's name, else the tidied
/// email local part). Shown at most once per account on this device. Never
/// throws; a failure here must not get in the way of the sign-in flow it
/// follows.
Future<void> maybePromptForDisplayName(
  BuildContext context,
  WidgetRef ref,
  User? user,
) async {
  if (user == null) return;
  try {
    if (StorageService.displayNamePromptShown(user.id)) return;
    final result = await ref
        .read(profileRepositoryProvider)
        .getProfile(user.id);
    final currentName = switch (result) {
      Success(data: final p) => p.displayName,
      _ => null,
    };
    if (!context.mounted) return;
    // Marked before showing, so a dismissal by any route never repeats it.
    await StorageService.setDisplayNamePromptShown(user.id);
    if (!context.mounted) return;
    final initial = initialDisplayName(
      currentName: currentName,
      meta: user.userMetadata,
      email: user.email,
    );
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ChooseDisplayNameSheet(
        initialName: initial,
        hint: initial.isEmpty ? currentName : null,
      ),
    );
  } catch (e, st) {
    AppLogger.warn('Display name prompt failed', error: e, st: st);
  }
}

class ChooseDisplayNameSheet extends ConsumerStatefulWidget {
  const ChooseDisplayNameSheet({super.key, this.initialName = '', this.hint});

  final String initialName;

  /// Shown in the empty field (the current placeholder name).
  final String? hint;

  @override
  ConsumerState<ChooseDisplayNameSheet> createState() =>
      _ChooseDisplayNameSheetState();
}

class _ChooseDisplayNameSheetState
    extends ConsumerState<ChooseDisplayNameSheet> {
  late final TextEditingController _controller;
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    final name = sanitizeDisplayName(_controller.text);
    final result = await ref
        .read(profileNotifierProvider.notifier)
        .updateDisplayName(name);
    if (!mounted) return;
    switch (result) {
      case Success():
        Navigator.of(context).pop(true);
      case Failure(error: final error):
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.userMessage)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const minTarget = Size.fromHeight(AppSizes.minTouchTarget);
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      namesRoute: true,
      label: AppStrings.chooseNameSemantics,
      child: SingleChildScrollView(
        padding: EdgeInsetsDirectional.only(
          start: 24,
          end: 24,
          top: 24,
          bottom: 24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  AppStrings.chooseNameTitle,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                AppStrings.chooseNameBody,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _controller,
                autofocus: true,
                maxLength: kMaxDisplayNameLength,
                textCapitalization: TextCapitalization.words,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: (v) => validateName(v ?? ''),
                decoration: InputDecoration(
                  labelText: AppStrings.chooseNameField,
                  hintText: widget.hint,
                  counterText: '',
                ),
                onFieldSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: minTarget),
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(AppStrings.chooseNameSave),
              ),
              const SizedBox(height: 8),
              TextButton(
                style: TextButton.styleFrom(minimumSize: minTarget),
                onPressed: _isSaving
                    ? null
                    : () => Navigator.of(context).pop(false),
                child: const Text(AppStrings.notNow),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
