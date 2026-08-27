import '../domain/progression/day_key.dart';

/// WHICH puzzle a game screen is playing — the `GameController` family key.
///
/// ---------------------------------------------------------------------------
/// WHY THE KEY GREW FROM `int` INTO A SEALED TYPE (P11)
///
/// P07 keyed `GameController` by the level number, which was exactly right
/// while a level number described every puzzle that existed. The Daily
/// Challenge (Ch12) is a puzzle that no level number describes: it is seeded
/// by a DATE, it has a fixed shape rather than a place on the Ch07 curve, it
/// is playable once, and — the part that actually forces the fork — finishing
/// it must NOT perform the Zeigarnik swap, because there is no next daily
/// today to swap into.
///
/// The alternative was a second controller duplicating the whole state
/// machine, or a reserved level number smuggling a mode through an `int`.
/// Both hide the fork instead of naming it. A sealed key names it, and every
/// `switch` over it is exhaustive — so the next mode (Blitz, v1.2) cannot be
/// added without the compiler pointing at each place that has to decide.
sealed class GameSession {
  const GameSession();

  /// The level number this session reports. Journey sessions carry the real
  /// one; the daily carries `DailyPuzzle.levelId` (0), which is never a real
  /// journey level.
  int get level;
}

/// A numbered level from the Ch07 curve.
final class JourneySession extends GameSession {
  const JourneySession(this.level, {this.downshift = false});

  @override
  final int level;

  /// Ch02/P12: true when this ATTEMPT should generate its grid with one
  /// fewer word — two consecutive abandons of this level, resolved and
  /// consumed by `journeyDownshiftProvider` (`game_controller.dart`) BEFORE
  /// `GameScreen` constructs this session, never inside `GameController`
  /// itself. See `GameController`'s file header, decision 5: mixing a
  /// database read into the state machine's own `build` would make the
  /// hottest, purely-derived path in the app await I/O.
  ///
  /// DELIBERATELY EXCLUDED from [==]/[hashCode] — the family key names WHICH
  /// puzzle this is (the starting level), not how this one attempt happens to
  /// be tuned. Including it would let two callers that construct
  /// `JourneySession(n)` with different `downshift` values silently talk to
  /// two different provider instances for what is supposed to be the SAME
  /// screen's controller — exactly the bug `GameDebugPanel` would hit, since
  /// it reconstructs `JourneySession(widget.level)` at its own default to
  /// reach the notifier for whatever session is actually mounted.
  final bool downshift;

  @override
  bool operator ==(Object other) =>
      other is JourneySession && other.level == level;

  @override
  int get hashCode => Object.hash('journey', level);

  @override
  String toString() => 'JourneySession($level)';
}

/// The once-a-day puzzle for a UTC calendar day.
final class DailySession extends GameSession {
  const DailySession(this.day);

  final DayKey day;

  /// Always 0 — see [GameSession.level] and `DailyPuzzle.levelId`.
  @override
  int get level => 0;

  @override
  bool operator ==(Object other) => other is DailySession && other.day == day;

  @override
  int get hashCode => Object.hash('daily', day);

  @override
  String toString() => 'DailySession($day)';
}
