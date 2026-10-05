import 'package:flutter_test/flutter_test.dart';
import 'package:icos/features/groups/domain/models/blocked_user.dart';

void main() {
  group('BlockedUser.fromJson', () {
    test('parses the list_blocked_users row shape', () {
      final user = BlockedUser.fromJson({
        'user_id': 'u-2',
        'display_name': 'Bob',
        'blocked_at': '2026-10-05T10:00:00Z',
      });

      expect(user.userId, 'u-2');
      expect(user.displayName, 'Bob');
      expect(user.blockedAt, DateTime.utc(2026, 10, 5, 10));
    });

    test('falls back to Player when the name is missing or blank', () {
      final user = BlockedUser.fromJson({
        'user_id': 'u-2',
        'display_name': null,
        'blocked_at': '2026-10-05T10:00:00Z',
      });
      expect(user.displayName, 'Player');
    });
  });
}
