/// Live-ops levers (Ch14) — the values a designer can retune without shipping
/// a build.
///
/// P20 owns the Firebase Remote Config binding. THIS prompt owns the shape:
/// the typed key table, the hardcoded defaults, and a [RemoteConfig] seam the
/// economy already reads through — so when P20 lands, it fills in one
/// implementation rather than hunting down constants scattered across the
/// progression code.
///
/// ---------------------------------------------------------------------------
/// THE DEFAULT IS PART OF THE KEY, NOT A FALLBACK AT THE CALL SITE
///
/// Every lookup below can fail: no network on first launch, a fetch timeout, a
/// key a newer console added that this build has never heard of, a value typed
/// as a string by mistake. Each of those has to resolve to the same sane
/// number, and the only way to guarantee that is for the default to live with
/// the key rather than at each `getInt(...)`. CLAUDE.md's rule — "tunable
/// values live in RemoteConfigKeys" — is this: one table, one default, no
/// second opinion.
///
/// A corollary the implementations below all honour: a remote value is
/// CLAMPED, never trusted. A console typo that sets `hint_cost_coins` to 0 or
/// to 2^31 must not brick a player's economy, so the sane range is declared
/// with the key too.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/progression/ad_policy.dart';
import '../../domain/progression/coin_economy.dart';
import '../../domain/progression/dda.dart';

part 'remote_config.g.dart';

/// One tunable, with its wire name, its shipped default and its sane range.
final class RemoteConfigKey {
  const RemoteConfigKey(
    this.name,
    this.defaultValue, {
    required this.min,
    required this.max,
  });

  /// The key as it appears in the Firebase console. Snake case, matching the
  /// names Ch14 uses verbatim.
  final String name;
  final int defaultValue;

  /// Inclusive bounds a fetched value is clamped into. See the library header.
  final int min;
  final int max;

  int clamp(int value) => value < min
      ? min
      : value > max
      ? max
      : value;

  @override
  String toString() => 'RemoteConfigKey($name = $defaultValue [$min..$max])';
}

/// Every lever this build reads.
abstract final class RemoteConfigKeys {
  /// Ch02: a chest every 5th level. 0 disables chests entirely, which is a
  /// legitimate live-ops position (an A/B arm) and so is inside the range.
  static const chestEveryNLevels = RemoteConfigKey(
    'chest_every_n_levels',
    5,
    min: 0,
    max: 50,
  );

  /// Ch02: 50 coins a hint. The single most sensitive number in the economy —
  /// see `economy_simulation.dart`.
  static const hintCostCoins = RemoteConfigKey(
    'hint_cost_coins',
    50,
    min: 1,
    max: 1000,
  );

  static const levelBaseCoins = RemoteConfigKey(
    'level_base_coins',
    10,
    min: 0,
    max: 500,
  );

  static const coinsPerStar = RemoteConfigKey(
    'coins_per_star',
    5,
    min: 0,
    max: 500,
  );

  static const starterGrantCoins = RemoteConfigKey(
    'starter_grant_coins',
    50,
    min: 0,
    max: 5000,
  );

  /// Ch02/P12: seconds of no successful-or-attempted selection before the
  /// silent, free grapheme pulse fires. See `domain/progression/dda.dart`.
  static const ddaStuckSeconds = RemoteConfigKey(
    'dda_stuck_seconds',
    25,
    min: 5,
    max: 300,
  );

  /// Ch02/P12: seconds of idle before the free (never rewarded-ad) hint offer
  /// appears. Always greater than [ddaStuckSeconds] in practice, but nothing
  /// here enforces that ordering — a console typo swapping them still clamps
  /// into a sane range and merely fires the offer before the pulse, which
  /// degrades gracefully rather than crashing.
  static const ddaHintOfferSeconds = RemoteConfigKey(
    'dda_hint_offer_seconds',
    60,
    min: 10,
    max: 600,
  );

  /// Pre-P18: the fixed gap `AdFrequencyPolicy` enforces between two
  /// interstitials, in levels completed. `min: 1` is deliberate, not just a
  /// safety floor — CLAUDE.md's "never escalate ad frequency" rule would be
  /// trivially defeated by a console value of 0 turning every completion
  /// into an ad, so the range itself rules that console typo out rather
  /// than trusting every future editor of this key to remember why.
  static const minLevelsBetweenInterstitials = RemoteConfigKey(
    'min_levels_between_interstitials',
    4,
    min: 1,
    max: 50,
  );

