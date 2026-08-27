/// The daily streak and its freezes (Ch02).
///
/// PURE DART, and deliberately a state MACHINE rather than a set of counters
/// the UI nudges: every transition is one of two functions below, both total,
/// both deterministic in `(state, today)`. That is what lets
/// `streak_test.dart` walk a year of synthetic calendars in a loop, and what
/// keeps the "did a freeze fire?" question answerable without a device.
///
/// ---------------------------------------------------------------------------
/// THE RULES, AS Ch02 STATES THEM
///
///   * a streak day is a day with at least one COMPLETED level;
///   * a freeze is granted every 7 days of streak, at most [maxFreezes] held;
///   * a missed day AUTO-CONSUMES a freeze — the player does not choose.
///
/// ---------------------------------------------------------------------------
/// THREE DECISIONS THIS FILE MAKES THAT Ch02 LEAVES OPEN
///
/// 1. A FREEZE PRESERVES THE STREAK; IT DOES NOT EXTEND IT. Being away for a
///    day and coming back to `7` is a rescue. Coming back to `8` would be the
///    game claiming you played on a day you did not, which is exactly the kind
///    of small dishonesty that makes a counter stop meaning anything.
///
/// 2. FREEZES ARE ONLY SPENT WHEN THEY FULLY COVER THE GAP. One freeze against
///    a three-day absence cannot save the streak, so it is not burned trying —
///    the player keeps it for a gap it can actually bridge. Spending it anyway
///    would be strictly worse for the player and invisible to them.
///
/// 3. A BROKEN STREAK KEEPS ITS FREEZES. They were earned. Confiscating them
///    at the moment the player is already losing something is a punishment on
///    top of a punishment, and the [maxFreezes] cap already stops them
///    accumulating into an exploit.
///
/// ---------------------------------------------------------------------------
/// [settle] IS THE WHOLE TRICK
///
/// A streak decays with time passing, not with anything the player does — so
/// the state on disk goes stale on its own, and every reader has to age it
/// forward before trusting it. [settle] is that ageing, and it is pure, so the
/// home screen can render "your streak as of today" without writing anything,
/// while [registerPlay] performs the same ageing before extending. One
/// definition, two callers, no way for the number shown to disagree with the
/// number stored.
library;

import 'day_key.dart';

/// A streak, as stored. Immutable.
final class StreakState {
  const StreakState({
    this.current = 0,
    this.longest = 0,
    this.lastActiveDay,
    this.lastPlayedDay,
    this.freezes = 0,
  });

  /// A player who has never finished a level.
  static const StreakState empty = StreakState();

  /// Consecutive streak days, including days a freeze covered.
  final int current;

  /// Best [current] ever reached. Never decreases.
  final int longest;

  /// The last day the streak counted — played OR covered by a freeze.
  ///
  /// Separate from [lastPlayedDay] precisely so a freeze can advance the
  /// streak's "alive through" date without the game thinking the player
  /// already played that day.
  final DayKey? lastActiveDay;

  /// The last day a level was actually completed. Gates "already counted
  /// today", and is what the Daily/home UI means by "played".
  final DayKey? lastPlayedDay;

  /// Unspent freezes, 0..[StreakRules.maxFreezes].
  final int freezes;

  bool get hasEverPlayed => lastPlayedDay != null;

  bool playedOn(DayKey day) => lastPlayedDay == day;

  StreakState copyWith({
    int? current,
    int? longest,
    DayKey? lastActiveDay,
    DayKey? lastPlayedDay,
    int? freezes,
    bool clearDays = false,
  }) => StreakState(
    current: current ?? this.current,
    longest: longest ?? this.longest,
    lastActiveDay: clearDays ? null : (lastActiveDay ?? this.lastActiveDay),
    lastPlayedDay: clearDays ? null : (lastPlayedDay ?? this.lastPlayedDay),
    freezes: freezes ?? this.freezes,
  );

  @override
  bool operator ==(Object other) =>
      other is StreakState &&
      other.current == current &&
      other.longest == longest &&
      other.lastActiveDay == lastActiveDay &&
      other.lastPlayedDay == lastPlayedDay &&
      other.freezes == freezes;

  @override
  int get hashCode =>
      Object.hash(current, longest, lastActiveDay, lastPlayedDay, freezes);

  @override
  String toString() =>
      'StreakState(current: $current, longest: $longest, '
      'lastActive: $lastActiveDay, lastPlayed: $lastPlayedDay, '
      'freezes: $freezes)';
}

/// What [StreakRules.settle] or [StreakRules.registerPlay] did, so the caller
/// can show it. A freeze firing silently is the one outcome that would feel
/// like a bug to a player who was counting on their streak.
enum StreakEvent {
  /// Nothing changed — same day, or no absence to account for.
  unchanged,

  /// [StreakState.current] went up by one.
  extended,

  /// A first day, after never having played or after a break.
  started,

  /// One or more freezes were spent to cover an absence. The streak survived.
  frozen,

  /// The absence was longer than the freezes held. The streak is back to 0.
  broken,
}

