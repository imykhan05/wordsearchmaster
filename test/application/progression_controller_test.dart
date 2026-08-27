import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/application/game_controller.dart';
import 'package:word_search_master/application/progression_controller.dart';
import 'package:word_search_master/data/content/content_repository.dart';
import 'package:word_search_master/data/local/app_database.dart';
import 'package:word_search_master/data/local/outbox_kind.dart';
import 'package:word_search_master/data/repositories/coins_repository.dart';
import 'package:word_search_master/data/repositories/dda_repository.dart';
import 'package:word_search_master/data/repositories/progress_repository.dart';
import 'package:word_search_master/domain/progression/coin_economy.dart';
import 'package:word_search_master/domain/progression/day_key.dart';
import 'package:word_search_master/domain/progression/streak.dart';
import 'package:word_search_master/domain/scoring/score_event.dart';
import 'package:word_search_master/domain/text/language.dart';
import 'package:word_search_master/services/remote_config/remote_config.dart';
import 'package:word_search_master/services/time/trusted_clock.dart';

import '../support/fake_content.dart';
import '../support/local_db.dart';

/// The whole P11 award path, end to end against a real (in-memory) database:
/// one completion writes progress, credits coins, maybe rolls a chest,
/// registers the streak day and unlocks badges — and every one of those lands
/// through the repository it belongs to, not a mock.
void main() {
  final today = DayKey.parse('2026-08-26');

  /// A container wired to a real in-memory database, the fake content pack and
  /// a clock pinned to [today], so a test can assert an exact day.
  Future<(ProviderContainer, TestDatabase)> harness({DayKey? day}) async {
    final db = await openMemoryDatabase();
    final content = await buildTestContentRepository();
    final marks = InMemoryDayHighWaterMarkStore();

    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db.database),
        contentRepositoryProvider.overrideWith((ref) => content),
        trustedClockProvider.overrideWithValue(
          TrustedClock(
            marks: marks,
            localClock: () =>
                (day ?? today).utcMidnight.add(const Duration(hours: 9)),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(db.database.close);
    return (container, db);
  }

  LevelCompletionSummary summary({
    required int level,
    int stars = 3,
    int score = 200,
    int hintsUsed = 0,
    GameSession? session,
  }) => LevelCompletionSummary(
    session: session ?? JourneySession(level),
    language: Language.english,
    level: level,
    score: score,
    stars: stars,
    maxCombo: 4,
    hintsUsed: hintsUsed,
    events: const [WordFound(graphemeCount: 5)],
  );

  group('a journey completion', () {
    test('writes progress, credits coins and registers the streak', () async {
      final (container, db) = await harness();
      final controller = container.read(progressionControllerProvider.notifier);

      final reward = await controller.recordCompletion(summary(level: 1));

      // Coins: base + star bonus, from the economy the levers built.
      const economy = CoinEconomy.defaults;
      expect(reward.coinsEarned, economy.coinsForLevel(stars: 3));
      expect(reward.chest, isNull, reason: 'level 1 is not a chest level');
      expect(reward.streak.state.current, 1);
      expect(reward.streak.event, StreakEvent.started);

      // …and every one of those actually landed in the database.
      final progress = await container.read(progressRepositoryProvider.future);
      expect(await progress.completedLevels(Language.english), {1});

      final coins = await container.read(coinsRepositoryProvider.future);
      expect(await coins.watchBalance().first, reward.coinsEarned);
    });

    test('clears any pending DDA abandon streak — Ch02/P12: finishing breaks '
        'the "never manages to finish this one" pattern', () async {
      final (container, _) = await harness();
      final ddaRepo = await container.read(ddaRepositoryProvider.future);
      await ddaRepo.recordAbandon(Language.english, 1);
      expect(await ddaRepo.abandonCount(Language.english, 1), 1);

      final controller = container.read(progressionControllerProvider.notifier);
      await controller.recordCompletion(summary(level: 1));

      expect(await ddaRepo.abandonCount(Language.english, 1), 0);
    });

    test('a chest level pays the level coins PLUS the chest', () async {
      final (container, _) = await harness();
      final controller = container.read(progressionControllerProvider.notifier);

      final reward = await controller.recordCompletion(summary(level: 5));

      expect(reward.chest, isNotNull);
      expect(reward.chest!.coins, inInclusiveRange(20, 200));
      expect(
        reward.coinsEarned,
        CoinEconomy.defaults.coinsForLevel(stars: 3) + reward.chest!.coins,
      );

      final coins = await container.read(coinsRepositoryProvider.future);
      expect(await coins.watchBalance().first, reward.coinsEarned);
    });

    test('the chest is a SEPARATE ledger row, so it is traceable', () async {
      final (container, _) = await harness();
      await container
          .read(progressionControllerProvider.notifier)
          .recordCompletion(summary(level: 5));

      final coins = await container.read(coinsRepositoryProvider.future);
      final ledger = await coins.watchLedger().first;

      expect(ledger, hasLength(2));
      expect(
        ledger.map((row) => row.reason).any((r) => r.startsWith('chest:')),
        isTrue,
      );
      expect(
        ledger
            .map((row) => row.reason)
            .any((r) => r.startsWith('level_complete:')),
        isTrue,
      );
    });

    test('fewer stars pays fewer coins — the hint has a second cost', () async {
      final (container, _) = await harness();
      final controller = container.read(progressionControllerProvider.notifier);

      final threeStars = await controller.recordCompletion(
        summary(level: 1, stars: 3),
      );
      final oneStar = await controller.recordCompletion(
        summary(level: 2, stars: 1, hintsUsed: 2),
      );

      expect(oneStar.coinsEarned, lessThan(threeStars.coinsEarned));
    });

    test('queues the completion for the server to replay', () async {
      final (container, db) = await harness();
      await container
          .read(progressionControllerProvider.notifier)
          .recordCompletion(summary(level: 1));

      final outbox = await db.database.select(db.database.outbox).get();
      final kinds = outbox.map((row) => row.kind).toSet();

      expect(kinds, contains(OutboxKind.levelComplete.name));
      expect(kinds, contains(OutboxKind.coinsDelta.name));
    });
  });

  group('a daily completion', () {
    test('records the daily and pays coins, but no journey progress', () async {
      final (container, db) = await harness();

      final reward = await container
          .read(progressionControllerProvider.notifier)
          .recordCompletion(summary(level: 0, session: DailySession(today)));

      expect(reward.alreadyRecorded, isFalse);
      expect(reward.coinsEarned, CoinEconomy.defaults.coinsForLevel(stars: 3));
      expect(reward.chest, isNull, reason: 'chests are a journey reward');
      expect(reward.streak.state.current, 1);

      final progress = await container.read(progressRepositoryProvider.future);
      expect(
        await progress.completedLevels(Language.english),
        isEmpty,
        reason: 'a daily must never unlock a journey node',
      );

      final daily = await db.database.select(db.database.dailyResults).get();
      expect(daily, hasLength(1));
      expect(daily.single.date, today.toString());
    });

    test('a SECOND daily the same day pays nothing further', () async {
      final (container, _) = await harness();
      final controller = container.read(progressionControllerProvider.notifier);

      final first = await controller.recordCompletion(
        summary(level: 0, session: DailySession(today)),
      );
      final second = await controller.recordCompletion(
        summary(level: 0, session: DailySession(today)),
      );

      expect(second.alreadyRecorded, isTrue);
      expect(second.coinsEarned, 0);

      final coins = await container.read(coinsRepositoryProvider.future);
      expect(
        await coins.watchBalance().first,
        first.coinsEarned,
        reason: 'one attempt per day means one payout per day',
      );
    });

    test('a replayed daily still keeps the streak — a player replaying for fun '
        'should not lose today', () async {
      final (container, _) = await harness();
      final controller = container.read(progressionControllerProvider.notifier);

      await controller.recordCompletion(
        summary(level: 0, session: DailySession(today)),
      );
      final second = await controller.recordCompletion(
        summary(level: 0, session: DailySession(today)),
      );

      expect(second.streak.state.current, 1);
      expect(second.streak.state.lastPlayedDay, today);
    });
  });

  group('the streak advances across days', () {
    test('two consecutive days give a streak of 2', () async {
      final (day1, _) = await harness(day: today);
      await day1
          .read(progressionControllerProvider.notifier)
          .recordCompletion(summary(level: 1));

      // A second harness would use a fresh database, so drive the same one
      // through a clock that has moved on instead.
      final db = await openMemoryDatabase();
      addTearDown(db.database.close);
      final content = await buildTestContentRepository();

      Future<StreakTransition> playOn(DayKey day, int level) async {
        final container = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(db.database),
            contentRepositoryProvider.overrideWith((ref) => content),
            trustedClockProvider.overrideWithValue(
              TrustedClock(
                marks: InMemoryDayHighWaterMarkStore(),
                localClock: () => day.utcMidnight.add(const Duration(hours: 9)),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);
        final reward = await container
            .read(progressionControllerProvider.notifier)
            .recordCompletion(summary(level: level));
        return reward.streak;
      }

      expect((await playOn(today, 1)).state.current, 1);
      expect((await playOn(today.next, 2)).state.current, 2);
      expect((await playOn(today.addDays(2), 3)).state.current, 3);
    });
  });

  group('tryBuyHint', () {
    test(
      'refuses when the wallet cannot cover it, and writes nothing',
      () async {
        final (container, _) = await harness();

        final bought = await container
            .read(progressionControllerProvider.notifier)
            .tryBuyHint(const JourneySession(1));

        expect(bought, isFalse);

        final coins = await container.read(coinsRepositoryProvider.future);
        expect(await coins.watchBalance().first, 0);
        expect(await coins.watchLedger().first, isEmpty);
      },
    );

    test('spends the hint cost and reveals a hint when affordable', () async {
      final (container, _) = await harness();
      final controller = container.read(progressionControllerProvider.notifier);

      // Earn enough for a hint first: level 5 pays its coins plus a chest.
      final earned = await controller.recordCompletion(summary(level: 5));
      final balanceBefore = earned.coinsEarned;

      // The game controller has to exist for the hint to land on something.
      await container.read(
        gameControllerProvider(const JourneySession(1)).future,
      );

      final bought = await controller.tryBuyHint(const JourneySession(1));

      if (balanceBefore >= CoinEconomy.defaults.hintCostCoins) {
        expect(bought, isTrue);

        final coins = await container.read(coinsRepositoryProvider.future);
        expect(
          await coins.watchBalance().first,
          balanceBefore - CoinEconomy.defaults.hintCostCoins,
        );

        final state = container
            .read(gameControllerProvider(const JourneySession(1)))
            .value!;
        expect(state.hintsUsed, 1);
        expect(state.hintedCell, isNotNull);
      } else {
        // The chest rolled low. The refusal path is covered above; assert the
        // invariant that actually matters either way.
        expect(bought, isFalse);
      }
    });

    test('reads the hint cost from Remote Config, not a constant', () async {
      final db = await openMemoryDatabase();
      addTearDown(db.database.close);
      final content = await buildTestContentRepository();

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db.database),
          contentRepositoryProvider.overrideWith((ref) => content),
          trustedClockProvider.overrideWithValue(
            TrustedClock(
              marks: InMemoryDayHighWaterMarkStore(),
              localClock: () => today.utcMidnight,
            ),
          ),
          remoteConfigProvider.overrideWithValue(
            const OverrideRemoteConfig({'hint_cost_coins': 1}),
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(progressionControllerProvider.notifier);
      await controller.recordCompletion(summary(level: 1));
      await container.read(
        gameControllerProvider(const JourneySession(1)).future,
      );

      expect(
        await controller.tryBuyHint(const JourneySession(1)),
        isTrue,
        reason: 'a 1-coin hint is affordable on a level-1 payout',
      );

      final coins = await container.read(coinsRepositoryProvider.future);
      final ledger = await coins.watchLedger().first;
      expect(ledger.first.delta, -1);
    });
  });

  group('collection badges', () {
    test('unlock when the last level of a category is finished', () async {
      // The fake content pack is all one category ('nature') across 30
      // levels, so finishing all of them earns exactly one badge.
      final (container, _) = await harness();
      final controller = container.read(progressionControllerProvider.notifier);

      LevelReward? last;
      for (var level = 1; level <= 30; level++) {
        last = await controller.recordCompletion(summary(level: level));
        if (level < 30) {
          expect(
            last.newBadges,
            isEmpty,
            reason: 'nothing is complete until level 30',
          );
        }
      }

      expect(last!.newBadges, hasLength(1));
      expect(last.newBadges.single.category, 'nature');
      expect(last.newBadges.single.isEarned, isTrue);
    });

    test('REPLAYING a level in a finished category does not re-fire', () async {
      final (container, _) = await harness();
      final controller = container.read(progressionControllerProvider.notifier);

      for (var level = 1; level <= 30; level++) {
        await controller.recordCompletion(summary(level: level));
      }

      final replay = await controller.recordCompletion(summary(level: 1));
      expect(replay.newBadges, isEmpty);
    });
  });
}
