import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/app/bootstrap.dart';
import 'package:word_search_master/app/config/app_config.dart';
import 'package:word_search_master/domain/text/language.dart';
import 'package:word_search_master/services/analytics/analytics_service.dart';
import 'package:word_search_master/services/audio/audio_service.dart';
import 'package:word_search_master/services/auth/auth_service.dart';
import 'package:word_search_master/services/diagnostics/error_reporter.dart';
import 'package:word_search_master/services/firebase/firebase_gateway.dart';
import 'package:word_search_master/services/remote_config/remote_config.dart';

import '../support/fake_content.dart';

/// P13 ACCEPTANCE CRITERION 1: "Airplane mode mein cold start theek chalta
/// hai aur game khelne deta hai" — a cold start with no network must reach a
/// playable game.
///
/// Bootstrap steps 2–5 all touch the network and all of them fail on a plane.
/// This file drives `initializeServices` with each of those failure shapes and
/// asserts the same two things every time: it COMPLETES, and what it returns
/// is playable.
///
/// Why this is a real test and not a smoke test: the failure being guarded
/// against is a bootstrap that HANGS (an un-timed-out fetch) or THROWS (an
/// unhandled Firebase exception), and both would show up here as a timeout or
/// an error rather than as a passing assertion.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// A gateway that fails the way a plane does: Firebase simply is not there.
  /// This is also the REAL binding on an unconfigured checkout — see
  /// `app/config/firebase_options.dart` for why those are one code path.
  const offline = NoopFirebaseGateway();

  /// The nastier shape: a gateway that throws rather than returning null.
  /// A `Firebase.initializeApp` that raises must be caught by bootstrap's own
  /// `_step`, not propagate out of `initializeServices`.
  final throwing = _ThrowingFirebaseGateway();

  Future<BootstrapServices> boot({FirebaseGateway? gateway}) =>
      initializeServices(
        AppConfig.dev(),
        firebase: gateway ?? offline,
        // In-memory rather than `drift_flutter`, which needs a platform
        // channel that does not exist under `flutter_test`.
        openDatabase: NativeDatabase.memory,
        // `ContentRepository.load`'s default reads `rootBundle`, whose asset
        // reads never complete under fake async (the P11/P12 lesson).
        loadContent: buildTestContentRepository,
        // The real preload needs platform channels and, on Linux, GStreamer.
        loadAudio: () async => const NoopAudioService(),
      );

  group('a cold start with no Firebase', () {
    test('completes rather than hanging or throwing', () async {
      final services = await boot();

      expect(services.firebaseAvailable, isFalse);
    });

    test('THE CRITERION: the game is playable', () async {
      final services = await boot();

      expect(
        services.isPlayable,
        isTrue,
        reason: 'local DB + content are what gameplay actually needs',
      );
      expect(services.database, isNotNull);
      expect(services.content, isNotNull);
    });

    test('content really loaded — level 1 has a word list to play', () async {
      final services = await boot();
      final content = services.content!;

      // The narrowest end-to-end statement of "playable": level 1 resolves to
      // a real definition and that definition yields real words to find.
      final level = content.getLevel(1, Language.english);
      expect(content.getWordsForLevel(level), isNotEmpty);
    });

    test(
      'every Firebase-backed service falls back to a working Noop',
      () async {
        final services = await boot();

        // Each of these has to be SAFE TO CALL, not merely non-null: gameplay
        // fires analytics and reads levers on paths that do not check whether
        // Firebase came up.
        expect(services.auth, isA<NoopAuthService>());
        expect(services.analytics, isA<NoopAnalyticsService>());
        expect(services.remoteConfig, isA<DefaultRemoteConfig>());
        expect(services.reporter, isA<NoopErrorReporter>());

        expect(await services.auth.ensureSignedIn(), isNull);
        services.analytics.logEvent('smoke', const {'a': 1});
        services.reporter.nonFatal(StateError('smoke'));
      },
    );

    test('levers still resolve — to their shipped defaults', () async {
      final services = await boot();

      expect(services.remoteConfigFetched, isFalse);
      expect(
        services.remoteConfig.getInt(RemoteConfigKeys.hintCostCoins),
        RemoteConfigKeys.hintCostCoins.defaultValue,
      );
      expect(
        services.remoteConfig.getInt(RemoteConfigKeys.ddaStuckSeconds),
        25,
      );
    });

    test('the trusted clock still knows what day it is', () async {
      // Ch12 requires the Daily playable with the radio off, which needs a
      // day boundary resolved without a server.
      final services = await boot();

      expect(services.clock, isNotNull);
      expect(await services.clock!.today(), isNotNull);
    });

    test('settings resolved, so the first frame has a locale', () async {
      final services = await boot();

      expect(services.settings, isNotNull);
      // Reading these must not throw — the language screen needs them before
      // anything else renders.
      expect(services.settings.soundEnabled, isA<bool>());
      expect(services.settings.selectedLanguage, isNull);
    });
  });

  group('a Firebase gateway that THROWS is caught, not propagated', () {
    test('initializeServices still completes and is still playable', () async {
      final services = await boot(gateway: throwing);

      expect(throwing.wasCalled, isTrue);
      expect(services.firebaseAvailable, isFalse);
      expect(services.isPlayable, isTrue);
    });
  });

  group('a broken local database is survivable too', () {
    test('bootstrap completes, and says the game is not playable', () async {
      // Not an acceptance criterion — but the same `_step` guard covers it,
      // and a bootstrap that threw here would take startup down. The right
      // behaviour is to come back with `isPlayable: false` so the caller can
      // decide, rather than to crash before anything can decide anything.
      final services = await initializeServices(
        AppConfig.dev(),
        firebase: offline,
        openDatabase: () => throw StateError('disk full'),
        loadContent: buildTestContentRepository,
        loadAudio: () async => const NoopAudioService(),
      );

      expect(services.database, isNull);
      expect(services.isPlayable, isFalse);
      expect(
        services.content,
        isNotNull,
        reason: 'one failed step must not cascade into the next',
      );
    });
  });
}

final class _ThrowingFirebaseGateway implements FirebaseGateway {
  bool wasCalled = false;

  @override
  Future<FirebaseServices?> initialize() async {
    wasCalled = true;
    throw StateError('no network');
  }
}
