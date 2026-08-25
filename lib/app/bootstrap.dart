import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config/app_config.dart';
import 'provider_observer.dart';

/// The documented app init order (Production Bible Ch13 / P13). Every
/// numbered step below is a stub until its owning prompt lands — see the
/// TODO on each. Steps 5–8 must never be able to block or crash startup:
/// on failure they log and the app continues with defaults.
///
/// 1. Flutter binding + error handlers → Crashlytics
/// 2. Firebase.initializeApp
/// 3. App Check activate
/// 4. Anonymous auth
/// 5. Remote Config fetch (3s timeout, hardcoded defaults as fallback)
/// 6. Local DB open + migration
/// 7. Content load
/// 8. Ads init (deferred, never blocks first frame)
/// 9. runApp
Future<void> bootstrap(
  AppConfig config,
  FutureOr<Widget> Function() appBuilder,
) async {
  await runZonedGuarded<Future<void>>(
    () async {
      // 1. Flutter binding + error handlers → Crashlytics
      WidgetsFlutterBinding.ensureInitialized();
      FlutterError.onError = (details) {
        _log(config, 'FlutterError: ${details.exceptionAsString()}');
        // TODO(P19): FirebaseCrashlytics.instance.recordFlutterFatalError(details)
      };

      // 2. Firebase.initializeApp
      await _step(config, 'firebase.initializeApp', () async {
        // TODO(P13): await Firebase.initializeApp(options: config.firebaseOptions);
      });

      // 3. App Check activate — must run before any other Firebase call.
      await _step(config, 'app_check.activate', () async {
        // TODO(P13): Play Integrity provider on Android, debug provider on dev/stg.
      });

      // 4. Anonymous auth — silent, never blocks the player.
      await _step(config, 'auth.signInAnonymously', () async {
        // TODO(P13): guest-first sign-in; see CLAUDE.md guest→Google merge rule.
      });

      // 5. Remote Config fetch — 3s timeout, hardcoded defaults as fallback.
      await _step(config, 'remoteConfig.fetch', () async {
        // TODO(P20): RemoteConfigKeys carries the sane hardcoded defaults.
      });

      // 6. Local DB open + migration.
      await _step(config, 'localDb.openAndMigrate', () async {
        // TODO(P08): open the Drift DB, run migrations from schema v1.
      });

      // 7. Content load.
      await _step(config, 'content.load', () async {
        // TODO(P10): load + cache words/levels JSON from assets/content/.
      });

      // 8. Ads init — deferred, must never block the first frame.
      unawaited(
        _step(config, 'ads.init', () async {
          // TODO(P18): init AdGateway behind the interface; NoopAdGateway if
          // ads_enabled is false or the SDK fails to init.
        }),
      );

      // 9. runApp
      final observers = config.flavor == Flavor.dev
          ? const [AppProviderObserver()]
          : const <ProviderObserver>[];
      runApp(
        ProviderScope(
          overrides: [appConfigProvider.overrideWithValue(config)],
          observers: observers,
          child: await appBuilder(),
        ),
      );
    },
    (error, stackTrace) {
      _log(config, 'Uncaught zone error: $error');
      // TODO(P19): FirebaseCrashlytics.instance.recordError(error, stackTrace, fatal: true)
    },
  );
}

Future<void> _step(
  AppConfig config,
  String name,
  Future<void> Function() run,
) async {
  final stopwatch = Stopwatch()..start();
  try {
    await run();
    _log(config, 'bootstrap: $name ok (${stopwatch.elapsedMilliseconds}ms)');
  } catch (error) {
    // A background/init step failing must never crash startup or surface to
    // the player — log and continue with defaults (CLAUDE.md → Never do).
    _log(config, 'bootstrap: $name failed, continuing with defaults: $error');
  }
}

void _log(AppConfig config, String message) {
  if (config.logLevel == AppLogLevel.debug) {
    debugPrint('[${config.flavor.name}] $message');
  }
}
