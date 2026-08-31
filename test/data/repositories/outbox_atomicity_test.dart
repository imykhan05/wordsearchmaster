import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;
import 'package:word_search_master/data/local/app_database.dart';
import 'package:word_search_master/data/local/outbox_kind.dart';
import 'package:word_search_master/data/local/submission_nonce.dart';
import 'package:word_search_master/data/local/tables.dart';
import 'package:word_search_master/data/repositories/coins_repository.dart';
import 'package:word_search_master/data/repositories/profile_repository.dart';
import 'package:word_search_master/data/repositories/progress_repository.dart';
import 'package:word_search_master/domain/scoring/score_event.dart';
import 'package:word_search_master/domain/scoring/scoring.dart';
import 'package:word_search_master/domain/text/language.dart';

import '../../support/local_db.dart';

/// THE OUTBOX CONTRACT (Ch10): a game-state change and its queued submission
/// are written in ONE transaction. Either both land or neither does.
///
/// A progress row with no outbox row is progress that silently never syncs.
/// An outbox row with no progress row submits a level the player never
/// finished. Both are invisible until a support ticket arrives months later,
/// which is exactly why this is pinned by a test.
///
/// HOW THE FAILURE IS INJECTED: a SQLite trigger that aborts any insert into
/// `outbox`. That makes the SECOND write of the pair fail against the REAL
/// repository code path — no mocks, no test-only seam in production code, and
/// no doubt about whether the thing being tested is the thing that ships.
void main() {
  late TestDatabase opened;
  late ProgressRepository progress;
  late CoinsRepository coins;
  late ProfileRepository profiles;

  setUp(() async {
    opened = await openMemoryDatabase();
    addTearDown(opened.database.close);
    progress = ProgressRepository(
      database: opened.database,
      integrity: opened.integrity,
      reporter: opened.reporter,
    );
    coins = CoinsRepository(
      database: opened.database,
      integrity: opened.integrity,
      reporter: opened.reporter,
    );
    profiles = ProfileRepository(
      database: opened.database,
      integrity: opened.integrity,
      reporter: opened.reporter,
    );
  });

  Future<void> breakOutboxWrites() => opened.database.customStatement(
    'CREATE TRIGGER fail_outbox BEFORE INSERT ON ${LocalTables.outbox} '
    "BEGIN SELECT RAISE(ABORT, 'simulated outbox failure'); END",
  );

  Future<List<LevelProgressRow>> progressRows() =>
      opened.database.select(opened.database.levelProgress).get();
  Future<List<CoinsLedgerRow>> ledgerRows() =>
      opened.database.select(opened.database.coinsLedger).get();
  Future<List<OutboxRow>> outboxRows() =>
      opened.database.select(opened.database.outbox).get();

  Future<void> completeLevel({int level = 4}) => progress.recordLevelComplete(
    language: Language.english,
    level: level,
    stars: 3,
    score: 240,
    hintsUsed: 0,
    events: const [WordFound(graphemeCount: 5), WordFound(graphemeCount: 4)],
  );

  group('the happy path writes BOTH rows', () {
    test('a completed level leaves progress and a queued submission', () async {
      await completeLevel();

      expect(await progressRows(), hasLength(1));
      expect(await outboxRows(), hasLength(1));
      expect((await outboxRows()).single.kind, OutboxKind.levelComplete.name);
    });

    test(
      'the queued payload carries the EVENTS, not the client total',
      () async {
        await completeLevel();
        final payload = (await outboxRows()).single.payload;

        // Ch08: the server replays these and computes the score itself. A
        // client-supplied total would be the one number worth forging.
        expect(payload, contains('"events"'));
        expect(payload, contains('"specVersion":${Scoring.specVersion}'));
        expect(
          payload,
          isNot(contains('"score"')),
          reason: 'the score is recomputed server-side, so it is not even sent',
        );
      },
    );

    test('the queued payload carries a replay nonce (P14)', () async {
      await completeLevel();
      final decoded = jsonDecode(
        (await outboxRows()).single.payload,
      ) as Map<String, Object?>;

      // Derived, not random, so the SAME row retried after a dropped
      // connection carries the SAME value and `submitScore` can answer it
      // idempotently instead of recording the level twice.
      expect(
        decoded['nonce'],
        SubmissionNonce.forLevel(
          language: Language.english,
          level: 4,
          completedAt: decoded['completedAt']! as int,
        ),
      );
    });
  });

  group('a failing outbox write rolls the WHOLE transaction back', () {
    test('NO PROGRESS ROW EXISTS WITHOUT ITS OUTBOX ROW', () async {
      await breakOutboxWrites();

      await expectLater(completeLevel(), throwsA(isA<SqliteException>()));

      expect(
        await progressRows(),
        isEmpty,
        reason:
            'the level_progress insert succeeded before the outbox insert '
            'failed; if it survives, the pair is not atomic and that '
            'progress would never sync',
      );
      expect(await outboxRows(), isEmpty);
    });

    test('no ledger row exists without its outbox row', () async {
      await breakOutboxWrites();

      await expectLater(
        coins.record(delta: 40, reason: 'level_complete:en:4'),
        throwsA(isA<SqliteException>()),
      );

      expect(await ledgerRows(), isEmpty);
      expect(await outboxRows(), isEmpty);
    });

    test('a refused spend leaves the ledger untouched', () async {
      await coins.record(delta: 100, reason: 'earn');
      await breakOutboxWrites();

      await expectLater(
        coins.trySpend(amount: 25, reason: 'hint'),
        throwsA(isA<SqliteException>()),
      );

      expect(await ledgerRows(), hasLength(1), reason: 'only the earn row');
      expect(
        await outboxRows(),
        hasLength(1),
        reason: 'only its own queue row',
      );
    });

    test('a profile edit rolls back too', () async {
      await profiles.updateDisplayName('Ayesha');
      await breakOutboxWrites();

      await expectLater(
        profiles.updateDisplayName('Bilal'),
        throwsA(isA<SqliteException>()),
      );

      final row = await profiles.watchProfile().first;
      expect(row!.displayName, 'Ayesha', reason: 'the first name still stands');
    });

    test('an earlier successful pair is not rolled back with it', () async {
      // Each call is its own transaction; a later failure must not undo
      // history that already committed.
      await completeLevel(level: 1);
      await breakOutboxWrites();

      await expectLater(
        completeLevel(level: 2),
        throwsA(isA<SqliteException>()),
      );

      expect((await progressRows()).map((row) => row.level), [1]);
      expect(await outboxRows(), hasLength(1));
    });

    test('the database is still usable afterwards', () async {
      await breakOutboxWrites();
      await expectLater(completeLevel(), throwsA(isA<SqliteException>()));

      await opened.database.customStatement('DROP TRIGGER fail_outbox');
      await completeLevel();

      expect(await progressRows(), hasLength(1));
      expect(await outboxRows(), hasLength(1));
    });
  });

  group('the pairing holds across many operations', () {
    test('every completed level has exactly one queued submission', () async {
      for (var level = 1; level <= 12; level++) {
        await completeLevel(level: level);
      }

      final levels = await progressRows();
      final queued = await outboxRows();

      expect(levels, hasLength(12));
      expect(queued, hasLength(12));
      expect(
        queued.every((row) => row.kind == OutboxKind.levelComplete.name),
        isTrue,
      );
    });

    test(
      'replaying a level updates progress and queues a NEW submission',
      () async {
        await completeLevel(level: 3);
        await completeLevel(level: 3);

        // One row (same primary key), but two submissions: the server needs to
        // see the second attempt even though it did not beat the first.
        expect(await progressRows(), hasLength(1));
        expect(await outboxRows(), hasLength(2));
      },
    );

    test('a replay never lowers the stored best score', () async {
      await progress.recordLevelComplete(
        language: Language.english,
        level: 9,
        stars: 3,
        score: 500,
        hintsUsed: 0,
        events: const [WordFound(graphemeCount: 5)],
      );
      await progress.recordLevelComplete(
        language: Language.english,
        level: 9,
        stars: 1,
        score: 40,
        hintsUsed: 2,
        events: const [WordFound(graphemeCount: 2), HintUsed()],
      );

      final row = (await progressRows()).single;
      expect(row.bestScore, 500);
      expect(row.stars, 3);
    });

    test('progress in one language does not appear in another', () async {
      await progress.recordLevelComplete(
        language: Language.urdu,
        level: 5,
        stars: 2,
        score: 90,
        hintsUsed: 1,
        events: const [WordFound(graphemeCount: 3)],
      );

      expect(await progress.watchAll(Language.urdu).first, hasLength(1));
      expect(await progress.watchAll(Language.hindi).first, isEmpty);
      expect(
        await progress.watchHighestCompletedLevel(Language.english).first,
        0,
      );
    });
  });
}
