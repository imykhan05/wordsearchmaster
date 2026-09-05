/**
 * Pure unit coverage for `shouldRemind` — the one real decision in
 * `streakReminders.ts`. The query/send/write-back plumbing around it needs a
 * real Firestore and a fake transport, so it lives in
 * `test/integration/streakReminders.test.ts` instead.
 */

import { describe, expect, it } from 'vitest';

import { shouldRemind } from '../src/streakReminders';

describe('shouldRemind', () => {
  it("reminds when the streak's last day was yesterday and nothing was sent today", () => {
    expect(
      shouldRemind({ current: 3, lastDay: '2026-09-04' }, '2026-09-05', null),
    ).toBe(true);
  });

  it('does not remind when there is no streak to lose', () => {
    expect(
      shouldRemind({ current: 0, lastDay: '2026-09-04' }, '2026-09-05', null),
    ).toBe(false);
  });

  it('does not remind when the player already played today', () => {
    expect(
      shouldRemind({ current: 3, lastDay: '2026-09-05' }, '2026-09-05', null),
    ).toBe(false);
  });

  it('does not remind when the streak already lapsed (2+ days ago)', () => {
    // A "you lost it" push is not what this function sends — see its header.
    expect(
      shouldRemind({ current: 3, lastDay: '2026-09-01' }, '2026-09-05', null),
    ).toBe(false);
  });

  it('never reminds twice in the same UTC day — the max-1-push-per-day rule', () => {
    expect(
      shouldRemind({ current: 3, lastDay: '2026-09-04' }, '2026-09-05', '2026-09-05'),
    ).toBe(false);
  });

  it('a push sent on an EARLIER day does not block a new one today', () => {
    expect(
      shouldRemind({ current: 3, lastDay: '2026-09-04' }, '2026-09-05', '2026-09-03'),
    ).toBe(true);
  });

  it('a streak with no lastDay at all is never reminded', () => {
    expect(shouldRemind({ current: 0, lastDay: null }, '2026-09-05', null)).toBe(false);
  });
});
