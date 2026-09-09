import 'package:flutter_test/flutter_test.dart';
import 'package:icos/features/groups/domain/models/group.dart';
import 'package:icos/features/groups/presentation/widgets/feed_tile.dart';

GroupFeedEvent _event(String event, {String? puzzleDate, int? timeSeconds}) =>
    GroupFeedEvent(
      id: 'f',
      groupId: 'g',
      userId: 'u',
      event: event,
      puzzleDate: puzzleDate,
      timeSeconds: timeSeconds,
      createdAt: DateTime.utc(2026, 9, 9, 8),
    );

void main() {
  group('formatRelativeTime', () {
    final now = DateTime.utc(2026, 9, 9, 12);

    test('buckets by age', () {
      expect(formatRelativeTime(now, now: now), 'just now');
      expect(
        formatRelativeTime(now.subtract(const Duration(minutes: 5)), now: now),
        '5m ago',
      );
      expect(
        formatRelativeTime(now.subtract(const Duration(hours: 3)), now: now),
        '3h ago',
      );
      expect(
        formatRelativeTime(now.subtract(const Duration(days: 2)), now: now),
        '2d ago',
      );
      expect(
        formatRelativeTime(now.subtract(const Duration(days: 10)), now: now),
        '2026-08-30',
      );
    });

    test('future timestamps read as just now', () {
      expect(
        formatRelativeTime(now.add(const Duration(minutes: 2)), now: now),
        'just now',
      );
    });
  });

  group('describeFeedEvent', () {
    test('solved today', () {
      expect(
        describeFeedEvent(
          _event('solved', puzzleDate: '2026-09-09', timeSeconds: 83),
          today: '2026-09-09',
        ),
        "solved today's puzzle in 01:23",
      );
    });

    test('solved another day without time', () {
      expect(
        describeFeedEvent(
          _event('solved', puzzleDate: '2026-09-08'),
          today: '2026-09-09',
        ),
        'solved the 2026-09-08 puzzle',
      );
    });

    test('known and unknown events', () {
      expect(describeFeedEvent(_event('joined'), today: 'x'), 'joined the group');
      expect(
        describeFeedEvent(_event('weird_thing'), today: 'x'),
        'weird thing',
      );
      expect(describeFeedEvent(_event(''), today: 'x'), 'did something');
    });
  });
}
