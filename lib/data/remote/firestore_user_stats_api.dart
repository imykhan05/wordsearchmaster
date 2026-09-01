import 'package:cloud_firestore/cloud_firestore.dart';

import '../../services/diagnostics/error_reporter.dart';
import 'user_stats_api.dart';

/// The real [UserStatsApi].
///
/// Reads exactly the two sub-shapes of `users/{uid}` P17's server owns:
/// `stats.achievements` (a map keyed by achievement id, written by
/// `recordSubmission`/`recordAchievementClaim`) and `stats.ranks.{board}`
/// (written by `recomputeLeaderboardRanks`, P17's periodic job). Both degrade
/// on any read failure — offline, permission-denied, App Check refused — the
/// same direction `FirestoreAccountRepository` already degrades in: an empty
/// achievement set and a null rank are both "nothing to show", never a crash
/// on a screen the player is only glancing at.
final class FirestoreUserStatsApi implements UserStatsApi {
  const FirestoreUserStatsApi({
    required FirebaseFirestore firestore,
    required ErrorReporter reporter,
    // ignore: prefer_initializing_formals
  }) : _firestore = firestore,
       // ignore: prefer_initializing_formals
       _reporter = reporter;

  final FirebaseFirestore _firestore;
  final ErrorReporter _reporter;

  static const String _collection = 'users';

  @override
  Stream<Set<String>> watchAchievementIds(String uid) {
    return _firestore
        .collection(_collection)
        .doc(uid)
        .snapshots()
        .map((doc) => _decodeAchievementIds(doc.data()))
        .handleError((Object error, StackTrace stackTrace) {
          _reporter.nonFatal(
            error,
            stackTrace: stackTrace,
            context: const {'stage': 'userStats.watchAchievementIds'},
          );
        });
  }

  @override
  Future<int?> fetchRank(String uid, String board) async {
    try {
      final doc = await _firestore.collection(_collection).doc(uid).get();
      final stats = doc.data()?['stats'];
      if (stats is! Map) return null;
      final ranks = stats['ranks'];
      if (ranks is! Map) return null;
      final rank = ranks[board];
      return switch (rank) {
        final int value => value,
        final double value => value.round(),
        _ => null,
      };
    } catch (error, stackTrace) {
      _reporter.nonFatal(
        error,
        stackTrace: stackTrace,
        context: const {'stage': 'userStats.fetchRank'},
      );
      return null;
    }
  }

  static Set<String> _decodeAchievementIds(Map<String, Object?>? document) {
    final stats = document?['stats'];
    if (stats is! Map) return const {};
    final achievements = stats['achievements'];
    if (achievements is! Map) return const {};
    return achievements.keys.whereType<String>().toSet();
  }
}
