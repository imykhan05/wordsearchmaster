/// Interstitial-ad eligibility (pre-P18, see CLAUDE.md's `## Never do`).
///
/// PURE DART, RemoteConfig-backed like `CoinEconomy`/`DdaConfig`: the one
/// tunable lives on an INSTANCE rather than as a `static const`, because a
/// live-ops lever (`min_levels_between_interstitials`) has to reach this
/// decision at runtime without a code change.
///
/// ---------------------------------------------------------------------------
/// WHY THERE IS EXACTLY ONE TUNABLE
///
/// CLAUDE.md's ad-frequency rules — written from mining two 100M+-install
/// competitors' reviews, before any ad code existed — name three hard
/// boundaries: never before the player's first completed level, never after
/// a failed or abandoned level, and never an ESCALATING frequency as the
/// player progresses. The first two are enforced by the CALLER never even
/// consulting this policy on those paths (see `game_screen.dart`'s call
/// site, P18) — this class exists to own the third, and it owns it by
/// construction: [canShowInterstitial] takes no input that varies with how
/// far the player has come, only with how many levels have passed since the
/// LAST interstitial. A fixed gap cannot escalate; there is no parameter
/// here a future call site could wire up to make it escalate without
/// editing this file.
library;

/// Every tunable this policy needs, in one place — the same shape
/// `CoinEconomy` and `DdaConfig` already use.
final class AdFrequencyPolicy {
  const AdFrequencyPolicy({required this.minLevelsBetweenInterstitials});

  /// Remote Config `min_levels_between_interstitials`. The same gap applies
  /// at level 2 and at level 200 — see the library header.
  final int minLevelsBetweenInterstitials;

  /// The shipped default — also what `RemoteConfigKeys` falls back to.
  static const AdFrequencyPolicy defaults = AdFrequencyPolicy(
    minLevelsBetweenInterstitials: 4,
  );

  /// Whether an interstitial may show now.
  ///
  /// [totalLevelsCompleted] gates the very first ad ever: CLAUDE.md forbids
  /// showing one before the player's first completed level, so 0 (or
  /// negative, from a corrupt counter) always answers false.
  ///
  /// [levelsSinceLastInterstitial] is how many level completions have
  /// happened since an interstitial last actually showed, or since the
  /// start of play if none ever has. The caller (`AdRepository`, P18) owns
  /// tracking that count; this function only compares it to the gap.
  ///
  /// Deliberately knows nothing about a failed or abandoned level — CLAUDE.md
  /// already forbids showing an interstitial there, and the right place to
  /// enforce that is the call site never asking in the first place (only a
  /// genuine level completion reaches this method), not a parameter here a
  /// future caller could pass incorrectly.
  bool canShowInterstitial({
    required int totalLevelsCompleted,
    required int levelsSinceLastInterstitial,
  }) {
    if (totalLevelsCompleted < 1) return false;
    return levelsSinceLastInterstitial >= minLevelsBetweenInterstitials;
  }

  @override
  bool operator ==(Object other) =>
      other is AdFrequencyPolicy &&
      other.minLevelsBetweenInterstitials == minLevelsBetweenInterstitials;

  @override
  int get hashCode => minLevelsBetweenInterstitials.hashCode;

  @override
  String toString() =>
      'AdFrequencyPolicy(every $minLevelsBetweenInterstitials levels)';
}
