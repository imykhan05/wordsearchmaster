/// Guest-first authentication (Ch02 / P13).
///
/// ---------------------------------------------------------------------------
/// GUEST FIRST, AND THE PLAYER IS NEVER BLOCKED
///
/// Ch02 is unambiguous: the FTUE is splash → language select → level 1, with
/// "no login, no permissions, no ads". So sign-in happens SILENTLY and
/// ANONYMOUSLY during bootstrap, the player is never shown an account screen
/// they did not ask for, and Google Sign-In is offered only after level 8 and
/// from the profile screen. Every method below is written so that failing is
/// survivable: an anonymous sign-in that cannot reach the network leaves the
/// game fully playable against the local database, because Drift — not
/// Firebase — is the source of truth (CLAUDE.md → Architecture).
///
/// ---------------------------------------------------------------------------
/// WHY THIS IS AN INTERFACE
///
/// Same reason `AdGateway`, `ErrorReporter`, `AudioService` and
/// `AnalyticsService` are: nothing outside `services/` may import a vendor
/// SDK, and a widget test that pumps the profile screen must not need a
/// Firebase app to exist. [NoopAuthService] is the binding in tests and on any
/// build where `Firebase.initializeApp` failed; `firebase_auth_service.dart`
/// holds the real one, and `bootstrap.dart` overrides the provider with it
/// once step 2 has actually succeeded.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'auth_service.g.dart';

/// Who is signed in right now.
///
/// Deliberately NOT Firebase's `User`: that type carries a live handle and
/// pulls the SDK into every file that wants to know whether the player is a
/// guest. This is a plain value.
final class AuthAccount {
  const AuthAccount({
    required this.uid,
    required this.isAnonymous,
    this.displayName,
    this.email,
  });

  final String uid;

  /// True for the silent guest account every player starts with.
  final bool isAnonymous;

  final String? displayName;
  final String? email;

  /// Whether this account has a real identity behind it — the only thing the
  /// UI actually branches on ("Sign in to save your progress" vs. showing who
  /// you are).
  bool get isLinked => !isAnonymous;

  @override
  bool operator ==(Object other) =>
      other is AuthAccount &&
      other.uid == uid &&
      other.isAnonymous == isAnonymous &&
      other.displayName == displayName &&
      other.email == email;

  @override
  int get hashCode => Object.hash(uid, isAnonymous, displayName, email);

  @override
  String toString() =>
      'AuthAccount($uid, anonymous: $isAnonymous, name: $displayName)';
}

/// What happened when the player tried to link a Google account.
///
/// A sealed type rather than a bool + nullable error, because the four
/// outcomes need genuinely different handling and the compiler should say so
/// at every call site — [LinkRequiresMerge] in particular is easy to forget
/// and is exactly the case that would lose a player's progress.
sealed class LinkOutcome {
  const LinkOutcome();
}

/// The anonymous account was upgraded in place. Nothing to merge: this uid is
/// the same one that owns all the local rows, it simply has a Google identity
/// attached to it now.
final class LinkSucceeded extends LinkOutcome {
  const LinkSucceeded(this.account);

  final AuthAccount account;

  @override
  String toString() => 'LinkSucceeded(${account.uid})';
}

/// THE CASE THAT MATTERS: Firebase rejected the link with
/// `credential-already-in-use`, meaning this Google account already has its
/// own Firebase user with its own cloud progress.
///
/// The documented recovery (Ch02) is a MERGE, never a choice between the two:
/// sign in as [existingAccount], read its cloud snapshot, merge it with what
/// the guest has locally per `AccountMerge`, and write the union back. The
/// guest's anonymous uid is abandoned afterwards — but the guest's DATA is
/// not, because it never left the local database.
final class LinkRequiresMerge extends LinkOutcome {
  const LinkRequiresMerge(this.existingAccount);

  /// The account that already owned the credential, already signed in — so
  /// the caller can read its cloud data immediately.
  final AuthAccount existingAccount;

