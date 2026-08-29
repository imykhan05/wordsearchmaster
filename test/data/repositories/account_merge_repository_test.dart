import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/data/repositories/account_merge_repository.dart';
import 'package:word_search_master/data/repositories/coins_repository.dart';
import 'package:word_search_master/data/repositories/progress_repository.dart';
import 'package:word_search_master/data/repositories/streak_repository.dart';
import 'package:word_search_master/domain/progression/account_merge.dart';
import 'package:word_search_master/domain/progression/day_key.dart';
import 'package:word_search_master/domain/progression/streak.dart';
import 'package:word_search_master/domain/scoring/score_event.dart';
import 'package:word_search_master/domain/text/language.dart';

import '../../support/local_db.dart';

/// P13 ACCEPTANCE CRITERION 2's WRITE PATH, against a real (in-memory)
/// database: the merge rules are proven pure in
/// `test/domain/progression/account_merge_test.dart`; this file proves they
/// actually land, land once, and never destroy what was already there.
void main() {
  Future<(AccountMergeRepository, TestDatabase)> openRepo() async {
    final db = await openMemoryDatabase();
    addTearDown(db.database.close);
    return (
      AccountMergeRepository(
        database: db.database,
        integrity: db.integrity,
        reporter: db.reporter,
      ),
      db,
    );
  }

  ProgressRepository progressOf(TestDatabase db) => ProgressRepository(
    database: db.database,
    integrity: db.integrity,
    reporter: db.reporter,
  );

  CoinsRepository coinsOf(TestDatabase db) => CoinsRepository(
    database: db.database,
    integrity: db.integrity,
    reporter: db.reporter,
  );

  LevelSnapshot level(int n, {int stars = 1, int score = 100}) => LevelSnapshot(
    language: Language.english,
    level: n,
    stars: stars,
    bestScore: score,
    hintsUsed: 0,
    completedAt: 1000,
  );

  Future<void> playLevel(
    TestDatabase db,
    int n, {
    int stars = 1,
    int score = 100,
  }) => progressOf(db).recordLevelComplete(
    language: Language.english,
    level: n,
    stars: stars,
    score: score,
    hintsUsed: 0,
    events: const [WordFound(graphemeCount: 5)],
  );

  group('readLocalSnapshot', () {
    test('reads back what the other repositories wrote', () async {
      final (repo, db) = await openRepo();
      await playLevel(db, 1, stars: 3, score: 500);
      await playLevel(db, 2, stars: 2, score: 200);
      await coinsOf(db).record(delta: 120, reason: 'test');

      final snapshot = await repo.readLocalSnapshot();

      expect(snapshot.levels.keys, containsAll(['en/1', 'en/2']));
      expect(snapshot.levels['en/1']!.stars, 3);
      expect(snapshot.coinBalance, 120);
    });

    test('a brand-new install reads as empty, not as an error', () async {
      final (repo, _) = await openRepo();

      final snapshot = await repo.readLocalSnapshot();

      expect(snapshot.isEmpty, isTrue);
    });
  });

  group('applyMerge', () {
    test('THE CRITERION: guest levels survive, cloud levels arrive', () async {
      final (repo, db) = await openRepo();
      // The guest played 1 and 2 on this device.
      await playLevel(db, 1, stars: 3, score: 500);
      await playLevel(db, 2, stars: 1, score: 100);

      // The Google account already had 2 (better) and 3.
      final merged = await repo.applyMerge(
        remoteUid: 'remote-uid',
        remote: AccountSnapshot(
          levels: {
            'en/2': level(2, stars: 3, score: 900),
            'en/3': level(3, stars: 2, score: 300),
          },
        ),
      );

      expect(merged, isNotNull);
      // Read back through the REAL repository, so this asserts the rows are
      // properly tagged and pass their integrity check — a merge that wrote
      // rows this device cannot verify would be worse than not merging.
      final after = await repo.readLocalSnapshot();
      expect(after.levels.keys, containsAll(['en/1', 'en/2', 'en/3']));
      expect(after.levels['en/1']!.stars, 3, reason: 'guest-only level kept');
      expect(after.levels['en/2']!.stars, 3, reason: 'better cloud row won');
      expect(after.levels['en/3']!.stars, 2, reason: 'cloud-only level added');
    });

    test('merged rows are readable by ProgressRepository too', () async {
      final (repo, db) = await openRepo();
      await repo.applyMerge(
        remoteUid: 'remote-uid',
        remote: AccountSnapshot(levels: {'en/7': level(7, stars: 3)}),
      );

      // The whole point of re-signing on write: the merged row has to be a
      // first-class local row, not an artefact only this repository can read.
      expect(await progressOf(db).completedLevels(Language.english), {7});
    });

    test('coins are credited once, however many times a merge runs', () async {
      final (repo, db) = await openRepo();
      await coinsOf(db).record(delta: 100, reason: 'guest earnings');

      const remote = AccountSnapshot(coinBalance: 250);
      await repo.applyMerge(remote: remote, remoteUid: 'remote-uid');
      await repo.applyMerge(remote: remote, remoteUid: 'remote-uid');
      await repo.applyMerge(remote: remote, remoteUid: 'remote-uid');

      // 100 guest + 250 remote, credited exactly once — not 100 + 750.
      expect(await coinsOf(db).watchBalance().first, 350);
    });

    test('a DIFFERENT remote account credits separately', () async {
      final (repo, db) = await openRepo();

      await repo.applyMerge(
        remote: const AccountSnapshot(coinBalance: 100),
        remoteUid: 'uid-a',
      );
      await repo.applyMerge(
        remote: const AccountSnapshot(coinBalance: 50),
        remoteUid: 'uid-b',
      );

      expect(await coinsOf(db).watchBalance().first, 150);
    });

    test('the credit is traceable in the ledger by remote uid', () async {
      final (repo, db) = await openRepo();
      await repo.applyMerge(
        remote: const AccountSnapshot(coinBalance: 42),
        remoteUid: 'remote-uid',
      );

      final ledger = await coinsOf(db).watchLedger().first;
      expect(
        ledger.map((row) => row.reason),
        contains(AccountMergeRepository.mergeReasonFor('remote-uid')),
      );
    });

    test('the streak merges to the better of the two', () async {
      final (repo, db) = await openRepo();
      final streaks = StreakRepository(
        database: db.database,
        integrity: db.integrity,
        reporter: db.reporter,
      );
      await streaks.registerPlay(DayKey.parse('2026-03-01'));

      await repo.applyMerge(
        remoteUid: 'remote-uid',
        remote: const AccountSnapshot(
          streak: StreakState(current: 9, longest: 15),
        ),
      );

      final after = await repo.readLocalSnapshot();
      expect(after.streak.current, 9);
      expect(after.streak.longest, 15);
    });

    test('achievements are unioned into the real table', () async {
      final (repo, _) = await openRepo();

      await repo.applyMerge(
        remoteUid: 'remote-uid',
        remote: const AccountSnapshot(
          achievements: {
            'collection:en:animals': AchievementSnapshot(
              id: 'collection:en:animals',
              progress: 25,
              unlockedAt: 999,
            ),
          },
        ),
      );

      final after = await repo.readLocalSnapshot();
      expect(after.achievements['collection:en:animals']!.unlockedAt, 999);
    });
  });

  group('never wipe — Ch02', () {
    test('merging against an EMPTY remote changes nothing', () async {
      // The airplane-mode case: the cloud read failed, so `remote` is empty.
      // This must be a no-op, not a reset.
      final (repo, db) = await openRepo();
      await playLevel(db, 1, stars: 3, score: 500);
      await playLevel(db, 2, stars: 2, score: 200);
      await coinsOf(db).record(delta: 300, reason: 'guest earnings');
      final before = await repo.readLocalSnapshot();

      await repo.applyMerge(
        remote: AccountSnapshot.empty,
        remoteUid: 'remote-uid',
      );

      final after = await repo.readLocalSnapshot();
      expect(after.levels, before.levels);
      expect(after.coinBalance, before.coinBalance);
    });

    test(
      'a merge that THROWS mid-write leaves local data byte-for-byte intact',
      () async {
        final (repo, db) = await openRepo();
        await playLevel(db, 1, stars: 3, score: 500);
        await coinsOf(db).record(delta: 300, reason: 'guest earnings');
        final before = await repo.readLocalSnapshot();

        // A row whose language this build does not know is written by
        // `_writeLevel` as a raw code — but a stars value outside the table's
        // own CHECK constraint aborts the transaction partway through, after
        // some rows have already been inserted. That is exactly the
        // "merging fails halfway" shape Ch02's rule is about.
        final result = await repo.applyMerge(
          remoteUid: 'remote-uid',
          remote: AccountSnapshot(
            levels: {
              'en/2': level(2, stars: 2),
              // stars: 99 violates `CHECK (stars BETWEEN 0 AND 3)`.
              'en/3': level(3, stars: 99),
            },
            coinBalance: 250,
          ),
        );

        expect(result, isNull, reason: 'a failed merge reports failure');

        final after = await repo.readLocalSnapshot();
        expect(after.levels, before.levels, reason: 'nothing was added');
        expect(
          after.coinBalance,
          before.coinBalance,
          reason: 'and no coins were credited by a rolled-back merge',
        );
      },
    );
  });
}
