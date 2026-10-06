import 'package:flutter/material.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/constants/app_urls.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/utils/external_links.dart';

/// "Contact support" row: opens the user's mail app addressed to support.
class ContactSupportTile extends StatelessWidget {
  const ContactSupportTile({super.key, this.onOpen = openExternalUrl});

  final Future<bool> Function(String url) onOpen;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: AppStrings.contactSupportSemantics,
      excludeSemantics: true,
      child: ListTile(
        contentPadding: EdgeInsetsDirectional.zero,
        minVerticalPadding: 12,
        leading: const Icon(Icons.mail_outline_rounded),
        title: const Text(AppStrings.contactSupport),
        subtitle: const Text(kSupportEmail),
        trailing: Icon(
          Icons.open_in_new_rounded,
          color: context.palette.textTertiary,
        ),
        onTap: () async {
          final ok = await onOpen(kSupportMailtoUrl);
          if (!ok && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(AppStrings.couldNotOpenMail(kSupportEmail)),
              ),
            );
          }
        },
      ),
    );
  }
}
