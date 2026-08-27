/// A pure simulation of a player's wallet across a run of levels.
///
/// EXISTS TO MAKE ONE CLAIM CHECKABLE. Ch02 asks that the economy be tuned so
/// a typical player "runs low roughly every 4 levels". That sentence is either
/// a measurement or a wish, and the difference is this file: it replays a
/// described player against a described [CoinEconomy] and reports how often
/// they reached for a hint they could not afford.
///
/// PURE DART, deterministic in its seed, and it computes stars by calling the
/// REAL `Scoring.computeStars` rather than a local copy — a retune of the star
/// rule has to move this number too, which is exactly the coupling that should
/// exist between "how hard is a hint to earn back" and "what does a hint cost
/// you in stars".
///
/// ---------------------------------------------------------------------------
/// WHAT "RUNS LOW" MEANS HERE
///
/// Not "balance hit zero" — a player who never wants a hint can sit at zero
/// forever and feel nothing. It means the player WANTED a hint and the wallet
/// said no. That is the only moment scarcity is experienced, and it is the
/// exact moment P18's rewarded ad becomes something a player is glad to see
/// rather than something interrupting them.
library;

import 'dart:math';

import '../scoring/scoring.dart';
import 'coin_economy.dart';

/// How often a modelled player reaches for a hint.
///
/// A DISTRIBUTION, not an average: a player who wants exactly 0.9 hints every
/// level never experiences a hard level, and the whole question here is what
/// happens on the levels where they want two.
final class PlayerProfile {
  const PlayerProfile({required this.id, required this.hintDemandWeights});

  /// The Ch02 "typical player": comfortable on about a third of levels, wants
  /// one nudge on half of them, and is properly stuck on a fifth. Mean demand
  /// 0.9 hints per level.
  static const PlayerProfile typical = PlayerProfile(
    id: 'typical',
    hintDemandWeights: [30, 50, 20],
  );

  /// Never asks for help. The upper bound on how rich a player can get, and
  /// the check that the economy is not accidentally a faucet.
  static const PlayerProfile selfSufficient = PlayerProfile(
    id: 'self_sufficient',
    hintDemandWeights: [100],
  );

  /// Leans on hints hard. Should run low often — if this profile does NOT,
  /// the economy is too generous for anyone.
  static const PlayerProfile hintHungry = PlayerProfile(
    id: 'hint_hungry',
    hintDemandWeights: [10, 30, 40, 20],
  );

  final String id;

  /// `hintDemandWeights[n]` is the relative likelihood of wanting exactly `n`
  /// hints on a level.
  final List<int> hintDemandWeights;

  /// Expected hints wanted per level.
  double get meanHintDemand {
    final total = hintDemandWeights.fold(0, (sum, w) => sum + max(w, 0));
    if (total <= 0) return 0;
    var weighted = 0.0;
    for (var n = 0; n < hintDemandWeights.length; n++) {
      weighted += n * max(hintDemandWeights[n], 0);
    }
    return weighted / total;
  }

  int _drawDemand(Random random) {
    final total = hintDemandWeights.fold(0, (sum, w) => sum + max(w, 0));
    if (total <= 0) return 0;
    var roll = random.nextInt(total);
    for (var n = 0; n < hintDemandWeights.length; n++) {
      roll -= max(hintDemandWeights[n], 0);
      if (roll < 0) return n;
    }
    return hintDemandWeights.length - 1;
  }
}

/// One simulated level.
final class SimulatedLevel {
  const SimulatedLevel({
    required this.level,
    required this.balanceBefore,
    required this.hintsWanted,
    required this.hintsTaken,
    required this.stars,
    required this.levelCoins,
    required this.chest,
    required this.balanceAfter,
  });

  final int level;
  final int balanceBefore;
  final int hintsWanted;
  final int hintsTaken;
  final int stars;
  final int levelCoins;
  final ChestReward? chest;
  final int balanceAfter;

  /// Hints the player reached for and could not pay for.
  int get hintsDenied => hintsWanted - hintsTaken;

  /// THE measurement — see the library header.
  bool get ranLow => hintsDenied > 0;

  @override
  String toString() =>
      'L$level bal $balanceBefore→$balanceAfter, hints $hintsTaken/$hintsWanted'
      '${ranLow ? ' (RAN LOW)' : ''}, $stars★ +$levelCoins'
      '${chest != null ? ' +chest ${chest!.coins}' : ''}';
}

/// The result of one [EconomySimulation.run].
final class EconomySimulationResult {
  const EconomySimulationResult({required this.levels, required this.profile});

