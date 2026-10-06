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
import '../../domain/display_name_placeholder.dart';
import '../../providers/profile_provider.dart';

/// The name the identity provider gave us, if any (Apple omits it after the
/// first authorisation, and Hide My Email gives none at all).
String providerNameOf(User user) {
  final meta = user.userMetadata;
  for (final key in const ['full_name', 'name']) {
    final value = meta?[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return '';
}

/// After a sign-in or link completes: if the account still has a placeholder
/// name ("Player 1234"), asks the player to choose one. Shown at most once per
/// account on this device. Never throws; a failure here must not get in the way
/// of the sign-in flow it follows.
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
    final profile = switch (result) {
      Success(data: final p) => p,
      _ => null,
    };
    if (profile == null || !isPlaceholderDisplayName(profile.displayName)) {
      return;
    }
    if (!context.mounted) return;
    // Marked before showing, so a dismissal by any route never repeats it.
    await StorageService.setDisplayNamePromptShown(user.id);
    if (!context.mounted) return;
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ChooseDisplayNameSheet(initialName: providerNameOf(user)),
    );
  } catch (e, st) {
    AppLogger.warn('Display name prompt failed', error: e, st: st);
  }
}

class ChooseDisplayNameSheet extends ConsumerStatefulWidget {
  const ChooseDisplayNameSheet({super.key, this.initialName = ''});

  final String initialName;

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
                decoration: const InputDecoration(
                  labelText: AppStrings.chooseNameField,
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
