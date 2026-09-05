/**
 * Pure unit coverage for `crossesReportThreshold` — the one real decision in
 * `nameReports.ts`, split out precisely so it can be walked with no emulator.
 * `applyNameReport`'s own transaction is covered against a real Firestore in
 * `test/integration/moderation.test.ts`.
 */

import { describe, expect, it } from 'vitest';

import { crossesReportThreshold } from '../src/nameReports';

describe('crossesReportThreshold', () => {
  it('does not cross with one report, threshold 3', () => {
    expect(crossesReportThreshold([], 'alice', 3)).toBe(false);
  });

  it('does not cross with two DISTINCT reporters, threshold 3', () => {
    expect(crossesReportThreshold(['alice'], 'bob', 3)).toBe(false);
  });

  it('crosses on the third distinct reporter', () => {
    expect(crossesReportThreshold(['alice', 'bob'], 'carol', 3)).toBe(true);
  });

  it('crosses when already past threshold (a 4th, 5th... reporter)', () => {
    expect(crossesReportThreshold(['a', 'b', 'c'], 'd', 3)).toBe(true);
  });

  it('never crosses on a REPEAT reporter, no matter how many times', () => {
    // The whole point: one hostile account cannot blank a name alone by
    // reporting it repeatedly.
    expect(crossesReportThreshold(['alice', 'alice', 'alice'], 'alice', 3)).toBe(false);
  });

  it('a repeat reporter does not consume a threshold slot for anyone else', () => {
    expect(crossesReportThreshold(['alice'], 'alice', 3)).toBe(false);
  });

  it('defaults to LIMITS.nameReportThreshold when no threshold is given', () => {
    // Two distinct reporters is one below the shipped threshold (3).
    expect(crossesReportThreshold(['alice'], 'bob')).toBe(false);
    expect(crossesReportThreshold(['alice', 'bob'], 'carol')).toBe(true);
  });
});
