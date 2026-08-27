import 'dart:convert';

import 'package:drift/drift.dart';

import '../../services/diagnostics/error_reporter.dart';
import '../local/app_database.dart';
import '../local/integrity.dart';
import '../local/integrity_tags.dart';
import '../local/outbox_kind.dart';
import '../local/tables.dart';

/// Checks row tags on the read path and reports the failures.
///
/// WHY THIS DEDUPES: a Drift stream re-emits on every write to the tables it
/// watches. A single tampered row would therefore file a fresh Crashlytics
/// non-fatal on every keystroke of gameplay — thousands of identical reports
/// that bury the signal they exist to provide. One report per row address per
/// process is enough to see the problem in aggregate.
final class IntegrityGuard {
  IntegrityGuard({required this.reporter});

  final ErrorReporter reporter;
  final Set<String> _reported = {};

  /// True when [stored] is the tag this install would have written.
  ///
  /// A false return means the caller must DROP the row — never repair it,
  /// never surface it. Ch10: a failed check resets to a default or re-syncs
  /// from cloud, and the player is never shown an error.
  bool accepts({
    required String table,
    required String rowKey,
    required String expected,
    required String stored,
  }) {
    if (RowIntegrity.tagsMatch(expected, stored)) return true;

    if (_reported.add('$table/$rowKey')) {
      reporter.nonFatal(IntegrityViolation(table: table, rowKey: rowKey));
    }
    return false;
  }
}

/// Shared plumbing for the three Ch10 repositories.
///
/// ---------------------------------------------------------------------------
/// THE READ PATH NEVER TOUCHES THE NETWORK. Not "usually" — never. Every
/// public stream below resolves entirely against Drift, which is what makes
/// the game playable with the radio off (CLAUDE.md → Architecture). Sync is a
/// background WRITE concern, carried by the outbox.
///
/// TAMPERED ROWS ARE EXCLUDED, NOT DELETED. Two reasons:
///
///   * deleting inside a stream's map function is re-entrant — the delete
///     dirties the table, the stream re-emits, and the map runs again;
///   * a forged row is EVIDENCE. Ch10 wants cheating visible, and a row that
///     has been silently swept up tells nobody anything.
///
/// Excluding it gives the app the same behaviour as deletion (the row does not
/// exist as far as gameplay is concerned) while leaving the artefact on disk.
/// TODO(P13): the cloud sync overwrites these by primary key on the next
/// successful pull, which is the "re-fetched from cloud" half of the Ch10
/// rule; until then the affected row reads as its default.
abstract base class LocalRepository {
  LocalRepository({
    required this.database,
    required this.integrity,
    required ErrorReporter reporter,
    DateTime Function()? clock,
  }) : guard = IntegrityGuard(reporter: reporter),
       _clock = clock ?? DateTime.now;

  final AppDatabase database;
  final RowIntegrity integrity;
  final IntegrityGuard guard;
  final DateTime Function() _clock;

  /// Millis since epoch, from the injected clock so tests can pin timestamps.
  int get nowMillis => _clock().millisecondsSinceEpoch;

  /// Appends one row to the sync queue.
  ///
  /// MUST be called inside the caller's transaction, alongside the game-state
  /// write it describes. That pairing is the whole outbox contract (Ch10):
  /// either the player's progress and its queued submission both land, or
  /// neither does. A progress row with no outbox row is silently unsynced
  /// forever; an outbox row with no progress row submits a level the player
  /// never finished.
  Future<void> enqueue({
    required OutboxKind kind,
    required Map<String, Object?> payload,
    required int createdAt,
  }) async {
    final id = await database.nextRowId(LocalTables.outbox);
    final encoded = jsonEncode(payload);

    await database
        .into(database.outbox)
        .insert(
          OutboxCompanion.insert(
            id: Value(id),
            kind: kind.name,
            payload: encoded,
            createdAt: createdAt,
            integrityTag: RowTags.outbox(
              integrity,
              id: id,
              kind: kind.name,
              payload: encoded,
              createdAt: createdAt,
            ),
          ),
        );
  }

  // -------------------------------------------------------------------------
  // kv_settings
  // -------------------------------------------------------------------------
  //
  // Shared here rather than reimplemented per repository for the same reason
  // `RowTags` is one file: a caller that forgot to tag a write, or that
  // verified a different field list than the writer signed, would fail every
  // read afterwards and look to the player like lost progress.

  /// The verified value of [key], or null when it is absent OR fails its tag.
  ///
  /// A tampered KV row reads as MISSING, not as an error — the Ch10 rule for
  /// any failed check. A forged streak therefore resets to zero rather than
  /// paying out, and the row stays on disk as evidence.
  Future<String?> readKv(String key) async {
    final row = await (database.select(
      database.kvSettings,
    )..where((row) => row.key.equals(key))).getSingleOrNull();
    if (row == null) return null;

    final intact = guard.accepts(
      table: LocalTables.kvSettings,
      rowKey: key,
      expected: RowTags.kvSetting(integrity, key: key, value: row.value),
      stored: row.integrityTag,
    );
    return intact ? row.value : null;
  }

  /// Writes [value] under [key] with a fresh tag.
  ///
  /// Safe to call inside a caller's transaction; takes no transaction of its
  /// own so it can be paired atomically with an outbox row.
  Future<void> writeKv(String key, String value) => database
      .into(database.kvSettings)
      .insertOnConflictUpdate(
        KvSettingsCompanion.insert(
          key: key,
          value: value,
          integrityTag: RowTags.kvSetting(integrity, key: key, value: value),
        ),
      );
}
