import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:word_search_master/data/local/tables.dart';
import 'package:word_search_master/data/repositories/coins_repository.dart';
import 'package:word_search_master/data/repositories/profile_repository.dart';
import 'package:word_search_master/data/repositories/progress_repository.dart';
import 'package:word_search_master/domain/scoring/score_event.dart';
import 'package:word_search_master/domain/text/language.dart';

import '../../support/local_db.dart';

/// THE P08 ACCEPTANCE CRITERION: editing the database file by hand is caught.
///
/// Every edit below goes through a SECOND, RAW sqlite3 connection opened
/// directly on the file — never through Drift, never through a repository.
/// That is the only version of this test worth having: a "tamper" performed
/// with the app's own update method proves nothing about a player who
/// sideloads a SQLite editor, which is the actual threat Ch10 names.
void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = createTempDbDir();
    file = File('${dir.path}/wsm.sqlite');
  });

  /// Runs [sql] against the raw file, the way an external editor would.
  ///
  /// The Drift connection is closed first: two writers on one SQLite file is
  /// its own source of confusion, and closing makes it unambiguous that the
  /// bytes on disk changed underneath the app rather than through it.
  void editFileDirectly(String sql, [List<Object?> parameters = const []]) {
    final raw = sqlite3.open(file.path);
    try {
      raw.execute(sql, parameters);
    } finally {
      raw.close();
    }
  }

  group('level_progress', () {
    setUp(() async {
      final opened = await openFileDatabase(file);
      final progress = ProgressRepository(
        database: opened.database,
        integrity: opened.integrity,
        reporter: opened.reporter,
      );

      await progress.recordLevelComplete(
        language: Language.english,
        level: 3,
        stars: 2,
        score: 180,
        hintsUsed: 1,
        events: const [WordFound(graphemeCount: 5), HintUsed()],
      );
      await opened.database.close();
    });

    test('an honest row reads back fine', () async {
      final opened = await openFileDatabase(file);
      addTearDown(opened.database.close);

      final progress = ProgressRepository(
        database: opened.database,
        integrity: opened.integrity,
        reporter: opened.reporter,
      );
      final rows = await progress.watchAll(Language.english).first;

      expect(rows, hasLength(1));
      expect(rows.single.bestScore, 180);
      expect(opened.reporter.integrityViolations, isEmpty);
    });

    test('A HAND-EDITED BEST SCORE IS REJECTED', () async {
      editFileDirectly(
        'UPDATE ${LocalTables.levelProgress} SET best_score = 999999 '
        "WHERE language_code = 'en' AND level = 3",
      );

      final opened = await openFileDatabase(file);
      addTearDown(opened.database.close);

      // The row is still physically there...
      final raw = await opened.database
          .select(opened.database.levelProgress)
          .get();
      expect(raw.single.bestScore, 999999);

      // ...but the repository refuses to hand it to the game.
      final progress = ProgressRepository(
        database: opened.database,
        integrity: opened.integrity,
        reporter: opened.reporter,
      );
      expect(await progress.watchAll(Language.english).first, isEmpty);
      expect(
        await progress.watchHighestCompletedLevel(Language.english).first,
        0,
      );
    });

    test('a hand-edited star count is rejected', () async {
      editFileDirectly(
        'UPDATE ${LocalTables.levelProgress} SET stars = 3 '
        "WHERE language_code = 'en' AND level = 3",
      );

      final opened = await openFileDatabase(file);
      addTearDown(opened.database.close);

      final progress = ProgressRepository(
        database: opened.database,
        integrity: opened.integrity,
        reporter: opened.reporter,
      );
      expect(await progress.watchLevel(Language.english, 3).first, isNull);
    });

    test('the rejection is reported as a Crashlytics non-fatal', () async {
      editFileDirectly(
        'UPDATE ${LocalTables.levelProgress} SET best_score = 5000 '
        "WHERE language_code = 'en' AND level = 3",
      );

      final opened = await openFileDatabase(file);
      addTearDown(opened.database.close);

      final progress = ProgressRepository(
        database: opened.database,
        integrity: opened.integrity,
        reporter: opened.reporter,
      );
      await progress.watchAll(Language.english).first;

      final violations = opened.reporter.integrityViolations.toList();
      expect(violations, hasLength(1));
      expect(violations.single.table, LocalTables.levelProgress);
      expect(violations.single.rowKey, 'en/3');
    });

    test(
      'a violation is reported ONCE, not on every stream emission',
      () async {
        // A Drift stream re-emits on every write to the table. Without
        // deduping, one tampered row would file thousands of identical reports
        // and bury the signal.
        editFileDirectly(
          'UPDATE ${LocalTables.levelProgress} SET best_score = 5000 '
          "WHERE language_code = 'en' AND level = 3",
        );

        final opened = await openFileDatabase(file);
        addTearDown(opened.database.close);

        final progress = ProgressRepository(
          database: opened.database,
          integrity: opened.integrity,
          reporter: opened.reporter,
        );
        for (var i = 0; i < 5; i++) {
          await progress.watchAll(Language.english).first;
        }

        expect(opened.reporter.integrityViolations, hasLength(1));
      },
    );

    test('COPYING a valid row onto another level is rejected', () async {
      // The cheapest cheat there is, and the reason the tag is bound to the
      // row's address rather than just its contents.
      editFileDirectly(
        'INSERT INTO ${LocalTables.levelProgress} (language_code, level, '
        'stars, best_score, hints_used, completed_at, integrity_tag) '
        "SELECT 'en', 50, stars, best_score, hints_used, completed_at, "
        'integrity_tag FROM ${LocalTables.levelProgress} '
        "WHERE language_code = 'en' AND level = 3",
      );

      final opened = await openFileDatabase(file);
      addTearDown(opened.database.close);

      final progress = ProgressRepository(
        database: opened.database,
        integrity: opened.integrity,
        reporter: opened.reporter,
      );
      final rows = await progress.watchAll(Language.english).first;

      expect(rows.map((row) => row.level), [3], reason: 'level 50 is refused');
    });

    test('a forged row cannot become a permanent best score', () async {
      // If a tampered row were treated as a floor to beat, an honest replay
      // that scored less would leave the forged number in place forever.
      editFileDirectly(
        'UPDATE ${LocalTables.levelProgress} SET best_score = 999999 '
        "WHERE language_code = 'en' AND level = 3",
      );

      final opened = await openFileDatabase(file);
      addTearDown(opened.database.close);

      final progress = ProgressRepository(
        database: opened.database,
        integrity: opened.integrity,
        reporter: opened.reporter,
      );
      await progress.recordLevelComplete(
        language: Language.english,
        level: 3,
        stars: 1,
        score: 40,
        hintsUsed: 2,
        events: const [WordFound(graphemeCount: 4)],
      );

      final rows = await progress.watchAll(Language.english).first;
      expect(rows.single.bestScore, 40);
    });
  });

  group('coins_ledger', () {
    setUp(() async {
      final opened = await openFileDatabase(file);
      final coins = CoinsRepository(
        database: opened.database,
        integrity: opened.integrity,
        reporter: opened.reporter,
      );
      await coins.record(delta: 30, reason: 'level_complete:en:1');
      await coins.record(delta: -10, reason: 'hint');
      await opened.database.close();
    });

    // The ledger has TWO defences and they cover different attacks. The
    // triggers stop an edit outright; the HMAC catches the edits the triggers
    // cannot see. Both are exercised below.

    test('the triggers refuse an edit even from a raw connection', () {
      // Not a weaker version of the tests further down — this is the first
      // line, and it holds against a SQLite editor, not just against the
      // repository declining to expose an update method.
      expect(
        () => editFileDirectly(
          'UPDATE ${LocalTables.coinsLedger} SET delta = 500000 WHERE id = 1',
        ),
        throwsA(isA<SqliteException>()),
      );
      expect(
        () => editFileDirectly(
          'DELETE FROM ${LocalTables.coinsLedger} WHERE id = 2',
        ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('a FORGED INSERTED row is excluded from the balance', () async {
      // Inserting is the attack the triggers permit by design — the ledger
      // has to stay appendable. So this is where the HMAC earns its keep.
      editFileDirectly(
        'INSERT INTO ${LocalTables.coinsLedger} '
        '(id, delta, reason, created_at, integrity_tag) '
        "VALUES (99, 500000, 'free money', 0, 'not-a-real-tag')",
      );

      final opened = await openFileDatabase(file);
      addTearDown(opened.database.close);

      final coins = CoinsRepository(
        database: opened.database,
        integrity: opened.integrity,
        reporter: opened.reporter,
      );

      // The honest 30 and -10 still count; only the forged row is dropped.
      expect(await coins.watchBalance().first, 20);
    });

    test('the forged row stays on disk as evidence', () async {
      editFileDirectly(
        'INSERT INTO ${LocalTables.coinsLedger} '
        '(id, delta, reason, created_at, integrity_tag) '
        "VALUES (99, 500000, 'free money', 0, 'not-a-real-tag')",
      );

      final opened = await openFileDatabase(file);
      addTearDown(opened.database.close);

      final coins = CoinsRepository(
        database: opened.database,
        integrity: opened.integrity,
        reporter: opened.reporter,
      );
      await coins.watchBalance().first;

      // Excluded from the sum, but never swept up: Ch10 wants cheating
      // visible, and a deleted row tells nobody anything.
      final raw = await opened.database
          .select(opened.database.coinsLedger)
          .get();
      expect(raw, hasLength(3));
      expect(opened.reporter.integrityViolations, hasLength(1));
    });

    test(
      'DROPPING THE TRIGGERS DOES NOT HELP — the HMAC still catches it',
      () async {
        // The honest limit of a trigger: anyone who can edit the file can also
        // drop the trigger. This is precisely why the integrity tag exists on
        // top of it, and the case that proves the two layers are not redundant.
        editFileDirectly('DROP TRIGGER coins_ledger_no_update');
        editFileDirectly('DROP TRIGGER coins_ledger_no_delete');
        editFileDirectly(
          'UPDATE ${LocalTables.coinsLedger} SET delta = 500000 WHERE id = 1',
        );

        final opened = await openFileDatabase(file);
        addTearDown(opened.database.close);

        final coins = CoinsRepository(
          database: opened.database,
          integrity: opened.integrity,
          reporter: opened.reporter,
        );

        expect(await coins.watchBalance().first, -10);
        expect(opened.reporter.integrityViolations, hasLength(1));
      },
    );

    test('editing the reason string is also caught', () async {
      // The reason is signed too — it is what a human reads on a support
      // ticket, so a row that lies about where coins came from is as bad as
      // one that lies about how many.
      editFileDirectly('DROP TRIGGER coins_ledger_no_update');
      editFileDirectly(
        "UPDATE ${LocalTables.coinsLedger} SET reason = 'purchase' WHERE id = 2",
      );

      final opened = await openFileDatabase(file);
      addTearDown(opened.database.close);

      final coins = CoinsRepository(
        database: opened.database,
        integrity: opened.integrity,
        reporter: opened.reporter,
      );
      expect(await coins.watchBalance().first, 30);
    });
  });

  group('profile', () {
    test('a hand-edited display name is rejected', () async {
      final first = await openFileDatabase(file);
      final profiles = ProfileRepository(
        database: first.database,
        integrity: first.integrity,
        reporter: first.reporter,
      );
      await profiles.updateDisplayName('Bilal');
      await first.database.close();

      editFileDirectly(
        "UPDATE ${LocalTables.profile} SET display_name = 'Admin' WHERE id = 1",
      );

      final opened = await openFileDatabase(file);
      addTearDown(opened.database.close);

      final reopened = ProfileRepository(
        database: opened.database,
        integrity: opened.integrity,
        reporter: opened.reporter,
      );
      expect(await reopened.watchProfile().first, isNull);
    });
  });

  group('the install id is the whole key', () {
    test('changing it invalidates EVERY row — the failure is closed', () async {
      final first = await openFileDatabase(file);
      final progress = ProgressRepository(
        database: first.database,
        integrity: first.integrity,
        reporter: first.reporter,
      );
      await progress.recordLevelComplete(
        language: Language.english,
        level: 1,
        stars: 3,
        score: 100,
        hintsUsed: 0,
        events: const [WordFound(graphemeCount: 5)],
      );
      await first.database.close();

      // The install id is exempt from integrity checking because it is an
      // input to the key. Editing it does not forge anything — it changes
      // the derived key, so every OTHER row stops verifying at once.
      editFileDirectly(
        'UPDATE ${LocalTables.kvSettings} SET value = ? WHERE key = ?',
        ['attacker-chosen-id', KvKeys.installId],
      );

      final opened = await openFileDatabase(file);
      addTearDown(opened.database.close);

      final reopened = ProgressRepository(
        database: opened.database,
        integrity: opened.integrity,
        reporter: opened.reporter,
      );
      expect(await reopened.watchAll(Language.english).first, isEmpty);
    });
  });
}
