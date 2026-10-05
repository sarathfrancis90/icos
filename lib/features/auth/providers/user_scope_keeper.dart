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

/// Local records are per user, so when the signed-in user *id* changes from
/// one user to another every
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
      final previous = _lastUserId;
      if (id == previous) return;
      _lastUserId = id;

      // No session -> first user is not an account switch: play that happened
      // before there was a session belongs to this device's first user, and
      // storage adopts the `u.none.` records (game state included) for them.
      // Only a change away from a real user resets per-player state.
      final switched = previous != null;
      if (switched) {
        // Before any I/O, so a timer tick cannot save the old user's game
        // under the new user's prefix.
        ref.invalidate(gameNotifierProvider);
        ref.invalidate(hintUiProvider);
        ref.invalidate(scoreSubmitterProvider);
        ref.invalidate(practiceStatsNotifierProvider);
      }
      // main() has normally switched the storage scope already; this makes
      // the order certain before anything is re-read.
      await StorageService.setActiveUser(id);
      ref.read(submissionResultsVersionProvider.notifier).bump();
      ref.invalidate(statsOverviewProvider);
      ref.invalidate(solveHistoryProvider);
      ref.invalidate(streakProvider);
      ref.read(syncNotifierProvider.notifier).flush();
    });
  }
}
