/// Retry schedule for the outbox (Ch10 / P16).
///
/// PURE DART. No clock and no `Random` it did not receive as an argument —
/// the same discipline `dda.dart` and `coin_economy.dart` keep, and the reason
/// `backoff_test.dart` can walk every step of the ladder deterministically
/// without waiting a single real second.
///
/// ---------------------------------------------------------------------------
/// THE LADDER IS Ch10'S, VERBATIM
///
///   attempt 1  immediate
///   attempt 2  5s
///   attempt 3  30s
///   attempt 4  5m
///   attempt 5  30m
///   attempt 6+ 6h
///
/// Six steps spanning six hours, which is a deliberate shape rather than a
/// smooth exponential curve. The first retry is instant because the commonest
/// failure by far is a two-second connectivity blip while walking past a
/// tunnel; the last is six hours because the second-commonest is a player who
/// has no data balance until they next top up. A curve tuned for one of those
/// serves the other badly.
///
/// ---------------------------------------------------------------------------
/// WHY THE LADDER NEVER GIVES UP
///
/// There is no "too many attempts, drop it" step, and that is not an
/// oversight. A 5xx or an offline device is a TRANSIENT condition by
/// definition, and the row it stranded is a level the player really finished.
/// Ch01's audience is on 2G in places where a week without a working
/// connection is ordinary, so a queue that expired its rows would lose real
/// progress from exactly the players this game is for. Rows only ever leave
/// the queue by succeeding or by being refused permanently (a 4xx), and that
/// second case is `OutboxStatus.failedPermanent`, not an attempt count.
///
/// ---------------------------------------------------------------------------
/// WHY THE JITTER MATTERS MORE THAN THE DELAYS
///
/// Every device that lost connectivity during the same outage regains it at
/// roughly the same moment, and each then walks the same fixed ladder — so
/// without jitter the retries stay in lockstep and arrive as a series of
/// synchronised spikes, each one landing on a backend that is still recovering
/// from the outage that caused them. That is a thundering herd, and it is
/// self-inflicted: the spikes exist only because every client agreed on the
/// same delay.
///
/// +/-20% spreads a step across a window wide enough to flatten the spike
/// while staying narrow enough that the ladder still means what it says — a
/// 6h step lands between 4.8h and 7.2h, never at 12h.
library;

import 'dart:math';

abstract final class BackoffSchedule {
  /// Ch10's table. Index is the number of failures so far, clamped to the end.
  static const List<Duration> steps = [
    Duration.zero,
    Duration(seconds: 5),
    Duration(seconds: 30),
    Duration(minutes: 5),
    Duration(minutes: 30),
    Duration(hours: 6),
  ];

  /// +/-20%, as a fraction of the step.
  static const double jitterFraction = 0.2;

  /// The step for a row that has failed [failures] times, before jitter.
  ///
  /// Clamps rather than throwing on a negative or an out-of-range count: this
  /// is fed by a persisted column that a player with a SQLite editor can set
  /// to anything, and the right answer to a nonsensical attempt count is a
  /// sensible delay, not a crash in a background worker.
  static Duration stepFor(int failures) =>
      steps[min(max(failures, 0), steps.length - 1)];

  /// [stepFor] with +/-[jitterFraction] applied.
  ///
  /// A zero step stays exactly zero — 20% of nothing is nothing — which is
  /// what keeps "immediate" immediate rather than turning the first attempt
  /// into a coin flip about whether it happens now.
  static Duration delayFor(int failures, Random random) {
    final base = stepFor(failures).inMilliseconds;
    if (base == 0) return Duration.zero;

    // nextDouble() is [0,1); the transform maps it onto [-1,1), so the band is
    // [0.8x, 1.2x). Deliberately NOT `nextInt(41) - 20` percent: an integer
    // percentage quantises a 5-second step into 41 possible values, and a few
    // thousand devices hitting 41 buckets is a smaller herd but still a herd.
    final factor = 1 + (random.nextDouble() * 2 - 1) * jitterFraction;
    return Duration(milliseconds: (base * factor).round());
  }

  /// Wall-clock millis at which a row that has failed [failures] times becomes
  /// eligible again.
  ///
  /// Returned as an absolute instant rather than a duration because that is
  /// what the `next_retry_at` column stores: a delay would have to be
  /// re-derived against a clock every time the queue is scanned, and the
  /// scan happens on every connectivity change.
  static int nextRetryAtMillis({
    required int failures,
    required int nowMillis,
    required Random random,
  }) => nowMillis + delayFor(failures, random).inMilliseconds;

  /// The widest window a step can land in, for tests and for the Sync
  /// Inspector's own display.
  static (Duration min, Duration max) bandFor(int failures) {
    final base = stepFor(failures);
    if (base == Duration.zero) return (Duration.zero, Duration.zero);
    return (
      Duration(
        milliseconds: (base.inMilliseconds * (1 - jitterFraction)).round(),
      ),
      Duration(
        milliseconds: (base.inMilliseconds * (1 + jitterFraction)).round(),
      ),
    );
  }
}
