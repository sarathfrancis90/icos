import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:icos/core/utils/result.dart';
import 'package:icos/features/stats/data/stats_repository.dart';

import '../../../helpers/data_api_test_helpers.dart';

void main() {
  test(
    'getTotalSolved uses an exact-count HEAD request (no 200-row cap)',
    () async {
      final requests = <http.Request>[];
      final repo = StatsRepository(
        () => testDataApi((req) async {
          requests.add(req);
          return http.Response('', 200, headers: {'content-range': '*/437'});
        }),
      );

      final result = await repo.getTotalSolved('u-1');

      expect((result as Success<int, Object>).data, 437);
      final req = requests.single;
      expect(req.method, 'HEAD');
      expect(req.url.path, endsWith('/puzzle_attempts'));
      expect(req.url.queryParameters['user_id'], 'eq.u-1');
      expect(req.url.queryParameters['completed'], 'eq.true');
      expect(
        req.headers['Prefer'] ?? req.headers['prefer'],
        contains('count=exact'),
      );
    },
  );
}
