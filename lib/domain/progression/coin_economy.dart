/// The coin economy (Ch02) — earn rates, the chest table, and what a hint
/// costs.
///
/// PURE DART, and every number that decides how the economy FEELS lives on one
/// [CoinEconomy] instance rather than scattered as constants. Two reasons that
/// shape matters more than it looks like it should:
///
///   * the live-ops levers (`chest_every_n_levels`, `hint_cost_coins`) arrive
///     from Remote Config at runtime (Ch14/P20), so these cannot be `const` at
///     the call sites that read them;
///   * "tune the economy so a player runs low roughly every 4 levels" is only
///     a checkable claim if the tuning is data a simulation can be handed —
///     see `economy_simulation.dart`, which does exactly that, and
///     `coin_economy_test.dart`, which fails the build if [defaults] drifts
///     out of the target band.
///
/// ---------------------------------------------------------------------------
/// THE SCARCITY IS THE PRODUCT, NOT AN ACCIDENT
///
/// Ch02 asks for a player who runs low roughly every fourth level. That is the
/// number the whole rewarded-ad proposition in P18 rests on: an ad the player
/// WANTS is one offered at the moment they just failed to afford something
/// they wanted. Too generous and the ad is noise; too mean and the game reads
/// as a paywall and they leave. So [defaults] is tuned to sit at a small
/// per-level DEFICIT — income slightly under the cost of the hints a typical
/// player reaches for — with chests as the periodic reprieve that keeps it
/// from feeling like a slow bleed.
library;

import 'dart:math';

/// One band of the chest reward table.
final class ChestTier {
  const ChestTier({
    required this.id,
    required this.minCoins,
    required this.maxCoins,
    required this.weight,
  });

  /// Stable identifier — analytics (Ch11) and the open animation both key off
  /// this rather than off the tier's index, so reordering the table is safe.
  final String id;

  /// Inclusive bounds.
  final int minCoins;
  final int maxCoins;

  /// Relative likelihood. Only ratios matter; the table need not sum to 100.
  final int weight;

  @override
  bool operator ==(Object other) =>
      other is ChestTier &&
      other.id == id &&
      other.minCoins == minCoins &&
      other.maxCoins == maxCoins &&
      other.weight == weight;

  @override
  int get hashCode => Object.hash(id, minCoins, maxCoins, weight);

  @override
  String toString() => 'ChestTier($id: $minCoins-$maxCoins, w$weight)';
}

/// What one opened chest paid out.
final class ChestReward {
  const ChestReward({required this.tier, required this.coins});

  final ChestTier tier;
  final int coins;

  @override
  bool operator ==(Object other) =>
      other is ChestReward && other.tier == tier && other.coins == coins;

  @override
  int get hashCode => Object.hash(tier, coins);

  @override
  String toString() => 'ChestReward(${tier.id}, $coins)';
}

/// Every tunable in the economy, in one place.
final class CoinEconomy {
  const CoinEconomy({
    required this.levelBaseCoins,
    required this.coinsPerStar,
    required this.hintCostCoins,
    required this.chestEveryNLevels,
    required this.starterGrantCoins,
    required this.chestTable,
  });

  /// THE SHIPPED TUNING. Changing a number here changes how often a player
  /// hits an empty wallet — `coin_economy_test.dart` re-runs the Ch02
  /// simulation against it and fails if the result leaves the target band, so
  /// a retune is measured rather than hoped for.
  static const CoinEconomy defaults = CoinEconomy(
    // Measured, not guessed. `EconomySimulation` over 400 twenty-level runs of
    // the `typical` profile puts this pair at one dry level every 4.00 — the
    // Ch02 target — with the median run ending on ~130 coins, so the wallet
    // oscillates rather than either draining to nothing or filling forever.
    // The surface is smooth around it (perStar 4 → 3.6, perStar 6 → 4.5), so
    // this is a tuning with room either side, not a knife edge.
    levelBaseCoins: 10,
    coinsPerStar: 5,
    hintCostCoins: 50,
    chestEveryNLevels: 5,
    starterGrantCoins: 50,
    chestTable: defaultChestTable,
  );

  /// Ch02's 20–200 span, split into four bands.
  ///
  /// Weighted heavily toward the bottom on purpose: the top band is what makes
  /// opening a chest worth watching, and it only does that if it is rare. A
  /// flat 20–200 roll has the same mean but no memorable outcomes — every
  /// chest becomes "about 110" and the animation is a loading spinner.
  static const List<ChestTier> defaultChestTable = [
    ChestTier(id: 'common', minCoins: 20, maxCoins: 40, weight: 40),
    ChestTier(id: 'uncommon', minCoins: 41, maxCoins: 80, weight: 35),
    ChestTier(id: 'rare', minCoins: 81, maxCoins: 140, weight: 20),
    ChestTier(id: 'legendary', minCoins: 141, maxCoins: 200, weight: 5),
  ];

