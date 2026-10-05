import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/constants/app_strings.dart';
import '../../core/constants/app_urls.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/external_links.dart';

/// "By continuing, you agree to our Terms of Service and Privacy Policy."
/// with each document a separately tappable, separately announced link.
class LegalConsentText extends StatelessWidget {
  const LegalConsentText({super.key, this.onOpen = openExternalUrl});

  /// Opens a url; returns false when it could not be opened. Injectable so
  /// tests do not reach for the platform.
  final Future<bool> Function(String url) onOpen;

  Future<void> _open(BuildContext context, String url) async {
    final ok = await onOpen(url);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AppStrings.couldNotOpen(url))));
    }
  }

  WidgetSpan _link(BuildContext context, String label, String url) {
    final style = AppTheme.darkTheme.textTheme.bodySmall?.copyWith(
      color: AppColors.purpleLight,
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.underline,
      decorationColor: AppColors.purpleLight,
    );
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Semantics(
        link: true,
        label: label,
        excludeSemantics: true,
        onTap: () => _open(context, url),
        child: InkWell(
          onTap: () => _open(context, url),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: AppSizes.xs,
              ),
              child: Align(widthFactor: 1, child: Text(label, style: style)),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final base = AppTheme.darkTheme.textTheme.bodySmall?.copyWith(
      color: AppColors.textSecondaryDark,
    );
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          const TextSpan(text: AppStrings.consentPrefix),
          _link(context, AppStrings.termsOfService, kTermsUrl),
          const TextSpan(text: AppStrings.consentAnd),
          _link(context, AppStrings.privacyPolicy, kPrivacyPolicyUrl),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}
