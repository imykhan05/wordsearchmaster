/// Reads the server-authored halves of `users/{uid}` (P17): the achievement
/// map `recordSubmission`/`submitAchievement` write, and the ranks
/// `recomputeLeaderboardRanks` writes.
///
/// Interface + Noop + real, the same shape `CloudAccountRepository` (P13)
/// already uses — so a widget test can pump a screen that reads either
/// without a Firestore plugin, and `bootstrap.dart` overrides the Noop only
/// once Firebase actually initialised.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'user_stats_api.g.dart';

abstract interface class UserStatsApi {
  /// LIVE. The achievement ids [uid] currently holds, keyed exactly as
  /// `functions/src/stats.ts`'s `ACHIEVEMENTS` map and
  /// `submitAchievement.ts`'s `achievementIdFor` produce them.
  ///
  /// A stream because an achievement can unlock asynchronously, minutes after
  /// the level that earned it — the outbox (Ch10) decouples playing from
  /// syncing, so "the moment it happens" is a server event, not a client one.
  Stream<Set<String>> watchAchievementIds(String uid);

  /// ONE-SHOT. [uid]'s rank on [board], or null if it has never been
  /// computed (a board `recomputeLeaderboardRanks` has not reached yet, or a
  /// player with no score on it at all).
  ///
  /// Not a stream: a rank is only ever as fresh as the last periodic run
  /// (`ranks.ts`'s own header — SECURITY.md's AR-10), so a live listener would
  /// buy nothing beyond the cost of holding one open.
  Future<int?> fetchRank(String uid, String board);
}

final class NoopUserStatsApi implements UserStatsApi {
  const NoopUserStatsApi();

  @override
  Stream<Set<String>> watchAchievementIds(String uid) => const Stream.empty();

  @override
  Future<int?> fetchRank(String uid, String board) async => null;
}

/// Defaults to Noop; `bootstrap.dart` upgrades it once Firebase initialises,
/// the same way it upgrades `CloudAccountRepository`.
@Riverpod(keepAlive: true)
UserStatsApi userStatsApi(Ref ref) => const NoopUserStatsApi();
