import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;
import 'package:word_search_master/data/local/app_database.dart';
import 'package:word_search_master/data/local/tables.dart';

import '../../support/local_db.dart';

void main() {
  late AppDatabase database;

  setUp(() async {
    database = (await openMemoryDatabase()).database;
    addTearDown(database.close);
  });

  group('table names are pinned', () {
    // The HMAC input includes the table name, so a rename silently invalidates
    // every tag on every device. Drift needs `tableName` to be a literal, so
    // this is where the literal and the `LocalTables` constant are held
    // together.
    test('every generated table name matches its LocalTables constant', () {
      expect(database.profile.actualTableName, LocalTables.profile);
      expect(database.levelProgress.actualTableName, LocalTables.levelProgress);
      expect(database.dailyResults.actualTableName, LocalTables.dailyResults);
      expect(database.coinsLedger.actualTableName, LocalTables.coinsLedger);
      expect(database.achievements.actualTableName, LocalTables.achievements);
      expect(database.outbox.actualTableName, LocalTables.outbox);
      expect(database.kvSettings.actualTableName, LocalTables.kvSettings);
    });

    test('the Ch10 table set is complete', () async {
      final rows = await database
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name NOT LIKE 'sqlite_%'",
          )
          .get();
      final names = rows.map((row) => row.read<String>('name')).toSet();

      expect(
        names,
        containsAll(<String>[
          LocalTables.profile,
          LocalTables.levelProgress,
          LocalTables.dailyResults,
          LocalTables.coinsLedger,
          LocalTables.achievements,
          LocalTables.outbox,
          LocalTables.kvSettings,
        ]),
      );
    });
  });

  group('coins_ledger is append-only, enforced by SQLite', () {
    // The guarantee has to hold against a SQLite editor, not just against a
    // repository that declines to expose an update method.
    Future<void> insertRow() => database.customStatement(
      'INSERT INTO ${LocalTables.coinsLedger} '
      '(id, delta, reason, created_at, integrity_tag) VALUES (1, 50, ?, 0, ?)',
      ['test', 'tag'],
    );

    test('UPDATE is refused', () async {
      await insertRow();

      // expectLater, not expect: these statements are async, and an
      // un-awaited rejected Future leaves Drift's queue wedged rather than
      // failing the assertion.
      await expectLater(
        database.customStatement(
          'UPDATE ${LocalTables.coinsLedger} SET delta = 999999 WHERE id = 1',
        ),
        throwsA(isA<SqliteException>()),
      );

      final row = await database
          .customSelect('SELECT delta FROM ${LocalTables.coinsLedger}')
          .getSingle();
      expect(row.read<int>('delta'), 50, reason: 'the row is untouched');
    });

    test('DELETE is refused — a spend cannot be erased', () async {
      await insertRow();

      await expectLater(
        database.customStatement(
          'DELETE FROM ${LocalTables.coinsLedger} WHERE id = 1',
        ),
        throwsA(isA<SqliteException>()),
      );

      final rows = await database
          .customSelect('SELECT id FROM ${LocalTables.coinsLedger}')
          .get();
      expect(rows, hasLength(1));
    });

    test('INSERT is still allowed', () async {
      await insertRow();
      await database.customStatement(
        'INSERT INTO ${LocalTables.coinsLedger} '
        '(id, delta, reason, created_at, integrity_tag) VALUES (2, -20, ?, 0, ?)',
        ['spend', 'tag'],
      );

      final rows = await database
          .customSelect('SELECT id FROM ${LocalTables.coinsLedger}')
          .get();
      expect(rows, hasLength(2));
    });
  });

  group('schema constraints reject nonsense before integrity even runs', () {
    test('a level cannot have four stars', () async {
      await expectLater(
        database.customStatement(
          'INSERT INTO ${LocalTables.levelProgress} (language_code, level, '
          'stars, best_score, hints_used, completed_at, integrity_tag) '
          "VALUES ('en', 1, 4, 0, 0, 0, 'tag')",
        ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('a zero-delta ledger row is refused', () async {
      await expectLater(
        database.customStatement(
          'INSERT INTO ${LocalTables.coinsLedger} '
          '(id, delta, reason, created_at, integrity_tag) '
          "VALUES (1, 0, 'nothing', 0, 'tag')",
        ),
        throwsA(isA<SqliteException>()),
      );
    });
  });

  group('install id', () {
    test('is created once and reused', () async {
      final first = await database.ensureInstallId();
      final second = await database.ensureInstallId();

      expect(first, isNotEmpty);
      expect(second, first);
    });

    test('is stored WITHOUT an integrity tag — it is the key material', () async {
      await database.ensureInstallId();

      final row = await database
          .customSelect(
            'SELECT integrity_tag FROM ${LocalTables.kvSettings} WHERE key = ?',
            variables: [Variable<String>(KvKeys.installId)],
          )
          .getSingle();

      expect(row.read<String>('integrity_tag'), isEmpty);
    });

    test('two databases get different install ids', () async {
      final other = (await openMemoryDatabase()).database;
      addTearDown(other.close);

      expect(
        await other.ensureInstallId(),
        isNot(await database.ensureInstallId()),
      );
    });
  });

  test('the singleton profile row exists after open', () async {
    final rows = await database.select(database.profile).get();

    expect(rows, hasLength(1));
    expect(rows.single.id, AppDatabase.profileId);
  });
}
