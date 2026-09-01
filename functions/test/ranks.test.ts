import { describe, expect, it } from 'vitest';

import { computeRanks, isRotatingBoard, liveBoardsFor } from '../src/ranks';

describe('computeRanks', () => {
  it('assigns 1-based ranks in the order given', () => {
    expect(
      computeRanks([
        { uid: 'a', score: 900 },
        { uid: 'b', score: 500 },
        { uid: 'c', score: 100 },
      ]),
    ).toEqual([
      { uid: 'a', rank: 1 },
      { uid: 'b', rank: 2 },
      { uid: 'c', rank: 3 },
    ]);
  });

  it("does not re-sort — it trusts the caller's own score-descending order", () => {
    // The caller is a Firestore query already ordered by score desc; a
    // second sort here would risk disagreeing with it on a tie-break rule.
    const scores = [
      { uid: 'z', score: 1 },
      { uid: 'a', score: 999 },
    ];
    expect(computeRanks(scores).map((entry) => entry.uid)).toEqual(['z', 'a']);
  });

  it('an empty board ranks nothing', () => {
    expect(computeRanks([])).toEqual([]);
  });

  it('gives a true rank far outside any reasonable top-100 window', () => {
    const board = Array.from({ length: 250 }, (_, i) => ({
      uid: `p${i}`,
      score: 250 - i,
    }));
    const ranked = computeRanks(board);
    const pinned = ranked.find((entry) => entry.uid === 'p199')!;
    expect(pinned.rank).toBe(200);
    expect(pinned.rank).toBeGreaterThan(100);
  });
});

describe('isRotatingBoard', () => {
  it('flags weekly and daily boards, which accumulate stale rank keys over time', () => {
    expect(isRotatingBoard('weekly_2026-W36')).toBe(true);
    expect(isRotatingBoard('daily_2026-08-31')).toBe(true);
  });

  it('leaves the evergreen boards alone', () => {
    expect(isRotatingBoard('global')).toBe(false);
    expect(isRotatingBoard('en')).toBe(false);
    expect(isRotatingBoard('ur')).toBe(false);
  });
});

describe('liveBoardsFor', () => {
  it('is exactly the six tabs the leaderboard screen shows', () => {
    const boards = liveBoardsFor(new Date(Date.UTC(2026, 7, 31, 12)));
    expect(boards).toEqual([
      'global',
      'ur',
      'hi',
      'en',
      'weekly_2026-W36',
      'daily_2026-08-31',
    ]);
  });

  it('rolls the daily board forward across a UTC midnight', () => {
    const justBefore = liveBoardsFor(new Date(Date.UTC(2026, 7, 31, 23, 59)));
    const justAfter = liveBoardsFor(new Date(Date.UTC(2026, 8, 1, 0, 1)));
    expect(justBefore).toContain('daily_2026-08-31');
    expect(justAfter).toContain('daily_2026-09-01');
  });
});
