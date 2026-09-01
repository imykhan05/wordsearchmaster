import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/domain/leaderboard/leaderboard_keys.dart';
import 'package:word_search_master/domain/progression/day_key.dart';

/// Parity cases lifted straight from `functions/test/leaderboardKeys.test.ts`
/// — the client has to compute the identical board id the server writes to,
/// with no round trip, so the fixture is shared by inspection rather than by
/// a generated file (there is no cross-language port harness for this one,
/// unlike `Scoring`/P14 — the stakes here are "wrong tab shows the wrong
/// board", not a rejected submission).
void main() {
  DateTime utc(String yyyyMmDd) => DateTime.parse('${yyyyMmDd}T00:00:00Z');

  group('isoWeekKey', () {
    test('an ordinary week', () {
      expect(isoWeekKey(utc('2026-08-31')), '2026-W36');
      expect(isoWeekKey(utc('2026-09-06')), '2026-W36');
      expect(isoWeekKey(utc('2026-09-07')), '2026-W37');
    });

    test('a year boundary where the ISO year lags the calendar year', () {
      // 2027-01-01 is a Friday, so it belongs to 2026's last week — the case
      // a naive day-of-year/7 division gets wrong.
      expect(isoWeekKey(utc('2027-01-01')), '2026-W53');
      expect(isoWeekKey(utc('2027-01-03')), '2026-W53');
      expect(isoWeekKey(utc('2027-01-04')), '2027-W01');
    });

    test('a year boundary where the ISO year leads the calendar year', () {
      expect(isoWeekKey(utc('2024-12-30')), '2025-W01');
    });

    test('an ordinary week 2', () {
      expect(isoWeekKey(utc('2026-01-05')), '2026-W02');
    });

    test('stable across every UTC hour of one day', () {
      final keys = <String>{
        for (var hour = 0; hour < 24; hour++)
          isoWeekKey(DateTime.utc(2026, 8, 31, hour, 30)),
      };
      expect(keys, {'2026-W36'});
    });
  });

  test('weeklyBoardId prefixes the week key', () {
    expect(weeklyBoardId(utc('2026-08-31')), 'weekly_2026-W36');
  });

  test('dailyBoardId is DayKey.toString(), prefixed', () {
    expect(dailyBoardId(DayKey.parse('2026-08-31')), 'daily_2026-08-31');
  });

  test('currentDailyBoardId reads the UTC calendar day', () {
    expect(currentDailyBoardId(utc('2026-08-31')), 'daily_2026-08-31');
  });

  test('languageBoardId is the bare language code', () {
    expect(languageBoardId('ur'), 'ur');
    expect(languageBoardId('hi'), 'hi');
    expect(languageBoardId('en'), 'en');
  });
}
