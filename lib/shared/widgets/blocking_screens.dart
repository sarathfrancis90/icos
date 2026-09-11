import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/services/app_logger.dart';

/// Full-screen block shown when the installed version is below
/// `min_supported_version`.
class ForceUpdateScreen extends StatelessWidget {
  const ForceUpdateScreen({
    super.key,
    required this.storeUrl,
    this.latestVersion,
  });

  final String storeUrl;
  final String? latestVersion;

  Future<void> _openStore() async {
    final uri = Uri.tryParse(storeUrl);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      AppLogger.warn('Could not open store URL', error: e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _BlockingScaffold(
      icon: Icons.system_update_rounded,
      iconColor: AppColors.purpleLight,
      title: 'Update required',
      message: latestVersion != null
          ? 'A new version ($latestVersion) of Icos is available. '
              'Please update to keep playing.'
          : 'A new version of Icos is available. Please update to keep playing.',
      action: FilledButton.icon(
        onPressed: _openStore,
        icon: const Icon(Icons.open_in_new_rounded),
        label: const Text('Update now'),
      ),
    );
  }
}

/// Full-screen block shown while `maintenance_mode` is enabled.
class MaintenanceScreen extends StatelessWidget {
  const MaintenanceScreen({super.key, this.message, this.onRetry});

  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return _BlockingScaffold(
      icon: Icons.construction_rounded,
      iconColor: AppColors.warning,
      title: 'Back soon',
      message: message ??
          'Icos is undergoing scheduled maintenance. '
              'Please check back in a little while.',
      action: onRetry != null
          ? OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            )
          : null,
    );
  }
}

/// Full-screen block shown when `profiles.is_banned` is true.
class BannedScreen extends StatelessWidget {
  const BannedScreen({super.key, this.onSignOut});

  final VoidCallback? onSignOut;

  static const supportEmail = 'sarathfrancis90@gmail.com';

  Future<void> _contactSupport() async {
    final uri = Uri(
      scheme: 'mailto',
      path: supportEmail,
      queryParameters: {'subject': 'Icos account appeal'},
    );
    try {
      await launchUrl(uri);
    } catch (e) {
      AppLogger.warn('Could not open mail client', error: e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _BlockingScaffold(
      icon: Icons.block_rounded,
      iconColor: AppColors.error,
      title: 'Account suspended',
      message: 'This account has been suspended for violating the Icos '
          'community guidelines. If you believe this is a mistake, contact '
          '$supportEmail.',
      action: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          OutlinedButton.icon(
            onPressed: _contactSupport,
            icon: const Icon(Icons.mail_outline_rounded),
            label: const Text('Contact support'),
          ),
          if (onSignOut != null) ...[
            const SizedBox(height: AppSizes.sm),
            TextButton(
              onPressed: onSignOut,
              child: const Text('Sign out'),
            ),
          ],
        ],
      ),
    );
  }
}

class _BlockingScaffold extends StatelessWidget {
  const _BlockingScaffold({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: AppSizes.contentMaxWidth),
            child: Padding(
              padding: const EdgeInsetsDirectional.all(AppSizes.xl),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: iconColor.withValues(alpha: 0.12),
                      border: Border.all(
                        color: iconColor.withValues(alpha: 0.4),
                        width: 1.5,
                      ),
                    ),
                    child: Icon(icon, size: 48, color: iconColor),
                  ),
                  const SizedBox(height: AppSizes.lg),
                  Text(
                    title,
                    style: theme.textTheme.headlineLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSizes.md),
                  Text(
                    message,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: secondary,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (action != null) ...[
                    const SizedBox(height: AppSizes.xl),
                    action!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
