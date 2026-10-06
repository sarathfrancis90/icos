import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/utils/external_links.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  group('openExternalUrl launch mode', () {
    Future<LaunchMode?> modeFor(String url) async {
      LaunchMode? seen;
      await openExternalUrl(
        url,
        launcher: (uri, {required mode}) async {
          seen = mode;
          return true;
        },
      );
      return seen;
    }

    test('https links open in the in-app browser view', () async {
      expect(
        await modeFor('https://icos.sarathfrancis.work/privacy-policy.html'),
        LaunchMode.inAppBrowserView,
      );
    });

    test('mailto links do not use the in-app browser view', () async {
      final mode = await modeFor('mailto:support@example.com?subject=Hi');
      expect(mode, isNotNull);
      expect(mode, isNot(LaunchMode.inAppBrowserView));
    });

    test('returns false when the launcher throws', () async {
      final ok = await openExternalUrl(
        'https://example.com',
        launcher: (uri, {required mode}) async => throw Exception('boom'),
      );
      expect(ok, isFalse);
    });
  });
}
