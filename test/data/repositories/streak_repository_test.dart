// `isNull`/`isNotNull` collide with matcher's — this file wants the matchers.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/data/local/streak_codec.dart';
import 'package:word_search_master/data/local/tables.dart';
import 'package:word_search_master/data/repositories/streak_repository.dart';
import 'package:word_search_master/domain/progression/day_key.dart';
import 'package:word_search_master/domain/progression/streak.dart';

import '../../support/local_db.dart';

void main() {
  DayKey day(int n) => DayKey.parse('2026-03-01').addDays(n);

  Future<(StreakRepository, TestDatabase)> openRepo() async {
    final db = await openMemoryDatabase();
    addTearDown(db.database.close);
    return (
      StreakRepository(
        database: db.database,
        integrity: db.integrity,
        reporter: db.reporter,
      ),
      db,
    );
  }

  group('registerPlay', () {
    test('persists across repository instances', () async {
      final (repo, db) = await openRepo();

      await repo.registerPlay(day(0));
      await repo.registerPlay(day(1));

      final reopened = StreakRepository(
        database: db.database,
        integrity: db.integrity,
        reporter: db.reporter,
      );
      expect((await reopened.readRaw()).current, 2);
    });

    test('is idempotent within a day', () async {
      final (repo, _) = await openRepo();

      for (var i = 0; i < 5; i++) {
        await repo.registerPlay(day(0));
      }

      expect((await repo.readRaw()).current, 1);
    });

    test('returns the transition so the caller can tell the player', () async {
      final (repo, _) = await openRepo();

      for (var i = 0; i < 7; i++) {
        await repo.registerPlay(day(i));
      }
      // Day 7 missed; day 8 fires the freeze on the way in.
      final resumed = await repo.registerPlay(day(8));

      expect(resumed.freezesSpent, 1);
      expect(resumed.state.current, 8);
    });
  });

  group('reads are settled against today', () {
    test('streakAsOf ages the stored state forward without writing', () async {
      final (repo, _) = await openRepo();
      for (var i = 0; i < 7; i++) {
        await repo.registerPlay(day(i));
      }

      final settled = await repo.streakAsOf(day(8));
      expect(settled.event, StreakEvent.frozen);
      expect(settled.state.freezes, 0);

      // The row on disk is untouched — a read path that writes turns a Drift
      // stream into a feedback loop.
      expect((await repo.readRaw()).freezes, 1);
    });

    test('watchStreakAsOf emits the settled state', () async {
      final (repo, _) = await openRepo();
      for (var i = 0; i < 7; i++) {
        await repo.registerPlay(day(i));
      }

      final emitted = await repo.watchStreakAsOf(day(8)).first;

      expect(emitted.event, StreakEvent.frozen);
      expect(emitted.state.current, 7);
    });

    test('a never-played profile reads as empty, not as an error', () async {
      final (repo, _) = await openRepo();

      expect(await repo.readRaw(), StreakState.empty);
      expect(
        (await repo.watchStreakAsOf(day(0)).first).state,
        StreakState.empty,
      );
    });
  });

  group('settleAndPersist', () {
    test('writes the settled state', () async {
      final (repo, _) = await openRepo();
      for (var i = 0; i < 7; i++) {
        await repo.registerPlay(day(i));
      }

      await repo.settleAndPersist(day(8));

      expect(
        (await repo.readRaw()).freezes,
        0,
        reason: 'a freeze spent while the app was closed has to be durable',
      );
    });

    test('writes nothing when settling changed nothing', () async {
      final (repo, db) = await openRepo();
      await repo.registerPlay(day(0));

      final before = await (db.database.select(
        db.database.kvSettings,
      )..where((row) => row.key.equals(KvKeys.streakState))).getSingle();

      await repo.settleAndPersist(day(0));

      final after = await (db.database.select(
        db.database.kvSettings,
      )..where((row) => row.key.equals(KvKeys.streakState))).getSingle();

      expect(after.value, before.value);
    });
  });

  group('integrity', () {
    test('A HAND-EDITED STREAK IS REJECTED and reads as empty', () async {
      final (repo, db) = await openRepo();
      for (var i = 0; i < 5; i++) {
        await repo.registerPlay(day(i));
      }
      expect((await repo.readRaw()).current, 5);

      // Forge a 500-day streak directly in the row, leaving the tag alone —
      // exactly what a player with a SQLite editor would do.
      await db.database.customUpdate(
        'UPDATE ${LocalTables.kvSettings} SET value = ? WHERE key = ?',
        variables: [
          Variable<String>(
            StreakCodec.encode(
              StreakState(
                current: 500,
                longest: 500,
                lastActiveDay: day(4),
                lastPlayedDay: day(4),
                freezes: 2,
              ),
            ),
          ),
          Variable<String>(KvKeys.streakState),
        ],
        updates: {db.database.kvSettings},
      );

      expect(
        (await repo.readRaw()).current,
        0,
        reason: 'a failed check drops the row rather than paying out',
      );
      expect(db.reporter.integrityViolations, isNotEmpty);
    });

    test(
      'the tampered row is EXCLUDED, not deleted — it is evidence',
      () async {
        final (repo, db) = await openRepo();
        await repo.registerPlay(day(0));

        await db.database.customUpdate(
          'UPDATE ${LocalTables.kvSettings} SET value = ? WHERE key = ?',
          variables: [
            const Variable<String>('{"current":999}'),
            Variable<String>(KvKeys.streakState),
          ],
          updates: {db.database.kvSettings},
        );

        await repo.readRaw();

        final row = await (db.database.select(
          db.database.kvSettings,
        )..where((r) => r.key.equals(KvKeys.streakState))).getSingleOrNull();
        expect(row, isNotNull);
      },
    );
  });

  group('DriftDayHighWaterMarkStore', () {
    test('round-trips a day', () async {
      final db = await openMemoryDatabase();
      addTearDown(db.database.close);
      final store = DriftDayHighWaterMarkStore(
        database: db.database,
        integrity: db.integrity,
        reporter: db.reporter,
      );

      expect(await store.read(), isNull);

      await store.write(day(3));
      expect(await store.read(), day(3));

      await store.write(day(9));
      expect(await store.read(), day(9));
    });

    test(
      'a forged mark reads as absent, losing the guard rather than lying',
      () async {
        final db = await openMemoryDatabase();
        addTearDown(db.database.close);
        final store = DriftDayHighWaterMarkStore(
          database: db.database,
          integrity: db.integrity,
          reporter: db.reporter,
        );
        await store.write(day(3));

        await db.database.customUpdate(
          'UPDATE ${LocalTables.kvSettings} SET value = ? WHERE key = ?',
          variables: [
            const Variable<String>('2099-12-31'),
            Variable<String>(KvKeys.dayHighWaterMark),
          ],
          updates: {db.database.kvSettings},
        );

        expect(await store.read(), isNull);
      },
    );
  });
}
