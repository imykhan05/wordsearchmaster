import { describe, expect, it } from 'vitest';

import { FLAGS, LIMITS } from '../src/config';
import { DAILY_SHAPE, levelShape } from '../src/levels';
import type { ScoreEvent } from '../src/scoring';
import {
  EMPTY_TIMING,
  MalformedSubmission,
  advanceTiming,
  deriveDailyNonce,
  deriveLevelNonce,
  evaluateSubmission,
  nextRateWindow,
  parseDailySubmission,
  parseEvents,
  parseLevelSubmission,
  timingIsPlausible,
  type LevelSubmission,
  type PlayerContext,
} from '../src/validation';

const NOW = Date.UTC(2026, 7, 31, 12, 0, 0);

const found = (g: number): ScoreEvent => ({ t: 'w', g });
const wrong: ScoreEvent = { t: 'x' };
const hint: ScoreEvent = { t: 'h' };

/** A clean level-1 submission: four 3-grapheme words, no hints, no mistakes. */
function honestLevelOne(overrides: Partial<LevelSubmission> = {}): LevelSubmission {
  return {
    kind: 'level',
    language: 'en',
    level: 1,
    events: [found(3), found(3), found(3), found(3)],
    completedAt: NOW - 60_000,
    specVersion: 1,
    nonce: 'level:en:1:1',
    clientStars: 3,
    clientHintsUsed: 0,
    ...overrides,
  };
}

function context(overrides: Partial<PlayerContext> = {}): PlayerContext {
  return {
    serverNowMillis: NOW,
    highestLevel: 0,
    timing: EMPTY_TIMING,
    ...overrides,
  };
}

// ---------------------------------------------------------------------------

describe('parsing rejects what an honest client cannot produce', () => {
  const valid = {
    language: 'en',
    level: 1,
    stars: 3,
    hintsUsed: 0,
    completedAt: NOW,
    specVersion: 1,
    events: [{ t: 'w', g: 3 }],
    nonce: 'n1',
  };

  it('accepts the outbox payload shape verbatim', () => {
    const parsed = parseLevelSubmission(valid);
    expect(parsed.language).toBe('en');
    expect(parsed.level).toBe(1);
    expect(parsed.events).toEqual([{ t: 'w', g: 3 }]);
    expect(parsed.nonce).toBe('n1');
  });

  it.each([
    ['a non-object payload', 'not an object'],
    ['a missing language', { ...valid, language: undefined }],
    ['an unknown language', { ...valid, language: 'fr' }],
    ['a non-integer level', { ...valid, level: 1.5 }],
    ['a missing specVersion', { ...valid, specVersion: undefined }],
    ['a non-array events field', { ...valid, events: {} }],
    ['a completedAt of zero', { ...valid, completedAt: 0 }],
  ])('refuses %s', (_label, payload) => {
    expect(() => parseLevelSubmission(payload)).toThrow(MalformedSubmission);
  });

  it('refuses an events array past the structural ceiling', () => {
    const events = Array.from({ length: LIMITS.maxEvents + 1 }, () => ({ t: 'x' }));
    expect(() => parseEvents(events)).toThrow(MalformedSubmission);
  });

  it('refuses an unreadable event rather than dropping it', () => {
    // The CLIENT's decoder drops what it cannot parse, so a bad queue row
    // never wedges sync. The server must do the opposite: a dropped event
    // silently changes the score.
    expect(() => parseEvents([{ t: 'w' }])).toThrow(MalformedSubmission);
    expect(() => parseEvents([{ t: 'zzz' }])).toThrow(MalformedSubmission);
  });

  it('derives a nonce for a row queued before P14 added the field', () => {
    const parsed = parseLevelSubmission({ ...valid, nonce: undefined });
    expect(parsed.nonce).toBe(deriveLevelNonce('en', 1, NOW));
  });

  it('derives a daily nonce the same way', () => {
    const parsed = parseDailySubmission({
      language: 'ur',
      date: '2026-08-31',
      stars: 3,
      completedAt: NOW,
      specVersion: 1,
      events: [],
    });
    expect(parsed.nonce).toBe(deriveDailyNonce('ur', '2026-08-31', NOW));
  });

  it('refuses a daily whose date is not a DayKey', () => {
    expect(() =>
      parseDailySubmission({
        language: 'ur',
        date: '31-08-2026',
        completedAt: NOW,
        specVersion: 1,
        events: [],
      }),
    ).toThrow(MalformedSubmission);
  });
});

