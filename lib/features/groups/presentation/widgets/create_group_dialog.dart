import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/utils/app_error.dart';
import '../../../../core/utils/result.dart';
import '../../domain/group_name_validator.dart';
import '../../domain/models/group.dart';
import '../../providers/groups_provider.dart';

/// Shows the create-group dialog and returns the created [Group], or `null`
/// when cancelled or failed (errors are surfaced inside the dialog).
Future<Group?> showCreateGroupDialog(BuildContext context) {
  return showDialog<Group>(
    context: context,
    builder: (_) => const CreateGroupDialog(),
  );
}

class CreateGroupDialog extends ConsumerStatefulWidget {
  const CreateGroupDialog({super.key});

  static const maxDescriptionLength = 120;

  @override
  ConsumerState<CreateGroupDialog> createState() => _CreateGroupDialogState();
}

class _CreateGroupDialogState extends ConsumerState<CreateGroupDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _isSaving = false;
  String? _serverError;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _serverError = null);
    if (_formKey.currentState?.validate() != true) return;

    setState(() => _isSaving = true);
    final result = await ref.read(myGroupsProvider.notifier).createGroup(
          name: GroupNameValidator.sanitize(_nameController.text),
          description: _descriptionController.text.trim(),
        );
    if (!mounted) return;

    switch (result) {
      case Success(data: final group):
        Navigator.of(context).pop(group);
      case Failure(error: final error):
        setState(() {
          _isSaving = false;
          _serverError = error.userMessage;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text(AppStrings.createGroup),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const Key('create_group_name'),
              controller: _nameController,
              autofocus: true,
              enabled: !_isSaving,
              maxLength: AppSizes.maxGroupNameLength,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: GroupNameValidator.validate,
              decoration: const InputDecoration(
                labelText: 'Group name',
                hintText: 'e.g. Sunday Solvers',
              ),
            ),
            const SizedBox(height: AppSizes.sm),
            TextFormField(
              key: const Key('create_group_description'),
              controller: _descriptionController,
              enabled: !_isSaving,
              maxLength: CreateGroupDialog.maxDescriptionLength,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                hintText: 'What is this group about?',
                counterText: '',
              ),
            ),
            if (_serverError != null) ...[
              const SizedBox(height: AppSizes.sm),
              Text(
                _serverError!,
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
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('create_group_submit'),
          onPressed: _isSaving ? null : _submit,
          child: _isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create'),
        ),
      ],
    );
  }
}
