import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/domain/progression/coin_economy.dart';
import 'package:word_search_master/domain/progression/economy_simulation.dart';

/// P11 acceptance criterion 3: "coins economy 20 levels simulate karne par
/// ~har 4th level par khatam hoti hai" — simulating 20 levels, a typical
/// player runs low roughly every 4th level.
///
/// ---------------------------------------------------------------------------
/// WHY THE ASSERTION IS AN AGGREGATE, NOT ONE 20-LEVEL RUN
///
/// A single 20-level run draws ~18 hint demands from a distribution, and its
/// dry-level count swings between 3 and 6 purely on the seed. Pinning one seed
/// would produce a test that passes for exactly one tuning and says nothing
/// about the economy — and picking the seed that happens to give 5 would be
/// choosing the answer first.
///
/// So the primary assertion runs 400 independent 20-level players and measures
/// the ECONOMY: levels per dry level across all of them. The distribution of
/// single runs is then asserted separately, as a median, which is the honest
/// way to say "a typical 20-level run looks like this".
void main() {
  group('coinsForLevel', () {
    test('base plus a star bonus', () {
      const economy = CoinEconomy.defaults;

      expect(economy.coinsForLevel(stars: 0), economy.levelBaseCoins);
      expect(
        economy.coinsForLevel(stars: 3),
        economy.levelBaseCoins + 3 * economy.coinsPerStar,
      );
    });

    test('more stars always pays more — the hint has a second cost', () {
      const economy = CoinEconomy.defaults;
      var previous = -1;
      for (var stars = 0; stars <= 3; stars++) {
        final coins = economy.coinsForLevel(stars: stars);
        expect(coins, greaterThan(previous));
        previous = coins;
      }
    });
  });

  group('chests', () {
    test('awarded every chestEveryNLevels-th level', () {
      const economy = CoinEconomy.defaults;

      expect(economy.awardsChest(5), isTrue);
      expect(economy.awardsChest(10), isTrue);
      expect(economy.awardsChest(300), isTrue);
      expect(economy.awardsChest(4), isFalse);
      expect(economy.awardsChest(6), isFalse);
      expect(economy.awardsChest(0), isFalse);
    });

    test('a zero cadence disables chests rather than dividing by zero', () {
      final off = CoinEconomy.defaults.copyWith(chestEveryNLevels: 0);

      for (var level = 1; level <= 50; level++) {
        expect(off.awardsChest(level), isFalse);
      }
    });

    test('Ch02s 20-200 payout range, never outside it', () {
      const economy = CoinEconomy.defaults;
      expect(economy.chestPayoutRange, (20, 200));

      final random = Random(20260827);
      for (var i = 0; i < 5000; i++) {
        final reward = economy.rollChest(random);
        expect(reward.coins, greaterThanOrEqualTo(20));
        expect(reward.coins, lessThanOrEqualTo(200));
      }
    });

    test('the same seed rolls the same chest', () {
      const economy = CoinEconomy.defaults;

      final a = economy.rollChest(Random(7));
      final b = economy.rollChest(Random(7));

      expect(a, b);
    });

    test('the weights actually bias the draw toward the common tier', () {
      const economy = CoinEconomy.defaults;
      final random = Random(1234);
      final counts = <String, int>{};

      for (var i = 0; i < 20000; i++) {
        final reward = economy.rollChest(random);
        counts[reward.tier.id] = (counts[reward.tier.id] ?? 0) + 1;
      }

      // 40 / 35 / 20 / 5 in the default table.
      expect(counts['common']!, greaterThan(counts['uncommon']!));
      expect(counts['uncommon']!, greaterThan(counts['rare']!));
      expect(counts['rare']!, greaterThan(counts['legendary']!));
      expect(
        counts['legendary']! / 20000,
        closeTo(0.05, 0.02),
        reason: 'the top band has to stay rare to stay worth watching',
      );
    });

    test('a broken table degrades instead of throwing', () {
      final broken = CoinEconomy.defaults.copyWith(
        chestTable: const [
          ChestTier(id: 'zero', minCoins: 20, maxCoins: 40, weight: 0),
        ],
      );

      final reward = broken.rollChest(Random(1));
      expect(reward.coins, inInclusiveRange(20, 40));
    });
  });

  group('THE ACCEPTANCE CRITERION — a typical player runs low every ~4 levels', () {
    test('measured across 400 twenty-level runs', () {
      final levelsPerDry = EconomySimulation.meanLevelsPerDryLevel(
        levelCount: 20,
        runs: 400,
      );

      expect(
        levelsPerDry,
        inInclusiveRange(3.5, 4.5),
        reason:
            'Ch02 asks for roughly every 4th level. Measured $levelsPerDry — '
            'retune CoinEconomy.defaults if this drifts, do not widen the band',
      );
    });

    test('the median 20-level run has 4-6 dry levels', () {
      final dryCounts = <int>[
        for (var i = 0; i < 400; i++)
          EconomySimulation.run(
            levelCount: 20,
            seed: 20260826 + i,
          ).levelsRunLow,
      ]..sort();

      expect(dryCounts[200], inInclusiveRange(4, 6));
    });

    test(
      'the wallet oscillates — it neither drains to nothing nor runs away',
      () {
        final finals = <int>[
          for (var i = 0; i < 400; i++)
            EconomySimulation.run(
              levelCount: 20,
              seed: 20260826 + i,
            ).finalBalance,
        ]..sort();

        final median = finals[200];
        expect(
          median,
          inInclusiveRange(20, 400),
          reason:
              'a median run ending near zero is a paywall; one ending in the '
              'thousands is a faucet and P18s rewarded ad has nothing to sell',
        );
      },
    );
  });

  group('the simulation reacts to the levers it is given', () {
    test('a player who never hints never runs low', () {
      final result = EconomySimulation.run(
        profile: PlayerProfile.selfSufficient,
        levelCount: 20,
      );

      expect(result.levelsRunLow, 0);
      expect(result.levelsPerDryLevel, double.infinity);
      expect(result.meanStars, 3.0, reason: 'no hints means three stars');
    });

    test('a hint-hungry player runs low far more often than a typical one', () {
      final hungry = EconomySimulation.meanLevelsPerDryLevel(
        profile: PlayerProfile.hintHungry,
        levelCount: 20,
        runs: 200,
      );
      final typical = EconomySimulation.meanLevelsPerDryLevel(
        levelCount: 20,
        runs: 200,
      );

      expect(hungry, lessThan(typical));
      expect(hungry, lessThan(2.5));
    });

    test('a cheaper hint means fewer dry levels', () {
      final cheap = EconomySimulation.meanLevelsPerDryLevel(
        economy: CoinEconomy.defaults.copyWith(hintCostCoins: 20),
        levelCount: 20,
        runs: 200,
      );
      final normal = EconomySimulation.meanLevelsPerDryLevel(
        levelCount: 20,
        runs: 200,
      );

      expect(
        cheap,
        greaterThan(normal),
        reason: 'the hint_cost_coins lever has to actually move the economy',
      );
    });

    test('turning chests off makes the economy meaner', () {
      final noChests = EconomySimulation.meanLevelsPerDryLevel(
        economy: CoinEconomy.defaults.copyWith(chestEveryNLevels: 0),
        levelCount: 20,
        runs: 200,
      );
      final normal = EconomySimulation.meanLevelsPerDryLevel(
        levelCount: 20,
        runs: 200,
      );

      expect(noChests, lessThan(normal));
    });

    test('is deterministic in its seed', () {
      final a = EconomySimulation.run(seed: 99);
      final b = EconomySimulation.run(seed: 99);

      expect(a.levelsRunLow, b.levelsRunLow);
      expect(a.finalBalance, b.finalBalance);
    });

    test('the starter grant covers exactly one hint', () {
      const economy = CoinEconomy.defaults;
      expect(economy.starterGrantCoins, economy.hintCostCoins);

      // So a player who wants a hint on level 1 can always afford it — the
      // cost of a hint is learned by using one, not by reading a number.
      final result = EconomySimulation.run(
        profile: PlayerProfile.hintHungry,
        levelCount: 1,
        seed: 3,
      );
      expect(result.levels.first.hintsTaken, greaterThanOrEqualTo(1));
    });
  });
}