/// The outcome of a transition: the new state plus what happened to it.
final class StreakTransition {
  const StreakTransition({
    required this.state,
    required this.event,
    this.freezesSpent = 0,
    this.freezesGranted = 0,
  });

  final StreakState state;
  final StreakEvent event;
  final int freezesSpent;
  final int freezesGranted;

  @override
  bool operator ==(Object other) =>
      other is StreakTransition &&
      other.state == state &&
      other.event == event &&
      other.freezesSpent == freezesSpent &&
      other.freezesGranted == freezesGranted;

  @override
  int get hashCode => Object.hash(state, event, freezesSpent, freezesGranted);

  @override
  String toString() =>
      'StreakTransition(${event.name}, spent: $freezesSpent, '
      'granted: $freezesGranted, $state)';
}

/// The pure streak state machine. See the library header.
abstract final class StreakRules {
  /// A freeze is granted each time the streak reaches a multiple of this.
  static const int freezeGrantEveryDays = 7;

  /// Ch02's cap. Without it, a player who never misses a day accumulates an
  /// unlimited absence budget and the streak stops being a daily commitment.
  static const int maxFreezes = 2;

  /// Ages [state] forward to [today], spending freezes for any missed days.
  ///
  /// PURE and IDEMPOTENT: settling twice for the same [today] is the same as
  /// settling once, which is what makes it safe to call on every read (the
  /// home screen renders through it) as well as on the write path.
  ///
  /// "Missed" means a full UTC day between [StreakState.lastActiveDay] and
  /// [today] with no completion. Today itself is never missed — the player
  /// still has the rest of it to play.
  static StreakTransition settle(StreakState state, DayKey today) {
    final lastActive = state.lastActiveDay;
    if (lastActive == null) {
      return StreakTransition(state: state, event: StreakEvent.unchanged);
    }

    final gap = today.daysSince(lastActive);

    // A gap of 0 (already active today) or 1 (active yesterday, today still
    // open) means nothing has been missed yet. A NEGATIVE gap means the clock
    // moved backwards under us; treat it as nothing missed rather than as a
    // rescue opportunity — see `services/time/trusted_clock.dart`, which is
    // where a rolled-back clock is actually defended against.
    if (gap <= 1) {
      return StreakTransition(state: state, event: StreakEvent.unchanged);
    }

    final missed = gap - 1;

    // Decision 2 in the header: all-or-nothing. A freeze that cannot save the
    // streak is not burned trying.
    if (state.freezes >= missed) {
      return StreakTransition(
        state: state.copyWith(
          freezes: state.freezes - missed,
          // Alive right up to yesterday, so a completion today extends rather
          // than restarts — and so settling again is a no-op.
          lastActiveDay: today.previous,
        ),
        event: StreakEvent.frozen,
        freezesSpent: missed,
      );
    }

    // Decision 3: `longest` and `freezes` both survive the break.
    return StreakTransition(
      state: StreakState(
        current: 0,
        longest: state.longest,
        freezes: state.freezes,
      ),
      event: StreakEvent.broken,
    );
  }

  /// Records that a level was completed on [today].
  ///
  /// Settles first (so an absence is accounted for before the new day is
  /// added), then extends. Calling this twice in one day is a no-op — Ch02
  /// counts DAYS with a completion, not completions.
  static StreakTransition registerPlay(StreakState state, DayKey today) {
    final settled = settle(state, today);
    final aged = settled.state;

    if (aged.playedOn(today)) {
      // Already counted. Report the settle's own outcome rather than
      // `unchanged`, so a freeze that fired on this call is still visible to
      // the caller that has to tell the player about it.
      return StreakTransition(
        state: aged,
        event: settled.event,
        freezesSpent: settled.freezesSpent,
      );
    }

    final lastActive = aged.lastActiveDay;
    final continues = lastActive != null && today.daysSince(lastActive) == 1;

    final current = continues ? aged.current + 1 : 1;
    final granted = current % freezeGrantEveryDays == 0 ? 1 : 0;
    final freezes = _capFreezes(aged.freezes + granted);

    return StreakTransition(
      state: StreakState(
        current: current,
        longest: current > aged.longest ? current : aged.longest,
        lastActiveDay: today,
        lastPlayedDay: today,
        freezes: freezes,
      ),
      event: continues ? StreakEvent.extended : StreakEvent.started,
      freezesSpent: settled.freezesSpent,
      // Reports what was actually banked, not what was notionally earned: a
      // grant that hits the cap is a grant the player never received, and
      // showing "+1 freeze" while the counter stays at 2 reads as a bug.
      freezesGranted: freezes - aged.freezes,
    );
  }

  /// Days remaining until the next freeze grant, given a [current] streak.
  /// Purely for display — nothing above reads it.
  static int daysUntilNextFreeze(int current) =>
      freezeGrantEveryDays - (current % freezeGrantEveryDays);

  static int _capFreezes(int freezes) =>
      freezes > maxFreezes ? maxFreezes : freezes;
}
