/**
 * Board ids for `/leaderboards/{board}/entries/{uid}`.
 *
 * ---------------------------------------------------------------------------
 * EVERY KEY IS DERIVED FROM UTC, NEVER FROM A LOCAL CALENDAR
 *
 * The same rule `DayKey` and `ContentRepository.getDailySeed` already keep on
 * the client (P10/P11), for the same reason: a local calendar day disagrees
 * across timezones, so "today's board" would be a different board depending on
 * where the player stands. Here it matters twice over, because the board is
 * shared — two players in Karachi and Delhi comparing scores must be looking
 * at one document, not two.
 *
 * The client sends the date it computed from `DayKey` (already UTC); these
 * helpers derive the week key and normalise the board ids.
 */

import type { LanguageCode } from './config';

/** Boards that accumulate for the life of the account. */
export const GLOBAL_BOARD = 'global';

/**
 * ISO-8601 week key, `YYYY-Www`.
 *
 * ISO weeks start on MONDAY and belong to the year containing their Thursday,
 * which is why the year in the key is not always the year of the date: 2027-01-01
 * is a Friday and therefore sits in 2026-W53. Getting that wrong produces a
 * board that quietly resets three days early once a year, so the Thursday
 * pivot is done explicitly rather than by dividing day-of-year by seven.
 */
export function isoWeekKey(date: Date): string {
  // Work on a UTC copy pinned to midnight so DST and local offsets cannot move
  // the day underneath the arithmetic.
  const pivot = new Date(
    Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()),
  );
  // getUTCDay(): Sunday is 0. ISO wants Monday = 1 … Sunday = 7.
  const isoDayOfWeek = pivot.getUTCDay() === 0 ? 7 : pivot.getUTCDay();
  // Step to the Thursday of this ISO week; its calendar year IS the ISO year.
  pivot.setUTCDate(pivot.getUTCDate() + 4 - isoDayOfWeek);

  const isoYear = pivot.getUTCFullYear();
  const firstThursday = new Date(Date.UTC(isoYear, 0, 4));
  const firstIsoDayOfWeek =
    firstThursday.getUTCDay() === 0 ? 7 : firstThursday.getUTCDay();
  firstThursday.setUTCDate(firstThursday.getUTCDate() + 4 - firstIsoDayOfWeek);

  const week =
    1 + Math.round((pivot.getTime() - firstThursday.getTime()) / (7 * 86400000));

  return `${isoYear}-W${String(week).padStart(2, '0')}`;
}

/** `weekly_2026-W35`. */
export function weeklyBoardId(date: Date): string {
  return `weekly_${isoWeekKey(date)}`;
}

/**
 * `daily_2026-08-31`, keyed by the DATE ALONE.
 *
 * A date has three daily puzzles, one per language (`DailyRepository` keys its
 * rows by `(date, language)`), and they share one board. That is defensible
 * rather than sloppy: `DailyPuzzle` fixes an IDENTICAL shape for all three —
 * 10x10, 8 words, diagonal tier — and `Scoring` is language-blind, so the
 * boards compare like with like; only the word pack differs. If a future
 * prompt decides the packs are not equally hard, the split is
 * `daily_{date}_{lang}` and a migration, and it is flagged in
 * `functions/README.md` rather than assumed away here.
 */
export function dailyBoardId(date: string): string {
  return `daily_${date}`;
}

/** `ur` / `hi` / `en` — one cumulative board per script. */
export function languageBoardId(language: LanguageCode): string {
  return language;
}

/** `YYYY-MM-DD`, the shape `DayKey.toString()` produces. */
export function isDayKey(value: unknown): value is string {
  return typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value);
}

/** Parses a `DayKey` string to a UTC `Date`, or null when it is not a real date. */
export function parseDayKey(value: string): Date | null {
  if (!isDayKey(value)) return null;
  const [year, month, day] = value.split('-').map(Number) as [number, number, number];
  const date = new Date(Date.UTC(year, month - 1, day));
  // Rejects 2026-02-31, which `Date.UTC` would happily roll into March.
  if (
    date.getUTCFullYear() !== year ||
    date.getUTCMonth() !== month - 1 ||
    date.getUTCDate() !== day
  ) {
    return null;
  }
  return date;
}
