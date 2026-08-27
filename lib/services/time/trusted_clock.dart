/// Deciding what DAY it is, when the device's own answer cannot be trusted.
///
/// Two retention systems hang off this: the streak (Ch02) and the Daily
/// Challenge's one-attempt-per-day rule (Ch12). Both are worth cheating, and
/// both are cheated the same way — move the device clock. So the day boundary
/// is resolved here, once, rather than by whoever happens to call
/// `DateTime.now()`.
///
/// ---------------------------------------------------------------------------
/// THREE ANSWERS, IN ORDER OF TRUST
///
/// 1. SERVER TIME, when the app is online. Authoritative, and it OVERRIDES the
///    guard below in both directions — a server that says "it is earlier than
///    you think" is correcting a clock that was set forward, which is exactly
///    the case the local guard cannot see.
///
/// 2. LOCAL TIME, offline. Ch12 requires the Daily to be fully playable with
///    the radio off, so refusing to answer is not an option — an unreachable
///    server must degrade to the device clock, never to a spinner.
///
/// 3. LOCAL TIME, FLOORED AT THE HIGHEST DAY ALREADY SEEN. The monotonic
///    guard. A player who winds the clock back to replay today's Daily or to
///    rescue a broken streak gets the day they already had.
///
/// ---------------------------------------------------------------------------
/// WHAT THIS HONESTLY DOES NOT DO
///
/// It does not stop a player who sets the clock FORWARD while offline. They
/// can reach tomorrow's Daily early — and they pay for it, because the guard
/// then holds them at that day until real time catches up, and their streak
/// breaks across the gap they invented. Blocking it outright needs a server,
/// which is what makes this a defence in depth and not the defence: Ch08's
/// server-side replay (P14) is where a submission is actually adjudicated.
/// Stating that plainly here is deliberate, the same way `integrity.dart`
/// states that its HMAC is tamper EVIDENCE and not tamper proof.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/progression/day_key.dart';

part 'trusted_clock.g.dart';

/// Which of the three answers above produced an instant.
enum TimeSource {
  /// Straight from [ServerTimeSource], or from a local clock corrected by an
  /// offset that source established earlier this session.
  server,

  /// The device clock, unmodified. Offline, and no rollback detected.
  local,

  /// The device clock said a day that had already passed, so the highest day
  /// seen was used instead.
  rollbackGuard,
}

/// A resolved instant plus how much to trust it.
final class TrustedNow {
  const TrustedNow({required this.utc, required this.source});

  /// Always UTC.
  final DateTime utc;
  final TimeSource source;

  /// The calendar day the rest of the app counts in.
  DayKey get day => DayKey.fromDateTime(utc);

  /// True when the device clock was caught behind a day already recorded.
  /// Feeds a Ch11 analytics counter; never shown to the player, who is far
  /// more likely to have a flat battery than to be cheating.
  bool get wasRolledBack => source == TimeSource.rollbackGuard;

  @override
  bool operator ==(Object other) =>
      other is TrustedNow && other.utc == utc && other.source == source;

  @override
  int get hashCode => Object.hash(utc, source);

  @override
  String toString() => 'TrustedNow($utc, ${source.name})';
}

/// An authoritative clock reached over the network.
///
/// P13/P14 implements this against a Firestore server timestamp (or the
/// `Date` header of any authenticated call — the point is that the value does
/// not come from the device). Returning null means "not available right now",
/// which is a normal state, not an error.
abstract interface class ServerTimeSource {
  Future<DateTime?> fetchUtcNow();
}

/// The binding until P13 lands, and the binding in every offline test.
final class UnavailableServerTime implements ServerTimeSource {
  const UnavailableServerTime();

  @override
  Future<DateTime?> fetchUtcNow() async => null;
}

/// Persists the highest day the app has ever resolved.
///
/// Backed by `kv_settings` in the real app (integrity-tagged, like every other
/// game-state value — CLAUDE.md → Never do: `shared_preferences` is for UI
/// toggles only, and a rollback high-water mark is emphatically not a UI
/// toggle).
abstract interface class DayHighWaterMarkStore {
  Future<DayKey?> read();
  Future<void> write(DayKey day);
}

/// A mark that lives only as long as the object. For tests and for a run where
/// the database failed to open.
final class InMemoryDayHighWaterMarkStore implements DayHighWaterMarkStore {
  InMemoryDayHighWaterMarkStore([this._day]);

  DayKey? _day;