// ---------------------------------------------------------------------------

describe('an honest submission is accepted with no flags', () => {
  it('recomputes the score and raises nothing', () => {
    const result = evaluateSubmission(honestLevelOne(), levelShape(1), context());
    expect(result.flags).toEqual([]);
    expect(result.suspicious).toBe(false);
    // 3*10 + 3*12 + 3*14 + 3*16 = 156.
    expect(result.score).toBe(156);
    expect(result.stars).toBe(3);
    expect(result.wordsFound).toBe(4);
    expect(result.maxCombo).toBe(4);
  });

  it('accepts a level the P12 downshift trimmed by one word', () => {
    const result = evaluateSubmission(
      honestLevelOne({
        level: 100,
        events: Array.from({ length: 9 }, () => found(4)),
        completedAt: NOW - 600_000,
      }),
      levelShape(100),
      context({ highestLevel: 99 }),
    );
    expect(result.flags).toEqual([]);
  });

  it('accepts a replay of a level already finished', () => {
    const result = evaluateSubmission(
      honestLevelOne({ level: 3 }),
      levelShape(3),
      context({ highestLevel: 40 }),
    );
    expect(result.flags).toEqual([]);
  });
});

// ---------------------------------------------------------------------------

describe('every Ch08 check produces a flag rather than an error', () => {
  it('flags a level id outside 1..300', () => {
    const result = evaluateSubmission(
      honestLevelOne({ level: 9999 }),
      null,
      context({ highestLevel: 9998 }),
    );
    expect(result.flags).toContain(FLAGS.unknownLevel);
    expect(result.suspicious).toBe(true);
  });

  it('flags more words than the level contains', () => {
    const result = evaluateSubmission(
      honestLevelOne({ events: Array.from({ length: 12 }, () => found(3)) }),
      levelShape(1),
      context(),
    );
    expect(result.flags).toContain(FLAGS.wordCountOutOfBounds);
  });

  it('flags fewer words than even a downshifted level would have', () => {
    const result = evaluateSubmission(
      honestLevelOne({ events: [found(3)] }),
      levelShape(1),
      context(),
    );
    expect(result.flags).toContain(FLAGS.wordCountOutOfBounds);
  });

  it('flags a word longer than the board', () => {
    const result = evaluateSubmission(
      honestLevelOne({ events: [found(3), found(3), found(3), found(11)] }),
      levelShape(1),
      context(),
    );
    expect(result.flags).toContain(FLAGS.graphemeCountImplausible);
  });

  it('flags a spec version the server does not implement', () => {
    const result = evaluateSubmission(
      honestLevelOne({ specVersion: 99 }),
      levelShape(1),
      context(),
    );
    expect(result.flags).toContain(FLAGS.specVersionMismatch);
  });

  it('flags a completion stamped in the future', () => {
    const result = evaluateSubmission(
      honestLevelOne({ completedAt: NOW + 86_400_000 }),
      levelShape(1),
      context(),
    );
    expect(result.flags).toContain(FLAGS.clockAhead);
  });

  it('flags a completion from before the game existed', () => {
    const result = evaluateSubmission(
      honestLevelOne({ completedAt: NOW - 500 * 86_400_000 }),
      levelShape(1),
      context(),
    );
    expect(result.flags).toContain(FLAGS.clockRewound);
  });

  it('does NOT flag a completion that predates the account document', () => {
    // The outbox makes this normal: the `users/{uid}` doc is created by the
    // first submission, and the levels in it were played before that.
    const result = evaluateSubmission(
      honestLevelOne({ completedAt: NOW - 30 * 86_400_000 }),
      levelShape(1),
      context(),
    );
    expect(result.flags).not.toContain(FLAGS.clockRewound);
  });

  it('flags a level reached without playing the one before it', () => {
    const result = evaluateSubmission(
      honestLevelOne({
        level: 250,
        events: Array.from({ length: 12 }, () => found(5)),
      }),
      levelShape(250),
      context({ highestLevel: 3 }),
    );
    expect(result.flags).toContain(FLAGS.progressionGap);
  });

  it('flags a star count that disagrees with the events', () => {
    const result = evaluateSubmission(
      honestLevelOne({
        events: [found(3), found(3), found(3), found(3), hint],
        clientStars: 3,
      }),
      levelShape(1),
      context(),
    );
    expect(result.flags).toContain(FLAGS.clientStarsMismatch);
    // And the SERVER's number is what comes back, not the claim.
    expect(result.stars).toBe(2);
  });

  it('flags a hint count that disagrees with the events', () => {
    const result = evaluateSubmission(
      honestLevelOne({ clientHintsUsed: 7 }),
      levelShape(1),
      context(),
    );
    expect(result.flags).toContain(FLAGS.clientHintsMismatch);
  });

  it('flags more hints than the level has words', () => {
    const result = evaluateSubmission(
      honestLevelOne({
        events: [found(3), found(3), found(3), found(3), hint, hint, hint, hint, hint],
        clientHintsUsed: 5,
        clientStars: 1,
      }),
      levelShape(1),
      context(),
    );
    expect(result.flags).toContain(FLAGS.hintCountImplausible);
  });
});

