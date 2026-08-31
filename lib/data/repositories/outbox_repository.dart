import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/sync/backoff.dart';
import '../../domain/sync/outbox_status.dart';
import '../../services/diagnostics/error_reporter.dart';
import '../local/app_database.dart';
import '../local/integrity_tags.dart';
import '../local/outbox_kind.dart';
import '../local/tables.dart';
import 'local_repository.dart';

part 'outbox_repository.g.dart';

/// The queue's read and settle surface (Ch10 / P16).
///
/// `LocalRepository.enqueue` is still the only WRITER of new rows — every
/// mutation writes its game-state row and its outbox row in one transaction,
/// and nothing here changes that. This class is the other half: reading what
/// is due, and recording what happened to it.
///
/// ---------------------------------------------------------------------------
/// A ROW THAT FAILS ITS TAG IS NEVER SENT
///
/// The payload is what the server scores, so a forged one is the whole attack.
/// `_isIntact` drops it exactly like every other repository drops a tampered
/// row: excluded from the drain, reported once as a Crashlytics non-fatal,
/// left on disk as evidence, and never surfaced to the player. The difference
/// from a `level_progress` row is only in what "dropped" costs — a tampered
/// progress row degrades to "not completed", while a tampered outbox row
/// simply never syncs, which is the correct outcome for a payload nobody can
/// vouch for.
final class OutboxRepository extends LocalRepository {
  OutboxRepository({
    required super.database,
    required super.integrity,
    required super.reporter,
    super.clock,
    Random? random,
  }) : _random = random ?? Random();

  /// Injected so `backoff_test.dart` and the drain tests can pin the jitter.
  /// Ch10's ladder is only checkable if the randomness is an argument.
  final Random _random;

  /// Rows that are eligible to send right now, oldest first.
  ///
  /// OLDEST FIRST IS LOAD-BEARING, not tidiness. `ConflictResolver`'s rule 1
  /// reconciles a level against the server's best-of, and that number is only
  /// correct once every earlier submission for that level has landed. FIFO is
  /// what makes "earlier" mean anything.
  ///
  /// `failedPermanent` rows are excluded by the status filter, so a payload
  /// the server has already refused never blocks the rows behind it — a queue
  /// that stalled on its first bad row would be a queue that stops working
  /// the first time a build ships a payload bug.
  Future<List<OutboxRow>> due({int? nowMillis, int limit = 200}) async {
    final now = nowMillis ?? this.nowMillis;

    final query = database.select(database.outbox)
      ..where(
        (row) =>
            row.status.equals(OutboxStatus.pending.name) &
            (row.nextRetryAt.isNull() |
                row.nextRetryAt.isSmallerOrEqualValue(now)),
      )
      ..orderBy([(row) => OrderingTerm.asc(row.id)])
      ..limit(limit);

    return [
      for (final row in await query.get())
        if (_isIntact(row)) row,
    ];
  }

  /// Every row, newest first — the Sync Inspector's list.
  ///
  /// Includes `failedPermanent` rows and tampered ones alike, because a
  /// developer looking at this screen is looking for exactly the rows the
  /// drain refuses to touch. Tampered rows are marked rather than hidden.
  Stream<List<OutboxRow>> watchAll({int limit = 200}) {
    final query = database.select(database.outbox)
      ..orderBy([(row) => OrderingTerm.desc(row.id)])
      ..limit(limit);
    return query.watch();
  }

  /// Whether [row] still verifies. Exposed for the Inspector, which shows it.
  bool isIntact(OutboxRow row) => _isIntact(row);

