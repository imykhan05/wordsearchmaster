/// ============================================================================
/// SCORING SPEC v1 — the normative definition
///
/// Ch08's Cloud Function (`functions/src/submitScore.ts`, P14) re-implements
/// this in TypeScript, and the two MUST agree on every input. Treat this
/// header as the contract; change it and the port together, and bump the
/// version.
///
/// PURITY: every function below is pure — no clock, no I/O, no randomness, no
/// global state. Score depends only on its arguments. This is what lets the
/// server recompute a submission and compare.
///
/// ---------------------------------------------------------------------------
/// INPUT — an ordered list of events, replayed start to finish:
///
///   WordFound { graphemeCount: int >= 1 }   a word was correctly traced
///   WrongSelection {}                       a released selection matched nothing
///   HintUsed {}                             a paid hint was consumed
///
/// ---------------------------------------------------------------------------
/// RULES
///
/// 1. BASE POINTS
///      base = graphemeCount * 10
///    Counted in grapheme clusters, so "पानी" is 2, not 4.
///
/// 2. COMBO
///    `combo` counts CONSECUTIVE correct words. It starts at 0, increments on
///    each WordFound, and resets to 0 on WrongSelection. HintUsed does NOT
///    reset it. The multiplier is taken at the combo value AFTER incrementing,
///    capped at 6:
///
///      combo:      1     2     3     4     5     6+
///      multiplier: x1.0  x1.2  x1.4  x1.6  x1.8  x2.0
///
///    IMPLEMENTED AS INTEGER POINTS PER GRAPHEME, not as a float multiply:
///
///      combo:      1     2     3     4     5     6+
///      perGrapheme: 10    12    14    16    18    20
///
///    These are exactly `10 * multiplier`, so the ladder is identical — but a
///    float multiply is not. `0.1 + 0.2` and rounding behaviour are the classic
///    ways two languages silently disagree by one point, and one point of
///    disagreement means a rejected submission. Integers cannot diverge.
///    The TypeScript port MUST use the integer table too.
///
///      wordPoints = graphemeCount * perGrapheme[min(combo, 6)]
///
/// 3. HINT PENALTY
///      -25 points per HintUsed. Flat; not scaled by combo.
///
/// 4. FLOOR
///      The level score is clamped at 0. Hints can never push a player
///      negative.
///
/// 5. STARS — RELAXED MODE
///      3 stars = 0 hints
///      2 stars = 1 hint
///      1 star  = 2 or more hints
///
///    Stars take NO time input. That is enforced by the signature, not by a
///    convention: `computeStars` has no elapsed parameter to pass, so relaxed
///    mode cannot accidentally grow a time dependency. Timing only ever
///    matters in Blitz mode (v1.2), which will get its own function rather
///    than a flag on this one.
///
/// ---------------------------------------------------------------------------
/// WORKED EXAMPLE — used verbatim as a cross-language parity test in P14:
///
///   [WordFound(5), WordFound(4), WrongSelection, WordFound(3), HintUsed]
///
///   WordFound(5)   combo 1  ->  5 * 10 = 50    total 50
///   WordFound(4)   combo 2  ->  4 * 12 = 48    total 98
///   WrongSelection combo -> 0                  total 98
///   WordFound(3)   combo 1  ->  3 * 10 = 30    total 128
///   HintUsed                 ->      -25       total 103
///
///   computeScore = 103, computeStars(hintsUsed: 1) = 2
/// ============================================================================
library;

import 'dart:math';

import 'score_event.dart';

/// Pure scoring rules. See the spec header above.
abstract final class Scoring {
  /// Spec version. The Cloud Function checks this so a client built against
  /// older rules is detectable rather than silently mis-scored.
  static const int specVersion = 1;

  static const int basePointsPerGrapheme = 10;
  static const int hintPenalty = 25;

  /// Longest combo that still increases the multiplier.
  static const int maxComboStep = 6;

  /// Points per grapheme at combo 1..6. Integer on purpose — see rule 2.
  static const List<int> comboPointsPerGrapheme = [10, 12, 14, 16, 18, 20];

  /// The multiplier a player sees on screen ("x1.4"). Display only: scoring
  /// itself never multiplies by these, to keep Dart and TypeScript identical.
  static double comboMultiplier(int consecutiveCorrect) =>
      comboPointsPerGrapheme[_comboIndex(consecutiveCorrect)] /
      basePointsPerGrapheme;

  /// Points for one word found as the [consecutiveCorrect]-th in a row
  /// (1-based: the first correct word of a streak is 1).
  static int wordScore({
    required int graphemeCount,
    required int consecutiveCorrect,
  }) {
    if (graphemeCount <= 0) return 0;
    return graphemeCount *
        comboPointsPerGrapheme[_comboIndex(consecutiveCorrect)];
  }

  /// The level score, by replaying [events] in order.
  ///
  /// Pure. The Cloud Function runs the identical algorithm over the events the
  /// client submitted and writes ITS result, never the client's number.
  static int computeScore(List<ScoreEvent> events) {
    var score = 0;
    var combo = 0;

    for (final event in events) {
      switch (event) {
        case WordFound(:final graphemeCount):
          combo++;
          score += wordScore(
            graphemeCount: graphemeCount,
            consecutiveCorrect: combo,
          );
        case WrongSelection():
          combo = 0;
        case HintUsed():
          score -= hintPenalty;
      }
    }

    return max(score, 0);
  }

  /// Stars for a completed level in RELAXED mode.
  ///
  /// Deliberately takes no elapsed time: relaxed is the product default and
  /// timing pressure is what drives this game's audience away (Ch01/Ch02).
  static int computeStars({required int hintsUsed}) {
    if (hintsUsed <= 0) return 3;
    if (hintsUsed == 1) return 2;
    return 1;
  }

  /// Convenience for callers holding an event list rather than a counter.
  static int hintsIn(List<ScoreEvent> events) =>
      events.whereType<HintUsed>().length;

  /// The longest run of consecutive correct words in [events]. Feeds the
  /// `combo_max` analytics parameter (Ch11).
  static int maxComboIn(List<ScoreEvent> events) {
    var best = 0;
    var current = 0;
    for (final event in events) {
      switch (event) {
        case WordFound():
          current++;
          best = max(best, current);
        case WrongSelection():
          current = 0;
        case HintUsed():
          break;
      }
    }
    return best;
  }

  /// Clamps a 1-based combo position onto the ladder.
  static int _comboIndex(int consecutiveCorrect) =>
      min(max(consecutiveCorrect, 1), maxComboStep) - 1;
}
