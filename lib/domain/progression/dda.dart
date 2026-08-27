/// FTUE + anti-frustration (DDA) — Chapter 02 (P12).
///
/// PURE DART. No clock, no Timer, no I/O, no randomness it did not receive as
/// an argument — the same discipline `streak.dart` and `coin_economy.dart`
/// already keep. The Timer that measures "how long has the player been idle"
/// lives in the presentation layer (`game_screen.dart`); everything here is a
/// total, deterministic function of the numbers that Timer hands in.
///
/// ---------------------------------------------------------------------------
/// WHY THIS IS NOT ONE MORE FIELD ON GameState
///
/// `GameState`'s getters are all replays of `events` (`game_controller.dart`'s
/// own decision 1) — nothing on it depends on wall-clock time elapsed with no
/// player action, and DDA is exactly that: a function of TIME PASSING, not of
/// anything the player did. Folding it in would mean either a `Timer` ticking
/// Riverpod state every second (rebuilding the grid AND the top bar, the exact
/// per-frame-rebuild mistake P06/P07 spent two prompts avoiding) or a stale
/// "idle since" timestamp `GameState` can't itself keep current. So the split
/// mirrors P07's own selection split: `GameController` stays a pure state
/// machine; the countdown that feeds it is presentation-owned.
///
/// ---------------------------------------------------------------------------
/// TWO THRESHOLDS, TWO DIFFERENT INTERVENTIONS
///
///  * `stuckSeconds` (default 25, RemoteConfig `dda_stuck_seconds`) → PULSE.
///    Free, silent, no event, no cost — a single grapheme softly glows and
///    nothing else changes. [DdaState.pulse].
///  * `hintOfferSeconds` (default 60, RemoteConfig `dda_hint_offer_seconds`)
///    → OFFER. A soft inline prompt offers a hint the player can accept — for
///    free, never a rewarded ad (Ch02: "monetising frustration is how you get
///    uninstalls").  [DdaState.hintOffer].
///
/// The two are mutually exclusive at any instant — [DdaEngine.stateFor] picks
/// whichever threshold the idle duration has crossed, never both — because a
/// player already offered a hint does not also need a silent pulse competing
/// for the same moment.
library;

/// The two live thresholds, sourced from Remote Config
/// (`services/remote_config/remote_config.dart`) rather than literals here,
/// for the same reason every other live-ops lever is: a designer retunes
/// "stuck" without shipping a build.
final class DdaConfig {
  const DdaConfig({required this.stuckSeconds, required this.hintOfferSeconds});

  final int stuckSeconds;
  final int hintOfferSeconds;

  /// The shipped defaults — also what `RemoteConfigKeys` falls back to.
  static const DdaConfig defaults = DdaConfig(
    stuckSeconds: 25,
    hintOfferSeconds: 60,
  );

  @override
  bool operator ==(Object other) =>
      other is DdaConfig &&
      other.stuckSeconds == stuckSeconds &&
      other.hintOfferSeconds == hintOfferSeconds;

  @override
  int get hashCode => Object.hash(stuckSeconds, hintOfferSeconds);

  @override
  String toString() =>
      'DdaConfig(stuck: ${stuckSeconds}s, hintOffer: ${hintOfferSeconds}s)';
}

/// What the idle timer should do right now.
///
/// NEVER rendered as text that names itself — see the library header and
/// CLAUDE.md's "never surface any message implying the game was made easier".
/// A UI built on this enum may show a generic, silent glow ([pulse]) or a
/// neutral "want a hint?" offer ([hintOffer]); it must never say why.
enum DdaState {
  /// Below both thresholds: nothing.
  none,

  /// `stuckSeconds` crossed: pulse a random remaining word's first grapheme.
  pulse,

  /// `hintOfferSeconds` crossed: offer a free hint.
  hintOffer,
}

/// The pure decision function.
abstract final class DdaEngine {
  /// [idleFor] is wall-clock time since the player's last selection attempt
  /// (correct or wrong) — see `game_screen.dart` for where that clock resets.
  static DdaState stateFor({
    required Duration idleFor,
    DdaConfig config = DdaConfig.defaults,
  }) {
    if (idleFor.inSeconds >= config.hintOfferSeconds) {
      return DdaState.hintOffer;
    }
    if (idleFor.inSeconds >= config.stuckSeconds) return DdaState.pulse;
    return DdaState.none;
  }
}

/// "Two consecutive abandons of the same level → next attempt uses a grid one
/// size smaller or one fewer word" (Ch02).
///
/// An ABANDON is one attempt at a level that ended without finishing it — see
/// `game_screen.dart`'s own doc for the exact signal this build uses (an
/// explicit leave, not backgrounding: the app has no reliable, testable
/// signal for "backgrounded" within this prompt's scope). CONSECUTIVE: any
/// completed attempt resets the count to zero — `ProgressionController`
/// clears it the moment a level is won, since the pattern this rule watches
/// for is specifically "never manages to finish this one".
abstract final class DdaAbandonRules {
  /// How many consecutive abandons trigger the downshift.
  static const int abandonsToDownshift = 2;

  static bool shouldDownshift(int consecutiveAbandons) =>
      consecutiveAbandons >= abandonsToDownshift;
}

/// The downshift itself: one fewer word, never a grid-size change.
///
/// Ch02 offers a choice ("a grid one size smaller OR one fewer word"); this
/// build always takes the word-count path. Shrinking `gridSize` risks a word
/// that no longer fits (a longer target word on a smaller board), reopening
/// exactly the placement-failure surface `tool/validate_content.dart` exists
/// to rule out for the SHIPPED curve — this grid is generated live, off the
/// shipped seed, and is never re-validated the way the 900 canonical levels
/// are. Dropping the last word is always safe: fewer words to place can only
/// make `GridGenerator` (which "never throws and never loops forever",
/// `grid_generator.dart`) succeed MORE easily, never less.
abstract final class DdaDownshift {
  /// The floor a level is never dropped below, matching the breather-level
  /// floor `assets/content/levels.json`'s own curve already uses (P10).
  static const int minWords = 3;

  /// [words] with its last entry dropped, unless that would go below
  /// [minWords] — a breather level already at the floor is left alone rather
  /// than shrinking further.
  static List<T> dropOneWord<T>(List<T> words) =>
      words.length > minWords ? words.sublist(0, words.length - 1) : words;
}
