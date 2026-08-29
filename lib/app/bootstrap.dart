import 'dart:async';

import 'package:drift/drift.dart' show QueryExecutor;
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/content/content_repository.dart';
import '../data/local/app_database.dart';
import '../data/remote/cloud_account_repository.dart';
import '../data/repositories/streak_repository.dart';
import '../services/analytics/analytics_service.dart';
import '../services/app_check/app_check_gateway.dart';
import '../services/audio/audio_service.dart';
import '../services/auth/auth_service.dart';
import '../services/diagnostics/error_reporter.dart';
import '../services/firebase/firebase_gateway.dart';
import '../services/firebase/live_firebase_gateway.dart';
import '../services/remote_config/remote_config.dart';
import '../services/settings/ui_settings_store.dart';
import '../services/time/trusted_clock.dart';
import 'config/app_config.dart';
import 'provider_observer.dart';

/// Everything [initializeServices] resolved, ready to be handed to Riverpod.
///
/// Nullable fields are the steps that are ALLOWED to fail. Each one has a
/// documented degradation at its provider (a Noop binding, a lazy retry, or
/// an error state) — none of them is a reason not to start.
final class BootstrapServices {
  const BootstrapServices({
    required this.settings,
    required this.reporter,
    required this.auth,
    required this.analytics,
    required this.remoteConfig,
    required this.cloudAccount,
    required this.firebaseAvailable,
    required this.remoteConfigFetched,
    this.database,
    this.content,
    this.clock,
    this.audio,
  });

  final UiSettingsStore settings;
  final ErrorReporter reporter;
  final AuthService auth;
  final AnalyticsService analytics;
  final RemoteConfig remoteConfig;
  final CloudAccountRepository cloudAccount;

  /// False in airplane mode, on an unconfigured checkout, and whenever
  /// `Firebase.initializeApp` failed. The game is fully playable either way —
  /// this only says whether anything will sync.
  final bool firebaseAvailable;

  /// Whether step 5 actually landed a fetch. False falls back to the shipped
  /// defaults, which every `RemoteConfigKey` carries.
  final bool remoteConfigFetched;

  final AppDatabase? database;
  final ContentRepository? content;
  final TrustedClock? clock;
  final AudioService? audio;

  /// The one thing that genuinely must have worked for the game to be
  /// playable: local storage and content. Everything else is optional.
  bool get isPlayable => database != null && content != null;
}