// ---------------------------------------------------------------------------

describe('the timing floor', () => {
  it('never flags the very first submission, however fast', () => {
    const result = evaluateSubmission(honestLevelOne(), levelShape(1), context());
    expect(result.flags).not.toContain(FLAGS.timingFloor);
  });

  /** A full, correct replay of [level] — the right number of words for its curve step. */
  function fullClear(level: number, completedAt: number): LevelSubmission {
    return honestLevelOne({
      level,
      completedAt,
      events: Array.from({ length: levelShape(level).wordCount }, () => found(3)),
    });
  }

  it('flags fifty levels claimed inside one second', () => {
    let timing = EMPTY_TIMING;
    const start = NOW - 500;
    let flagged = false;
    for (let i = 0; i < 50; i++) {
      const result = evaluateSubmission(
        fullClear(i + 1, start + i),
        levelShape(i + 1),
        context({ timing, highestLevel: i }),
      );
      timing = result.timing;
      if (result.flags.includes(FLAGS.timingFloor)) flagged = true;
    }
    expect(flagged).toBe(true);
  });

  it('does not flag the same fifty levels played at a human pace', () => {
    let timing = EMPTY_TIMING;
    const start = NOW - 50 * 10 * 60_000;
    for (let i = 0; i < 50; i++) {
      const result = evaluateSubmission(
        fullClear(i + 1, start + i * 10 * 60_000),
        levelShape(i + 1),
        context({ timing, highestLevel: i }),
      );
      timing = result.timing;
      expect(result.flags).toEqual([]);
    }
  });

  it('is order independent, so an out-of-order outbox retry is not a flag', () => {
    // The outbox retries, and a retried row can land behind a newer one. A
    // check written as "this minus the previous" would flag that; a cumulative
    // span check does not.
    const forward = [0, 1, 2].reduce(
      (timing, i) => advanceTiming(timing, NOW + i * 60_000, 4),
      EMPTY_TIMING,
    );
    const reversed = [2, 0, 1].reduce(
      (timing, i) => advanceTiming(timing, NOW + i * 60_000, 4),
      EMPTY_TIMING,
    );
    expect(timingIsPlausible(forward)).toBe(timingIsPlausible(reversed));
    expect(forward.minRequiredMillis).toBe(reversed.minRequiredMillis);
  });

  it('refuses to let a future-stamped completion widen the span', () => {
    // The cheapest attack on a cumulative bound is to inflate the bound.
    const clean = evaluateSubmission(honestLevelOne(), levelShape(1), context());
    const withForgery = evaluateSubmission(
      honestLevelOne({ completedAt: NOW + 400 * 86_400_000, level: 2 }),
      levelShape(2),
      context({ timing: clean.timing, highestLevel: 1 }),
    );
    expect(withForgery.flags).toContain(FLAGS.clockAhead);
    expect(withForgery.timing).toEqual(clean.timing);
  });
});

