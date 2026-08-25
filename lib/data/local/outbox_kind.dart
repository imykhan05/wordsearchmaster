/// What a queued outbox row asks the server to do (Ch10).
///
/// Stored by `name`, parsed back on read. An unrecognised value is reported
/// and skipped rather than throwing — see the `kind` column doc in
/// `tables.dart`.
enum OutboxKind {
  /// A finished level. Payload carries the ordered `ScoreEvent` list so
  /// P14's Cloud Function can replay it and compute the score itself.
  levelComplete,

  /// A finished Daily Challenge (Ch12).
  dailyResult,

  /// One append to the coin ledger.
  coinsDelta,

  /// An achievement crossing from in-progress to unlocked.
  achievementUnlocked,

  /// Display name / avatar edits.
  profileUpdate;

  /// [OutboxKind] for [name], or null if this build does not know it.
  ///
  /// Null rather than a throw because a row written by a NEWER build that the
  /// player then downgraded away from is a real situation, and it must not
  /// crash the sync worker or wedge the queue.
  static OutboxKind? tryParse(String name) {
    for (final kind in OutboxKind.values) {
      if (kind.name == name) return kind;
    }
    return null;
  }
}
