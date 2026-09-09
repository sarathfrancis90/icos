import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_strings.dart';
import '../../domain/invite_code.dart';
import '../../domain/models/group.dart';
import 'group_ui.dart';

/// Share text for a group invite (used by the share sheet).
String inviteShareText(Group group) {
  final code = InviteCode.normalize(group.inviteCode);
  return 'Join my ${AppStrings.appName} group "${group.name}"! '
      'Use invite code $code or tap ${InviteCode.joinLink(code)}';
}

/// Opens the OS share sheet with the invite text + deep link.
Future<void> shareGroupInvite(BuildContext context, Group group) async {
  final box = context.findRenderObject() as RenderBox?;
  await Share.share(
    inviteShareText(group),
    subject: 'Join "${group.name}" on ${AppStrings.appName}',
    sharePositionOrigin:
        box == null ? null : box.localToGlobal(Offset.zero) & box.size,
  );
}

Future<void> copyInviteCode(BuildContext context, Group group) async {
  await Clipboard.setData(
    ClipboardData(text: InviteCode.normalize(group.inviteCode)),
  );
  if (context.mounted) showAppSnackBar(context, AppStrings.inviteCodeCopied);
}

/// Shows a QR code encoding the join deep link.
Future<void> showInviteQrDialog(BuildContext context, Group group) {
  return showDialog<void>(
    context: context,
    builder: (_) => InviteQrDialog(group: group),
  );
}

class InviteQrDialog extends StatelessWidget {
  const InviteQrDialog({required this.group, super.key});

  final Group group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final code = InviteCode.normalize(group.inviteCode);
    final link = InviteCode.joinLink(code);

    return AlertDialog(
      title: Text(group.name, textAlign: TextAlign.center),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            label: 'QR code for invite link $link',
            image: true,
            child: Container(
              padding: const EdgeInsetsDirectional.all(AppSizes.sm),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              ),
              child: QrImageView(
                data: link,
                size: 220,
                padding: EdgeInsets.zero,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: AppColors.deepBlack,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: AppColors.deepBlack,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSizes.md),
          Text(
            code,
            style: theme.textTheme.headlineSmall?.copyWith(
              letterSpacing: 4,
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSizes.xs),
          Text(
            link,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: secondaryTextColor(context),
            ),
          ),
          const SizedBox(height: AppSizes.xs),
          Text(
            'Scan to join this group',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          onPressed: () => copyInviteCode(context, group),
          icon: const Icon(Icons.copy_rounded, size: 18),
          label: const Text('Copy code'),
        ),
        TextButton.icon(
          onPressed: () => shareGroupInvite(context, group),
          icon: const Icon(Icons.share_rounded, size: 18),
          label: const Text('Share'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
