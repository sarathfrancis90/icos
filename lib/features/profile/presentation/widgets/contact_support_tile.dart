import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_urls.dart';
import '../../../../core/utils/external_links.dart';

/// "Contact support" row: opens the user's mail app addressed to support.
class ContactSupportTile extends StatelessWidget {
  const ContactSupportTile({super.key, this.onOpen = openExternalUrl});

  final Future<bool> Function(String url) onOpen;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Contact support by email',
      excludeSemantics: true,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        minVerticalPadding: 12,
        leading: const Icon(Icons.mail_outline_rounded),
        title: const Text('Contact support'),
        subtitle: const Text(kSupportEmail),
        trailing: const Icon(
          Icons.open_in_new_rounded,
          color: AppColors.textTertiaryDark,
        ),
        onTap: () async {
          final ok = await onOpen(kSupportMailtoUrl);
          if (!ok && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Could not open your mail app. Email $kSupportEmail'),
              ),
            );
          }
        },
      ),
    );
  }
}
