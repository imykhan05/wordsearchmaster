import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/data/local/app_database.dart';
import 'package:word_search_master/data/repositories/dda_repository.dart';
import 'package:word_search_master/domain/text/language.dart';

import '../../support/local_db.dart';

/// `DdaRepository`'s abandon-count persistence (Ch02/P12) — the same
/// tagged-`kv_settings`-row shape `streak_repository_test.dart` already
/// proves for the streak, walked here for the abandon counter instead.
void main() {
  Future<DdaRepository> openRepo() async {
    final db = await openMemoryDatabase();
    addTearDown(db.database.close);
    return DdaRepository(
      database: db.database,
      integrity: db.integrity,
      reporter: db.reporter,
    );
  }

  test('a level never abandoned reads as zero', () async {
    final repo = await openRepo();

    expect(await repo.abandonCount(Language.english, 5), 0);
    expect(await repo.shouldDownshift(Language.english, 5), isFalse);
  });

  test('one abandon does not trigger a downshift', () async {
    final repo = await openRepo();

    await repo.recordAbandon(Language.english, 5);

    expect(await repo.abandonCount(Language.english, 5), 1);
    expect(await repo.shouldDownshift(Language.english, 5), isFalse);
  });

  test('two CONSECUTIVE abandons trigger a downshift — Ch02', () async {
    final repo = await openRepo();

    await repo.recordAbandon(Language.english, 5);
    await repo.recordAbandon(Language.english, 5);

    expect(await repo.abandonCount(Language.english, 5), 2);
    expect(await repo.shouldDownshift(Language.english, 5), isTrue);
  });

  test('consumeDownshift resets the counter, so it takes two more', () async {
    final repo = await openRepo();
    await repo.recordAbandon(Language.english, 5);
    await repo.recordAbandon(Language.english, 5);

    await repo.consumeDownshift(Language.english, 5);

    expect(await repo.abandonCount(Language.english, 5), 0);
    expect(await repo.shouldDownshift(Language.english, 5), isFalse);
  });

  test('clearAbandon (a completion) resets the counter the same way', () async {
    final repo = await openRepo();
    await repo.recordAbandon(Language.english, 5);

    await repo.clearAbandon(Language.english, 5);

    expect(await repo.abandonCount(Language.english, 5), 0);
  });

  test('(language, level) is a genuinely separate counter', () async {
    final repo = await openRepo();

    await repo.recordAbandon(Language.english, 5);
    await repo.recordAbandon(Language.english, 5);

    expect(
      await repo.abandonCount(Language.urdu, 5),
      0,
      reason: 'level 5 in Urdu is a different puzzle (P10)',
    );
    expect(
      await repo.abandonCount(Language.english, 6),
      0,
      reason: 'a different level must not share the same counter',
    );
  });

  test('persists across repository instances, like the streak', () async {
    final db = await openMemoryDatabase();
    addTearDown(db.database.close);
    final repo = DdaRepository(
      database: db.database,
      integrity: db.integrity,
      reporter: db.reporter,
    );

    await repo.recordAbandon(Language.hindi, 12);

    final reopened = DdaRepository(
      database: db.database,
      integrity: db.integrity,
      reporter: db.reporter,
    );
    expect(await reopened.abandonCount(Language.hindi, 12), 1);
  });

  test('a tampered row reads as zero, not as an error — Ch10', () async {
    final db = await openMemoryDatabase();
    addTearDown(db.database.close);
    final repo = DdaRepository(
      database: db.database,
      integrity: db.integrity,
      reporter: db.reporter,
    );
    await repo.recordAbandon(Language.english, 5);

    // A wrong tag can never verify, whatever wrote it — writes the row
    // through Drift directly (bypassing `RowTags.kvSetting`) rather than
    // `repo.writeKv`, so the tag is deliberately wrong instead of correct.
    await db.database
        .into(db.database.kvSettings)
        .insertOnConflictUpdate(
          KvSettingsCompanion.insert(
            key: 'dda_abandon:en:5',
            value: '2',
            integrityTag: 'forged',
          ),
        );

    expect(await repo.abandonCount(Language.english, 5), 0);
    expect(db.reporter.integrityViolations, isNotEmpty);
  });
}
