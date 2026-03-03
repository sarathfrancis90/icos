import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/utils/app_error.dart';
import '../../../../core/utils/result.dart';
import '../../providers/profile_provider.dart';

class EditNameDialog extends ConsumerStatefulWidget {
  const EditNameDialog({
    super.key,
    required this.currentName,
  });

  final String currentName;

  @override
  ConsumerState<EditNameDialog> createState() => _EditNameDialogState();
}

class _EditNameDialogState extends ConsumerState<EditNameDialog> {
  late final TextEditingController _controller;
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;

  // Placeholder profanity filter - words that should not be allowed.
  static const _blockedWords = [
    'admin',
    'moderator',
    'icos',
    'support',
  ];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Display name cannot be empty';
    }

    final trimmed = value.trim();

    if (trimmed.length > AppSizes.maxDisplayNameLength) {
      return 'Max ${AppSizes.maxDisplayNameLength} characters';
    }

    if (trimmed.length < 2) {
      return 'Must be at least 2 characters';
    }

    final lower = trimmed.toLowerCase();
    for (final word in _blockedWords) {
      if (lower.contains(word)) {
        return 'This name is not allowed';
      }
    }

    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final name = _controller.text.trim();
    final result = await ref
        .read(profileNotifierProvider.notifier)
        .updateDisplayName(name);

    if (!mounted) return;

    switch (result) {
      case Success():
        Navigator.of(context).pop(true);
      case Failure(error: final error):
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.userMessage)),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Display Name'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          maxLength: AppSizes.maxDisplayNameLength,
          textCapitalization: TextCapitalization.words,
          validator: _validateName,
          decoration: const InputDecoration(
            hintText: 'Enter display name',
            counterText: '',
          ),
          onFieldSubmitted: (_) => _save(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
