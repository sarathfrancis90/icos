import 'package:url_launcher/url_launcher.dart';

import '../services/app_logger.dart';

/// Opens [url] in the platform's external handler (browser, mail app).
/// Returns false instead of throwing when nothing can handle it.
Future<bool> openExternalUrl(String url) async {
  try {
    return await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
  } catch (e) {
    AppLogger.warn('launchUrl failed', error: e, data: {'url': url});
    return false;
  }
}