  /// Paid for finishing a level, before the star bonus.
  final int levelBaseCoins;

  /// Added per star earned (0–3).
  final int coinsPerStar;

  /// Remote Config `hint_cost_coins`, default 50.
  final int hintCostCoins;

  /// Remote Config `chest_every_n_levels`, default 5.
  final int chestEveryNLevels;

  /// Granted once, on the first level completed.
  ///
  /// Exactly one hint's worth, and that is the whole design: the player's
  /// first hint is free and the second one is not, so the cost of a hint is
  /// learned by using one rather than by reading a number.
  final int starterGrantCoins;

  final List<ChestTier> chestTable;

  CoinEconomy copyWith({
    int? levelBaseCoins,
    int? coinsPerStar,
    int? hintCostCoins,
    int? chestEveryNLevels,
    int? starterGrantCoins,
    List<ChestTier>? chestTable,
  }) => CoinEconomy(
    levelBaseCoins: levelBaseCoins ?? this.levelBaseCoins,
    coinsPerStar: coinsPerStar ?? this.coinsPerStar,
    hintCostCoins: hintCostCoins ?? this.hintCostCoins,
    chestEveryNLevels: chestEveryNLevels ?? this.chestEveryNLevels,
    starterGrantCoins: starterGrantCoins ?? this.starterGrantCoins,
    chestTable: chestTable ?? this.chestTable,
  );

  /// Coins for completing a level with [stars].
  ///
  /// Star-weighted rather than flat so a hint has a SECOND cost beyond its
  /// price: using one drops a star, which drops the payout, which makes the
  /// next hint harder to afford. That coupling is what turns the economy from
  /// a wallet into a difficulty dial.
  int coinsForLevel({required int stars}) {
    assert(stars >= 0 && stars <= 3, 'stars is 0-3, got $stars');
    return levelBaseCoins + stars * coinsPerStar;
  }

  /// Whether finishing [level] awards a chest.
  ///
  /// Level numbers are 1-based, so this is true at 5, 10, 15, … for the
  /// default cadence. A non-positive [chestEveryNLevels] (a Remote Config
  /// typo, or a deliberate "chests off") disables chests rather than dividing
  /// by zero — a live-ops lever must not be able to crash a client.
  bool awardsChest(int level) =>
      chestEveryNLevels > 0 && level > 0 && level % chestEveryNLevels == 0;

  /// Rolls one chest from [chestTable], using [random] for BOTH the tier and
  /// the amount inside it.
  ///
  /// Takes the [Random] rather than owning one, the same discipline
  /// `GridGenerator` follows: a seeded caller gets a reproducible reward,
  /// which is what makes the chest testable and what would let a future
  /// server replay a chest award to verify it (Ch08).
  ChestReward rollChest(Random random) {
    final table = chestTable.isEmpty ? defaultChestTable : chestTable;
    final totalWeight = table.fold(0, (sum, tier) => sum + max(tier.weight, 0));

    // Every weight zero or negative is a broken table; fall back to the last
    // tier rather than throwing at the moment a player taps a chest.
    if (totalWeight <= 0) {
      return _rollWithin(table.last, random);
    }

    var roll = random.nextInt(totalWeight);
    for (final tier in table) {
      roll -= max(tier.weight, 0);
      if (roll < 0) return _rollWithin(tier, random);
    }
    return _rollWithin(table.last, random);
  }

  ChestReward _rollWithin(ChestTier tier, Random random) {
    final low = min(tier.minCoins, tier.maxCoins);
    final high = max(tier.minCoins, tier.maxCoins);
    return ChestReward(tier: tier, coins: low + random.nextInt(high - low + 1));
  }

  /// The mean payout of [chestTable], for tuning and for the economy test.
  /// Not read by gameplay.
  double get meanChestCoins {
    final table = chestTable.isEmpty ? defaultChestTable : chestTable;
    final totalWeight = table.fold(0, (sum, tier) => sum + max(tier.weight, 0));
    if (totalWeight <= 0) return 0;

    var weighted = 0.0;
    for (final tier in table) {
      final midpoint = (tier.minCoins + tier.maxCoins) / 2;
      weighted += midpoint * max(tier.weight, 0);
    }
    return weighted / totalWeight;
  }

  /// The lowest and highest coins any chest can ever pay. Ch02 specifies
  /// 20–200; `coin_economy_test.dart` pins it so a table edit cannot quietly
  /// widen the range.
  (int, int) get chestPayoutRange {
    final table = chestTable.isEmpty ? defaultChestTable : chestTable;
    return (
      table.map((tier) => min(tier.minCoins, tier.maxCoins)).reduce(min),
      table.map((tier) => max(tier.minCoins, tier.maxCoins)).reduce(max),
    );
  }
}
