import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:drift_flutter/drift_flutter.dart';

import '../data/content/content_repository.dart';
import '../data/local/app_database.dart';
import '../data/repositories/streak_repository.dart';
import '../services/audio/audio_service.dart';
import '../services/diagnostics/error_reporter.dart';
import '../services/time/trusted_clock.dart';
import '../services/settings/ui_settings_store.dart';
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

      // 5b. UI settings. Must resolve BEFORE the first frame: the very first
      // screen needs a locale and a text direction, and both come from the
      // stored language choice (P08).
      var settings = InMemoryUiSettingsStore() as UiSettingsStore;
      await _step(config, 'settings.load', () async {
        settings = await PrefsUiSettingsStore.open();
      });

      // 6. Local DB open + migration.
      AppDatabase? database;
      await _step(config, 'localDb.openAndMigrate', () async {
        final opened = AppDatabase(driftDatabase(name: 'wsm'));
        // Drift opens lazily, so this first query is what actually runs
        // onCreate/onUpgrade/beforeOpen. Doing it here means a failed
        // migration is logged as a bootstrap step rather than surfacing as a
        // mysterious error on the first gameplay read.
        await opened.ensureInstallId();
        database = opened;
      });

      // 7. Content load — the word packs and level defs are needed as soon
      // as the home/journey screen shows a single level card, so unlike
      // progressRepository (lazy, watched only once a game actually starts)
      // this is loaded eagerly here rather than left for its provider's own
      // build to do on first watch.
      ContentRepository? content;
      await _step(config, 'content.load', () async {
        content = await ContentRepository.load();
      });

      // 7a. Trusted clock + streak settle (P11).
      //
      // The rollback guard's high-water mark lives in `kv_settings`, so the
      // clock has to be built over the OPENED database — the default provider
      // keeps its mark in memory, which would silently lose the guard across
      // launches (exactly when a wound-back clock would be used).
      //
      // Settling the streak here, rather than waiting for the next
      // completion, is what makes "a freeze is consumed on a missed day"
      // durable for a player who opens the app and does not finish a level:
      // `StreakRules.settle` is idempotent, and `settleAndPersist` writes
      // nothing when nothing changed, so this cannot churn the row on resume.
      TrustedClock? clock;
      await _step(config, 'time.trustedClock', () async {
        if (database case final AppDatabase opened) {
          final integrity = await opened.integrity();
          final built = TrustedClock(
            marks: DriftDayHighWaterMarkStore(
              database: opened,
              integrity: integrity,
              reporter: const NoopErrorReporter(),
            ),
            // TODO(P13): a real ServerTimeSource once Firebase is wired.
          );
          clock = built;

          final streaks = StreakRepository(
            database: opened,
            integrity: integrity,
            reporter: const NoopErrorReporter(),
          );
          await streaks.settleAndPersist(await built.today());
        }
      });

      // 7b. Audio preload (Ch03 juice pass). "First-play latency must be
      // imperceptible" means the decode cost has to be paid before the
      // first frame that could trigger a sound — unlike step 8, this stays
      // a normal blocking step rather than deferred, because the clips are
      // tiny, bundled assets with no network involved.
      AudioService? audioService;
      await _step(config, 'audio.preload', () async {
        final service = AudioPlayersAudioService();
        await service.preload();
        audioService = service;
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
          overrides: [
            appConfigProvider.overrideWithValue(config),
            uiSettingsStoreProvider.overrideWithValue(settings),
            // Absent only if step 6 threw. The provider then opens its own
            // handle lazily — which will likely fail the same way, but fails
            // at the point of use instead of taking startup down with it.
            if (database case final AppDatabase opened)
              appDatabaseProvider.overrideWithValue(opened),
            // Absent only if step 7b threw, in which case the default
            // NoopAudioService binding stands — silent, never a crash.
            if (audioService case final AudioService loaded)
              audioServiceProvider.overrideWithValue(loaded),
            // Absent only if step 7 threw. Unlike audio, there is no safe
            // Noop content pack — the provider then falls back to its own
            // default body (ContentRepository.load() again), surfacing the
            // same failure as this provider's error state rather than a
            // silent empty game (CLAUDE.md → never a user-visible crash, but
            // also never a game that pretends it has content when it doesn't).
            if (content case final ContentRepository loaded)
              contentRepositoryProvider.overrideWith((ref) => loaded),
            // Absent only if step 7a threw (or the database never opened), in
            // which case the default in-memory-mark clock stands: the app
            // still knows what day it is, only the anti-rollback floor is
            // lost. Degrading the guard beats refusing to answer.
            if (clock case final TrustedClock resolved)
              trustedClockProvider.overrideWithValue(resolved),
          ],
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
