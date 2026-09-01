import { describe, expect, it } from 'vitest';

import {
  ACHIEVEMENTS,
  EMPTY_STATS,
  THRESHOLDS,
  advanceEngagementStreak,
  advanceStats,
  readUserStats,
  statsUpdatePayload,
  type AcceptedSubmissionEvent,
  type UserStats,
} from '../src/stats';

function level(
  overrides: Partial<AcceptedSubmissionEvent> = {},
): AcceptedSubmissionEvent {
  return {
    kind: 'level',
    language: 'en',
    wordsFound: 4,
    hintsUsed: 0,
    completedAtMillis: Date.UTC(2026, 7, 31, 12, 0, 0),
    ...overrides,
  };
}

describe('First Word', () => {
  it('unlocks on the very first accepted word', () => {
    const { newlyUnlocked } = advanceStats(EMPTY_STATS, level({ wordsFound: 1 }));
    expect(newlyUnlocked).toContain(ACHIEVEMENTS.firstWord);
  });

  it('does not re-unlock on a later submission', () => {
    const first = advanceStats(EMPTY_STATS, level({ wordsFound: 1 }));
    const second = advanceStats(first.stats, level({ wordsFound: 1 }));
    expect(second.newlyUnlocked).not.toContain(ACHIEVEMENTS.firstWord);
  });

  it('does not unlock on zero words (a mistakes-only run)', () => {
    const { newlyUnlocked } = advanceStats(EMPTY_STATS, level({ wordsFound: 0 }));
    expect(newlyUnlocked).not.toContain(ACHIEVEMENTS.firstWord);
  });
});

describe('Word Master (500 words)', () => {
  it('unlocks the moment the cumulative total crosses the threshold', () => {
    let stats = EMPTY_STATS;
    let unlockedAt = -1;
    for (let i = 0; i < 200; i++) {
      const advance = advanceStats(stats, level({ wordsFound: 3 }));
      stats = advance.stats;
      if (
        advance.newlyUnlocked.includes(ACHIEVEMENTS.wordMaster) &&
        unlockedAt === -1
      ) {
        unlockedAt = stats.wordsFoundTotal;
      }
    }
    expect(unlockedAt).toBeGreaterThanOrEqual(THRESHOLDS.wordMasterWords);
    // And the crossing submission is the FIRST one at or past 500, not later.
    expect(unlockedAt - 3).toBeLessThan(THRESHOLDS.wordMasterWords);
  });
});

describe('Trilingual', () => {
  it('requires all three languages, not just two', () => {
    let stats = EMPTY_STATS;
    stats = advanceStats(stats, level({ language: 'en' })).stats;
    const afterTwo = advanceStats(stats, level({ language: 'ur' }));
    expect(afterTwo.newlyUnlocked).not.toContain(ACHIEVEMENTS.trilingual);

    const afterThree = advanceStats(afterTwo.stats, level({ language: 'hi' }));
    expect(afterThree.newlyUnlocked).toContain(ACHIEVEMENTS.trilingual);
  });

  it('counts a daily as having "played" a language too', () => {
    let stats = EMPTY_STATS;
    stats = advanceStats(stats, level({ language: 'en' })).stats;
    stats = advanceStats(stats, level({ kind: 'daily', language: 'ur' })).stats;
    const { newlyUnlocked } = advanceStats(stats, level({ language: 'hi' }));
    expect(newlyUnlocked).toContain(ACHIEVEMENTS.trilingual);
  });

  it('replaying the same language repeatedly never unlocks it alone', () => {
    let stats = EMPTY_STATS;
    for (let i = 0; i < 10; i++) {
      stats = advanceStats(stats, level({ language: 'en' })).stats;
    }
    expect(stats.languagesPlayed).toEqual(['en']);
  });
});

describe('On Fire (5 levels, no hints)', () => {
  it('unlocks on the fifth consecutive hint-free LEVEL', () => {
    let stats = EMPTY_STATS;
    let unlocked = false;
    for (let i = 0; i < 5; i++) {
      const advance = advanceStats(stats, level({ hintsUsed: 0 }));
      stats = advance.stats;
      unlocked = advance.newlyUnlocked.includes(ACHIEVEMENTS.onFire);
    }
    expect(unlocked).toBe(true);
    expect(stats.onFireStreak).toBe(5);
  });

  it('a single hint resets the streak to zero', () => {
    let stats = EMPTY_STATS;
    for (let i = 0; i < 4; i++) {
      stats = advanceStats(stats, level({ hintsUsed: 0 })).stats;
    }
    expect(stats.onFireStreak).toBe(4);
    stats = advanceStats(stats, level({ hintsUsed: 1 })).stats;
    expect(stats.onFireStreak).toBe(0);
  });

  it('a hint-free DAILY neither advances nor breaks the level streak', () => {
    let stats = EMPTY_STATS;
    for (let i = 0; i < 3; i++) {
      stats = advanceStats(stats, level({ hintsUsed: 0 })).stats;
    }
    stats = advanceStats(stats, level({ kind: 'daily', hintsUsed: 5 })).stats;
    expect(stats.onFireStreak).toBe(3);
  });
});

describe('Daily Devotee (10 dailies)', () => {
  it('unlocks on the tenth accepted daily', () => {
    let stats = EMPTY_STATS;
    let unlocked = false;
    for (let i = 0; i < 10; i++) {
      const advance = advanceStats(stats, level({ kind: 'daily' }));
      stats = advance.stats;
      unlocked = advance.newlyUnlocked.includes(ACHIEVEMENTS.dailyDevotee);
    }
    expect(unlocked).toBe(true);
  });

  it('a level submission does not count toward it', () => {
    let stats = EMPTY_STATS;
    for (let i = 0; i < 20; i++) {
      stats = advanceStats(stats, level({ kind: 'level' })).stats;
    }
    expect(stats.dailyCount).toBe(0);
  });
});