  /// The whole table, for the dev panel and for
  /// `remote_config_test.dart`'s "every key has a distinct wire name" check.
  static const List<RemoteConfigKey> all = [
    chestEveryNLevels,
    hintCostCoins,
    levelBaseCoins,
    coinsPerStar,
    starterGrantCoins,
    ddaStuckSeconds,
    ddaHintOfferSeconds,
    minLevelsBetweenInterstitials,
  ];
}

/// Reads a lever. One method, because every lever this build has is an int;
/// P20 widens this when a bool or string lever first appears rather than
/// inventing accessors nothing calls.
abstract interface class RemoteConfig {
  int getInt(RemoteConfigKey key);
}

/// Every key at its shipped default.
///
/// The binding until P20, and permanently the binding in tests: an economy
/// test that silently depended on whatever the live console said would be a
/// test that fails on a Tuesday for reasons nobody can reproduce.
final class DefaultRemoteConfig implements RemoteConfig {
  const DefaultRemoteConfig();

  @override
  int getInt(RemoteConfigKey key) => key.defaultValue;
}

/// Defaults with named overrides — the dev debug panel, and the seam a test
/// uses to prove a lever is actually read rather than hardcoded downstream.
final class OverrideRemoteConfig implements RemoteConfig {
  const OverrideRemoteConfig(this.overrides);

  /// Keyed by [RemoteConfigKey.name]. Values are clamped like any other
  /// fetched value, so an override cannot do what a console typo cannot.
  final Map<String, int> overrides;

  @override
  int getInt(RemoteConfigKey key) {
    final raw = overrides[key.name];
    return raw == null ? key.defaultValue : key.clamp(raw);
  }
}

/// The app's levers. Overridden in `bootstrap.dart` once P20 fetches real
/// values; until then every read resolves to the shipped default.
@Riverpod(keepAlive: true)
RemoteConfig remoteConfig(Ref ref) => const DefaultRemoteConfig();

/// The economy, assembled from the levers.
///
/// THE ONE PLACE `CoinEconomy` IS BUILT for the running app. Gameplay reads
/// this provider rather than `CoinEconomy.defaults`, so a Remote Config change
/// reaches the wallet without a code change — which is the entire reason the
/// tunables are fields on an instance instead of `static const`s
/// (`coin_economy.dart`'s header).
@Riverpod(keepAlive: true)
CoinEconomy coinEconomy(Ref ref) {
  final config = ref.watch(remoteConfigProvider);
  return CoinEconomy(
    levelBaseCoins: config.getInt(RemoteConfigKeys.levelBaseCoins),
    coinsPerStar: config.getInt(RemoteConfigKeys.coinsPerStar),
    hintCostCoins: config.getInt(RemoteConfigKeys.hintCostCoins),
    chestEveryNLevels: config.getInt(RemoteConfigKeys.chestEveryNLevels),
    starterGrantCoins: config.getInt(RemoteConfigKeys.starterGrantCoins),
    chestTable: CoinEconomy.defaultChestTable,
  );
}

/// The DDA thresholds, assembled from the levers — the same "one place this
/// is built" shape as [coinEconomy] above, so a Remote Config change reaches
/// the idle timer without a code change.
@Riverpod(keepAlive: true)
DdaConfig ddaConfig(Ref ref) {
  final config = ref.watch(remoteConfigProvider);
  return DdaConfig(
    stuckSeconds: config.getInt(RemoteConfigKeys.ddaStuckSeconds),
    hintOfferSeconds: config.getInt(RemoteConfigKeys.ddaHintOfferSeconds),
  );
}

/// The interstitial gap, assembled from the levers — the same "one place
/// this is built" shape as [coinEconomy]/[ddaConfig] above, so a Remote
/// Config change reaches ad frequency without a code change.
@Riverpod(keepAlive: true)
AdFrequencyPolicy adFrequencyPolicy(Ref ref) {
  final config = ref.watch(remoteConfigProvider);
  return AdFrequencyPolicy(
    minLevelsBetweenInterstitials: config.getInt(
      RemoteConfigKeys.minLevelsBetweenInterstitials,
    ),
  );
}
