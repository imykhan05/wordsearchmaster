/// Ch10's conflict table, as one documented decision function per row (P16).
///
/// PURE DART. No clock, no I/O, no `Random` — every rule below is a total
/// function of the two sides it is handed, which is what lets
/// `conflict_resolver_test.dart` walk the whole table without a database or a
/// network.
///
/// ---------------------------------------------------------------------------
/// THE TABLE
///
/// | # | Conflict                                   | Winner              |
/// |---|--------------------------------------------|---------------------|
/// | 1 | Level score/stars, after server recompute   | SERVER, even lower  |
/// | 2 | Level progress row, two devices             | Better row, WHOLE   |
/// | 3 | Daily result for one (date, language)       | The FIRST attempt   |
/// | 4 | Coin balance                                | SUM, as a delta     |
/// | 5 | Achievement                                 | Union, EARLIEST unlock |
/// | 6 | Streak                                      | Per field           |
/// | 7 | Profile display fields                      | Last write, tie→local |
/// | 8 | Device settings                             | LOCAL, always       |
/// | 9 | Unreadable remote value                     | LOCAL               |
///
/// Every row is a [ConflictRule] value and every value has its own group in
/// the test file — which is asserted there, by enumerating this enum, so a row
/// added here without a test fails the build rather than shipping untested.
///
/// ---------------------------------------------------------------------------
/// ONE RULE POINTS THE OTHER WAY FROM EVERY OTHER, AND IT IS THE IMPORTANT ONE
///
/// Rules 2 and 4-6 all resolve TOWARDS the player: take the better row, sum the
/// coins, union the achievements, keep both days of a streak. That is Ch02's
/// "never lose progress", and it is why linking an account is safe.
///
/// Rule 1 does not. A submission the server has recomputed comes back as the
/// truth even when the truth is SMALLER, because the server's number is not a
/// second opinion — it is the only number that was ever authoritative (Ch08).
/// A local score that disagrees is either a client built against a different
/// spec version or a client that was tampered with, and "keep the bigger one"
/// would make the second of those a working exploit.
///
/// In practice this rule changes nothing almost every time it runs: the client
/// computes its optimistic score with the same `Scoring` code the server
/// re-implements, over the same events, and P14's parity fixture exists to
/// keep those two identical. The case where it DOES change something is
/// exactly the case it was written for.
///
/// ---------------------------------------------------------------------------
/// WHY RULE 3 DISAGREES WITH `AccountMerge`, ON PURPOSE
///
/// `AccountMerge` (P13) resolves a daily with "better row wins", and this file
/// resolves it with "the first attempt wins". That is not a contradiction —
/// they are answers to different questions:
///
///   * LINKING two accounts joins two separate histories that were never
///     competing. Neither played "first" in any shared sense, so taking the
///     better is the never-lose-progress rule doing its job.
///   * SYNCING reconciles one account against a server that has already
///     decided which attempt counted. `submitDaily` keeps the first
///     submission and answers a later one with the stored result, because
///     "one attempt per day" with a best-of write would let a player grind the
///     daily leaderboard. Local has to match what the board already shows.
///
/// `conflict_resolver_test.dart` pins BOTH behaviours against each other, so
/// that a future reader who notices the difference finds a test explaining it
/// rather than "fixing" one of them.
library;

import '../progression/account_merge.dart';
import '../progression/streak.dart';

/// One row of the table above.
///
/// An enum rather than doc comments alone, because it is what the test file
/// enumerates to prove every row is covered.
enum ConflictRule {
  /// 1 — a level submission the server replayed and rescored.
  serverRecomputedScore,

  /// 2 — the same level, finished on two devices, neither adjudicated.
  levelProgress,

  /// 3 — the same daily, submitted twice.
  dailyResult,

  /// 4 — coin balances that both moved while offline.
  coinBalance,

  /// 5 — an achievement unlocked on both sides.
  achievement,

  /// 6 — streak state from two devices.
  streak,

  /// 7 — display name / photo edited in two places.
  profileDisplay,

  /// 8 — sound, haptics, chosen language.
  deviceSettings,

  /// 9 — a remote field this build cannot read.
  unreadableRemoteValue,
}

/// What the server said about one submitted level or daily.
///
/// Mirrors P14's `SubmitResponse`. Note that it carries BOTH the score for
/// this attempt and the account's best — see [ConflictResolver.resolveSubmittedLevel]
/// for why only one of them is ever written.
final class ServerScoreAck {
  const ServerScoreAck({
    required this.score,
    required this.stars,
    required this.bestScore,
    required this.bestStars,
    this.alreadyRecorded = false,
  });

  /// What this attempt scored, by the server's replay.
  final int score;
  final int stars;

  /// The best the account holds for this puzzle, across every attempt the
  /// server has accepted.
  final int bestScore;
  final int bestStars;

  /// True when the call did not create a new record — a replayed nonce, or a
  /// daily whose day was already spent. The response is otherwise identical,
  /// deliberately, so this says nothing about whether anything was flagged.
  final bool alreadyRecorded;

