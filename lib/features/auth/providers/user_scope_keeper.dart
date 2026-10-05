import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/services/storage_service.dart';
import '../../../core/services/sync_service.dart';
import '../../practice/providers/practice_provider.dart';
import '../../puzzle/providers/game_provider.dart';
import '../../puzzle/providers/puzzle_result_provider.dart';
import '../../puzzle/providers/score_submission_provider.dart';
import '../../stats/providers/stats_provider.dart';
import 'auth_provider.dart';

part 'user_scope_keeper.g.dart';

/// Local records are per user, so when the signed-in user *id* changes every
/// provider that caches per-player state must start over: results, stats,
/// streak, the kept-alive game / hint / score-submitter state and practice
/// stats. Events that keep the same id (linkIdentity, updateUser, token
/// refresh) change nothing, so in-progress play survives linking a guest.
///
/// Instantiated once at app start.
@Riverpod(keepAlive: true)
class UserScopeKeeper extends _$UserScopeKeeper {
  String? _lastUserId;

  @override
  void build() {
    _lastUserId = StorageService.activeUserId;
    ref.listen(authStateChangesProvider, (prev, next) async {
      final id = next.valueOrNull?.session?.user.id;
      if (id == _lastUserId) return;
      _lastUserId = id;
      // main() has normally switched the storage scope already; this makes
      // the order certain before anything is invalidated and re-read.
      await StorageService.setActiveUser(id);
      ref.invalidate(gameNotifierProvider);
      ref.invalidate(hintUiProvider);
      ref.invalidate(scoreSubmitterProvider);
      ref.invalidate(practiceStatsNotifierProvider);
      ref.read(submissionResultsVersionProvider.notifier).bump();
      ref.invalidate(statsOverviewProvider);
      ref.invalidate(solveHistoryProvider);
      ref.invalidate(streakProvider);
      ref.read(syncNotifierProvider.notifier).flush();
    });
  }
}
