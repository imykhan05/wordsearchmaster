/// The guest→Google sign-in flow, end to end (Ch02 / P13).
///
/// ---------------------------------------------------------------------------
/// ONE PLACE THAT KNOWS THE WHOLE SEQUENCE
///
/// Linking is four steps that have to happen in order and have to be undone
/// safely if any of them fails: open the Google sheet, upgrade or fall back
/// to the existing account, read that account's cloud snapshot, merge it into
/// the local database. Spreading them across a screen's button handler is how
/// the merge step gets skipped on one of the two paths — and skipping it on
/// the `credential-already-in-use` path is precisely the bug that loses a
/// player's progress.
///
/// So [AccountController.linkWithGoogle] owns the sequence and returns a
/// single [AccountLinkResult] the UI can render without knowing any of it.
///
/// ---------------------------------------------------------------------------
/// EVERY `ref` READ HAPPENS BEFORE THE FIRST `await`
///
/// The same load-bearing rule `ProgressionController` documents at length:
/// nothing WATCHES this controller, so a `ref` read placed after an `await`
/// races its own disposal and throws `UnmountedRefException`. That is not
/// theoretical here — the player taps "Sign in", the Google sheet takes over
/// the screen for several seconds, and a rebuild in the meantime is ordinary.
/// `keepAlive: true` guards it, and every method resolves its whole
/// dependency set synchronously at the top as well.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/remote/cloud_account_repository.dart';
import '../data/repositories/account_merge_repository.dart';
import '../data/repositories/profile_repository.dart';
import '../services/auth/auth_service.dart';

part 'account_controller.g.dart';

/// What the UI shows after a sign-in attempt.
enum AccountLinkResult {
  /// Signed in, and any cloud progress has been merged into the local
  /// database. The only outcome that should read as a success.
  linked,

  /// The player closed the Google sheet. Show nothing at all.
  cancelled,

  /// Sign-in itself failed. The guest session and every local row are intact;
  /// the UI offers to try again.
  failed,

  /// Signed in, but the cloud snapshot could not be merged — the write failed
  /// or rolled back.
  ///
  /// DISTINCT FROM [failed] on purpose. The player IS signed in, so telling
  /// them sign-in failed would be a lie they can disprove by looking at the
  /// screen; and their local progress is untouched, so telling them anything
  /// alarming would be worse than the truth. Ch02: keep local data and retry.
  linkedMergePending,
}

@Riverpod(keepAlive: true)
class AccountController extends _$AccountController {
  @override
  void build() {}

  /// Signs in with Google, merging any existing cloud account into this one.
  Future<AccountLinkResult> linkWithGoogle() async {
    // ---- every ref read, before any await. See the library header. ----
    final auth = ref.read(authServiceProvider);
    final cloud = ref.read(cloudAccountRepositoryProvider);
    final mergeRepoFuture = ref.read(accountMergeRepositoryProvider.future);
    final profileRepoFuture = ref.read(profileRepositoryProvider.future);
    // -------------------------------------------------------------------

    final outcome = await auth.linkWithGoogle();

    switch (outcome) {
      case LinkCancelled():
        return AccountLinkResult.cancelled;

      case LinkFailed():
        return AccountLinkResult.failed;

      case LinkSucceeded(:final account):
        // The anonymous account was upgraded IN PLACE, so this uid already
        // owns every local row. There is nothing to merge — and running a
        // merge anyway would read the account's own cloud copy and credit its
        // balance a second time.
        await _rememberCloudUser(profileRepoFuture, account.uid);
        return AccountLinkResult.linked;

      case LinkRequiresMerge(:final existingAccount):
        // The path that matters. The player is now signed in as an account
        // that already had progress; the guest's rows are still sitting
        // untouched in the local database, and the merge is what brings the
        // two together.
        final remote = await cloud.readSnapshot(existingAccount.uid);
        final mergeRepo = await mergeRepoFuture;
        final merged = await mergeRepo.applyMerge(
          remote: remote,
          remoteUid: existingAccount.uid,
        );
        await _rememberCloudUser(profileRepoFuture, existingAccount.uid);

        // A null merge means the transaction rolled back — local data is
        // exactly as it was. Say so honestly rather than reporting success.
        return merged == null
            ? AccountLinkResult.linkedMergePending
            : AccountLinkResult.linked;
    }
  }

  /// Signs out and returns to a FRESH guest session.
  ///
  /// Local data is deliberately untouched — Ch02. The profile row's
  /// `cloudUserId` is cleared so the UI stops showing a linked account, but
  /// levels, coins and the streak all stay exactly where they are, because a
  /// player who signs out has not asked to lose anything.
  Future<void> signOut() async {
    final auth = ref.read(authServiceProvider);
    final profileRepoFuture = ref.read(profileRepositoryProvider.future);

    await auth.signOut();
    await _rememberCloudUser(profileRepoFuture, null);
  }

  Future<void> _rememberCloudUser(
    Future<ProfileRepository> repoFuture,
    String? uid,
  ) async {
    final repo = await repoFuture;
    await repo.linkCloudUser(uid);
  }
}
