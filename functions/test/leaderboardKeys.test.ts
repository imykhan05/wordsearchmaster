import { describe, expect, it } from 'vitest';

import {
  dailyBoardId,
  isDayKey,
  isoWeekKey,
  languageBoardId,
  parseDayKey,
  weeklyBoardId,
} from '../src/leaderboardKeys';

const utc = (iso: string): Date => new Date(`${iso}T00:00:00.000Z`);

describe('ISO week keys', () => {
  it('starts the week on Monday', () => {
    // 2026-08-31 is a Monday; 2026-09-06 is the Sunday that closes that week.
    expect(isoWeekKey(utc('2026-08-31'))).toBe('2026-W36');
    expect(isoWeekKey(utc('2026-09-06'))).toBe('2026-W36');
    expect(isoWeekKey(utc('2026-09-07'))).toBe('2026-W37');
  });

  it('puts early-January days in the previous ISO year when they belong there', () => {
    // The case a naive day-of-year / 7 gets wrong: 2027-01-01 is a Friday, so
    // its ISO week is the last week of 2026. Getting this wrong resets the
    // weekly board three days early, once a year.
    expect(isoWeekKey(utc('2027-01-01'))).toBe('2026-W53');
    expect(isoWeekKey(utc('2027-01-03'))).toBe('2026-W53');
    expect(isoWeekKey(utc('2027-01-04'))).toBe('2027-W01');
  });

  it('puts late-December days in the next ISO year when they belong there', () => {
    // 2024-12-30 is a Monday whose Thursday falls in 2025.
    expect(isoWeekKey(utc('2024-12-30'))).toBe('2025-W01');
  });

  it('pads the week number to two digits so keys sort lexically', () => {
    expect(isoWeekKey(utc('2026-01-05'))).toBe('2026-W02');
  });

  it('is stable across every hour of a UTC day', () => {
    // Two players in different timezones must land on the same board.
    const keys = new Set<string>();
    for (let hour = 0; hour < 24; hour++) {
      keys.add(isoWeekKey(new Date(Date.UTC(2026, 7, 31, hour, 30))));
    }
    expect([...keys]).toEqual(['2026-W36']);
  });
});

describe('board ids', () => {
  it('prefixes the weekly board with its ISO week', () => {
    expect(weeklyBoardId(utc('2026-08-31'))).toBe('weekly_2026-W36');
  });

  it('keys the daily board by date alone', () => {
    expect(dailyBoardId('2026-08-31')).toBe('daily_2026-08-31');
  });

  it('uses the bare language code for a script board', () => {
    expect(languageBoardId('ur')).toBe('ur');
    expect(languageBoardId('hi')).toBe('hi');
    expect(languageBoardId('en')).toBe('en');
  });
});

describe('DayKey parsing', () => {
  it('accepts the shape DayKey.toString produces', () => {
    expect(isDayKey('2026-08-31')).toBe(true);
    expect(isDayKey('2026-8-31')).toBe(false);
    expect(isDayKey('not a date')).toBe(false);
    expect(isDayKey(20260831)).toBe(false);
  });

  it('rejects a well-shaped date that does not exist', () => {
    // `Date.UTC` would silently roll this into March.
    expect(parseDayKey('2026-02-31')).toBeNull();
    expect(parseDayKey('2026-13-01')).toBeNull();
  });

  it('parses a real date at UTC midnight', () => {
    expect(parseDayKey('2026-08-31')?.toISOString()).toBe('2026-08-31T00:00:00.000Z');
  });
});
