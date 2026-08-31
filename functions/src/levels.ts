/**
 * The Ch07 difficulty curve, ported so the server can bound a submission
 * without shipping `assets/content/levels.json` into the function bundle.
 *
 * ---------------------------------------------------------------------------
 * WHY A PORTED FUNCTION RATHER THAN THE ASSET
 *
 * `levels.json` is 900 rows (300 ids x 3 languages, P10). Every field the
 * server needs from it — `gridSize` and `wordCount` — is a pure function of
 * the level id, because that is exactly what `tool/validate_content.dart`
 * asserts about all 900 of them on every CI run. So the server can derive the
 * bounds instead of loading, parsing and keeping in sync a copy of a file it
 * would only ever read two fields from.
 *
 * That derivation is only safe while it really does match the shipped asset,
 * which is why `levels.test.ts` reads the REAL `assets/content/levels.json`
 * and checks `levelShape` against every row. If the curve is ever retuned in
 * content without being retuned here, that test fails — the same shape of
 * guard the Dart/TypeScript scoring parity fixture provides.
 *
 * ---------------------------------------------------------------------------
 * DAILY LEVELS ARE NOT ON THE CURVE
 *
 * `DailyPuzzle` fixes its own shape (10x10, 8 words) precisely so every
 * player gets the same board, so a daily is bounded by [DAILY_SHAPE] rather
 * than by a level id — its `LevelDefinition.id` is 0, which is never a
 * journey level.
 */

import { LIMITS } from './config';

export interface LevelShape {
  readonly gridSize: number;
  readonly wordCount: number;
}

interface CurveStep {
  readonly maxLevel: number;
  readonly gridSize: number;
  readonly wordCount: number;
}

/** Mirrors `curve` in `tool/validate_content.dart`. */
const CURVE: readonly CurveStep[] = [
  { maxLevel: 5, gridSize: 6, wordCount: 4 },
  { maxLevel: 20, gridSize: 8, wordCount: 6 },
  { maxLevel: 60, gridSize: 10, wordCount: 8 },
  { maxLevel: 150, gridSize: 10, wordCount: 10 },
  { maxLevel: 300, gridSize: 12, wordCount: 12 },
];

/** `DailyPuzzle.gridSize` / `.wordCount`. */
export const DAILY_SHAPE: LevelShape = { gridSize: 10, wordCount: 8 };

export function isKnownLevel(level: number): boolean {
  return (
    Number.isInteger(level) && level >= LIMITS.minLevel && level <= LIMITS.maxLevel
  );
}

/**
 * The shape of journey level [level], including the breather rule: every 7th
 * level trims `wordCount` by 2, floored at 3, and leaves `gridSize` alone.
 */
export function levelShape(level: number): LevelShape {
  const step = CURVE.find((it) => level <= it.maxLevel) ?? CURVE[CURVE.length - 1]!;
  const wordCount =
    level % 7 === 0
      ? Math.min(Math.max(step.wordCount - 2, LIMITS.minWordsPerLevel), step.wordCount)
      : step.wordCount;
  return { gridSize: step.gridSize, wordCount };
}

/**
 * The largest number of words a submission for [shape] may legitimately
 * claim, and the smallest.
 *
 * THE FLOOR IS NOT `shape.wordCount`, and that is the whole subtlety here.
 * P12's anti-frustration downshift hands a struggling player a level with ONE
 * FEWER WORD after two consecutive abandons (`DdaDownshift.dropOneWord`), so a
 * perfectly honest submission can arrive one word short of the curve. A server
 * that insisted on an exact match would flag precisely the players the DDA
 * exists to help — and silently, since a flagged score never shows an error.
 * The floor therefore allows the downshift, and never drops below the
 * breather floor of 3.
 */
export function wordCountBounds(shape: LevelShape): { min: number; max: number } {
  return {
    min: Math.max(shape.wordCount - 1, LIMITS.minWordsPerLevel),
    max: shape.wordCount,
  };
}

/**
 * Whether a claimed grapheme count could belong to a word on a [shape] board.
 *
 * The content pipeline caps words at 9 graphemes and requires at least 2
 * (P10), and a word can never be longer than the board it sits on.
 */
export function isPlausibleGraphemeCount(
  graphemeCount: number,
  shape: LevelShape,
): boolean {
  return (
    Number.isInteger(graphemeCount) &&
    graphemeCount >= 2 &&
    graphemeCount <= Math.min(9, shape.gridSize)
  );
}
