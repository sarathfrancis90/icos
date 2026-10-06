import 'package:url_launcher/url_launcher.dart';

import '../services/app_logger.dart';

/// Signature of `launchUrl`, injectable for tests.
typedef UrlLauncher = Future<bool> Function(
  Uri uri, {
  required LaunchMode mode,
});

Future<bool> _defaultLauncher(Uri uri, {required LaunchMode mode}) =>
    launchUrl(uri, mode: mode);

/// Opens [url]. Web pages (http/https) open inside the app
/// (SFSafariViewController / Custom Tabs) so the user never leaves the app;
/// everything else (mailto:, tel:) goes to the platform's external handler.
/// Returns false instead of throwing when nothing can handle it.
Future<bool> openExternalUrl(
  String url, {
  UrlLauncher launcher = _defaultLauncher,
}) async {
  try {
    final uri = Uri.parse(url);
    final isWeb = uri.scheme == 'https' || uri.scheme == 'http';
    return await launcher(
      uri,
      mode: isWeb
          ? LaunchMode.inAppBrowserView
          : LaunchMode.externalApplication,
    );
  } catch (e) {
    AppLogger.warn('launchUrl failed', error: e, data: {'url': url});
    return false;
  }
}
