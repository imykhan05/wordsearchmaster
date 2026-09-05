import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart' as rc;
import 'package:flutter/foundation.dart';

import '../../app/config/app_config.dart';
import '../../data/remote/firestore_account_repository.dart';
import '../../data/remote/firestore_friends_api.dart';
import '../../data/remote/firestore_leaderboard_api.dart';
import '../../data/remote/firestore_name_report_api.dart';
import '../../data/remote/firestore_notification_registration_api.dart';
import '../../data/remote/firestore_user_stats_api.dart';
import '../analytics/firebase_analytics_service.dart';
import '../app_check/firebase_app_check_gateway.dart';
import '../auth/firebase_auth_service.dart';
import '../diagnostics/crashlytics_error_reporter.dart';
import '../diagnostics/error_reporter.dart';
import '../notifications/firebase_notification_service.dart';
import '../remote_config/firebase_remote_config.dart';
import 'firebase_gateway.dart';

/// The real [FirebaseGateway]. The only file that calls
/// `Firebase.initializeApp`.
///
/// Everything it builds is one of the Firebase-backed implementations of an
/// interface the app already had a Noop for, so a failure here is never a
/// missing capability — only a quieter one.
final class LiveFirebaseGateway implements FirebaseGateway {
  const LiveFirebaseGateway(this._config);

  final AppConfig _config;

  @override
  Future<FirebaseServices?> initialize() async {
    final options = _config.firebaseOptions;
    // Unconfigured is not a failure — see `app/config/firebase_options.dart`.
    // Returning null here is what puts a freshly-cloned checkout into the
    // same local-only mode airplane mode uses.
    if (options == null) return null;

    try {
      await Firebase.initializeApp(options: options);
    } catch (error) {
      // A duplicate-app error means a hot restart re-entered bootstrap; the
      // existing app is fine to keep using. Anything else genuinely failed.
      if (error is! FirebaseException || error.code != 'duplicate-app') {
        return null;
      }
    }

    try {
      final crashlytics = FirebaseCrashlytics.instance;
      final reporter = CrashlyticsErrorReporter(crashlytics);
      final remoteConfig = rc.FirebaseRemoteConfig.instance;
      final firestore = FirebaseFirestore.instance;
      final functions = FirebaseFunctions.instanceFor(
        region: AppConfig.functionsRegion,
      );

      return FirebaseServices(
        reporter: reporter,
        appCheck: FirebaseAppCheckGateway(
          appCheck: FirebaseAppCheck.instance,
          reporter: reporter,
        ),
        auth: FirebaseAuthService(
          auth: fb.FirebaseAuth.instance,
          reporter: reporter,
          serverClientId: _config.googleServerClientId,
        ),
        analytics: FirebaseAnalyticsService(
          analytics: FirebaseAnalytics.instance,
          reporter: reporter,
        ),
        remoteConfig: FirebaseRemoteConfigAdapter(remoteConfig),
        cloudAccount: FirestoreAccountRepository(
          firestore: firestore,
          reporter: reporter,
        ),
        fetchRemoteConfig: () =>
            FirebaseRemoteConfigAdapter.activateWithDefaults(
              remoteConfig,
              reporter: reporter,
            ),
        userStats: FirestoreUserStatsApi(
          firestore: firestore,
          reporter: reporter,
        ),
        leaderboard: FirestoreLeaderboardApi(
          firestore: firestore,
          reporter: reporter,
        ),
        friends: FirestoreFriendsApi(
          firestore: firestore,
          functions: functions,
          reporter: reporter,
        ),
        nameReport: FirestoreNameReportApi(
          firestore: firestore,
          reporter: reporter,
        ),
        notifications: FirebaseNotificationService(
          messaging: FirebaseMessaging.instance,
          reporter: reporter,
        ),
        notificationRegistration: FirestoreNotificationRegistrationApi(
          firestore: firestore,
          reporter: reporter,
        ),
      );
    } catch (_) {
      // `.instance` on any of these can throw if the platform channel is not
      // registered (a desktop build, a test host). Degrade to Noop rather
      // than taking startup down.
      return null;
    }
  }
}

/// Wires Flutter's two global error handlers into Crashlytics — step 1 of the
/// init sequence.
///
/// Separate from [LiveFirebaseGateway] because it must run BEFORE
/// `Firebase.initializeApp`: an exception thrown during initialisation itself
/// is exactly the one worth catching, and a handler installed afterwards
/// would miss it. Crashlytics buffers to disk and uploads once it is up, so
/// installing the handler early loses nothing.
void installCrashlyticsHandlers({required ErrorReporter fallback}) {
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    previousOnError?.call(details);
    try {
      FirebaseCrashlytics.instance.recordFlutterFatalError(details);
    } catch (_) {
      // Firebase not up yet (or never will be) — fall back to the reporter
      // bootstrap already has, which is a Noop that at least does not throw.
      fallback.nonFatal(
        details.exception,
        stackTrace: details.stack,
        context: const {'stage': 'flutterError'},
      );
    }
  };
}
