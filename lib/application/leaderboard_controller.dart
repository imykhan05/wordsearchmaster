/// The leaderboard screen's data providers (P17).
///
/// ---------------------------------------------------------------------------
/// AUTODISPOSE IS THE WHOLE MECHANISM, NOT AN OPTIMISATION
///
/// "Snapshot listeners left running are the main cause of surprise Firestore
/// bills" (the prompt's own words) is why [leaderboardTopProvider] is a
/// PLAIN `@riverpod` family — no `keepAlive` — rather than the `keepAlive:
/// true` every other provider in this codebase reaches for by default. The
/// moment the widget watching a given board id stops watching (the tab is
/// switched, or the screen is left), Riverpod tears the provider down, which
/// cancels the underlying `StreamSubscription` and — because
/// `FirestoreLeaderboardApi.watchTop` is a bare `snapshots()` map with
/// nothing else holding a reference — closes the Firestore listener with it.
/// `LeaderboardScreen` reinforces this from the other side: it deliberately
/// does NOT use `TabBarView` (whose `PageView` keeps off-screen children
/// built for swipe smoothness), so at most one board's provider is ever
/// watched at once.
///
/// ---------------------------------------------------------------------------
/// A LIVE READ WRITES THROUGH TO THE OFFLINE CACHE
///
/// Every snapshot [leaderboardTopProvider] receives is mirrored into
/// `LeaderboardCache` (P16) — best-effort, fire-and-forget, the same
/// "nothing waits on it" shape the outbox drain uses. That is what makes
/// `cachedLeaderboardProvider` (the fallback the screen reads while offline
/// or before the first live snapshot lands) a genuinely LAST-SEEN copy rather
/// than permanently empty on a build that never had P16's own writer.
library;

import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/remote/leaderboard_api.dart';
import '../data/repositories/leaderboard_cache.dart';
import '../services/auth/auth_service.dart';

part 'leaderboard_controller.g.dart';

/// LIVE top 100 of [board]. AutoDispose — see the file header.
@riverpod
Stream<List<LeaderboardEntry>> leaderboardTop(Ref ref, String board) {
  final cacheFuture = ref.watch(leaderboardCacheProvider.future);
  return ref.watch(leaderboardApiProvider).watchTop(board).map((entries) {
    if (entries.isNotEmpty) {
      unawaited(
        cacheFuture.then(
          (cache) => cache.write(
            CachedLeaderboard(
              board: board,
              entries: entries,
              fetchedAtMillis: DateTime.now().millisecondsSinceEpoch,
            ),
          ),
        ),
      );
    }
    return entries;
  });
}

/// ONE-SHOT: the signed-in player's own entry (score, display name, last
/// computed rank) on [board], or null with no account or no entry yet.
/// Never live — see `LeaderboardApi.fetchOwnEntry`'s own header for why.
@riverpod
Future<LeaderboardEntry?> ownLeaderboardEntry(Ref ref, String board) async {
  final uid = ref.watch(currentAccountProvider).value?.uid;
  if (uid == null) return null;
  return ref.watch(leaderboardApiProvider).fetchOwnEntry(uid, board);
}
