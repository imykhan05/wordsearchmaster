import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/domain/progression/day_key.dart';

void main() {
  group('fromDateTime', () {
    test('reads the UTC calendar day, whatever timezone it carries', () {
      final utc = DateTime.utc(2026, 8, 26, 14, 30);
      expect(DayKey.fromDateTime(utc).toString(), '2026-08-26');
      expect(DayKey.fromDateTime(utc.toLocal()), DayKey.fromDateTime(utc));
    });

    test('the whole UTC day maps to one key', () {
      final keys = {
        for (var hour = 0; hour < 24; hour++)
          DayKey.fromDateTime(DateTime.utc(2026, 8, 26, hour, 59, 59)),
      };
      expect(keys, hasLength(1));
    });

    test('one second past UTC midnight is the next day', () {
      expect(
        DayKey.fromDateTime(DateTime.utc(2026, 8, 26, 23, 59, 59)).toString(),
        '2026-08-26',
      );
      expect(
        DayKey.fromDateTime(DateTime.utc(2026, 8, 27, 0, 0, 1)).toString(),
        '2026-08-27',
      );
    });
  });

  group('parse', () {
    test('round-trips toString', () {
      const value = '2026-08-26';
      expect(DayKey.parse(value).toString(), value);
    });

    test('rejects a malformed string', () {
      expect(() => DayKey.parse('2026-8-26'), throwsFormatException);
      expect(() => DayKey.parse('26-08-2026'), throwsFormatException);
      expect(() => DayKey.parse(''), throwsFormatException);
      expect(() => DayKey.parse('not a date'), throwsFormatException);
    });

    test('rejects a date that is not a real calendar day', () {
      // A normalising parse would silently turn this into March 2nd, and then
      // two different strings would compare equal after a round trip.
      expect(() => DayKey.parse('2026-02-30'), throwsFormatException);
      expect(() => DayKey.parse('2026-13-01'), throwsFormatException);
    });

    test('accepts a real leap day', () {
      expect(DayKey.parse('2028-02-29').toString(), '2028-02-29');
    });
  });

  group('arithmetic', () {
    test('next and previous step one day', () {
      final day = DayKey.parse('2026-08-26');
      expect(day.next.toString(), '2026-08-27');
      expect(day.previous.toString(), '2026-08-25');
    });

    test('crosses a month boundary', () {
      expect(DayKey.parse('2026-08-31').next.toString(), '2026-09-01');
      expect(DayKey.parse('2026-09-01').previous.toString(), '2026-08-31');
    });

    test('crosses a year boundary', () {
      expect(DayKey.parse('2026-12-31').next.toString(), '2027-01-01');
    });

    test('crosses a leap day', () {
      expect(DayKey.parse('2028-02-28').next.toString(), '2028-02-29');
      expect(DayKey.parse('2028-02-29').next.toString(), '2028-03-01');
      expect(DayKey.parse('2027-02-28').next.toString(), '2027-03-01');
    });

    test('daysSince is signed and counts whole days', () {
      final a = DayKey.parse('2026-08-26');
      final b = DayKey.parse('2026-09-02');

      expect(b.daysSince(a), 7);
      expect(a.daysSince(b), -7);
      expect(a.daysSince(a), 0);
    });

    test('daysSince is exact across a DST-shifting stretch', () {
      // Computed from UTC midnights, so the 23- and 25-hour local days that
      // DST creates cannot drop or double a streak day.
      final march = DayKey.parse('2026-03-01');
      final april = DayKey.parse('2026-04-01');
      expect(april.daysSince(march), 31);
    });

    test('addDays walks in both directions', () {
      final day = DayKey.parse('2026-08-26');
      expect(day.addDays(10).toString(), '2026-09-05');
      expect(day.addDays(-10).toString(), '2026-08-16');
      expect(day.addDays(0), day);
    });
  });

  group('ordering and equality', () {
    test('compares chronologically', () {
      final earlier = DayKey.parse('2026-08-26');
      final later = DayKey.parse('2026-08-27');

      expect(earlier < later, isTrue);
      expect(later > earlier, isTrue);
      expect(earlier <= earlier, isTrue);
      expect(earlier >= earlier, isTrue);
      expect(earlier.compareTo(later), lessThan(0));
    });

    test('sorts', () {
      final days = [
        DayKey.parse('2026-09-01'),
        DayKey.parse('2026-08-26'),
        DayKey.parse('2026-08-31'),
      ]..sort();

      expect(days.map((d) => d.toString()).toList(), [
        '2026-08-26',
        '2026-08-31',
        '2026-09-01',
      ]);
    });

    test('value equality, so it works as a map key and in sets', () {
      final a = DayKey.parse('2026-08-26');
      final b = DayKey.fromDateTime(DateTime.utc(2026, 8, 26, 9));

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect({a, b}, hasLength(1));
      expect({a: 1}[b], 1);
    });
  });

  test('utcMidnight is midnight, and is UTC', () {
    final midnight = DayKey.parse('2026-08-26').utcMidnight;

    expect(midnight.isUtc, isTrue);
    expect(midnight.hour, 0);
    expect(midnight.minute, 0);
    expect(midnight.second, 0);
  });
}
