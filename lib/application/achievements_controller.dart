/// The unlock popup queue (P17).
///
/// ---------------------------------------------------------------------------
/// TWO SOURCES, ONE QUEUE
///
/// The six server-granted achievements (`AchievementId`) arrive on a LIVE
/// Firestore listener — `UserStatsApi.watchAchievementIds` — because the
/// outbox (Ch10) decouples playing from syncing, so the moment one crosses
/// its threshold is a server event, minutes after the level that earned it,
/// not something `GameController` can know synchronously. Collector is the
/// opposite: `ProgressionController.recordCompletion` already computes
/// `newBadges` locally, synchronously, the instant a level completes — no
/// server round trip needed to know a category shelf just filled. Both feed
/// the SAME queue so "two unlocks never overlap" (P17's own words) holds
/// regardless of which source fired.
///
/// ---------------------------------------------------------------------------
/// "HAVE I SHOWN THIS" LIVES IN `UiSettingsStore`, NOT HERE
///
/// The Firestore listener replays the FULL current achievement set on every
/// cold start — that is what a snapshot listener does. Without a seen-set,
/// a player who unlocked First Word last week would see its popup again
/// every time the app opens. [seenAchievementPopupIds] is that seen-set
/// (P17's addition to the existing UI-toggle carve-out), and it is checked
/// BEFORE enqueueing, not before dequeueing — so a duplicate stream event for
/// an id already sitting in the queue is also filtered, never shown twice in
/// one session either.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/remote/user_stats_api.dart';
import '../domain/progression/achievements.dart';
import '../domain/progression/collections.dart';
import '../domain/text/language.dart';
import '../services/auth/auth_service.dart';
import '../services/settings/ui_settings_store.dart';

part 'achievements_controller.g.dart';

/// One popup's worth of information — enough to render its card without the
/// widget needing to know which of the two sources produced it.
sealed class AchievementUnlock {
  const AchievementUnlock();

  /// The id [UiSettingsStore.markAchievementPopupSeen] records. For the six
  /// named achievements this is [AchievementId.serverId]; for Collector it is
  /// [CategoryBadge.achievementId] — the same string
  /// `functions/src/submitAchievement.ts`'s `achievementIdFor` produces.
  String get popupId;
}

final class NamedAchievementUnlock extends AchievementUnlock {
  const NamedAchievementUnlock(this.id);

  final AchievementId id;

  @override
  String get popupId => id.serverId;

  @override
  bool operator ==(Object other) =>
      other is NamedAchievementUnlock && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

final class CollectorAchievementUnlock extends AchievementUnlock {
  const CollectorAchievementUnlock({
    required this.category,
    required this.language,
  });

  final String category;
  final Language language;

  @override
  String get popupId => CategoryBadge.achievementIdFor(category, language);

  @override
  bool operator ==(Object other) =>
      other is CollectorAchievementUnlock &&
      other.category == category &&
      other.language == language;

  @override
  int get hashCode => Object.hash(category, language);
}

/// The FIFO queue driving the popup overlay. `state.first` (if any) is the
/// card currently on screen; everything after it is waiting.
@Riverpod(keepAlive: true)
class AchievementPopupQueue extends _$AchievementPopupQueue {
  @override
  List<AchievementUnlock> build() => const [];

  /// Adds [unlock] to the back of the queue, unless its popup has already
  /// been shown this install or it is already waiting in the queue.
  void enqueueIfUnseen(AchievementUnlock unlock) {
    final store = ref.read(uiSettingsStoreProvider);
    if (store.seenAchievementPopupIds.contains(unlock.popupId)) return;
    if (state.any((queued) => queued.popupId == unlock.popupId)) return;
    state = [...state, unlock];
  }

  /// Marks the currently-showing card as seen and advances the queue.
  Future<void> dismissCurrent() async {
    if (state.isEmpty) return;
    final current = state.first;
    await ref
        .read(uiSettingsStoreProvider)
        .markAchievementPopupSeen(current.popupId);
    state = state.skip(1).toList();
  }
}

/// The live achievement-id set for whoever is signed in, or an empty stream
/// before an account has resolved. Follows `currentAccountProvider` through
/// sign-out→fresh-guest and guest→linked-account: each is a different
/// `users/{uid}` document.
///
/// Reads [currentAccountProvider]'s AsyncVALUE, never its `.future` — that
/// provider's Noop binding (`NoopAuthService.watchAccount` returns
/// `Stream.empty()`) never emits at all, so awaiting `.future` hangs forever
/// and Riverpod throws on disposal ("disposed during loading state, yet no
/// value could be emitted") the moment a test tears the widget tree down
/// mid-wait. Watching the synchronous `AsyncValue` instead — this function
/// re-runs whenever it changes, which is the plain "watch inside a Stream
/// provider" pattern `currentAccountProvider` itself already uses — degrades
/// to "no uid yet" instead of hanging.
@riverpod
Stream<Set<String>> watchedAchievementIds(Ref ref) {
  final uid = ref.watch(currentAccountProvider).value?.uid;
  if (uid == null) return const Stream.empty();
  return ref.watch(userStatsApiProvider).watchAchievementIds(uid);
}

/// Diffs [watchedAchievementIdsProvider] against what has already been
/// queued or shown, and enqueues anything new.
///
/// A SEPARATE PROVIDER FROM THE QUEUE, watched once at the app root — the
/// same shape `syncTriggersProvider`/`audioMuteSyncProvider` already use
/// (P09/P16), and for the identical reason: a notifier's `build` should stay
/// free of side effects, and a bare `ProviderContainer` test that only wants
/// the queue must not also stand up a Firestore listener.
@riverpod
void achievementPopupSync(Ref ref) {
  ref.listen<AsyncValue<Set<String>>>(watchedAchievementIdsProvider, (
    previous,
    next,
  ) {
    for (final serverId in next.value ?? const {}) {
      final id = AchievementId.tryParse(serverId);
      if (id == null) continue; // A Collector id, or an id this build does
      // not know — Collector already enqueues itself from
      // `game_screen.dart`, and an unknown future id has no card to show.
      ref
          .read(achievementPopupQueueProvider.notifier)
          .enqueueIfUnseen(NamedAchievementUnlock(id));
    }
  }, fireImmediately: true);
}
