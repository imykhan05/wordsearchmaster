/**
 * The server derives level shapes from a ported curve instead of shipping
 * `assets/content/levels.json`. That is only safe while the derivation and the
 * asset agree, so this reads the REAL asset and checks all 900 rows.
 */

import { readFileSync } from 'node:fs';
import { join } from 'node:path';

import { describe, expect, it } from 'vitest';

import {
  DAILY_SHAPE,
  isKnownLevel,
  isPlausibleGraphemeCount,
  levelShape,
  wordCountBounds,
} from '../src/levels';

interface AssetLevel {
  id: number;
  lang: string;
  gridSize: number;
  wordCount: number;
}

const levels = JSON.parse(
  readFileSync(join(__dirname, '..', '..', 'assets', 'content', 'levels.json'), 'utf8'),
) as { levels: AssetLevel[] } | AssetLevel[];

const rows = Array.isArray(levels) ? levels : levels.levels;

describe('levelShape against the shipped content pack', () => {
  it('reads all 900 (level, language) rows', () => {
    expect(rows).toHaveLength(900);
  });

  it('matches gridSize and wordCount on every one of them', () => {
    const mismatches = rows.filter((row) => {
      const shape = levelShape(row.id);
      return shape.gridSize !== row.gridSize || shape.wordCount !== row.wordCount;
    });
    expect(
      mismatches.map((row) => ({
        id: row.id,
        lang: row.lang,
        asset: { gridSize: row.gridSize, wordCount: row.wordCount },
        derived: levelShape(row.id),
      })),
    ).toEqual([]);
  });

  it('reproduces the breather rule on a level the curve trims', () => {
    // 21-60 is the 10x10 / 8-word band; 21 is a breather (21 % 7 === 0).
    expect(levelShape(21)).toEqual({ gridSize: 10, wordCount: 6 });
    expect(levelShape(22)).toEqual({ gridSize: 10, wordCount: 8 });
  });

  it('floors a breather at three words rather than going below it', () => {
    // Levels 1-5 carry 4 words; level 7 is in the 6-word band, so the only
    // place the floor could bite is a band that is already small.
    for (const level of [7, 14, 28, 35, 49, 63, 77, 105, 154, 294]) {
      expect(levelShape(level).wordCount).toBeGreaterThanOrEqual(3);
    }
  });
});

describe('level existence', () => {
  it('accepts 1..300 and nothing else', () => {
    expect(isKnownLevel(1)).toBe(true);
    expect(isKnownLevel(300)).toBe(true);
    expect(isKnownLevel(0)).toBe(false);
    expect(isKnownLevel(301)).toBe(false);
    expect(isKnownLevel(-5)).toBe(false);
    expect(isKnownLevel(1.5)).toBe(false);
  });

  it('does not treat the daily sentinel id as a journey level', () => {
    // `DailyPuzzle.levelId` is 0 precisely so it can never be mistaken for one.
    expect(isKnownLevel(0)).toBe(false);
  });
});

describe('word-count bounds', () => {
  it('allows P12 anti-frustration downshifts of exactly one word', () => {
    // Two consecutive abandons hand the player one fewer word
    // (`DdaDownshift.dropOneWord`), so an honest submission can arrive short.
    const bounds = wordCountBounds(levelShape(100)); // 10 words
    expect(bounds).toEqual({ min: 9, max: 10 });
  });

  it('never drops the floor below the breather minimum of three', () => {
    const bounds = wordCountBounds({ gridSize: 6, wordCount: 3 });
    expect(bounds.min).toBe(3);
  });
});

describe('grapheme plausibility', () => {
  const shape = { gridSize: 6, wordCount: 4 };

  it('rejects a word longer than the board it claims to sit on', () => {
    expect(isPlausibleGraphemeCount(6, shape)).toBe(true);
    expect(isPlausibleGraphemeCount(7, shape)).toBe(false);
  });

  it('rejects a one-cell word', () => {
    // The content pipeline guarantees 2..9 graphemes (P10).
    expect(isPlausibleGraphemeCount(1, shape)).toBe(false);
    expect(isPlausibleGraphemeCount(2, shape)).toBe(true);
  });

  it('caps at the content pipeline maximum even on a 12x12', () => {
    expect(isPlausibleGraphemeCount(9, { gridSize: 12, wordCount: 12 })).toBe(true);
    expect(isPlausibleGraphemeCount(10, { gridSize: 12, wordCount: 12 })).toBe(false);
  });
});

it('pins the daily shape to DailyPuzzle', () => {
  expect(DAILY_SHAPE).toEqual({ gridSize: 10, wordCount: 8 });
});
