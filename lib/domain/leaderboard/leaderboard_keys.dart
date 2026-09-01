/// Board ids for `leaderboards/{board}/entries/{uid}` (P17).
///
/// PURE DART, and a byte-for-byte port of `functions/src/leaderboardKeys.ts`
/// — the client has to compute the SAME `weekly_*`/`daily_*` id the server
/// writes to, with no round trip, purely so the Weekly/Daily tabs know which
/// document to query. Every key is derived from UTC, never the device's local
/// calendar, for the identical reason `DayKey` already gives (P10/P11): two
/// players in different timezones comparing scores must be looking at one
/// document, not two.
library;

import '../progression/day_key.dart';

/// Boards that accumulate for the life of the account.
const String globalBoard = 'global';

/// `ur` / `hi` / `en` — one cumulative board per script, matching
/// `Language.code`.
String languageBoardId(String languageCode) => languageCode;

/// `daily_2026-08-31`, keyed by the UTC date alone — see the server's own
/// header (`leaderboardKeys.ts`) for why all three daily languages share one
/// board.
String dailyBoardId(DayKey day) => 'daily_$day';

/// `daily_{today}`.
String currentDailyBoardId(DateTime now) =>
    dailyBoardId(DayKey.fromDateTime(now));

/// `weekly_{isoWeekKey}`.
String weeklyBoardId(DateTime date) => 'weekly_${isoWeekKey(date)}';

/// ISO-8601 week key, `YYYY-Www`. ISO weeks start on Monday and belong to the
/// year containing their Thursday, which is why the year in the key is not
/// always the calendar year of [date] — `2027-01-01` is a Friday and sits in
/// `2026-W53`. The Thursday pivot is computed explicitly, mirroring the
/// server's own comment on why dividing day-of-year by seven gets this wrong
/// once a year.
String isoWeekKey(DateTime date) {
  final utc = date.toUtc();
  var pivot = DateTime.utc(utc.year, utc.month, utc.day);
  // DateTime.weekday: Monday = 1 ... Sunday = 7 — already ISO-shaped.
  pivot = pivot.add(Duration(days: 4 - pivot.weekday));

  final isoYear = pivot.year;
  // Jan 4th always falls in ISO week 1 by definition; stepping it to that
  // week's own Thursday gives week 1's anchor to measure every other week
  // against.
  var firstThursday = DateTime.utc(isoYear, 1, 4);
  firstThursday = firstThursday.add(Duration(days: 4 - firstThursday.weekday));

  final week = 1 + (pivot.difference(firstThursday).inDays / 7).round();

  return '$isoYear-W${week.toString().padLeft(2, '0')}';
}
