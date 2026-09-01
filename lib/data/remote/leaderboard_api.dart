/// Live reads of `leaderboards/{board}/entries` (P17).
///
/// ---------------------------------------------------------------------------
/// LIVE ONLY ON THE VISIBLE TAB, AND THAT IS THE WHOLE POINT OF THIS SEAM
///
/// "Snapshot listeners left running are the main cause of surprise Firestore
/// bills" is the prompt's own words. [watchTop] returns a `Stream`, and a
/// Riverpod `autoDispose` family provider is what actually closes it — this
/// interface just has to make sure nothing here keeps a subscription alive on
/// its own once nobody is watching the stream, which a plain `snapshots()`
/// map already guarantees (Firestore itself unsubscribes when the last
/// listener on a `StreamSubscription` cancels).
///
/// ---------------------------------------------------------------------------
/// TOP-100 IS LIVE; A PLAYER'S OWN RANK IS ONE-SHOT
///
/// [fetchOwnEntry] is deliberately `Future`, not `Stream` — a rank is only
/// ever as fresh as P17's `recomputeLeaderboardRanks` periodic job
/// (`functions/src/ranks.ts`), so a live listener on it would hold a
/// connection open for a number that moves at most every 15 minutes. See
/// `SECURITY.md`'s AR-10.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../repositories/leaderboard_cache.dart';

part 'leaderboard_api.g.dart';

abstract interface class LeaderboardApi {
  /// The top [limit] entries of [board], ordered by score descending — the
  /// SAME order `recomputeRanksForBoard` assigns ranks in, so a row's
  /// position in this list plus one is its rank whenever it appears here.
  Stream<List<LeaderboardEntry>> watchTop(String board, {int limit = 100});

  /// [uid]'s own entry on [board] — score, display name and the last
  /// computed rank — or null when they have no entry on it yet.
  Future<LeaderboardEntry?> fetchOwnEntry(String uid, String board);
}

/// No board, ever. The binding whenever Firebase is unavailable — the same
/// code path as airplane mode (P13).
final class NoopLeaderboardApi implements LeaderboardApi {
  const NoopLeaderboardApi();

  @override
  Stream<List<LeaderboardEntry>> watchTop(String board, {int limit = 100}) =>
      const Stream.empty();

  @override
  Future<LeaderboardEntry?> fetchOwnEntry(String uid, String board) async =>
      null;
}

/// Defaults to Noop; `bootstrap.dart` upgrades it once Firebase initialises.
@Riverpod(keepAlive: true)
LeaderboardApi leaderboardApi(Ref ref) => const NoopLeaderboardApi();