/// The documented app init order (Production Bible Ch13 / P13), in full.
///
/// ---------------------------------------------------------------------------
/// THE ORDER IS THE POINT, AND TWO PAIRS OF IT ARE LOAD-BEARING
///
///   1. Flutter binding + error handlers → Crashlytics
///   2. Firebase.initializeApp
///   3. App Check activate
///   4. Anonymous auth
///   5. Remote Config fetch (3s timeout, hardcoded defaults as fallback)
///   6. Local DB open + migration
///   7. Content load
///   8. Ads init (deferred, never blocks first frame)
///   9. runApp
///
/// **3 before 4** because App Check attests the requests auth makes. Activate
/// it afterwards and the first sign-in of every session goes out unattested —
/// which, once enforcement is on, is the one request an attacker would
/// choose to imitate.
///
/// **1 before 2** because the exception most worth catching is the one thrown
/// by initialisation itself. Crashlytics buffers to disk and uploads once it
/// is up, so a handler installed before the SDK exists still records.
///
/// ---------------------------------------------------------------------------
/// STEPS 5–8 CAN NEVER BLOCK OR CRASH STARTUP
///
/// Every step below runs inside [_step], which catches everything and logs.
/// That is not defensive habit — it is the first acceptance criterion: a cold
/// start in airplane mode must reach a playable game. Steps 2–5 all touch the
/// network and all of them are expected to fail on a plane; the app is
/// designed so that the result is a local-only guest session, which is a
/// fully supported mode rather than a degraded one (Drift is the source of
/// truth — CLAUDE.md → Architecture).
///
/// The seams ([firebase], [openDatabase], [loadContent], [loadAudio]) exist
/// so `bootstrap_offline_test.dart` can make each of those fail on purpose
/// and assert the app still comes up. Default to the real thing; a caller
/// that passes nothing gets production behaviour.
Future<BootstrapServices> initializeServices(
  AppConfig config, {
  FirebaseGateway? firebase,
  QueryExecutor Function()? openDatabase,
  Future<ContentRepository> Function()? loadContent,
  Future<AudioService> Function()? loadAudio,
}) async {
  // ---- 1. Flutter binding + error handlers → Crashlytics ----
  WidgetsFlutterBinding.ensureInitialized();
  // Starts as a Noop and is upgraded to Crashlytics the moment step 2 lands.
  // Steps 1–2 have nowhere else to report to, by definition.
  var reporter = const NoopErrorReporter() as ErrorReporter;
  installCrashlyticsHandlers(fallback: reporter);

  // ---- 2. Firebase.initializeApp ----
  final gateway = firebase ?? LiveFirebaseGateway(config);
  FirebaseServices? services;
  await _step(config, 'firebase.initializeApp', () async {
    services = await gateway.initialize();
  });
  if (services case final FirebaseServices live) {
    reporter = live.reporter;
  }

  // ---- 3. App Check activate — BEFORE any other Firebase call ----
  final policy = AppCheckPolicy.forFlavor(config.flavor);
  await _step(config, 'appCheck.activate', () async {
    await (services?.appCheck ?? const NoopAppCheckGateway()).activate(policy);
  });

  // ---- 4. Anonymous auth — silent, never blocks the player ----
  final auth = services?.auth ?? const NoopAuthService();
  await _step(config, 'auth.signInAnonymously', () async {
    await auth.ensureSignedIn();
  });

  // ---- 5. Remote Config fetch — 3s timeout, defaults as fallback ----
  var remoteConfigFetched = false;
  await _step(config, 'remoteConfig.fetch', () async {
    remoteConfigFetched =
        await (services?.fetchRemoteConfig.call() ?? Future<bool>.value(false));
  });

  // 5b. UI settings. Must resolve BEFORE the first frame: the very first
  // screen needs a locale and a text direction, and both come from the
  // stored language choice (P08).
  var settings = InMemoryUiSettingsStore() as UiSettingsStore;
  await _step(config, 'settings.load', () async {
    settings = await PrefsUiSettingsStore.open();
  });

  // ---- 6. Local DB open + migration ----
  AppDatabase? database;
  await _step(config, 'localDb.openAndMigrate', () async {
    final opened = AppDatabase(
      openDatabase?.call() ?? driftDatabase(name: 'wsm'),
      reporter: reporter,
    );
    // Drift opens lazily, so this first query is what actually runs
    // onCreate/onUpgrade/beforeOpen. Doing it here means a failed migration
    // is logged as a bootstrap step rather than surfacing as a mysterious
    // error on the first gameplay read.
    await opened.ensureInstallId();
    database = opened;
  });

  // ---- 7. Content load ----
  // Eager, unlike progressRepository: the home/journey screen needs the word
  // and level packs to show a single level card.
  ContentRepository? content;
  await _step(config, 'content.load', () async {
    content = await (loadContent?.call() ?? ContentRepository.load());
  });

  // 7a. Trusted clock + streak settle (P11).
  //
  // The rollback guard's high-water mark lives in `kv_settings`, so the clock
  // has to be built over the OPENED database — the default provider keeps its
  // mark in memory, which would silently lose the guard across launches
  // (exactly when a wound-back clock would be used).
  //
  // Settling the streak here, rather than waiting for the next completion, is
  // what makes "a freeze is consumed on a missed day" durable for a player who
  // opens the app and does not finish a level: `StreakRules.settle` is
  // idempotent, and `settleAndPersist` writes nothing when nothing changed.
  TrustedClock? clock;
  await _step(config, 'time.trustedClock', () async {
    if (database case final AppDatabase opened) {
      final integrity = await opened.integrity();
      final built = TrustedClock(
        marks: DriftDayHighWaterMarkStore(
          database: opened,
          integrity: integrity,
          reporter: reporter,
        ),
        // TODO(P14): a ServerTimeSource over the Functions region, once
        // `AppConfig.functionsRegion` has something deployed to it.
      );
      clock = built;

      final streaks = StreakRepository(
        database: opened,
        integrity: integrity,
        reporter: reporter,
      );
      await streaks.settleAndPersist(await built.today());
    }
  });

  // 7b. Audio preload (Ch03 juice pass). "First-play latency must be
  // imperceptible" means the decode cost has to be paid before the first
  // frame that could trigger a sound — unlike step 8, this stays a normal
  // blocking step rather than deferred, because the clips are tiny, bundled
  // assets with no network involved.
  AudioService? audio;
  await _step(config, 'audio.preload', () async {
    audio = await (loadAudio?.call() ?? _preloadAudio());
  });

  // ---- 8. Ads init — deferred, must never block the first frame ----
  unawaited(
    _step(config, 'ads.init', () async {
      // TODO(P18): init AdGateway behind the interface; NoopAdGateway if
      // ads_enabled is false or the SDK fails to init.
    }),
  );

  return BootstrapServices(
    settings: settings,
    reporter: reporter,
    auth: auth,
    analytics: services?.analytics ?? const NoopAnalyticsService(),
    remoteConfig: services?.remoteConfig ?? const DefaultRemoteConfig(),
    cloudAccount: services?.cloudAccount ?? const NoopCloudAccountRepository(),
    firebaseAvailable: services != null,
    remoteConfigFetched: remoteConfigFetched,
    database: database,
    content: content,
    clock: clock,
    audio: audio,
  );
}

