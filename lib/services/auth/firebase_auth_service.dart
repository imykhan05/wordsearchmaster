import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:google_sign_in/google_sign_in.dart';

import '../diagnostics/error_reporter.dart';
import 'auth_service.dart';

/// The real [AuthService], over Firebase Auth + Google Sign-In.
///
/// The ONLY file in the app allowed to import `firebase_auth` or
/// `google_sign_in` — the same containment rule `max_ad_gateway.dart` will
/// have for AppLovin and `audio_service.dart` already has for audioplayers
/// (CLAUDE.md → Architecture).
///
/// ---------------------------------------------------------------------------
/// EVERY METHOD SWALLOWS ITS FAILURE
///
/// Not sloppiness — policy. CLAUDE.md: "Wrap every Firebase call in try/catch
/// → Crashlytics non-fatal, never a user-visible error for a
/// background/sync failure", and "Never block gameplay on a network call".
/// A player on a train with no signal must get a fully playable game, so
/// every path below has a defined answer for "the network was not there":
/// [ensureSignedIn] returns null, [linkWithGoogle] returns [LinkFailed], and
/// the game carries on against the local database either way.
// The lint below wants `this._auth`, which Dart rejects outright: a named
// parameter's external name cannot be private. Same carve-out as
// `AppDatabase`'s reporter and `TrustedClock`'s marks.
// ignore_for_file: prefer_initializing_formals
final class FirebaseAuthService implements AuthService {
  FirebaseAuthService({
    required fb.FirebaseAuth auth,
    required ErrorReporter reporter,
    GoogleSignIn? googleSignIn,
    String? serverClientId,
  }) : _auth = auth,
       _reporter = reporter,
       _google = googleSignIn ?? GoogleSignIn.instance,
       _serverClientId = serverClientId;

  final fb.FirebaseAuth _auth;
  final ErrorReporter _reporter;
  final GoogleSignIn _google;

  /// The OAuth web client id from the Firebase console, needed on Android so
  /// the returned id token is minted for THIS Firebase project. Comes from
  /// the flavor's `AppConfig`, because dev/stg/prod are three separate
  /// projects with three separate client ids.
  final String? _serverClientId;

  bool _googleInitialised = false;

  @override
  AuthAccount? get currentAccount => _toAccount(_auth.currentUser);

  @override
  Stream<AuthAccount?> watchAccount() =>
      _auth.authStateChanges().map(_toAccount);

  @override
  Future<AuthAccount?> ensureSignedIn() async {
    final existing = _auth.currentUser;
    if (existing != null) return _toAccount(existing);

    try {
      final credential = await _auth.signInAnonymously();
      return _toAccount(credential.user);
    } catch (error, stackTrace) {
      // Offline on first launch is the ordinary case here, not an incident:
      // the player has simply never had a network since installing. Reported
      // for visibility, then swallowed — bootstrap step 4 continues and the
      // game opens as a local-only guest.
      _reporter.nonFatal(
        error,
        stackTrace: stackTrace,
        context: const {'stage': 'auth.signInAnonymously'},
      );
      return null;
    }
  }

  @override
  Future<LinkOutcome> linkWithGoogle() async {
    final GoogleSignInAccount googleAccount;
    try {
      if (!_googleInitialised) {
        await _google.initialize(serverClientId: _serverClientId);
        _googleInitialised = true;
      }
      googleAccount = await _google.authenticate();
    } on GoogleSignInException catch (error, stackTrace) {
      // Backing out of the sheet is a decision, not a fault. Everything else
      // is worth a report.
      if (error.code == GoogleSignInExceptionCode.canceled) {
        return const LinkCancelled();
      }
      _reporter.nonFatal(
        error,
        stackTrace: stackTrace,
        context: const {'stage': 'auth.googleAuthenticate'},
      );
      return LinkFailed(error.code.name);
    } catch (error, stackTrace) {
      _reporter.nonFatal(
        error,
        stackTrace: stackTrace,
        context: const {'stage': 'auth.googleAuthenticate'},
      );
      return const LinkFailed('google-sign-in-failed');
    }

    final idToken = googleAccount.authentication.idToken;
    if (idToken == null) return const LinkFailed('missing-id-token');
    final credential = fb.GoogleAuthProvider.credential(idToken: idToken);

    final user = _auth.currentUser;
    if (user == null) {
      // No guest to upgrade — sign in directly. Nothing local is at risk,
      // because there is no anonymous session holding it.
      return _signInWith(credential);
    }

    try {
      final linked = await user.linkWithCredential(credential);
      return LinkSucceeded(_toAccount(linked.user)!);
    } on fb.FirebaseAuthException catch (error, stackTrace) {
      // THE CASE Ch02 CARES ABOUT. This Google account already has its own
      // Firebase user, so the anonymous account cannot absorb it. Sign in as
      // that existing user and hand the caller a LinkRequiresMerge — the
      // local rows are untouched at this point and stay that way until
      // `AccountMergeRepository` writes the UNION back.
      if (error.code == 'credential-already-in-use' ||
          error.code == 'email-already-in-use') {
        final existing = error.credential ?? credential;
        return _signInWith(existing, requiresMerge: true);
      }
      _reporter.nonFatal(
        error,
        stackTrace: stackTrace,
        context: {'stage': 'auth.linkWithCredential', 'code': error.code},
      );
      return LinkFailed(error.code);
    } catch (error, stackTrace) {
      _reporter.nonFatal(
        error,
        stackTrace: stackTrace,
        context: const {'stage': 'auth.linkWithCredential'},
      );
      return const LinkFailed('link-failed');
    }
  }

  Future<LinkOutcome> _signInWith(
    fb.AuthCredential credential, {
    bool requiresMerge = false,
  }) async {
    try {
      final result = await _auth.signInWithCredential(credential);
      final account = _toAccount(result.user);
      if (account == null) return const LinkFailed('no-user-after-sign-in');
      return requiresMerge
          ? LinkRequiresMerge(account)
          : LinkSucceeded(account);
    } catch (error, stackTrace) {
      _reporter.nonFatal(
        error,
        stackTrace: stackTrace,
        context: const {'stage': 'auth.signInWithCredential'},
      );
      return const LinkFailed('sign-in-failed');
    }
  }

  @override
  Future<AuthAccount?> signOut() async {
    try {
      await _google.signOut();
    } catch (error, stackTrace) {
      // A Google sign-out that fails must not stop the Firebase one — the
      // player asked to leave the account and has to actually leave it.
      _reporter.nonFatal(
        error,
        stackTrace: stackTrace,
        context: const {'stage': 'auth.googleSignOut'},
      );
    }

    try {
      await _auth.signOut();
    } catch (error, stackTrace) {
      _reporter.nonFatal(
        error,
        stackTrace: stackTrace,
        context: const {'stage': 'auth.signOut'},
      );
    }

    // Straight back to a fresh guest — Ch02: signing out returns to an
    // anonymous session, it does not delete local data. The Drift rows are
    // never touched by this method, by construction: it has no database
    // handle to touch them with.
    return ensureSignedIn();
  }

  static AuthAccount? _toAccount(fb.User? user) => user == null
      ? null
      : AuthAccount(
          uid: user.uid,
          isAnonymous: user.isAnonymous,
          displayName: user.displayName,
          email: user.email,
        );
}
