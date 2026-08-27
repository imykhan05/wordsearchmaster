import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/domain/progression/day_key.dart';
import 'package:word_search_master/services/time/trusted_clock.dart';

/// Covers the trust order in `trusted_clock.dart`'s library header: server
/// time when online, local time offline, and a monotonic floor that refuses a
/// clock wound backwards.
final class _FakeServerTime implements ServerTimeSource {
  _FakeServerTime(this.utcNow);

  DateTime? utcNow;
  int calls = 0;
  bool throwOnFetch = false;

  @override
  Future<DateTime?> fetchUtcNow() async {
    calls++;
    if (throwOnFetch) throw StateError('offline');
    return utcNow;
  }
}

void main() {
  DateTime local(int day, [int hour = 12]) => DateTime.utc(2026, 8, day, hour);

  group('offline — the device clock, unmodified', () {
    test('answers from the local clock when no server time exists', () async {
      final clock = TrustedClock(
        marks: InMemoryDayHighWaterMarkStore(),
        localClock: () => local(26),
      );

      final now = await clock.now();

      expect(now.source, TimeSource.local);
      expect(now.day, DayKey.parse('2026-08-26'));
      expect(now.wasRolledBack, isFalse);
    });

    test(
      'a server that throws is treated exactly like one that is absent',
      () async {
        final server = _FakeServerTime(local(26))..throwOnFetch = true;
        final clock = TrustedClock(
          marks: InMemoryDayHighWaterMarkStore(),
          server: server,
          localClock: () => local(26),
        );

        final now = await clock.now();

        expect(now.source, TimeSource.local);
        expect(clock.hasServerTime, isFalse);
      },
    );

    test('today() is the day of now()', () async {
      final clock = TrustedClock(
        marks: InMemoryDayHighWaterMarkStore(),
        localClock: () => local(26, 23),
      );

      expect(await clock.today(), DayKey.parse('2026-08-26'));
    });
  });

  group('the monotonic rollback guard', () {
    test(
      'a clock wound BACK past a day already seen returns the day already seen',
      () async {
        final marks = InMemoryDayHighWaterMarkStore();
        var today = local(26);
        final clock = TrustedClock(marks: marks, localClock: () => today);

        // Day 26 is recorded on the way through.
        expect((await clock.now()).day, DayKey.parse('2026-08-26'));

        // The player winds the clock back a week to replay today's Daily.
        today = local(19);
        final guarded = await clock.now();

        expect(guarded.source, TimeSource.rollbackGuard);
        expect(guarded.day, DayKey.parse('2026-08-26'));
        expect(guarded.wasRolledBack, isTrue);
      },
    );

    test('the mark persists across TrustedClock instances', () async {
      final marks = InMemoryDayHighWaterMarkStore();

      await TrustedClock(marks: marks, localClock: () => local(26)).now();

      // A fresh clock — a new app launch — still honours the stored floor.
      final guarded = await TrustedClock(
        marks: marks,
        localClock: () => local(20),
      ).now();

      expect(guarded.source, TimeSource.rollbackGuard);
      expect(guarded.day, DayKey.parse('2026-08-26'));
    });

    test('time moving FORWARD is accepted and advances the mark', () async {
      final marks = InMemoryDayHighWaterMarkStore();
      var today = local(26);
      final clock = TrustedClock(marks: marks, localClock: () => today);

      await clock.now();
      today = local(28);
      final later = await clock.now();

      expect(later.source, TimeSource.local);
      expect(later.day, DayKey.parse('2026-08-28'));
      expect(await marks.read(), DayKey.parse('2026-08-28'));
    });

    test('the same day again is not a rollback', () async {
      final marks = InMemoryDayHighWaterMarkStore();
      final clock = TrustedClock(marks: marks, localClock: () => local(26, 9));

      await clock.now();
      final again = await TrustedClock(
        marks: marks,
        localClock: () => local(26, 22),
      ).now();

      expect(again.source, TimeSource.local);
    });

    test(
      'a mark that cannot be read loses the guard, not the answer',
      () async {
        final clock = TrustedClock(
          marks: _ThrowingMarks(),
          localClock: () => local(26),
        );

        final now = await clock.now();

        expect(
          now.day,
          DayKey.parse('2026-08-26'),
          reason:
              'a broken guard must never stop the app knowing what day it is',
        );
      },
    );
  });

  group('server time is authoritative in BOTH directions', () {
    test('a server answer is used and recorded', () async {
      final marks = InMemoryDayHighWaterMarkStore();
      final clock = TrustedClock(
        marks: marks,
        server: _FakeServerTime(local(26)),
        localClock: () => local(20),
      );

      final now = await clock.now();

      expect(now.source, TimeSource.server);
      expect(now.day, DayKey.parse('2026-08-26'));
      expect(await marks.read(), DayKey.parse('2026-08-26'));
    });

    test(
      'a server that says it is EARLIER overrides the guard — it is correcting '
      'a clock that was set forward',
      () async {
        final marks = InMemoryDayHighWaterMarkStore(DayKey.parse('2026-12-25'));
        final clock = TrustedClock(
          marks: marks,
          server: _FakeServerTime(local(26)),
          localClock: () => local(26),
        );

        final now = await clock.now();

        expect(now.source, TimeSource.server);
        expect(now.day, DayKey.parse('2026-08-26'));
        expect(
          await marks.read(),
          DayKey.parse('2026-08-26'),
          reason: 'the forged forward mark is corrected, not preserved',
        );
      },
    );

    test(
      'the offset is cached — the network is hit once per session',
      () async {
        final server = _FakeServerTime(local(26));
        var deviceNow = local(26);
        final clock = TrustedClock(
          marks: InMemoryDayHighWaterMarkStore(),
          server: server,
          localClock: () => deviceNow,
        );

        await clock.now();
        await clock.now();
        await clock.now();

        expect(
          server.calls,
          1,
          reason: 'the home screen rebuilds; the radio should not',
        );
        expect(clock.hasServerTime, isTrue);

        // The device clock still ticks under the cached offset.
        deviceNow = local(27);
        expect((await clock.now()).day, DayKey.parse('2026-08-27'));
      },
    );

    test('a corrected offset carries into later reads', () async {
      // Device is a day behind; the server says so once, and every read after
      // that is corrected by the same delta.
      final clock = TrustedClock(
        marks: InMemoryDayHighWaterMarkStore(),
        server: _FakeServerTime(local(26)),
        localClock: () => local(25),
      );

      expect((await clock.now()).day, DayKey.parse('2026-08-26'));
      expect((await clock.now()).day, DayKey.parse('2026-08-26'));
    });
  });

  test('TrustedNow has value equality', () {
    final a = TrustedNow(utc: local(26), source: TimeSource.local);
    final b = TrustedNow(utc: local(26), source: TimeSource.local);

    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(TrustedNow(utc: local(26), source: TimeSource.server)));
  });
}

final class _ThrowingMarks implements DayHighWaterMarkStore {
  @override
  Future<DayKey?> read() async => throw StateError('database unavailable');

  @override
  Future<void> write(DayKey day) async => throw StateError('unavailable');
}
