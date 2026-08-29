import 'package:firebase_app_check/firebase_app_check.dart';

import '../diagnostics/error_reporter.dart';
import 'app_check_gateway.dart';

/// The real [AppCheckGateway]. The only file allowed to import
/// `firebase_app_check`.
///
/// See `app_check_gateway.dart`'s library header for the provider policy and
/// for the two-week monitor-mode rule — this file only performs the call that
/// header decides on.
// The lint below wants `this._appCheck`, which Dart rejects outright: a named
// parameter's external name cannot be private. Same situation as
// `AppDatabase`'s reporter and `TrustedClock`'s marks.
// ignore_for_file: prefer_initializing_formals
final class FirebaseAppCheckGateway implements AppCheckGateway {
  const FirebaseAppCheckGateway({
    required FirebaseAppCheck appCheck,
    required ErrorReporter reporter,
  }) : _appCheck = appCheck,
       _reporter = reporter;

  final FirebaseAppCheck _appCheck;
  final ErrorReporter _reporter;

  @override
  Future<void> activate(AppCheckPolicy policy) async {
    try {
      await _appCheck.activate(
        providerAndroid: switch (policy) {
          AppCheckPolicy.playIntegrity => AndroidPlayIntegrityProvider(),
          AppCheckPolicy.debug => AndroidDebugProvider(),
        },
        providerApple: switch (policy) {
          // App Attest is iOS's equivalent of Play Integrity. The app is
          // Android-first (Ch01), but activate() takes both and a wrong value
          // here would be a live bug the day an iOS build happens.
          AppCheckPolicy.playIntegrity => AppleAppAttestProvider(),
          AppCheckPolicy.debug => AppleDebugProvider(),
        },
      );
    } catch (error, stackTrace) {
      // App Check is a defence, not a dependency. If activation fails the app
      // still has to start — with enforcement in monitor mode (the documented
      // launch posture) the only consequence is unattested requests showing
      // up in the console chart, which is information rather than an outage.
      _reporter.nonFatal(
        error,
        stackTrace: stackTrace,
        context: {'stage': 'appCheck.activate', 'policy': policy.name},
      );
    }
  }
}
