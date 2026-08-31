import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/domain/sync/backoff.dart';

/// Ch10's retry ladder, walked without waiting a single real second.
void main() {
  group('the ladder is Ch10s table, verbatim', () {
    test('immediate, 5s, 30s, 5m, 30m, 6h', () {
      expect(BackoffSchedule.steps, const [
        Duration.zero,
        Duration(seconds: 5),
        Duration(seconds: 30),
        Duration(minutes: 5),
        Duration(minutes: 30),
        Duration(hours: 6),
      ]);
    });

    test('the first attempt waits for nothing', () {
      expect(BackoffSchedule.stepFor(0), Duration.zero);
    });

    test('each failure moves one rung up', () {
      expect(BackoffSchedule.stepFor(1), const Duration(seconds: 5));
      expect(BackoffSchedule.stepFor(2), const Duration(seconds: 30));
      expect(BackoffSchedule.stepFor(3), const Duration(minutes: 5));
      expect(BackoffSchedule.stepFor(4), const Duration(minutes: 30));
      expect(BackoffSchedule.stepFor(5), const Duration(hours: 6));
    });

    test('past the end it stays at six hours rather than giving up', () {
      // A 5xx or an offline device is transient by definition, and the row it
      // stranded is a level the player really finished. There is no attempt
      // count at which throwing it away becomes correct.
      for (final failures in [6, 7, 50, 10000]) {
        expect(BackoffSchedule.stepFor(failures), const Duration(hours: 6));
      }
    });

    test('a nonsensical attempt count clamps instead of throwing', () {
      // `attempts` is a persisted column a SQLite editor can set to anything,
      // and this runs inside a background worker with nowhere to put a crash.
      expect(BackoffSchedule.stepFor(-1), Duration.zero);
      expect(BackoffSchedule.stepFor(-9999), Duration.zero);
    });
  });

  group('jitter', () {
    test('keeps every draw inside +/-20% of the step', () {
      final random = Random(20260901);
      for (
        var failures = 1;
        failures < BackoffSchedule.steps.length;
        failures++
      ) {
        final base = BackoffSchedule.stepFor(failures).inMilliseconds;
        for (var i = 0; i < 2000; i++) {
          final delay = BackoffSchedule.delayFor(
            failures,
            random,
          ).inMilliseconds;
          expect(delay, greaterThanOrEqualTo((base * 0.8).round() - 1));
          expect(delay, lessThanOrEqualTo((base * 1.2).round() + 1));
        }
      }
    });

    test('leaves an immediate retry exactly immediate', () {
      // 20% of nothing is nothing. Jittering step 0 would turn "try now" into
      // a coin flip about whether the first attempt happens at all.
      final random = Random(7);
      for (var i = 0; i < 100; i++) {
        expect(BackoffSchedule.delayFor(0, random), Duration.zero);
      }
    });

    test('actually spreads, rather than landing on one value', () {
      // The whole point of jitter is that a thousand devices leaving the same
      // outage do NOT retry in lockstep. A "jitter" that returned the same
      // number every time would pass a range check and fix nothing.
      final random = Random(11);
      final draws = {
        for (var i = 0; i < 500; i++)
          BackoffSchedule.delayFor(3, random).inMilliseconds,
      };
      expect(draws.length, greaterThan(400));
    });

    test('spans a usefully wide window at the top of the ladder', () {
      final (low, high) = BackoffSchedule.bandFor(5);
      expect(low, const Duration(hours: 4, minutes: 48));
      expect(high, const Duration(hours: 7, minutes: 12));
    });

    test('is deterministic for a given seed, so the queue is testable', () {
      expect(
        BackoffSchedule.delayFor(2, Random(42)),
        BackoffSchedule.delayFor(2, Random(42)),
      );
    });
  });

  group('nextRetryAtMillis', () {
    test('is an absolute instant, not a delay', () {
      const now = 1_756_600_000_000;
      final at = BackoffSchedule.nextRetryAtMillis(
        failures: 2,
        nowMillis: now,
        random: Random(3),
      );
      expect(at, greaterThan(now));
      expect(at - now, inInclusiveRange(24000, 36000));
    });

    test('a first attempt is eligible immediately', () {
      const now = 1_756_600_000_000;
      expect(
        BackoffSchedule.nextRetryAtMillis(
          failures: 0,
          nowMillis: now,
          random: Random(3),
        ),
        now,
      );
    });

    test('three days offline never pushes a row past six hours out', () {
      // The acceptance-criterion shape: a player offline for days accumulates
      // failures, and the queue must still be eligible within one ladder step
      // of coming back rather than parked days into the future.
      const now = 1_756_600_000_000;
      final random = Random(5);
      var attempts = 0;
      for (var i = 0; i < 200; i++) {
        attempts++;
        final at = BackoffSchedule.nextRetryAtMillis(
          failures: attempts,
          nowMillis: now,
          random: random,
        );
        expect(
          at - now,
          lessThanOrEqualTo(const Duration(hours: 8).inMilliseconds),
        );
      }
    });
  });
}
