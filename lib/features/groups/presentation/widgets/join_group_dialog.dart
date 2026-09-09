import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/utils/app_error.dart';
import '../../../../core/utils/result.dart';
import '../../domain/invite_code.dart';
import '../../domain/models/group.dart';
import '../../providers/groups_provider.dart';

/// Shows the join-by-code dialog and returns the joined [Group], or `null`.
Future<Group?> showJoinGroupDialog(BuildContext context) {
  return showDialog<Group>(
    context: context,
    builder: (_) => const JoinGroupDialog(),
  );
}

class JoinGroupDialog extends ConsumerStatefulWidget {
  const JoinGroupDialog({super.key});

  @override
  ConsumerState<JoinGroupDialog> createState() => _JoinGroupDialogState();
}

class _JoinGroupDialogState extends ConsumerState<JoinGroupDialog> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  bool _isJoining = false;
  String? _serverError;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _serverError = null);
    if (_formKey.currentState?.validate() != true) return;

    setState(() => _isJoining = true);
    final result = await ref
        .read(myGroupsProvider.notifier)
        .joinGroup(InviteCode.normalize(_codeController.text));
    if (!mounted) return;

    switch (result) {
      case Success(data: final group):
        Navigator.of(context).pop(group);
      case Failure(error: final error):
        setState(() {
          _isJoining = false;
          _serverError = error.userMessage;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text(AppStrings.joinGroup),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const Key('join_group_code'),
              controller: _codeController,
              autofocus: true,
              enabled: !_isJoining,
              maxLength: AppSizes.inviteCodeLength,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              enableSuggestions: false,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
                _UpperCaseFormatter(),
              ],
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: InviteCode.validate,
              onFieldSubmitted: (_) => _submit(),
              style: theme.textTheme.titleLarge?.copyWith(letterSpacing: 4),
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                labelText: AppStrings.groupInviteCode,
                hintText: 'ABC123',
                counterText: '',
              ),
            ),
            if (_serverError != null) ...[
              const SizedBox(height: AppSizes.sm),
              Text(
                _serverError!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isJoining ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('join_group_submit'),
          onPressed: _isJoining ? null : _submit,
          child: _isJoining
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Join'),
        ),
      ],
    );
  }
}

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
