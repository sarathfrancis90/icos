import 'package:flutter_test/flutter_test.dart';
import 'package:icos/features/profile/data/profile_repository.dart';
import 'package:icos/features/profile/domain/models/profile.dart';

void main() {
  group('UserProfile.fromJson', () {
    test('parses a full row', () {
      final profile = UserProfile.fromJson({
        'id': 'u1',
        'display_name': 'Ada',
        'avatar_url': null,
        'is_anonymous': false,
        'is_banned': true,
        'colorblind_mode': 'deuteranopia',
        'theme_mode': 'dark',
        'haptic_enabled': false,
        'sound_enabled': true,
        'notification_enabled': false,
        'deleted_at': '2026-09-01T00:00:00Z',
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-02-01T00:00:00Z',
      });
      expect(profile.id, 'u1');
      expect(profile.displayName, 'Ada');
      expect(profile.isAnonymous, isFalse);
      expect(profile.isBanned, isTrue);
      expect(profile.colorblindMode, 'deuteranopia');
      expect(profile.hapticEnabled, isFalse);
      expect(profile.deletedAt, DateTime.utc(2026, 9, 1));
    });

    test('applies defaults for missing optional columns', () {
      final profile = UserProfile.fromJson({
        'id': 'u2',
        'display_name': 'Guest',
      });
      expect(profile.isAnonymous, isTrue);
      expect(profile.isBanned, isFalse);
      expect(profile.colorblindMode, 'none');
      expect(profile.themeMode, 'system');
      expect(profile.deletedAt, isNull);
    });
  });

  test('repository selects an explicit column list', () {
    final columns =
        ProfileRepository.columns.split(',').map((c) => c.trim()).toList();
    expect(
      columns,
      containsAll([
        'id',
        'display_name',
        'avatar_url',
        'is_anonymous',
        'is_banned',
        'colorblind_mode',
        'theme_mode',
        'haptic_enabled',
        'sound_enabled',
        'notification_enabled',
        'deleted_at',
        'created_at',
        'updated_at',
      ]),
    );
    expect(ProfileRepository.columns, isNot(contains('*')));
  });
}
