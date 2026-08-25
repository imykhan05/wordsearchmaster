import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../services/diagnostics/error_reporter.dart';
import '../local/app_database.dart';
import '../local/integrity_tags.dart';
import '../local/outbox_kind.dart';
import '../local/tables.dart';
import 'local_repository.dart';

part 'coins_repository.g.dart';

/// Coins, as an APPEND-ONLY ledger whose balance is derived (Ch10).
///
/// There is no `spend`/`earn` pair that mutates a stored number, because there
/// is no stored number. Every movement is a row; the balance is their sum.
/// That makes a wrong balance traceable to the row that caused it, and makes a
/// forged row visible instead of invisible.
final class CoinsRepository extends LocalRepository {
  CoinsRepository({
    required super.database,
    required super.integrity,
    required super.reporter,
    super.clock,
  });

  /// The current balance: the sum of every ledger row that still verifies.
  ///
  /// SUMMED IN DART, NOT BY SQL. `SELECT SUM(delta)` would be faster and would
  /// also happily add up forged rows — the verification is the entire point,
  /// and it needs the row's other columns to recompute the tag. The cost is
  /// O(rows) per emission, which is nothing at the scale one player's ledger
  /// reaches; TODO(P15): if the economy ever makes that untrue, checkpoint
  /// with a signed running balance rather than dropping the check.
  Stream<int> watchBalance() => watchLedger().map(
    (rows) => rows.fold(0, (total, row) => total + row.delta),
  );

  /// Every verified movement, newest first — the "where did my coins go"
  /// screen, and the first thing to read on a support ticket.
  Stream<List<CoinsLedgerRow>> watchLedger() {
    final query = database.select(database.coinsLedger)
      ..orderBy([(row) => OrderingTerm.desc(row.id)]);

    return query.watch().map(
      (rows) => [
        for (final row in rows)
          if (_isIntact(row)) row,
      ],
    );
  }

  /// Appends one movement and queues it, atomically.
  ///
  /// [delta] is signed and must not be zero — a zero movement is always a bug,
  /// and the schema rejects it.
  Future<void> record({required int delta, required String reason}) {
    final createdAt = nowMillis;

    return database.transaction(() async {
      final id = await database.nextRowId(LocalTables.coinsLedger);

      await database
          .into(database.coinsLedger)
          .insert(
            CoinsLedgerCompanion.insert(
              id: Value(id),
              delta: delta,
              reason: reason,
              createdAt: createdAt,
              integrityTag: RowTags.coinsLedger(
                integrity,
                id: id,
                delta: delta,
                reason: reason,
                createdAt: createdAt,
              ),
            ),
          );

      await enqueue(
        kind: OutboxKind.coinsDelta,
        createdAt: createdAt,
        payload: {
          'ledgerId': id,
          'delta': delta,
          'reason': reason,
          'createdAt': createdAt,
        },
      );
    });
  }

  /// Spends [amount] (a POSITIVE number) if the balance covers it.
  ///
  /// Returns false and writes nothing when it does not. The balance is read
  /// inside the transaction so two purchases racing on the same coins cannot
  /// both see enough and both succeed — the classic double-spend, which for a
  /// player is a shop that gives away a hint for free and for us is a support
  /// ticket nobody can reproduce.
  Future<bool> trySpend({required int amount, required String reason}) {
    assert(
      amount > 0,
      'spend takes a positive amount; the sign is applied here',
    );

    return database.transaction(() async {
      final rows = await (database.select(
        database.coinsLedger,
      )..orderBy([(row) => OrderingTerm.desc(row.id)])).get();

      final balance = rows
          .where(_isIntact)
          .fold(0, (total, row) => total + row.delta);
      if (balance < amount) return false;

      final createdAt = nowMillis;
      final id = await database.nextRowId(LocalTables.coinsLedger);

      await database
          .into(database.coinsLedger)
          .insert(
            CoinsLedgerCompanion.insert(
              id: Value(id),
              delta: -amount,
              reason: reason,
              createdAt: createdAt,
              integrityTag: RowTags.coinsLedger(
                integrity,
                id: id,
                delta: -amount,
                reason: reason,
                createdAt: createdAt,
              ),
            ),
          );

      await enqueue(
        kind: OutboxKind.coinsDelta,
        createdAt: createdAt,
        payload: {
          'ledgerId': id,
          'delta': -amount,
          'reason': reason,
          'createdAt': createdAt,
        },
      );
      return true;
    });
  }

  bool _isIntact(CoinsLedgerRow row) => guard.accepts(
    table: LocalTables.coinsLedger,
    rowKey: '${row.id}',
    expected: RowTags.coinsLedger(
      integrity,
      id: row.id,
      delta: row.delta,
      reason: row.reason,
      createdAt: row.createdAt,
    ),
    stored: row.integrityTag,
  );
}

@Riverpod(keepAlive: true)
Future<CoinsRepository> coinsRepository(Ref ref) async => CoinsRepository(
  database: ref.watch(appDatabaseProvider),
  integrity: await ref.watch(rowIntegrityProvider.future),
  reporter: ref.watch(errorReporterProvider),
);
