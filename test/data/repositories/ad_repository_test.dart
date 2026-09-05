import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/data/local/app_database.dart';
import 'package:word_search_master/data/repositories/ad_repository.dart';
import 'package:word_search_master/domain/progression/ad_policy.dart';

import '../../support/local_db.dart';

/// `AdRepository`'s pacing-counter persistence (pre-P18) — the same
/// tagged-`kv_settings`-row shape `dda_repository_test.dart` already proves
/// for the abandon counter, walked here for the two global ad counters
/// instead.
void main() {
  Future<AdRepository> openRepo() async {
    final db = await openMemoryDatabase();
    addTearDown(db.database.close);
    return AdRepository(
      database: db.database,
      integrity: db.integrity,
      reporter: db.reporter,
    );
  }

  test('a fresh install reads zero on both counters', () async {
    final repo = await openRepo();

    expect(await repo.totalLevelsCompleted(), 0);
    expect(await repo.levelsSinceLastInterstitial(), 0);
  });

  test('recordLevelCompleted advances both counters together', () async {
    final repo = await openRepo();

    await repo.recordLevelCompleted();
    await repo.recordLevelCompleted();
    await repo.recordLevelCompleted();

    expect(await repo.totalLevelsCompleted(), 3);
    expect(await repo.levelsSinceLastInterstitial(), 3);
  });

  test(
    'recordInterstitialShown resets ONLY the gap counter, never the total',
    () async {
      final repo = await openRepo();
      await repo.recordLevelCompleted();
      await repo.recordLevelCompleted();

      await repo.recordInterstitialShown();

      expect(await repo.levelsSinceLastInterstitial(), 0);
      expect(
        await repo.totalLevelsCompleted(),
        2,
        reason: 'the lifetime total never goes backwards',
      );
    },
  );

  test('the gap counter resumes counting after a reset', () async {
    final repo = await openRepo();
    await repo.recordLevelCompleted();
    await repo.recordInterstitialShown();

    await repo.recordLevelCompleted();
    await repo.recordLevelCompleted();

    expect(await repo.levelsSinceLastInterstitial(), 2);
    expect(await repo.totalLevelsCompleted(), 3);
  });

  group('canShowInterstitial', () {
    const policy = AdFrequencyPolicy(minLevelsBetweenInterstitials: 2);

    test('false before the gap is reached', () async {
      final repo = await openRepo();
      await repo.recordLevelCompleted();

      expect(await repo.canShowInterstitial(policy), isFalse);
    });

    test('true once the recorded history satisfies the policy', () async {
      final repo = await openRepo();
      await repo.recordLevelCompleted();
      await repo.recordLevelCompleted();

      expect(await repo.canShowInterstitial(policy), isTrue);
    });

    test('false again immediately after an interstitial shows', () async {
      final repo = await openRepo();
      await repo.recordLevelCompleted();
      await repo.recordLevelCompleted();
      expect(await repo.canShowInterstitial(policy), isTrue);

      await repo.recordInterstitialShown();

      expect(await repo.canShowInterstitial(policy), isFalse);
    });
  });

  test(
    'persists across repository instances, like the streak/DDA counters',
    () async {
      final db = await openMemoryDatabase();
      addTearDown(db.database.close);
      final repo = AdRepository(
        database: db.database,
        integrity: db.integrity,
        reporter: db.reporter,
      );

      await repo.recordLevelCompleted();
      await repo.recordLevelCompleted();

      final reopened = AdRepository(
        database: db.database,
        integrity: db.integrity,
        reporter: db.reporter,
      );
      expect(await reopened.totalLevelsCompleted(), 2);
      expect(await reopened.levelsSinceLastInterstitial(), 2);
    },
  );

  test('a tampered row reads as zero, not as an error — Ch10', () async {
    final db = await openMemoryDatabase();
    addTearDown(db.database.close);
    final repo = AdRepository(
      database: db.database,
      integrity: db.integrity,
      reporter: db.reporter,
    );
    await repo.recordLevelCompleted();

    // A wrong tag can never verify, whatever wrote it — writes the row
    // through Drift directly (bypassing `RowTags.kvSetting`) rather than
    // `repo.writeKv`, so the tag is deliberately wrong instead of correct.
    await db.database
        .into(db.database.kvSettings)
        .insertOnConflictUpdate(
          KvSettingsCompanion.insert(
            key: 'ad_total_levels_completed',
            value: '99',
            integrityTag: 'forged',
          ),
        );

    expect(await repo.totalLevelsCompleted(), 0);
    expect(db.reporter.integrityViolations, isNotEmpty);
  });
}