describe('advanceEngagementStreak — Streak Keeper backing counter', () => {
  const day = (iso: string) =>
    Date.UTC(
      Number(iso.slice(0, 4)),
      Number(iso.slice(5, 7)) - 1,
      Number(iso.slice(8, 10)),
      12,
    );

  it('starts at 1 on the first day ever seen', () => {
    const state = advanceEngagementStreak(
      EMPTY_STATS.engagementStreak,
      day('2026-08-25'),
    );
    expect(state).toEqual({ current: 1, lastDay: '2026-08-25' });
  });

  it('extends by one on the very next UTC day', () => {
    const first = advanceEngagementStreak(
      EMPTY_STATS.engagementStreak,
      day('2026-08-25'),
    );
    const second = advanceEngagementStreak(first, day('2026-08-26'));
    expect(second).toEqual({ current: 2, lastDay: '2026-08-26' });
  });

  it('a second submission on the SAME day does not double-count', () => {
    const first = advanceEngagementStreak(
      EMPTY_STATS.engagementStreak,
      day('2026-08-25'),
    );
    const again = advanceEngagementStreak(first, day('2026-08-25'));
    expect(again).toEqual(first);
  });

  it('a gap of more than one day restarts the streak at 1', () => {
    const first = advanceEngagementStreak(
      EMPTY_STATS.engagementStreak,
      day('2026-08-25'),
    );
    const gapped = advanceEngagementStreak(first, day('2026-08-28'));
    expect(gapped).toEqual({ current: 1, lastDay: '2026-08-28' });
  });

  it('seven consecutive days unlocks Streak Keeper', () => {
    let stats = EMPTY_STATS;
    let unlocked = false;
    for (let i = 0; i < 7; i++) {
      const advance = advanceStats(
        stats,
        level({ completedAtMillis: day('2026-08-2' + (0 + i)) }),
      );
      stats = advance.stats;
      unlocked = advance.newlyUnlocked.includes(ACHIEVEMENTS.streakKeeper);
    }
    expect(unlocked).toBe(true);
  });

  it('AN OUT-OF-ORDER BACKLOG ROW does not corrupt an established streak', () => {
    // The outbox can and does deliver an older row after a newer one.
    let stats = advanceEngagementStreak(
      EMPTY_STATS.engagementStreak,
      day('2026-08-25'),
    );
    stats = advanceEngagementStreak(stats, day('2026-08-26'));
    expect(stats.current).toBe(2);

    // A backlog row from BEFORE the streak started, arriving late.
    const late = advanceEngagementStreak(stats, day('2026-08-20'));
    expect(late).toEqual(stats); // unchanged — never regresses.
  });
});

describe('achievements only advance through advanceStats, never regress', () => {
  it('an already-unlocked id is never listed again, and progress keeps moving', () => {
    const stats = advanceStats(EMPTY_STATS, level({ wordsFound: 1 })).stats;
    expect(stats.achievements.has(ACHIEVEMENTS.firstWord)).toBe(true);

    const { newlyUnlocked, stats: after } = advanceStats(
      stats,
      level({ wordsFound: 1 }),
    );
    expect(newlyUnlocked).toEqual([]);
    expect(after.achievements.has(ACHIEVEMENTS.firstWord)).toBe(true);
  });
});

describe('readUserStats', () => {
  it('degrades a missing stats field to EMPTY_STATS', () => {
    expect(readUserStats(undefined)).toEqual(EMPTY_STATS);
    expect(readUserStats({})).toEqual(EMPTY_STATS);
  });

  it('degrades a malformed stats field rather than throwing', () => {
    expect(readUserStats({ stats: 'not an object' })).toEqual(EMPTY_STATS);
    expect(
      readUserStats({
        stats: { wordsFoundTotal: 'lots', languagesPlayed: 'en', achievements: 42 },
      }),
    ).toEqual(EMPTY_STATS);
  });

  it('round-trips a real stats object, including which achievements unlocked', () => {
    const written: UserStats = {
      wordsFoundTotal: 12,
      dailyCount: 3,
      onFireStreak: 2,
      languagesPlayed: ['en', 'ur'],
      engagementStreak: { current: 4, lastDay: '2026-08-30' },
      achievements: new Set([ACHIEVEMENTS.firstWord, ACHIEVEMENTS.trilingual]),
    };
    const asFirestoreDoc = {
      stats: {
        ...written,
        achievements: {
          [ACHIEVEMENTS.firstWord]: { unlockedAt: 1 },
          [ACHIEVEMENTS.trilingual]: { unlockedAt: 2 },
        },
      },
    };
    expect(readUserStats(asFirestoreDoc)).toEqual(written);
  });

  it('ignores an unknown achievement id rather than crashing on it', () => {
    const result = readUserStats({
      stats: { achievements: { not_a_real_id: { unlockedAt: 1 } } },
    });
    expect(result.achievements.size).toBe(0);
  });
});

describe('statsUpdatePayload', () => {
  it('omits achievements entirely when nothing unlocked THIS submission', () => {
    const advance = advanceStats(
      { ...EMPTY_STATS, achievements: new Set([ACHIEVEMENTS.firstWord]) },
      level({ wordsFound: 1 }),
    );
    const payload = statsUpdatePayload(advance);
    expect('achievements' in payload).toBe(false);
  });

  it('includes only the NEWLY unlocked ids when something does unlock', () => {
    const advance = advanceStats(EMPTY_STATS, level({ wordsFound: 1 }));
    const payload = statsUpdatePayload(advance);
    expect(Object.keys(payload['achievements'] as object)).toEqual([
      ACHIEVEMENTS.firstWord,
    ]);
  });
});
