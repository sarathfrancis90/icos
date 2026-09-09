import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/utils/app_error.dart';
import '../../../../core/utils/result.dart';
import '../../providers/groups_provider.dart';

enum ReportTarget { user, group }

/// Reasons stored verbatim in `reports.reason`.
enum ReportReason {
  inappropriateName('inappropriate_name', 'Inappropriate name'),
  harassment('harassment', 'Harassment or bullying'),
  cheating('cheating', 'Cheating'),
  spam('spam', 'Spam'),
  other('other', 'Something else');

  const ReportReason(this.value, this.label);
  final String value;
  final String label;
}

/// Opens the report dialog. Returns `true` when a report was submitted.
Future<bool> showReportDialog(
  BuildContext context, {
  required ReportTarget target,
  required String targetId,
  required String targetName,
}) async {
  final submitted = await showDialog<bool>(
    context: context,
    builder: (_) => ReportDialog(
      target: target,
      targetId: targetId,
      targetName: targetName,
    ),
  );
  return submitted ?? false;
}

class ReportDialog extends ConsumerStatefulWidget {
  const ReportDialog({
    required this.target,
    required this.targetId,
    required this.targetName,
    super.key,
  });

  final ReportTarget target;
  final String targetId;
  final String targetName;

  static const maxDetailsLength = 500;

  @override
  ConsumerState<ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends ConsumerState<ReportDialog> {
  final _detailsController = TextEditingController();
  ReportReason _reason = ReportReason.inappropriateName;
  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    final repo = ref.read(groupRepositoryProvider);
    final result = switch (widget.target) {
      ReportTarget.user => await repo.reportUser(
          userId: widget.targetId,
          reason: _reason.value,
          details: _detailsController.text,
        ),
      ReportTarget.group => await repo.reportGroup(
          groupId: widget.targetId,
          reason: _reason.value,
          details: _detailsController.text,
        ),
    };
    if (!mounted) return;
    switch (result) {
      case Success():
        Navigator.of(context).pop(true);
      case Failure(error: final error):
        setState(() {
          _isSubmitting = false;
          _error = error.userMessage;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final noun = widget.target == ReportTarget.user ? 'user' : 'group';
    return AlertDialog(
      title: Text('Report $noun'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reporting "${widget.targetName}". Our team reviews every '
              'report; the $noun will not be notified.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSizes.md),
            DropdownButtonFormField<ReportReason>(
              initialValue: _reason,
              decoration: const InputDecoration(labelText: 'Reason'),
              items: [
                for (final reason in ReportReason.values)
                  DropdownMenuItem(value: reason, child: Text(reason.label)),
              ],
              onChanged: _isSubmitting
                  ? null
                  : (value) {
                      if (value != null) setState(() => _reason = value);
                    },
            ),
            const SizedBox(height: AppSizes.sm),
            TextField(
              controller: _detailsController,
              enabled: !_isSubmitting,
              maxLength: ReportDialog.maxDetailsLength,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Details (optional)',
                hintText: 'Tell us what happened',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSizes.xs),
              Text(
                _error!,
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
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Submit report'),
        ),
      ],
    );
  }
}
