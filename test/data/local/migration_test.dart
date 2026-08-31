import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:word_search_master/data/local/integrity.dart';
import 'package:word_search_master/data/local/integrity_tags.dart';
import 'package:word_search_master/data/local/tables.dart';
import 'package:word_search_master/domain/sync/outbox_status.dart';
import 'package:word_search_master/data/repositories/outbox_repository.dart';
import 'package:word_search_master/data/repositories/coins_repository.dart';
import 'package:word_search_master/data/repositories/profile_repository.dart';

import '../../support/local_db.dart';

/// Migrating a REAL v1 database, byte for byte.
///
/// v1 stored the coin balance as a column on `profile`. v2 is the Ch10 schema:
/// that column is gone, and the append-only `coins_ledger` replaces it. The
/// upgrade has to turn the old number into an opening ledger entry without
/// losing it — and, less obviously, without LAUNDERING it: a v1 row whose tag
/// no longer matches must not be re-signed into a valid v2 one.
void main() {
  const installId = 'migration-test-install';

  /// The v1 schema, frozen. Deliberately written out rather than generated:
  /// the point of the test is to open the schema that actually shipped, and a
  /// snapshot derived from today's Dart classes would drift along with them
  /// and prove nothing.
  const v1Ddl = [
    '''
CREATE TABLE profile (
  id INTEGER NOT NULL,
  display_name TEXT NULL,
  cloud_user_id TEXT NULL,
  created_at INTEGER NOT NULL,
  last_seen_at INTEGER NOT NULL,
  coins INTEGER NOT NULL DEFAULT 0,
  integrity_tag TEXT NOT NULL,
  PRIMARY KEY (id)
)''',
    '''
CREATE TABLE level_progress (
  language_code TEXT NOT NULL,
  level INTEGER NOT NULL,
  stars INTEGER NOT NULL,
  best_score INTEGER NOT NULL,
  hints_used INTEGER NOT NULL,
  completed_at INTEGER NOT NULL,
  integrity_tag TEXT NOT NULL,
  PRIMARY KEY (language_code, level)
)''',
    '''
CREATE TABLE daily_results (
  date TEXT NOT NULL,
  language_code TEXT NOT NULL,
  score INTEGER NOT NULL,
  stars INTEGER NOT NULL,
  completed_at INTEGER NOT NULL,
  integrity_tag TEXT NOT NULL,
  PRIMARY KEY (date, language_code)
)''',
    '''
CREATE TABLE achievements (
  id TEXT NOT NULL,
  progress INTEGER NOT NULL DEFAULT 0,
  unlocked_at INTEGER NULL,
  integrity_tag TEXT NOT NULL,
  PRIMARY KEY (id)
)''',
    '''
CREATE TABLE outbox (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  kind TEXT NOT NULL,
  payload TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  last_attempt_at INTEGER NULL,
  integrity_tag TEXT NOT NULL
)''',
    '''
CREATE TABLE kv_settings (
  key TEXT NOT NULL,
  value TEXT NOT NULL,
  integrity_tag TEXT NOT NULL,
  PRIMARY KEY (key)
)''',
  ];

  late Directory dir;
  late File file;
  final integrity = RowIntegrity.forInstall(installId);

  /// The v1 profile tag shape — it signed the coin balance, which v2's does
  /// not.
  String v1ProfileTag({
    required int createdAt,
    required int lastSeenAt,
    required int coins,
    String? displayName,
  }) => integrity.tagFor(
    table: LocalTables.profile,
    rowKey: '1',
    fields: [displayName, null, createdAt, lastSeenAt, coins],
  );

  /// Writes a v1 database at [file] with the given stored balance.
  ///
  /// [tagCoins] is what the row's tag was computed over. Passing something
  /// other than [coins] simulates a player editing the balance in a SQLite
  /// editor and leaving the old tag behind.
  void writeV1Database({required int coins, int? tagCoins}) {
    final db = sqlite3.open(file.path);
    try {
      for (final statement in v1Ddl) {
        db.execute(statement);
      }

      db.execute(
        'INSERT INTO kv_settings (key, value, integrity_tag) VALUES (?, ?, ?)',
        [KvKeys.installId, installId, ''],
      );

      db.execute(
        'INSERT INTO profile (id, display_name, cloud_user_id, created_at, '
        'last_seen_at, coins, integrity_tag) VALUES (1, ?, NULL, ?, ?, ?, ?)',
        [
          'Ayesha',
          1000,
          2000,
          coins,
          v1ProfileTag(
            createdAt: 1000,
            lastSeenAt: 2000,
            coins: tagCoins ?? coins,
            displayName: 'Ayesha',
          ),
        ],
      );

      // An unrelated table, to prove the migration does not disturb it.
      db.execute(
        'INSERT INTO level_progress (language_code, level, stars, best_score, '
        'hints_used, completed_at, integrity_tag) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [
          'ur',
          7,
          3,
          420,
          0,
          1500,
          RowTags.levelProgress(
            integrity,
            languageCode: 'ur',
            level: 7,
            stars: 3,
            bestScore: 420,
            hintsUsed: 0,
            completedAt: 1500,
          ),
        ],
      );

      db.execute('PRAGMA user_version = 1');
    } finally {
      db.close();
    }
  }

  setUp(() {
    dir = createTempDbDir();
    file = File('${dir.path}/wsm.sqlite');
  });

  group('an intact v1 database', () {
    late TestDatabase opened;

    setUp(() async {
      writeV1Database(coins: 250);
      opened = await openFileDatabase(file);
      addTearDown(opened.database.close);
    });

    test('arrives at the CURRENT schema version, not just at v2', () async {
      // A v1 database opened by a P16 build runs v1->v2 AND v2->v3 in one
      // pass. Pinning the literal 2 here would have passed while leaving the
      // outbox without its scheduling columns — the migration would look done
      // and every queued submission would fail on the next read.
      final row = await opened.database
          .customSelect('PRAGMA user_version')
          .getSingle();

      expect(row.read<int>('user_version'), 3);
      expect(opened.database.schemaVersion, 3);
    });

    test('the outbox gains its v3 scheduling columns', () async {
      final columns = await opened.database
          .customSelect('PRAGMA table_info(${LocalTables.outbox})')
          .get();
      final names = columns.map((row) => row.read<String>('name')).toSet();

      expect(names, containsAll(['status', 'next_retry_at']));
    });

    test('the stored balance becomes ONE opening ledger row', () async {
      final rows = await opened.database
          .select(opened.database.coinsLedger)
          .get();

      expect(rows, hasLength(1));
      expect(rows.single.delta, 250);
      expect(rows.single.reason, 'migration:v1_balance');
    });

    test('the derived balance still reads 250 — no coins lost', () async {
      final coins = CoinsRepository(
        database: opened.database,
        integrity: opened.integrity,
        reporter: opened.reporter,
      );

      // The carried-over row must carry a VALID v2 tag, or the balance would
      // read 0 and every migrated player would lose their coins.
      expect(await coins.watchBalance().first, 250);
    });

    test(
      'the profile survives and re-verifies under the v2 tag shape',
      () async {
        final profiles = ProfileRepository(
          database: opened.database,
          integrity: opened.integrity,
          reporter: opened.reporter,
        );
        final row = await profiles.watchProfile().first;

        expect(row, isNotNull);
        expect(row!.displayName, 'Ayesha');
        expect(row.createdAt, 1000, reason: 'the original timestamps are kept');
        expect(opened.reporter.integrityViolations, isEmpty);
      },
    );

    test('the coins column is gone from profile', () async {
      final columns = await opened.database
          .customSelect('PRAGMA table_info(${LocalTables.profile})')
          .get();
      final names = columns.map((row) => row.read<String>('name')).toSet();

      expect(names, isNot(contains('coins')));
      expect(names, containsAll(<String>['id', 'display_name', 'created_at']));
    });

    test('unrelated tables are untouched', () async {
      final rows = await opened.database
          .select(opened.database.levelProgress)
          .get();

      expect(rows, hasLength(1));
      expect(rows.single.level, 7);
      expect(rows.single.bestScore, 420);
    });

    test(
      'the append-only ledger triggers are installed by the migration',
      () async {
        // A migrated database must be as locked down as a freshly created one;
        // creating the triggers only in onCreate would leave every upgrading
        // player with a writable ledger.
        await expectLater(
          opened.database.customStatement(
            'UPDATE ${LocalTables.coinsLedger} SET delta = 99999 WHERE id = 1',
          ),
          throwsA(isA<SqliteException>()),
        );
      },
    );
  });

  group('a TAMPERED v1 database', () {
    late TestDatabase opened;

    setUp(() async {
      // The row says 999999 coins; its tag was computed over 250.
      writeV1Database(coins: 999999, tagCoins: 250);
      opened = await openFileDatabase(file);
      addTearDown(opened.database.close);
    });

    test('the forged balance is NOT carried into the ledger', () async {
      final rows = await opened.database
          .select(opened.database.coinsLedger)
          .get();

      expect(
        rows,
        isEmpty,
        reason:
            'migrating a row that fails its check would re-sign the forged '
            'number into a perfectly valid v2 ledger entry — a free amnesty '
            'for anyone who cheated before upgrading',
      );
    });

    test('the balance reads zero', () async {
      final coins = CoinsRepository(
        database: opened.database,
        integrity: opened.integrity,
        reporter: opened.reporter,
      );

      expect(await coins.watchBalance().first, 0);
    });

    test('the profile is reset to defaults rather than kept', () async {
      final profiles = ProfileRepository(
        database: opened.database,
        integrity: opened.integrity,
        reporter: opened.reporter,
      );
      final row = await profiles.watchProfile().first;

      // Reset, not discarded: the row exists and verifies, it just carries
      // nothing that came from the tampered original.
      expect(row, isNotNull);
      expect(row!.displayName, isNull);
    });

    test('the violation is reported as a non-fatal', () async {
      expect(
        opened.reporter.integrityViolations.map((v) => v.table),
        contains(LocalTables.profile),
      );
    });
  });

  test(
    'a fresh install creates the current schema directly, with no migration',
    () async {
      final opened = await openFileDatabase(file);
      addTearDown(opened.database.close);

      final version = await opened.database
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(version.read<int>('user_version'), 3);

      final ledger = await opened.database
          .select(opened.database.coinsLedger)
          .get();
      expect(ledger, isEmpty, reason: 'no opening balance to carry over');
    },
  );

  group('v2 -> v3: the outbox learns to schedule itself (P16)', () {
    /// A v2 database: everything v3 has, minus the two scheduling columns.
    ///
    /// Built by opening the real schema and DROPPING them, rather than by
    /// hand-writing a v2 DDL that would drift from the real one the moment a
    /// table changes.
    Future<void> writeV2Database() async {
      final opened = await openFileDatabase(file);
      await opened.database.customStatement(
        'ALTER TABLE ${LocalTables.outbox} DROP COLUMN status',
      );
      await opened.database.customStatement(
        'ALTER TABLE ${LocalTables.outbox} DROP COLUMN next_retry_at',
      );
      await opened.database.customStatement('PRAGMA user_version = 2');
      await opened.database.close();
    }

    test('an existing queued row survives and is eligible immediately', () async {
      await writeV2Database();

      // A row queued by the older build, tagged the way that build tagged it.
      final seed = await openFileDatabase(file);
      final tags = seed.integrity;
      const payload = '{"language":"en","level":7}';
      await seed.database.customStatement(
        'INSERT INTO ${LocalTables.outbox} '
        '(id, kind, payload, created_at, attempts, integrity_tag) '
        'VALUES (1, ?, ?, 1000, 0, ?)',
        [
          'levelComplete',
          payload,
          tags.tagFor(
            table: LocalTables.outbox,
            rowKey: '1',
            fields: ['levelComplete', payload, 1000],
          ),
        ],
      );
      await seed.database.close();

      final opened = await openFileDatabase(file);
      addTearDown(opened.database.close);

      final row =
          (await opened.database.select(opened.database.outbox).get()).single;

      // The MIGRATION MUST NOT HAVE RE-TAGGED ANYTHING. `RowTags.outbox` signs
      // the submission (kind, payload, createdAt) and has never signed the
      // delivery bookkeeping, which is exactly why adding two columns is a
      // pure `ADD COLUMN` with no row rewrite.
      final outbox = OutboxRepository(
        database: opened.database,
        integrity: opened.integrity,
        reporter: opened.reporter,
      );
      expect(outbox.isIntact(row), isTrue);

      // And it is eligible right now, which is what it already was.
      expect(outboxStatusOf(row), OutboxStatus.pending);
      expect(row.nextRetryAt, isNull);
      expect(await outbox.due(), hasLength(1));
    });

    test('the database reports v3 afterwards', () async {
      await writeV2Database();
      final opened = await openFileDatabase(file);
      addTearDown(opened.database.close);

      final version = await opened.database
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(version.read<int>('user_version'), 3);
    });
  });
}
