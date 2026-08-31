import { describe, expect, it } from 'vitest';

import {
  COMBO_POINTS_PER_GRAPHEME,
  HINT_PENALTY,
  MAX_COMBO_STEP,
  SPEC_VERSION,
  comboMultiplier,
  computeScore,
  computeStars,
  hintsIn,
  maxComboIn,
  wordScore,
  wordsFoundIn,
  type ScoreEvent,
} from '../src/scoring';

const found = (g: number): ScoreEvent => ({ t: 'w', g });
const wrong: ScoreEvent = { t: 'x' };
const hint: ScoreEvent = { t: 'h' };

describe('the spec header worked example', () => {
  // Verbatim from `lib/domain/scoring/scoring.dart`'s header. This is the
  // cross-language parity fixture the spec names, so it is asserted here as
  // well as in the Dart tests and in the 200-case fixture.
  const events = [found(5), found(4), wrong, found(3), hint];

  it('scores 103', () => {
    expect(computeScore(events)).toBe(103);
  });

  it('awards 2 stars for the one hint', () => {
    expect(computeStars(hintsIn(events))).toBe(2);
  });

  it('walks the ladder 50 -> 98 -> 98 -> 128 -> 103', () => {
    expect(computeScore(events.slice(0, 1))).toBe(50);
    expect(computeScore(events.slice(0, 2))).toBe(98);
    expect(computeScore(events.slice(0, 3))).toBe(98);
    expect(computeScore(events.slice(0, 4))).toBe(128);
    expect(computeScore(events.slice(0, 5))).toBe(103);
  });
});

describe('the combo ladder', () => {
  it('is the integer table, not a float multiply', () => {
    expect(COMBO_POINTS_PER_GRAPHEME).toEqual([10, 12, 14, 16, 18, 20]);
    // Every entry must be an exact integer: the whole reason the table exists
    // is that `10 * 1.2` is not reliably 12 in two languages.
    for (const points of COMBO_POINTS_PER_GRAPHEME) {
      expect(Number.isInteger(points)).toBe(true);
    }
  });

  it('caps at step 6 and never grows past it', () => {
    expect(wordScore(1, MAX_COMBO_STEP)).toBe(20);
    expect(wordScore(1, MAX_COMBO_STEP + 1)).toBe(20);
    expect(wordScore(1, 1000)).toBe(20);
  });

  it('treats a combo below 1 as step 1', () => {
    expect(wordScore(3, 0)).toBe(30);
    expect(wordScore(3, -5)).toBe(30);
  });

  it('exposes display multipliers that match the table exactly', () => {
    expect([1, 2, 3, 4, 5, 6].map(comboMultiplier)).toEqual([
      1.0, 1.2, 1.4, 1.6, 1.8, 2.0,
    ]);
  });
});

describe('rules that a naive port would get wrong', () => {
  it('does not reset the combo on a hint', () => {
    // 3*10 + 3*12 = 66, minus one hint.
    expect(computeScore([found(3), hint, found(3)])).toBe(66 - HINT_PENALTY);
  });

  it('resets the combo on a wrong selection', () => {
    expect(computeScore([found(3), wrong, found(3)])).toBe(60);
  });

  it('clamps the score at zero rather than going negative', () => {
    expect(computeScore([hint, hint, hint])).toBe(0);
    expect(computeScore([found(2), hint, hint])).toBe(0);
  });

  it('scores a non-positive grapheme count as zero but still advances the combo', () => {
    // 0 then -3 pay nothing, but the third word is the THIRD in the streak.
    expect(computeScore([found(0), found(-3), found(2)])).toBe(2 * 14);
  });
});

describe('stars', () => {
  it('follows the relaxed-mode table', () => {
    expect(computeStars(0)).toBe(3);
    expect(computeStars(1)).toBe(2);
    expect(computeStars(2)).toBe(1);
    expect(computeStars(9)).toBe(1);
  });

  it('treats a negative hint count as zero hints', () => {
    expect(computeStars(-1)).toBe(3);
  });
});

describe('event summaries', () => {
  it('counts hints, words and the longest streak', () => {
    const events = [found(2), found(2), wrong, found(2), hint, found(2)];
    expect(hintsIn(events)).toBe(1);
    expect(wordsFoundIn(events)).toBe(4);
    expect(maxComboIn(events)).toBe(2);
  });

  it('reports a zero max combo for a replay with no words', () => {
    expect(maxComboIn([wrong, hint, wrong])).toBe(0);
  });

  it('does not break a streak across a hint', () => {
    expect(maxComboIn([found(2), hint, found(2), hint, found(2)])).toBe(3);
  });
});

it('declares the same spec version as the Dart side', () => {
  expect(SPEC_VERSION).toBe(1);
});
