import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/app_error.dart';
import '../../../../core/utils/result.dart';
import '../../../../core/utils/text_sanitizer.dart';
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

  String? _validateName(String? value) => validateName(value ?? '');

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    // Persist the sanitised form (invisible chars stripped, whitespace
    // collapsed) — the server applies the same rules.
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
          maxLength: kMaxDisplayNameLength,
          textCapitalization: TextCapitalization.words,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: _validateName,
          decoration: const InputDecoration(
            hintText: 'Enter display name',
            helperText:
                '$kMinDisplayNameLength–$kMaxDisplayNameLength characters',
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