  @override
  Future<DayKey?> read() async => _day;

  @override
  Future<void> write(DayKey day) async => _day = day;
}

/// Resolves "what day is it" per the trust order in the library header.
final class TrustedClock {
  // The lint below suggests `this._marks`/`this._server`, which Dart rejects
  // outright: a named parameter may not be private. Same situation, and the
  // same note, as `AppDatabase`'s reporter.
  // ignore_for_file: prefer_initializing_formals
  TrustedClock({
    required DayHighWaterMarkStore marks,
    ServerTimeSource server = const UnavailableServerTime(),
    DateTime Function()? localClock,
  }) : _marks = marks,
       _server = server,
       _localClock = localClock ?? DateTime.now;

  final DayHighWaterMarkStore _marks;
  final ServerTimeSource _server;
  final DateTime Function() _localClock;

  /// Server-minus-local, once a server answer has been obtained.
  ///
  /// Cached for the session so the streak counter on the home screen does not
  /// make a network call every time it rebuilds. The device clock still ticks
  /// underneath — this corrects its OFFSET, which is what was wrong with it,
  /// not its rate.
  Duration? _serverOffset;

  /// True once a server answer has been seen this session.
  bool get hasServerTime => _serverOffset != null;

  /// The current instant, and how much to trust it.
  ///
  /// Never throws and never blocks indefinitely on the network: a
  /// [ServerTimeSource] that fails is treated exactly like one that is
  /// offline, because to the player they are the same thing.
  Future<TrustedNow> now() async {
    final resolved = await _resolve();
    return _applyGuard(resolved);
  }

  /// [now], as a [DayKey]. The form both callers actually want.
  Future<DayKey> today() async => (await now()).day;

  Future<TrustedNow> _resolve() async {
    final cachedOffset = _serverOffset;
    if (cachedOffset != null) {
      return TrustedNow(
        utc: _localClock().toUtc().add(cachedOffset),
        source: TimeSource.server,
      );
    }

    DateTime? fetched;
    try {
      fetched = await _server.fetchUtcNow();
    } catch (_) {
      // TODO(P19): Crashlytics non-fatal. Silent here — a background time
      // fetch failing must never surface to a player (CLAUDE.md → Never do).
      fetched = null;
    }

    if (fetched != null) {
      final utc = fetched.toUtc();
      _serverOffset = utc.difference(_localClock().toUtc());
      return TrustedNow(utc: utc, source: TimeSource.server);
    }

    return TrustedNow(utc: _localClock().toUtc(), source: TimeSource.local);
  }

  Future<TrustedNow> _applyGuard(TrustedNow resolved) async {
    final day = resolved.day;

    DayKey? mark;
    try {
      mark = await _marks.read();
    } catch (_) {
      // A guard that cannot read its mark is a guard that is not there. The
      // day still resolves; only the anti-rollback property is lost, which is
      // strictly better than failing to tell the player what day it is.
      mark = null;
    }

    // A server answer is authoritative in BOTH directions: it may legitimately
    // move the app backwards, correcting a mark that a forward-set clock
    // wrote. Record it and return it unmodified.
    if (resolved.source == TimeSource.server) {
      if (mark == null || day != mark) await _store(day);
      return resolved;
    }

    if (mark != null && day < mark) {
      return TrustedNow(
        utc: mark.utcMidnight,
        source: TimeSource.rollbackGuard,
      );
    }

    if (mark == null || day > mark) await _store(day);
    return resolved;
  }

  Future<void> _store(DayKey day) async {
    try {
      await _marks.write(day);
    } catch (_) {
      // Same reasoning as the read above.
    }
  }
}

/// The app's clock. `bootstrap.dart` overrides this with one backed by
/// `kv_settings`; the default keeps the mark in memory so a run whose database
/// failed to open still knows what day it is.
@Riverpod(keepAlive: true)
TrustedClock trustedClock(Ref ref) =>
    TrustedClock(marks: InMemoryDayHighWaterMarkStore());

/// Today, resolved through [TrustedClock]. AUTO-DISPOSE, deliberately unlike
/// [trustedClockProvider]: "today" is a snapshot that goes stale the moment
/// midnight UTC passes, so nothing should hold it alive across app resumes —
/// every screen that cares (the Daily route, the streak counter) re-resolves
/// it fresh each time it is watched.
@riverpod
Future<DayKey> currentDay(Ref ref) => ref.watch(trustedClockProvider).today();
