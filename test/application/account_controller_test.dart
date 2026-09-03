import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/application/account_controller.dart';
import 'package:word_search_master/data/local/app_database.dart';
import 'package:word_search_master/data/remote/cloud_account_repository.dart';
import 'package:word_search_master/data/repositories/account_merge_repository.dart';
import 'package:word_search_master/data/repositories/coins_repository.dart';
import 'package:word_search_master/data/repositories/profile_repository.dart';
import 'package:word_search_master/data/repositories/progress_repository.dart';
import 'package:word_search_master/domain/progression/account_merge.dart';
import 'package:word_search_master/domain/scoring/score_event.dart';
import 'package:word_search_master/domain/text/language.dart';
import 'package:word_search_master/services/auth/auth_service.dart';

import '../support/local_db.dart';

/// The guest→Google sequence end to end, with the two Firebase-shaped parts
/// (auth and the cloud read) faked and everything else real.
///
/// P13 ACCEPTANCE CRITERION 2 in its most literal form: the
/// `credential-already-in-use` path — the one where a merge is required and
/// where forgetting to merge would silently discard a player's guest
/// progress.
void main() {
  Future<(ProviderContainer, TestDatabase)> harness({
    required AuthService auth,
    CloudAccountRepository? cloud,
  }) async {
    final db = await openMemoryDatabase();
    addTearDown(db.database.close);
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db.database),
        authServiceProvider.overrideWithValue(auth),
        if (cloud != null)
          cloudAccountRepositoryProvider.overrideWithValue(cloud),
      ],
    );
    addTearDown(container.dispose);
    return (container, db);
  }

  Future<void> playLevel(
    TestDatabase db,
    int n, {
    int stars = 1,
    int score = 100,
  }) =>
      ProgressRepository(
        database: db.database,
        integrity: db.integrity,
        reporter: db.reporter,
      ).recordLevelComplete(
        language: Language.english,
        level: n,
        stars: stars,
        score: score,
        hintsUsed: 0,
        events: const [WordFound(graphemeCount: 5)],
      );

  LevelSnapshot level(int n, {int stars = 1}) => LevelSnapshot(
    language: Language.english,
    level: n,
    stars: stars,
    bestScore: 100,
    hintsUsed: 0,
    completedAt: 1000,
  );

  group('linkWithGoogle', () {
    test('a plain success links without merging', () async {
      final (container, db) = await harness(
        auth: _FakeAuth(
          const LinkSucceeded(
            AuthAccount(uid: 'guest-upgraded', isAnonymous: false),
          ),
        ),
        // A cloud that would return coins if it were consulted. It must NOT
        // be: the anonymous account was upgraded in place, so its cloud copy
        // IS this account, and merging would credit its balance twice.
        cloud: _FakeCloud(const AccountSnapshot(coinBalance: 999)),
      );

      final result = await container
          .read(accountControllerProvider.notifier)
          .linkWithGoogle();

      expect(result, AccountLinkResult.linked);
      final coins = CoinsRepository(
        database: db.database,
        integrity: db.integrity,
        reporter: db.reporter,
      );
      expect(await coins.watchBalance().first, 0);
    });

    test('cancelling reports cancelled and touches nothing', () async {
      final (container, db) = await harness(
        auth: _FakeAuth(const LinkCancelled()),
      );
      await playLevel(db, 1, stars: 3);

      final result = await container
          .read(accountControllerProvider.notifier)
          .linkWithGoogle();

      expect(result, AccountLinkResult.cancelled);
      final profile = await container.read(profileRepositoryProvider.future);
      expect((await profile.watchProfile().first)?.cloudUserId, isNull);
    });

    test('a failure keeps the guest session and every local row', () async {
      final (container, db) = await harness(
        auth: _FakeAuth(const LinkFailed('network-request-failed')),
      );
      await playLevel(db, 1, stars: 3);

      final result = await container
          .read(accountControllerProvider.notifier)
          .linkWithGoogle();

      expect(result, AccountLinkResult.failed);
      final progress = await container.read(progressRepositoryProvider.future);
      expect(await progress.completedLevels(Language.english), {1});
    });

    test(
      'THE CRITERION: credential-already-in-use merges instead of choosing',
      () async {
        final (container, db) = await harness(
          auth: _FakeAuth(
            const LinkRequiresMerge(
              AuthAccount(uid: 'existing-uid', isAnonymous: false),
            ),
          ),
          cloud: _FakeCloud(
            AccountSnapshot(
              levels: {'en/2': level(2, stars: 3), 'en/3': level(3, stars: 2)},
              coinBalance: 250,
            ),
          ),
        );
        // The guest played 1 and 2 on this device.
        await playLevel(db, 1, stars: 3);
        await playLevel(db, 2, stars: 1);

        final result = await container
            .read(accountControllerProvider.notifier)
            .linkWithGoogle();

        expect(result, AccountLinkResult.linked);

        final merge = await container.read(
          accountMergeRepositoryProvider.future,
        );
        final after = await merge.readLocalSnapshot();
        expect(
          after.levels.keys,
          containsAll(['en/1', 'en/2', 'en/3']),
          reason: 'guest-only, contested and cloud-only levels all survive',
        );
        expect(after.levels['en/1']!.stars, 3, reason: 'guest level kept');
        expect(after.levels['en/2']!.stars, 3, reason: 'better cloud row won');
        expect(after.coinBalance, 250, reason: 'cloud coins credited');
      },
    );

    test('the merged account is remembered on the profile row', () async {
      final (container, _) = await harness(
        auth: _FakeAuth(
          const LinkRequiresMerge(
            AuthAccount(uid: 'existing-uid', isAnonymous: false),
          ),
        ),
        cloud: _FakeCloud(AccountSnapshot.empty),
      );

      await container.read(accountControllerProvider.notifier).linkWithGoogle();

      final profile = await container.read(profileRepositoryProvider.future);
      expect((await profile.watchProfile().first)?.cloudUserId, 'existing-uid');
    });

    test('a cloud read that comes back empty is a no-op, not a wipe', () async {
      // The offline-at-sign-in case: `FirestoreAccountRepository` returns
      // empty rather than throwing, and the merge must then preserve
      // everything local.
      final (container, db) = await harness(
        auth: _FakeAuth(
          const LinkRequiresMerge(
            AuthAccount(uid: 'existing-uid', isAnonymous: false),
          ),
        ),
        cloud: _FakeCloud(AccountSnapshot.empty),
      );
      await playLevel(db, 1, stars: 3);
      await playLevel(db, 2, stars: 2);

      final result = await container
          .read(accountControllerProvider.notifier)
          .linkWithGoogle();

      expect(result, AccountLinkResult.linked);
      final progress = await container.read(progressRepositoryProvider.future);
      expect(await progress.completedLevels(Language.english), {1, 2});
    });
  });

  group('signOut', () {
    test('clears the cloud id but keeps every local row — Ch02', () async {
      final auth = _FakeAuth(const LinkCancelled());
      final (container, db) = await harness(auth: auth);
      await playLevel(db, 1, stars: 3);
      final profile = await container.read(profileRepositoryProvider.future);
      await profile.linkCloudUser('some-uid');

      await container.read(accountControllerProvider.notifier).signOut();

      expect(auth.signedOut, isTrue);
      expect((await profile.watchProfile().first)?.cloudUserId, isNull);
      final progress = await container.read(progressRepositoryProvider.future);
      expect(await progress.completedLevels(Language.english), {
        1,
      }, reason: 'signing out is not a request to lose anything');
    });
  });
}

final class _FakeAuth implements AuthService {
  _FakeAuth(this._outcome);

  final LinkOutcome _outcome;
  bool signedOut = false;

  @override
  AuthAccount? get currentAccount =>
      const AuthAccount(uid: 'guest', isAnonymous: true);

  @override
  Stream<AuthAccount?> watchAccount() => Stream.value(currentAccount);

  @override
  Future<AuthAccount?> ensureSignedIn() async => currentAccount;

  @override
  Future<LinkOutcome> linkWithGoogle() async => _outcome;

  @override
  String? get lastGoogleSignInDiagnostic => null;

  @override
  Future<AuthAccount?> signOut() async {
    signedOut = true;
    return currentAccount;
  }
}

final class _FakeCloud implements CloudAccountRepository {
  _FakeCloud(this._snapshot);

  final AccountSnapshot _snapshot;
  bool wasRead = false;

  @override
  Future<AccountSnapshot> readSnapshot(String uid) async {
    wasRead = true;
    return _snapshot;
  }
}
