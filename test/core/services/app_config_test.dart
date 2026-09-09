import 'package:flutter_test/flutter_test.dart';
import 'package:icos/core/services/app_config_service.dart';
import 'package:icos/firebase_options.dart';

void main() {
  group('AppConfig.compareVersions', () {
    int cmp(String a, String b) => AppConfig.compareVersions(a, b);

    test('equal versions', () {
      expect(cmp('1.0.0', '1.0.0'), 0);
      expect(cmp('1.2', '1.2.0'), 0);
      expect(cmp('v1.2.3', '1.2.3'), 0);
      expect(cmp('1.0.0+2', '1.0.0+9'), 0);
    });

    test('ordering', () {
      expect(cmp('1.0.0', '1.0.1'), lessThan(0));
      expect(cmp('1.0.1', '1.0.0'), greaterThan(0));
      expect(cmp('1.9.0', '1.10.0'), lessThan(0));
      expect(cmp('2.0.0', '1.99.99'), greaterThan(0));
      expect(cmp('0.9', '1'), lessThan(0));
    });

    test('pre-release is lower than release', () {
      expect(cmp('1.0.0-beta', '1.0.0'), lessThan(0));
      expect(cmp('1.0.0', '1.0.0-rc1'), greaterThan(0));
      expect(cmp('1.0.0-alpha', '1.0.0-beta'), lessThan(0));
    });

    test('garbage components are treated as zero', () {
      expect(cmp('1.x.0', '1.0.0'), 0);
      expect(cmp('', '0.0.0'), 0);
      expect(cmp('abc', '0.0.1'), lessThan(0));
    });
  });

  group('AppConfig.isUpdateRequired', () {
    const config = AppConfig(
      minSupportedVersion: '1.2.0',
      latestVersion: '1.4.0',
    );

    test('below minimum requires update', () {
      expect(config.isUpdateRequired('1.1.9'), isTrue);
      expect(config.isUpdateRequired('0.9.0'), isTrue);
    });

    test('at or above minimum does not', () {
      expect(config.isUpdateRequired('1.2.0'), isFalse);
      expect(config.isUpdateRequired('1.2.0+5'), isFalse);
      expect(config.isUpdateRequired('1.3.0'), isFalse);
      expect(config.isUpdateRequired('2.0.0'), isFalse);
    });

    test('isUpdateAvailable compares against latest', () {
      expect(config.isUpdateAvailable('1.3.0'), isTrue);
      expect(config.isUpdateAvailable('1.4.0'), isFalse);
      expect(config.isUpdateAvailable('1.5.0'), isFalse);
    });

    test('defaults never require an update', () {
      expect(AppConfig.defaults.isUpdateRequired('0.0.1'), isFalse);
      expect(AppConfig.defaults.maintenanceMode, isFalse);
    });
  });

  group('AppConfig.fromRows', () {
    test('parses string and jsonb values', () {
      final config = AppConfig.fromRows(const [
        {'key': 'min_supported_version', 'value': '1.1.0'},
        {'key': 'latest_version', 'value': '1.3.0'},
        {'key': 'maintenance_mode', 'value': false},
        {
          'key': 'store_urls',
          'value': {
            'android': 'https://play.google.com/store/apps/details?id=x',
            'ios': 'https://apps.apple.com/app/id1',
          },
        },
      ]);
      expect(config.minSupportedVersion, '1.1.0');
      expect(config.latestVersion, '1.3.0');
      expect(config.maintenanceMode, isFalse);
      expect(config.storeUrlFor('ios'), 'https://apps.apple.com/app/id1');
      expect(
        config.storeUrlFor('android'),
        'https://play.google.com/store/apps/details?id=x',
      );
    });

    test('maintenance as object with message', () {
      final config = AppConfig.fromRows(const [
        {
          'key': 'maintenance_mode',
          'value': {'enabled': true, 'message': 'Back at 10:00 UTC'},
        },
      ]);
      expect(config.maintenanceMode, isTrue);
      expect(config.maintenanceMessage, 'Back at 10:00 UTC');
    });

    test('maintenance as string', () {
      expect(
        AppConfig.fromRows(const [
          {'key': 'maintenance_mode', 'value': 'true'},
        ]).maintenanceMode,
        isTrue,
      );
    });

    test('missing keys fall back to defaults and fallback store urls', () {
      final config = AppConfig.fromRows(const []);
      expect(config, AppConfig.defaults);
      expect(config.storeUrlFor('ios'), AppConfig.iosAppStoreFallback);
      expect(config.storeUrlFor('android'), AppConfig.androidPlayStoreFallback);
      expect(config.storeUrlFor('other'), AppConfig.androidPlayStoreFallback);
    });

    test('ignores malformed rows', () {
      final config = AppConfig.fromRows(const [
        {'nope': 1},
        {'key': 42, 'value': 'x'},
        {'key': 'store_urls', 'value': 'not-a-map'},
        {'key': 'min_supported_version', 'value': 7},
      ]);
      expect(config.minSupportedVersion, '0.0.0');
      expect(config.storeUrls, isEmpty);
    });

    test('equality and hashCode', () {
      const a = AppConfig(minSupportedVersion: '1.0.0', storeUrls: {'ios': 'u'});
      const b = AppConfig(minSupportedVersion: '1.0.0', storeUrls: {'ios': 'u'});
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('DefaultFirebaseOptions.isConfiguredFrom', () {
    test('requires every key to be non-empty', () {
      final env = {
        for (final k in DefaultFirebaseOptions.requiredKeys) k: 'value',
      };
      expect(DefaultFirebaseOptions.isConfiguredFrom(env), isTrue);

      final missing = Map<String, String>.from(env)
        ..remove('FIREBASE_IOS_APP_ID');
      expect(DefaultFirebaseOptions.isConfiguredFrom(missing), isFalse);

      final blank = Map<String, String>.from(env)..['FIREBASE_PROJECT_ID'] = ' ';
      expect(DefaultFirebaseOptions.isConfiguredFrom(blank), isFalse);
    });

    test('is false with no env loaded', () {
      expect(DefaultFirebaseOptions.isConfiguredFrom(const {}), isFalse);
      expect(DefaultFirebaseOptions.isConfigured, isFalse);
    });
  });
}
