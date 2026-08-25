import 'integrity.dart';
import 'tables.dart';

/// THE ONE DEFINITION of which columns each table's integrity tag covers.
///
/// Every writer and every reader goes through here. That is the whole point:
/// if the repository tagged `(stars, bestScore)` and the migration re-tagged
/// `(stars, bestScore, hintsUsed)`, every migrated row would fail its check
/// on the next read and the player would silently lose their progress. A
/// single shared definition makes that class of bug impossible to write.
///
/// Adding a column to a table means adding it here AND migrating existing
/// rows to the new tag — the field list is part of the schema, not an
/// implementation detail of one call site.
abstract final class RowTags {
  static String profile(
    RowIntegrity integrity, {
    required int id,
    required String? displayName,
    required String? cloudUserId,
    required int createdAt,
    required int lastSeenAt,
  }) => integrity.tagFor(
    table: LocalTables.profile,
    rowKey: '$id',
    fields: [displayName, cloudUserId, createdAt, lastSeenAt],
  );

  static String levelProgress(
    RowIntegrity integrity, {
    required String languageCode,
    required int level,
    required int stars,
    required int bestScore,
    required int hintsUsed,
    required int completedAt,
  }) => integrity.tagFor(
    table: LocalTables.levelProgress,
    rowKey: '$languageCode/$level',
    fields: [stars, bestScore, hintsUsed, completedAt],
  );

  static String dailyResult(
    RowIntegrity integrity, {
    required String date,
    required String languageCode,
    required int score,
    required int stars,
    required int completedAt,
  }) => integrity.tagFor(
    table: LocalTables.dailyResults,
    rowKey: '$date/$languageCode',
    fields: [score, stars, completedAt],
  );

  static String coinsLedger(
    RowIntegrity integrity, {
    required int id,
    required int delta,
    required String reason,
    required int createdAt,
  }) => integrity.tagFor(
    table: LocalTables.coinsLedger,
    rowKey: '$id',
    fields: [delta, reason, createdAt],
  );

  static String achievement(
    RowIntegrity integrity, {
    required String id,
    required int progress,
    required int? unlockedAt,
  }) => integrity.tagFor(
    table: LocalTables.achievements,
    rowKey: id,
    fields: [progress, unlockedAt],
  );

  /// Covers the submission only — NOT `attempts`/`lastAttemptAt`, which the
  /// sync worker mutates on every retry. See the [Outbox] doc comment.
  static String outbox(
    RowIntegrity integrity, {
    required int id,
    required String kind,
    required String payload,
    required int createdAt,
  }) => integrity.tagFor(
    table: LocalTables.outbox,
    rowKey: '$id',
    fields: [kind, payload, createdAt],
  );

  static String kvSetting(
    RowIntegrity integrity, {
    required String key,
    required String value,
  }) => integrity.tagFor(
    table: LocalTables.kvSettings,
    rowKey: key,
    fields: [value],
  );
}