  @override
  String toString() =>
      'ServerScoreAck(score: $score, stars: $stars, best: $bestScore/$bestStars'
      '${alreadyRecorded ? ', alreadyRecorded' : ''})';
}

/// The values a reconciled `level_progress` row should hold.
final class LevelReconciliation {
  const LevelReconciliation({
    required this.stars,
    required this.bestScore,
    required this.changed,
  });

  final int stars;
  final int bestScore;

  /// Whether anything actually moved.
  ///
  /// The caller uses this to skip the write entirely when nothing changed,
  /// which is the overwhelmingly common case — and skipping matters because a
  /// Drift write wakes every stream watching that table, so a no-op write
  /// would rebuild the journey map once per synced row for no reason.
  final bool changed;

  @override
  String toString() =>
      'LevelReconciliation(stars: $stars, score: $bestScore, '
      'changed: $changed)';
}

/// Display fields the player authors, and the stamp that orders two edits.
final class ProfileDisplay {
  const ProfileDisplay({
    this.displayName,
    this.photoUrl,
    required this.updatedAt,
  });

  final String? displayName;
  final String? photoUrl;

  /// Millis since epoch.
  final int updatedAt;

  @override
  bool operator ==(Object other) =>
      other is ProfileDisplay &&
      other.displayName == displayName &&
      other.photoUrl == photoUrl &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(displayName, photoUrl, updatedAt);

  @override
  String toString() =>
      'ProfileDisplay($displayName, $photoUrl, updatedAt: $updatedAt)';
}

abstract final class ConflictResolver {
  // -------------------------------------------------------------------------
  // Rule 1 — the server's recomputation wins, in both directions.
  // -------------------------------------------------------------------------

  /// Reconciles a local `level_progress` row against what the server returned
  /// for a submission of that level.
  ///
  /// TAKES [ServerScoreAck.bestScore], NEVER [ServerScoreAck.score], and the
  /// difference is the whole subtlety. `score` is what THIS attempt earned; a
  /// player replaying level 5 for fun and doing worse would otherwise have
  /// their best result overwritten by their worst, which is the same "replays
  /// must not cost you your best" rule `ProgressRepository.recordLevelComplete`
  /// already keeps locally. `bestScore` is the server's own best-of across
  /// every accepted attempt, so it is both authoritative AND monotonic under
  /// honest play.
  ///
  /// It can still move a value DOWN, and must be allowed to: that is the case
  /// where the local number was wrong.
  ///
  /// ORDERING IS LOAD-BEARING HERE. `bestScore` is only right if every earlier
  /// submission for this level has already landed, so the queue drains
  /// oldest-first and the worker never has two rows for the same conflict key
  /// in flight at once — see `SyncWorker`'s claim set. Without that, two
  /// concurrent submissions of the same level could return each other's stale
  /// best and the later reply would win by arriving last.
  static LevelReconciliation resolveSubmittedLevel({
    required int localStars,
    required int localBestScore,
    required ServerScoreAck ack,
  }) => LevelReconciliation(
    stars: ack.bestStars,
    bestScore: ack.bestScore,
    changed: ack.bestStars != localStars || ack.bestScore != localBestScore,
  );

  // -------------------------------------------------------------------------
  // Rule 2 — better row wins, whole.
  // -------------------------------------------------------------------------

  /// The winning `level_progress` row between two devices.
  ///
  /// Delegates to [LevelSnapshot.isBetterThan], which is also what
  /// `AccountMerge` uses — one implementation, so a level resolved at sync
  /// time and the same level resolved at account-link time cannot pick
  /// different winners. A dead tie keeps [local], which makes the rule stable
  /// under repetition: resolving twice cannot flip a row back and forth.
  ///
  /// The row wins ENTIRE. Taking max(stars) from one side and max(bestScore)
  /// from the other would synthesise a run that never happened — three stars
  /// (so, no hints) beside a score only reachable with one.
  static LevelSnapshot resolveLevel({
    required LevelSnapshot local,
    required LevelSnapshot remote,
  }) => remote.isBetterThan(local) ? remote : local;

  // -------------------------------------------------------------------------
  // Rule 3 — the first attempt is the attempt.
  // -------------------------------------------------------------------------

  /// The surviving daily result for one `(date, language)`.
  ///
  /// EARLIEST `completedAt` wins, regardless of score — see the library header
  /// for why this deliberately differs from `AccountMerge`'s link-time rule. A
  /// tie keeps [local], for the same stability reason as rule 2.
  static DailySnapshot resolveDaily({
    required DailySnapshot local,
    required DailySnapshot remote,
  }) => remote.completedAt < local.completedAt ? remote : local;

  // -------------------------------------------------------------------------
  // Rule 4 — coins are summed, and expressed as a delta.
  // -------------------------------------------------------------------------

