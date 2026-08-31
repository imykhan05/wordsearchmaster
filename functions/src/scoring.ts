/**
 * ============================================================================
 * SCORING SPEC v1 — the TypeScript half of a two-language normative contract.
 *
 * THE SPEC LIVES IN `lib/domain/scoring/scoring.dart`. That file's header is
 * the normative text; this file is its port, and the two MUST agree on every
 * input. Change one without the other and `scoring_parity.test.ts` fails,
 * which is the entire reason that test exists.
 *
 * Three rules keep the two implementations from drifting apart:
 *
 *  1. INTEGER POINTS PER GRAPHEME, never a float multiply. The displayed
 *     multipliers (x1.0 … x2.0) are presentation; scoring uses
 *     `COMBO_POINTS_PER_GRAPHEME` directly. A float multiply is the classic
 *     way two languages disagree by one point, and one point of disagreement
 *     is a rejected submission.
 *  2. The same replay shape. Score is computed by walking an ORDERED event
 *     list, because the combo ladder depends on the sequence of correct and
 *     wrong selections and cannot be reconstructed from counters.
 *  3. No clock, no I/O, no randomness, no module state. Everything here is a
 *     pure function of its arguments, which is what makes "recompute the
 *     client's submission and compare" meaningful at all.
 *
 * The worked example from the Dart header is asserted verbatim in
 * `scoring.test.ts`:
 *
 *   [WordFound(5), WordFound(4), WrongSelection, WordFound(3), HintUsed]
 *     -> computeScore = 103, computeStars(1) = 2
 * ============================================================================
 */

/**
 * Spec version. `submitScore` compares this against the client's declared
 * `specVersion` so a client built against older rules is DETECTABLE rather
 * than silently mis-scored.
 */
export const SPEC_VERSION = 1;

export const BASE_POINTS_PER_GRAPHEME = 10;
export const HINT_PENALTY = 25;

/** Longest combo that still increases the multiplier. */
export const MAX_COMBO_STEP = 6;

/** Points per grapheme at combo 1..6. Integer on purpose — see rule 1. */
export const COMBO_POINTS_PER_GRAPHEME: readonly number[] = [10, 12, 14, 16, 18, 20];

/**
 * The wire discriminators from `lib/data/local/score_event_codec.dart`.
 *
 * THESE VALUES ARE FROZEN on both sides. Changing one silently invalidates
 * every outbox row queued on every device that has not synced yet; add a new
 * value instead, and teach both ends about it.
 */
export const EVENT_WORD_FOUND = 'w';
export const EVENT_WRONG_SELECTION = 'x';
export const EVENT_HINT_USED = 'h';

export type ScoreEvent =
  | { readonly t: typeof EVENT_WORD_FOUND; readonly g: number }
  | { readonly t: typeof EVENT_WRONG_SELECTION }
  | { readonly t: typeof EVENT_HINT_USED };

/** Clamps a 1-based combo position onto the ladder. Mirrors `_comboIndex`. */
function comboIndex(consecutiveCorrect: number): number {
  return Math.min(Math.max(consecutiveCorrect, 1), MAX_COMBO_STEP) - 1;
}

/**
 * The multiplier a player sees on screen ("x1.4").
 *
 * DISPLAY ONLY, exactly as in Dart: scoring never multiplies by this. It
 * exists so the two files stay line-for-line comparable — a reader checking
 * the port should not have to wonder whether a missing function means a
 * missing rule.
 */
export function comboMultiplier(consecutiveCorrect: number): number {
  return (
    COMBO_POINTS_PER_GRAPHEME[comboIndex(consecutiveCorrect)]! /
    BASE_POINTS_PER_GRAPHEME
  );
}

/**
 * Points for one word found as the [consecutiveCorrect]-th in a row (1-based:
 * the first correct word of a streak is 1).
 */
export function wordScore(graphemeCount: number, consecutiveCorrect: number): number {
  if (graphemeCount <= 0) return 0;
  return graphemeCount * COMBO_POINTS_PER_GRAPHEME[comboIndex(consecutiveCorrect)]!;
}

/**
 * The level score, by replaying [events] in order.
 *
 * This is the number that gets WRITTEN. The client's own total is never read —
 * it is not even sent (see `ScoreEventCodec`'s header).
 */
export function computeScore(events: readonly ScoreEvent[]): number {
  let score = 0;
  let combo = 0;

  for (const event of events) {
    switch (event.t) {
      case EVENT_WORD_FOUND:
        combo++;
        score += wordScore(event.g, combo);
        break;
      case EVENT_WRONG_SELECTION:
        combo = 0;
        break;
      case EVENT_HINT_USED:
        score -= HINT_PENALTY;
        break;
    }
  }

  return Math.max(score, 0);
}

/**
 * Stars for a completed level in RELAXED mode.
 *
 * Takes no elapsed time, and that is enforced by the signature on both sides:
 * relaxed mode has no clock to pass in, so it cannot accidentally grow a time
 * dependency. Blitz (v1.2) gets its own function, never a flag on this one.
 */
export function computeStars(hintsUsed: number): number {
  if (hintsUsed <= 0) return 3;
  if (hintsUsed === 1) return 2;
  return 1;
}

/** Number of `HintUsed` events. Mirrors `Scoring.hintsIn`. */
export function hintsIn(events: readonly ScoreEvent[]): number {
  return events.reduce(
    (count, event) => (event.t === EVENT_HINT_USED ? count + 1 : count),
    0,
  );
}

/** Number of `WordFound` events — the words this submission claims. */
export function wordsFoundIn(events: readonly ScoreEvent[]): number {
  return events.reduce(
    (count, event) => (event.t === EVENT_WORD_FOUND ? count + 1 : count),
    0,
  );
}

/** The longest run of consecutive correct words. Mirrors `Scoring.maxComboIn`. */
export function maxComboIn(events: readonly ScoreEvent[]): number {
  let best = 0;
  let current = 0;
  for (const event of events) {
    switch (event.t) {
      case EVENT_WORD_FOUND:
        current++;
        best = Math.max(best, current);
        break;
      case EVENT_WRONG_SELECTION:
        current = 0;
        break;
      case EVENT_HINT_USED:
        break;
    }
  }
  return best;
}