  @override
  String toString() => 'LinkRequiresMerge(${existingAccount.uid})';
}

/// The player backed out of the Google sheet. Not an error, and must not be
/// reported as one — a dialog saying "sign-in failed" after someone
/// deliberately pressed cancel is a bug, not feedback.
final class LinkCancelled extends LinkOutcome {
  const LinkCancelled();

  @override
  String toString() => 'LinkCancelled()';
}

/// Something went wrong. The player keeps their guest session and every local
/// row; the UI says so gently and offers to try again.
final class LinkFailed extends LinkOutcome {
  const LinkFailed(this.reason);

  /// A diagnostic code (e.g. Firebase's `network-request-failed`), for
  /// Crashlytics and the dev log — NEVER shown to the player verbatim.
  final String reason;

  @override
  String toString() => 'LinkFailed($reason)';
}

/// The seam the app talks to.
abstract interface class AuthService {
  /// The account signed in right now, or null before [ensureSignedIn] has
  /// resolved one (and on any build where Firebase never initialised).
  AuthAccount? get currentAccount;

  /// Emits on every account change — anonymous sign-in resolving, a link
  /// succeeding, a sign-out returning to a fresh guest.
  Stream<AuthAccount?> watchAccount();

  /// Signs in anonymously if nobody is signed in yet. Idempotent.
  ///
  /// Returns null rather than throwing when it cannot reach Firebase: this is
  /// called from `bootstrap.dart` step 4, which must never be able to block
  /// or crash startup (Ch13). A null here means "playing offline as a
  /// guest", which is a fully supported state, not an error.
  Future<AuthAccount?> ensureSignedIn();

  /// Opens the Google sheet and upgrades the current anonymous account.
  Future<LinkOutcome> linkWithGoogle();

  /// Signs out and immediately signs back in as a FRESH anonymous guest.
  ///
  /// It does NOT delete local data — Ch02's rule, and the reason this returns
  /// the new guest account rather than null: the game must stay playable the
  /// instant sign-out completes, with the same local rows it had a moment
  /// before. Wiping on sign-out is how you turn "I wanted to switch accounts"
  /// into "I lost 40 levels".
  Future<AuthAccount?> signOut();
}

/// Nobody is ever signed in, and nothing throws.
///
/// The binding in tests and on any build where `Firebase.initializeApp`
/// failed — the app runs as a pure local guest, which is exactly the airplane
/// mode behaviour P13's first acceptance criterion asks for.
final class NoopAuthService implements AuthService {
  const NoopAuthService();

  @override
  AuthAccount? get currentAccount => null;

  @override
  Stream<AuthAccount?> watchAccount() => const Stream<AuthAccount?>.empty();

  @override
  Future<AuthAccount?> ensureSignedIn() async => null;

  @override
  Future<LinkOutcome> linkWithGoogle() async =>
      const LinkFailed('auth-unavailable');

  @override
  Future<AuthAccount?> signOut() async => null;
}

/// Overridden in `bootstrap.dart` with the Firebase-backed implementation
/// once step 2 has actually initialised an app.
///
/// Defaults to Noop rather than throwing, for the same reason
/// `uiSettingsStoreProvider` defaults to in-memory: every widget test and the
/// Style Gallery must keep working with no Firebase project registered.
@Riverpod(keepAlive: true)
AuthService authService(Ref ref) => const NoopAuthService();

/// The current account, as the UI watches it.
///
/// Seeded with [AuthService.currentAccount] so a screen built before the
/// first stream event still renders the right thing rather than flashing a
/// "signed out" state it is about to correct.
@Riverpod(keepAlive: true)
Stream<AuthAccount?> currentAccount(Ref ref) {
  final auth = ref.watch(authServiceProvider);
  final seed = auth.currentAccount;
  final changes = auth.watchAccount();
  return seed == null ? changes : changes.startWith(seed);
}

extension _StartWith<T> on Stream<T> {
  Stream<T> startWith(T value) async* {
    yield value;
    yield* this;
  }
}
