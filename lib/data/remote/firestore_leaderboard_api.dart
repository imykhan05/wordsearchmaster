import 'package:cloud_firestore/cloud_firestore.dart';

import '../../services/diagnostics/error_reporter.dart';
import '../repositories/leaderboard_cache.dart';
import 'leaderboard_api.dart';

/// The real [LeaderboardApi].
final class FirestoreLeaderboardApi implements LeaderboardApi {
  const FirestoreLeaderboardApi({
    required FirebaseFirestore firestore,
    required ErrorReporter reporter,
    // ignore: prefer_initializing_formals
  }) : _firestore = firestore,
       // ignore: prefer_initializing_formals
       _reporter = reporter;

  final FirebaseFirestore _firestore;
  final ErrorReporter _reporter;

  static const String _collection = 'leaderboards';
  static const String _entries = 'entries';

  @override
  Stream<List<LeaderboardEntry>> watchTop(String board, {int limit = 100}) {
    return _firestore
        .collection(_collection)
        .doc(board)
        .collection(_entries)
        .orderBy('score', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => [
            for (final doc in snapshot.docs) _decode(doc.id, doc.data()),
          ],
        )
        .handleError((Object error, StackTrace stackTrace) {
          _reporter.nonFatal(
            error,
            stackTrace: stackTrace,
            context: {'stage': 'leaderboard.watchTop', 'board': board},
          );
        });
  }

  @override
  Future<LeaderboardEntry?> fetchOwnEntry(String uid, String board) async {
    try {
      final doc = await _firestore
          .collection(_collection)
          .doc(board)
          .collection(_entries)
          .doc(uid)
          .get();
      final data = doc.data();
      if (data == null) return null;
      return _decode(uid, data);
    } catch (error, stackTrace) {
      _reporter.nonFatal(
        error,
        stackTrace: stackTrace,
        context: {'stage': 'leaderboard.fetchOwnEntry', 'board': board},
      );
      return null;
    }
  }

  static LeaderboardEntry _decode(String uid, Map<String, Object?> data) {
    final score = data['score'];
    final displayName = data['displayName'];
    final rank = data['rank'];
    return LeaderboardEntry(
      uid: uid,
      score: switch (score) {
        final int value => value,
        final double value => value.round(),
        _ => 0,
      },
      displayName: displayName is String && displayName.isNotEmpty
          ? displayName
          : null,
      rank: switch (rank) {
        final int value => value,
        final double value => value.round(),
        _ => null,
      },
    );
  }
}
