/// The Firebase-touching half of bootstrap, behind ONE seam (Ch13 / P13).
///
/// ---------------------------------------------------------------------------
/// WHY THIS EXISTS RATHER THAN CALLS INLINE IN `bootstrap.dart`
///
/// P13's first acceptance criterion is that a COLD START IN AIRPLANE MODE
/// works and leaves a playable game. That is a claim about what happens when
/// steps 2–5 of the init sequence all fail, and it is worth proving in a test
/// rather than by inspection — every prompt so far has had one thing that
/// "obviously" degrades gracefully and one that turned out not to.
///
/// `Firebase.initializeApp` cannot run under `flutter_test` (no platform
/// channels, no `google-services.json`), so a bootstrap that called it
/// directly would be untestable by construction. Routing all of it through
/// this interface means `bootstrap_offline_test.dart` can inject a gateway
/// that fails exactly the way a plane does, and assert the app still comes up.
///
/// [NoopFirebaseGateway] is not a test-only convenience either: it is the
/// REAL binding on any build where `flutterfire configure` has not been run
/// (see `app/config/firebase_options.dart`). Unconfigured and offline are
/// deliberately one code path, so the degraded path is exercised every time
/// anyone runs the app locally.
library;

import '../../data/remote/cloud_account_repository.dart';
import '../analytics/analytics_service.dart';
import '../app_check/app_check_gateway.dart';
import '../auth/auth_service.dart';
import '../diagnostics/error_reporter.dart';
import '../remote_config/remote_config.dart';

/// The services a live Firebase app provides, once step 2 has succeeded.
///
/// Every field has a working Noop counterpart, which is what lets bootstrap
/// treat "Firebase came up" and "Firebase did not" as the same shape.
final class FirebaseServices {
  const FirebaseServices({
    required this.reporter,
    required this.appCheck,
    required this.auth,
    required this.analytics,
    required this.remoteConfig,
    required this.cloudAccount,
    required this.fetchRemoteConfig,
  });

  /// Crashlytics-backed once Firebase is up. Replaces the Noop that steps 1–2
  /// had to use, since Crashlytics does not exist until `initializeApp` has
  /// returned.
  final ErrorReporter reporter;

  final AppCheckGateway appCheck;
  final AuthService auth;
  final AnalyticsService analytics;

  /// Reads levers. Already usable before [fetchRemoteConfig] runs — every key
  /// resolves to its shipped default until a fetch lands.
  final RemoteConfig remoteConfig;

  /// Reads another device's account, for the guest→Google merge.
  final CloudAccountRepository cloudAccount;

  /// Step 5, as a callable: fetch + activate, bounded by its own timeout.
  /// Returns whether a fetch actually landed. Never throws.
  final Future<bool> Function() fetchRemoteConfig;
}

/// Brings Firebase up, or reports that it could not.
abstract interface class FirebaseGateway {
  /// Steps 2 of the init sequence: `Firebase.initializeApp`, plus building
  /// every service that depends on it.
  ///
  /// Returns null when Firebase is unavailable — unconfigured credentials, no
  /// network on a cold first launch, a missing `google-services.json`. NEVER
  /// throws: a null is the supported answer, and bootstrap carries on with
  /// Noop bindings and a fully playable local game.
  Future<FirebaseServices?> initialize();
}

/// Firebase is not available. Always returns null.
///
/// The binding when `AppConfig.firebaseOptions` is null, and in tests.
final class NoopFirebaseGateway implements FirebaseGateway {
  const NoopFirebaseGateway();

  @override
  Future<FirebaseServices?> initialize() async => null;
}
