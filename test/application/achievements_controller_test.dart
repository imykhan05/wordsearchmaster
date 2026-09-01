import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/application/achievements_controller.dart';
import 'package:word_search_master/data/remote/user_stats_api.dart';
import 'package:word_search_master/domain/progression/achievements.dart';
import 'package:word_search_master/domain/text/language.dart';
import 'package:word_search_master/services/auth/auth_service.dart';
import 'package:word_search_master/services/settings/ui_settings_store.dart';

/// The P17 popup queue: two sources (the server diff, Collector's local
/// enqueue from `game_screen.dart`) feed one FIFO, and "have I shown this"
/// is checked BEFORE enqueueing so a duplicate never queues twice either.
void main() {
  ProviderContainer harness({
    required AuthService auth,
    required UserStatsApi userStats,
    UiSettingsStore? settings,
  }) {
    final container = ProviderContainer(
      overrides: [
        authServiceProvider.overrideWithValue(auth),
        userStatsApiProvider.overrideWithValue(userStats),
        uiSettingsStoreProvider.overrideWithValue(
          settings ?? InMemoryUiSettingsStore(),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('AchievementPopupQueue', () {
    test('enqueueIfUnseen adds to the back', () {
      final container = harness(
        auth: const _FakeAuth(null),
        userStats: const NoopUserStatsApi(),
      );
      final notifier = container.read(achievementPopupQueueProvider.notifier);

      notifier.enqueueIfUnseen(
        const NamedAchievementUnlock(AchievementId.firstWord),
      );
      notifier.enqueueIfUnseen(
        const NamedAchievementUnlock(AchievementId.wordMaster),
      );

      expect(container.read(achievementPopupQueueProvider), [
        const NamedAchievementUnlock(AchievementId.firstWord),
        const NamedAchievementUnlock(AchievementId.wordMaster),
      ]);
    });

    test('skips an id already marked seen', () {
      final settings = InMemoryUiSettingsStore(
        seenAchievementPopupIds: {'first_word'},
      );
      final container = harness(
        auth: const _FakeAuth(null),
        userStats: const NoopUserStatsApi(),
        settings: settings,
      );

      container
          .read(achievementPopupQueueProvider.notifier)
          .enqueueIfUnseen(
            const NamedAchievementUnlock(AchievementId.firstWord),
          );

      expect(container.read(achievementPopupQueueProvider), isEmpty);
    });

    test('skips a duplicate already sitting in the queue', () {
      final container = harness(
        auth: const _FakeAuth(null),
        userStats: const NoopUserStatsApi(),
      );
      final notifier = container.read(achievementPopupQueueProvider.notifier);

      notifier.enqueueIfUnseen(
        const NamedAchievementUnlock(AchievementId.onFire),
      );
      notifier.enqueueIfUnseen(
        const NamedAchievementUnlock(AchievementId.onFire),
      );

      expect(container.read(achievementPopupQueueProvider), hasLength(1));
    });

    test('a Collector unlock and a named unlock never collide by id', () {
      final container = harness(
        auth: const _FakeAuth(null),
        userStats: const NoopUserStatsApi(),
      );
      final notifier = container.read(achievementPopupQueueProvider.notifier);

      notifier.enqueueIfUnseen(
        const CollectorAchievementUnlock(
          category: 'animals',
          language: Language.english,
        ),
      );
      notifier.enqueueIfUnseen(
        const NamedAchievementUnlock(AchievementId.firstWord),
      );

      expect(container.read(achievementPopupQueueProvider), hasLength(2));
    });

    test(
      'dismissCurrent marks the front seen and advances the queue',
      () async {
        final settings = InMemoryUiSettingsStore();
        final container = harness(
          auth: const _FakeAuth(null),
          userStats: const NoopUserStatsApi(),
          settings: settings,
        );
        final notifier = container.read(achievementPopupQueueProvider.notifier);
        notifier.enqueueIfUnseen(
          const NamedAchievementUnlock(AchievementId.firstWord),
        );
        notifier.enqueueIfUnseen(
          const NamedAchievementUnlock(AchievementId.wordMaster),
        );

        await notifier.dismissCurrent();

        expect(settings.seenAchievementPopupIds, {'first_word'});
        expect(container.read(achievementPopupQueueProvider), [
          const NamedAchievementUnlock(AchievementId.wordMaster),
        ]);
      },
    );

    test('dismissCurrent on an empty queue is a no-op', () async {
      final container = harness(
        auth: const _FakeAuth(null),
        userStats: const NoopUserStatsApi(),
      );

      await container
          .read(achievementPopupQueueProvider.notifier)
          .dismissCurrent();

      expect(container.read(achievementPopupQueueProvider), isEmpty);
    });
  });

  group('achievementPopupSync', () {
    test('diffs the live stream, enqueueing only the six named ids', () async {
      final userStats = _FakeUserStats({'first_word', 'trilingual'});
      final container = harness(
        auth: const _FakeAuth(AuthAccount(uid: 'u1', isAnonymous: true)),
        userStats: userStats,
      );

      container.listen(achievementPopupSyncProvider, (_, _) {});
      await pumpEventQueue();

      expect(
        container.read(achievementPopupQueueProvider).map((u) => u.popupId),
        containsAll(['first_word', 'trilingual']),
      );
    });

    test(
      'a Collector-shaped id from the server is never enqueued here',
      () async {
        // Never actually written by the server (P17's stats map only holds
        // the six named ids), but the diff must stay defensive: an id this
        // build cannot parse has no card to show, so it is silently dropped
        // rather than crashing the sync.
        final userStats = _FakeUserStats({'collection:en:animals'});
        final container = harness(
          auth: const _FakeAuth(AuthAccount(uid: 'u1', isAnonymous: true)),
          userStats: userStats,
        );

        container.listen(achievementPopupSyncProvider, (_, _) {});
        await pumpEventQueue();

        expect(container.read(achievementPopupQueueProvider), isEmpty);
      },
    );

    test('no signed-in account means no diff and no crash', () async {
      final container = harness(
        auth: const _FakeAuth(null),
        userStats: _FakeUserStats(const {'first_word'}),
      );

      container.listen(achievementPopupSyncProvider, (_, _) {});
      await pumpEventQueue();

      expect(container.read(achievementPopupQueueProvider), isEmpty);
    });
  });
}

final class _FakeAuth implements AuthService {
  const _FakeAuth(this._account);

  final AuthAccount? _account;

  @override
  AuthAccount? get currentAccount => _account;

  @override
  Stream<AuthAccount?> watchAccount() =>
      _account == null ? const Stream.empty() : Stream.value(_account);

  @override
  Future<AuthAccount?> ensureSignedIn() async => _account;

  @override
  Future<LinkOutcome> linkWithGoogle() async => const LinkCancelled();

  @override
  Future<AuthAccount?> signOut() async => _account;
}

final class _FakeUserStats implements UserStatsApi {
  const _FakeUserStats(this._ids);

  final Set<String> _ids;

  @override
  Stream<Set<String>> watchAchievementIds(String uid) => Stream.value(_ids);

  @override
  Future<int?> fetchRank(String uid, String board) async => null;
}