  final List<SimulatedLevel> levels;
  final PlayerProfile profile;

  /// How many levels ended with at least one unaffordable hint.
  int get levelsRunLow => levels.where((level) => level.ranLow).length;

  /// THE HEADLINE: "one dry level every N levels". Ch02 targets ~4.
  ///
  /// [double.infinity] when the player never ran low, which is a real and
  /// meaningful answer (the economy is a faucet), not a divide-by-zero to
  /// guard against at the call site.
  double get levelsPerDryLevel =>
      levelsRunLow == 0 ? double.infinity : levels.length / levelsRunLow;

  int get totalHintsWanted =>
      levels.fold(0, (sum, level) => sum + level.hintsWanted);

  int get totalHintsTaken =>
      levels.fold(0, (sum, level) => sum + level.hintsTaken);

  int get finalBalance => levels.isEmpty ? 0 : levels.last.balanceAfter;

  int get peakBalance =>
      levels.fold(0, (peak, level) => max(peak, level.balanceAfter));

  double get meanStars => levels.isEmpty
      ? 0
      : levels.fold(0, (sum, level) => sum + level.stars) / levels.length;

  @override
  String toString() =>
      'EconomySimulationResult(${profile.id}, ${levels.length} levels, '
      'ran low $levelsRunLow× = 1 per ${levelsPerDryLevel.toStringAsFixed(2)}, '
      'final $finalBalance, peak $peakBalance, '
      'mean ${meanStars.toStringAsFixed(2)}★)';
}

/// Replays a modelled player against a [CoinEconomy].
abstract final class EconomySimulation {
  /// Runs [levelCount] levels from a standing start (a brand-new player, who
  /// receives [CoinEconomy.starterGrantCoins] on their first completion).
  ///
  /// Deterministic in [seed] — the same seed is the same run, forever, which
  /// is what lets the economy test assert an exact number rather than a fuzzy
  /// range that would pass for any tuning at all.
  static EconomySimulationResult run({
    CoinEconomy economy = CoinEconomy.defaults,
    PlayerProfile profile = PlayerProfile.typical,
    int levelCount = 20,
    int seed = 20260826,
  }) {
    final random = Random(seed);
    final levels = <SimulatedLevel>[];

    // The starter grant lands BEFORE level 1's hints, not after it: a player
    // whose first-ever hint is unaffordable has been taught that hints are a
    // wall, which is the opposite of what the grant is for.
    var balance = economy.starterGrantCoins;

    for (var level = 1; level <= levelCount; level++) {
      final balanceBefore = balance;
      final wanted = profile._drawDemand(random);

      var taken = 0;
      for (var i = 0; i < wanted; i++) {
        if (balance < economy.hintCostCoins) break;
        balance -= economy.hintCostCoins;
        taken++;
      }

      // Stars come from the hints actually USED — the real rule, called
      // directly, so this cannot drift from what a player would score.
      final stars = Scoring.computeStars(hintsUsed: taken);
      final levelCoins = economy.coinsForLevel(stars: stars);
      balance += levelCoins;

      final chest = economy.awardsChest(level)
          ? economy.rollChest(random)
          : null;
      if (chest != null) balance += chest.coins;

      levels.add(
        SimulatedLevel(
          level: level,
          balanceBefore: balanceBefore,
          hintsWanted: wanted,
          hintsTaken: taken,
          stars: stars,
          levelCoins: levelCoins,
          chest: chest,
          balanceAfter: balance,
        ),
      );
    }

    return EconomySimulationResult(levels: levels, profile: profile);
  }

  /// [run] averaged over [runs] consecutive seeds.
  ///
  /// One 20-level run is a small sample and its exact dry-level count moves
  /// with the seed. The tuning target is a property of the ECONOMY, not of one
  /// lucky calendar, so the test asserts against this and reports the single
  /// run separately.
  static double meanLevelsPerDryLevel({
    CoinEconomy economy = CoinEconomy.defaults,
    PlayerProfile profile = PlayerProfile.typical,
    int levelCount = 20,
    int runs = 200,
    int firstSeed = 20260826,
  }) {
    var totalDry = 0;
    var totalLevels = 0;

    for (var i = 0; i < runs; i++) {
      final result = run(
        economy: economy,
        profile: profile,
        levelCount: levelCount,
        seed: firstSeed + i,
      );
      totalDry += result.levelsRunLow;
      totalLevels += result.levels.length;
    }

    return totalDry == 0 ? double.infinity : totalLevels / totalDry;
  }
}
