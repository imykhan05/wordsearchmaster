import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../services/diagnostics/error_reporter.dart';
import '../local/app_database.dart';
import '../local/tables.dart';
import 'local_repository.dart';

part 'leaderboard_cache.g.dart';

/// The last leaderboard the device successfully read, kept for offline display
/// (Ch10 / P16).
///
/// ---------------------------------------------------------------------------
/// WHY A CACHE AND NOT AN EMPTY STATE
///
/// Ch10's rule is that the leaderboard shows CACHED DATA plus a "last updated"
/// timestamp when offline — not a spinner, not an error, and not an empty
/// list. The reasoning is the same one that drives the whole chapter: for this
/// audience, offline is the normal case, so a screen that only works online is
/// a screen that mostly does not work. Yesterday's standings answer almost
/// every question a player opens this screen to ask, and the timestamp is what
/// makes showing them honest rather than misleading.
///
/// ---------------------------------------------------------------------------
/// WHAT P16 OWNS HERE, AND WHAT IT DOES NOT
///
/// This class is the STORE and the staleness stamp. Fetching the board from
/// Firestore and deciding how often to refresh belong to the leaderboard
/// prompt (P17) — so nothing in this build writes it during normal play, and
/// that is deliberate rather than unfinished: P16's job is that the offline
/// path exists, is tested, and cannot show a dialog.
///
/// ---------------------------------------------------------------------------
/// A `kv_settings` ROW, NOT AN EIGHTH TABLE
///
/// The same carve-out `KvKeys.streakState` already uses, and for the same
/// reason: one value with no key space to query buys nothing from a table and
/// costs a schema migration. It carries an integrity tag like every other row,
/// so a forged cache reads as ABSENT (the Ch10 rule for a failed check) rather
/// than putting a fabricated name at the top of a board — a display-only lie,
/// but one the player would screenshot.
final class LeaderboardCache extends LocalRepository {
  LeaderboardCache({
    required super.database,
    required super.integrity,
    required super.reporter,
    super.clock,
  });

  /// The cached snapshot for [board], or null when there is none.
  Future<CachedLeaderboard?> read(String board) async {
    final raw = await readKv(_keyFor(board));
    if (raw == null) return null;
    return CachedLeaderboard.tryDecode(board, raw);
  }

  /// Replaces the cached snapshot for [board].
  Future<void> write(CachedLeaderboard snapshot) =>
      writeKv(_keyFor(snapshot.board), snapshot.encode());

  static String _keyFor(String board) =>
      '${KvKeys.leaderboardCachePrefix}$board';
}

/// One board as it was last seen.
final class CachedLeaderboard {
  const CachedLeaderboard({
    required this.board,
    required this.entries,
    required this.fetchedAtMillis,
  });

  final String board;
  final List<LeaderboardEntry> entries;

  /// When this copy was read from the server. Rendered as a RELATIVE time —
  /// the number the player needs is "is this stale", not a wall-clock stamp
  /// they would have to subtract from.
  final int fetchedAtMillis;

  String encode() => jsonEncode({
    'fetchedAt': fetchedAtMillis,
    'entries': [
      for (final entry in entries)
        {
          'uid': entry.uid,
          if (entry.displayName != null) 'displayName': entry.displayName,
          'score': entry.score,
        },
    ],
  });

  /// Decodes, or null if the row cannot be read.
  ///
  /// Null rather than a throw, and every field degrades: a cache written by a
  /// newer build must fail to a "no cached copy" screen, never to a crash on
  /// a screen the player only opened to look at some numbers.
  static CachedLeaderboard? tryDecode(String board, String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final fetchedAt = decoded['fetchedAt'];
      final entries = decoded['entries'];
      if (fetchedAt is! int || entries is! List) return null;

      return CachedLeaderboard(
        board: board,
        fetchedAtMillis: fetchedAt,
        entries: [
          for (final entry in entries)
            if (entry is Map && entry['uid'] is String && entry['score'] is int)
              LeaderboardEntry(
                uid: entry['uid']! as String,
                displayName: entry['displayName'] is String
                    ? entry['displayName']! as String
                    : null,
                score: entry['score']! as int,
              ),
        ],
      );
    } on FormatException {
      return null;
    }
  }
}

/// One row of a board.
///
/// Deliberately the SAME five-field shape `updateLeaderboards` publishes,
/// minus `photoUrl` and `updatedAt`, which nothing on this screen renders yet.
/// Storing fields no screen shows would be caching PII for no reason.
final class LeaderboardEntry {
  const LeaderboardEntry({
    required this.uid,
    required this.score,
    this.displayName,
  });

  final String uid;
  final String? displayName;
  final int score;

  @override
  bool operator ==(Object other) =>
      other is LeaderboardEntry &&
      other.uid == uid &&
      other.displayName == displayName &&
      other.score == score;

  @override
  int get hashCode => Object.hash(uid, displayName, score);

  @override
  String toString() => 'LeaderboardEntry($uid, $displayName, $score)';
}

@Riverpod(keepAlive: true)
Future<LeaderboardCache> leaderboardCache(Ref ref) async => LeaderboardCache(
  database: ref.watch(appDatabaseProvider),
  integrity: await ref.watch(rowIntegrityProvider.future),
  reporter: ref.watch(errorReporterProvider),
);

/// The global board's cached copy, for the leaderboard screen.
@riverpod
Future<CachedLeaderboard?> cachedGlobalLeaderboard(Ref ref) async {
  final cache = await ref.watch(leaderboardCacheProvider.future);
  return cache.read('global');
}