  /// The decoded payload, or null if it cannot be read.
  ///
  /// Null rather than a throw: a row whose JSON a newer build wrote in a shape
  /// this one cannot parse must not crash the worker or wedge the queue behind
  /// it. The caller marks it permanently failed, which is honest — this build
  /// genuinely cannot send it.
  Map<String, Object?>? payloadOf(OutboxRow row) {
    try {
      final decoded = jsonDecode(row.payload);
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  /// Accepted by the server: the row leaves the queue.
  ///
  /// Deleted rather than marked, because a queue is not a history. The record
  /// that the level was played lives in `level_progress`, which is the table
  /// anything would actually read; keeping a parallel copy of every
  /// submission forever would grow without bound on a device chosen for having
  /// very little storage.
  Future<void> markSucceeded(int id) => (database.delete(
    database.outbox,
  )..where((row) => row.id.equals(id))).go();

  /// A transient failure: count it and schedule the next attempt.
  ///
  /// The new `attempts` value drives the ladder, so the write and the schedule
  /// have to be computed from the same number — hence one statement rather
  /// than an increment followed by a separate update.
  Future<int> markTransientFailure(OutboxRow row, {int? nowMillis}) async {
    final now = nowMillis ?? this.nowMillis;
    final attempts = row.attempts + 1;
    final nextRetryAt = BackoffSchedule.nextRetryAtMillis(
      failures: attempts,
      nowMillis: now,
      random: _random,
    );

    await (database.update(
      database.outbox,
    )..where((it) => it.id.equals(row.id))).write(
      OutboxCompanion(
        attempts: Value(attempts),
        lastAttemptAt: Value(now),
        nextRetryAt: Value(nextRetryAt),
      ),
    );
    return nextRetryAt;
  }

  /// The server refused the payload and will refuse it again.
  ///
  /// Records a Crashlytics NON-FATAL and stops. Ch10 is explicit that a
  /// background sync failure never reaches the player: they finished the
  /// level, they can see it in their progress, and a dialog about a 4xx would
  /// be an error message about something they cannot act on. The developer
  /// finds out; the player does not.
  Future<void> markFailedPermanent(
    OutboxRow row, {
    required String reason,
    int? nowMillis,
  }) async {
    final now = nowMillis ?? this.nowMillis;
    await (database.update(
      database.outbox,
    )..where((it) => it.id.equals(row.id))).write(
      OutboxCompanion(
        status: Value(OutboxStatus.failedPermanent.name),
        lastAttemptAt: Value(now),
        nextRetryAt: const Value(null),
      ),
    );

    guard.reporter.nonFatal(
      OutboxPermanentFailure(id: row.id, kind: row.kind, reason: reason),
      context: {'outboxId': row.id, 'kind': row.kind, 'reason': reason},
    );
  }

  /// Clears every backoff so the next drain sends everything.
  ///
  /// The Sync Inspector's force-drain button, and nothing else — it is not
  /// reachable from any player-facing surface. Deliberately does NOT reset
  /// `attempts`: the count is the row's history, and a developer forcing a
  /// drain wants to see the next attempt, not to pretend the earlier ones did
  /// not happen.
  Future<void> clearBackoff() =>
      (database.update(database.outbox)
            ..where((row) => row.status.equals(OutboxStatus.pending.name)))
          .write(const OutboxCompanion(nextRetryAt: Value(null)));

  /// Returns a `failedPermanent` row to the queue. Inspector only.
  Future<void> retryPermanentFailure(int id) =>
      (database.update(
        database.outbox,
      )..where((row) => row.id.equals(id))).write(
        const OutboxCompanion(
          status: Value('pending'),
          nextRetryAt: Value(null),
        ),
      );

  bool _isIntact(OutboxRow row) => guard.accepts(
    table: LocalTables.outbox,
    rowKey: '${row.id}',
    expected: RowTags.outbox(
      integrity,
      id: row.id,
      kind: row.kind,
      payload: row.payload,
      createdAt: row.createdAt,
    ),
    stored: row.integrityTag,
  );
}

/// The non-fatal filed when the server refuses a payload outright.
///
/// A typed error rather than a string, so Crashlytics groups every occurrence
/// of one bad payload shape together instead of scattering them across
/// thousands of distinct messages — which is the difference between "42 users
/// hit this" and an unreadable issue list.
final class OutboxPermanentFailure implements Exception {
  const OutboxPermanentFailure({
    required this.id,
    required this.kind,
    required this.reason,
  });

  final int id;
  final String kind;
  final String reason;

  @override
  String toString() => 'OutboxPermanentFailure($kind #$id: $reason)';
}

/// [OutboxKind] for [row], or null when this build does not know it.
OutboxKind? outboxKindOf(OutboxRow row) => OutboxKind.tryParse(row.kind);

/// [OutboxStatus] for [row], defaulting to pending on an unknown value.
///
/// Defaults rather than returning null, because a row whose status a newer
/// build wrote is still a real submission — treating it as pending gets it
/// sent, which is the outcome that loses nothing.
OutboxStatus outboxStatusOf(OutboxRow row) =>
    OutboxStatus.tryParse(row.status) ?? OutboxStatus.pending;

@Riverpod(keepAlive: true)
Future<OutboxRepository> outboxRepository(Ref ref) async => OutboxRepository(
  database: ref.watch(appDatabaseProvider),
  integrity: await ref.watch(rowIntegrityProvider.future),
  reporter: ref.watch(errorReporterProvider),
);