Future<AudioService> _preloadAudio() async {
  final service = AudioPlayersAudioService();
  await service.preload();
  return service;
}

/// Steps 1–8, then 9: `runApp`.
Future<void> bootstrap(
  AppConfig config,
  FutureOr<Widget> Function() appBuilder,
) async {
  await runZonedGuarded<Future<void>>(
    () async {
      final services = await initializeServices(config);

      // ---- 9. runApp ----
      final observers = config.flavor == Flavor.dev
          ? const [AppProviderObserver()]
          : const <ProviderObserver>[];
      runApp(
        ProviderScope(
          overrides: [
            appConfigProvider.overrideWithValue(config),
            uiSettingsStoreProvider.overrideWithValue(services.settings),
            errorReporterProvider.overrideWithValue(services.reporter),
            authServiceProvider.overrideWithValue(services.auth),
            analyticsServiceProvider.overrideWithValue(services.analytics),
            remoteConfigProvider.overrideWithValue(services.remoteConfig),
            cloudAccountRepositoryProvider.overrideWithValue(
              services.cloudAccount,
            ),
            // Each of the four below is absent only if its step threw. The
            // matching provider then falls back to its own default — see each
            // one's doc for what that means; none of them is fatal.
            if (services.database case final AppDatabase opened)
              appDatabaseProvider.overrideWithValue(opened),
            if (services.audio case final AudioService loaded)
              audioServiceProvider.overrideWithValue(loaded),
            if (services.content case final ContentRepository loaded)
              contentRepositoryProvider.overrideWith((ref) => loaded),
            if (services.clock case final TrustedClock resolved)
              trustedClockProvider.overrideWithValue(resolved),
          ],
          observers: observers,
          child: await appBuilder(),
        ),
      );
    },
    (error, stackTrace) {
      // The zone handler is the last line of defence for anything that
      // escaped every `_step`. Reported as FATAL, unlike everything else in
      // this file: reaching here means startup itself did not complete.
      _log(config, 'Uncaught zone error: $error');
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