// ---------------------------------------------------------------------------

describe('rate limiting', () => {
  it('opens a fresh window on a first submission', () => {
    const result = nextRateWindow(null, NOW);
    expect(result.allowed).toBe(true);
    expect(result.window).toEqual({ windowStartMillis: NOW, count: 1 });
  });

  it('refuses past the ceiling inside one window', () => {
    const full = { windowStartMillis: NOW, count: LIMITS.rateMaxSubmissions };
    expect(nextRateWindow(full, NOW + 1000).allowed).toBe(false);
  });

  it('rolls the window over once it has expired', () => {
    const full = { windowStartMillis: NOW, count: LIMITS.rateMaxSubmissions };
    const rolled = nextRateWindow(full, NOW + LIMITS.rateWindowMillis + 1);
    expect(rolled.allowed).toBe(true);
    expect(rolled.window.count).toBe(1);
  });

  it('leaves room for an offline backlog to drain in one burst', () => {
    // Twenty levels played on a plane arrive within seconds of the radio
    // returning. A limit that rejected that would reject real progress.
    let window = nextRateWindow(null, NOW).window;
    for (let i = 1; i < 20; i++) {
      const step = nextRateWindow(window, NOW + i);
      expect(step.allowed).toBe(true);
      window = step.window;
    }
  });
});

// ---------------------------------------------------------------------------

describe('dailies are bounded by the fixed DailyPuzzle shape', () => {
  it('accepts eight words on a 10x10', () => {
    const result = evaluateSubmission(
      {
        kind: 'daily',
        language: 'hi',
        date: '2026-08-31',
        events: Array.from({ length: 8 }, () => found(4)),
        completedAt: NOW - 300_000,
        specVersion: 1,
        nonce: 'daily:hi:2026-08-31:1',
        clientStars: 3,
        clientHintsUsed: 0,
      },
      DAILY_SHAPE,
      context(),
    );
    expect(result.flags).toEqual([]);
  });

  it('flags a daily claiming twelve words', () => {
    const result = evaluateSubmission(
      {
        kind: 'daily',
        language: 'hi',
        date: '2026-08-31',
        events: Array.from({ length: 12 }, () => found(4)),
        completedAt: NOW - 300_000,
        specVersion: 1,
        nonce: 'daily:hi:2026-08-31:1',
        clientStars: 3,
        clientHintsUsed: 0,
      },
      DAILY_SHAPE,
      context(),
    );
    expect(result.flags).toContain(FLAGS.wordCountOutOfBounds);
  });

  it('never applies the journey progression rule to a daily', () => {
    const result = evaluateSubmission(
      {
        kind: 'daily',
        language: 'en',
        date: '2026-08-31',
        events: Array.from({ length: 8 }, () => found(4)),
        completedAt: NOW - 300_000,
        specVersion: 1,
        nonce: 'daily:en:2026-08-31:1',
        clientStars: 3,
        clientHintsUsed: 0,
      },
      DAILY_SHAPE,
      context({ highestLevel: 0 }),
    );
    expect(result.flags).not.toContain(FLAGS.progressionGap);
  });
});

// ---------------------------------------------------------------------------

it('never reads a score off the client, because there is nowhere to put one', () => {
  // A forged payload that carries an inflated `score` field: it is not part of
  // the parsed submission at all, so there is no code path that could read it.
  const parsed = parseLevelSubmission({
    language: 'en',
    level: 1,
    stars: 3,
    hintsUsed: 0,
    score: 999_999,
    completedAt: NOW,
    specVersion: 1,
    events: [found(3), found(3), found(3), found(3)],
    nonce: 'n',
  });
  expect(Object.keys(parsed)).not.toContain('score');

  const result = evaluateSubmission(parsed, levelShape(1), context());
  expect(result.score).toBe(156);
});

it('does not flag a wrong selection, which is just a player missing', () => {
  const result = evaluateSubmission(
    honestLevelOne({
      events: [found(3), wrong, wrong, found(3), found(3), wrong, found(3)],
    }),
    levelShape(1),
    context(),
  );
  expect(result.flags).toEqual([]);
});