  /// How many coins to APPEND to the local ledger so the balance reflects
  /// [remoteBalance] as well as what is already there.
  ///
  /// A delta rather than a balance because `coins_ledger` is append-only and
  /// the balance is `SUM(rows)` (Ch10) — "set the balance to X" is not a
  /// sentence this data model can say. The local rows are already in the
  /// ledger, so the amount to add is the REMOTE balance, not the sum;
  /// crediting the sum would pay the player's own coins to them twice.
  ///
  /// NOT IDEMPOTENT, and it cannot be made so here: deciding "have I already
  /// credited this" requires reading the ledger, which is I/O. The caller
  /// writes the row under a reason key and refuses a second row with the same
  /// key — the identical guard `AccountMergeRepository` already uses.
  ///
  /// Negative remote balances clamp to zero. A cloud read that came back
  /// nonsense must not be able to DEBIT a player's wallet; the worst it can do
  /// is fail to credit.
  static int resolveCoinCredit({required int remoteBalance}) =>
      remoteBalance > 0 ? remoteBalance : 0;

  // -------------------------------------------------------------------------
  // Rule 5 — union, max progress, earliest unlock.
  // -------------------------------------------------------------------------

  /// Merges one achievement's two sides.
  ///
  /// `progress` takes max like everything else, but `unlockedAt` takes the
  /// EARLIEST: the day a badge was earned is a fact about the past, and it
  /// does not move because a second device noticed it later. An unlocked side
  /// always beats a still-in-progress one, because null is not a date.
  /// Delegates to [AccountMerge.mergeAchievement], so — like rules 2 and 6 —
  /// there is exactly one implementation shared with the link-time merge.
  static AchievementSnapshot resolveAchievement({
    required AchievementSnapshot local,
    required AchievementSnapshot remote,
  }) => AccountMerge.mergeAchievement(local, remote);

  // -------------------------------------------------------------------------
  // Rule 6 — per field, unlike every other row.
  // -------------------------------------------------------------------------

  /// Merges streak state per FIELD rather than picking a winning row.
  ///
  /// Delegates to [AccountMerge.mergeStreaks], so the sync path and the
  /// link path cannot diverge. Counts take max, the two day stamps take the
  /// LATER day, and freezes are capped at [StreakRules.maxFreezes] so that
  /// reconciling is not a way to hoard them.
  ///
  /// Per field is right here precisely because it is wrong for rule 2: both
  /// sides describe the same real person, so if they played on one device
  /// yesterday and another today, both days genuinely happened and the streak
  /// spans them. A whole-row pick would throw away a day the player played.
  static StreakState resolveStreak({
    required StreakState local,
    required StreakState remote,
  }) => AccountMerge.mergeStreaks(local, remote);

  // -------------------------------------------------------------------------
  // Rule 7 — last write wins, and a tie keeps local.
  // -------------------------------------------------------------------------

  /// The surviving display name and photo.
  ///
  /// LAST WRITE WINS by `updatedAt`, which is the one place in this table
  /// where a timestamp decides anything — and it is safe here precisely
  /// because these fields are worth nothing to forge. A player who sets a name
  /// on their phone and a different one on their tablet wants the one they
  /// typed most recently; there is no "better" name to prefer, and no score
  /// riding on the answer.
  ///
  /// A TIE KEEPS LOCAL, which matters more than it looks: two devices with a
  /// coarse clock can easily stamp the same millisecond, and a rule that
  /// preferred remote on a tie would let a stale cloud value overwrite an edit
  /// the player is looking at right now.
  static ProfileDisplay resolveProfile({
    required ProfileDisplay local,
    required ProfileDisplay remote,
  }) => remote.updatedAt > local.updatedAt ? remote : local;

  // -------------------------------------------------------------------------
  // Rule 8 — local always.
  // -------------------------------------------------------------------------

  /// Sound, haptics and the chosen language: [local], unconditionally.
  ///
  /// These are properties of a DEVICE, not of an account. Muting a phone
  /// because it is in a meeting must not mute a tablet at home, and syncing a
  /// language choice would re-script the game under a player who deliberately
  /// switched. CLAUDE.md already keeps them out of the synced database
  /// entirely — they live in `shared_preferences` — so this row exists to say
  /// that the absence is deliberate rather than an oversight, and the generic
  /// signature is what makes it assertable in a test.
  static T resolveDeviceSetting<T>({required T local, required T remote}) =>
      local;

  // -------------------------------------------------------------------------
  // Rule 9 — an unreadable remote value changes nothing.
  // -------------------------------------------------------------------------

  /// [local], whenever the remote side could not be read.
  ///
  /// A field a newer build added, a type that changed, a null where a number
  /// was expected. The tempting alternative is to treat unreadable as empty
  /// and write that — which is how one bad field silently wipes a player's
  /// progress. Degrading to "keep what we have" makes the worst case a stale
  /// value instead of a lost one, and stale is recoverable on the next sync.
  static T resolveUnreadable<T>({required T local, Object? remote}) => local;
}
