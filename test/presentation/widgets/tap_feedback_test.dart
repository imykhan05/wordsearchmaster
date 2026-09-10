import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:word_search_master/app/app.dart';
import 'package:word_search_master/app/app_route.dart';
import 'package:word_search_master/app/config/app_config.dart';
import 'package:word_search_master/data/content/content_repository.dart';
import 'package:word_search_master/data/local/app_database.dart';
import 'package:word_search_master/l10n/app_localizations.dart';
import 'package:word_search_master/presentation/widgets/tap_feedback.dart';
import 'package:word_search_master/services/audio/audio_service.dart';
import 'package:word_search_master/services/haptics/haptics_service.dart';
import 'package:word_search_master/services/settings/ui_settings_store.dart';

import '../../support/fake_content.dart';
import '../../support/fake_meta.dart';
import '../../support/local_db.dart';
import '../../support/recording_services.dart';

/// Ch03's `button_tap`, and the gaps a real device found in it.
///
/// P09 wired the click inline at each call site and by the time the build
/// reached a phone, most controls were silent — the player named the AppBar
/// back arrow and "Continue with Google" specifically. The cases below pin
/// the two they named plus the shape of the fix, so the same gap cannot open
/// again unnoticed in exactly those places.
void main() {
  late RecordingAudioService audio;
  late RecordingHapticsService haptics;

  setUp(() {
    audio = RecordingAudioService();
    haptics = RecordingHapticsService();
  });

  group('the extension itself', () {
    testWidgets('one call plays the click AND fires the tick', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            audioServiceProvider.overrideWithValue(audio),
            hapticsServiceProvider.overrideWithValue(haptics),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: ref.tapFeedback,
                child: const Text('press me'),
              ),
            ),
          ),
        ),
      );

      expect(audio.allCalls, isEmpty);
      expect(haptics.allCalls, isEmpty);

      await tester.tap(find.text('press me'));
      await tester.pump();

      // BOTH halves, from ONE call — the pair is what P09's inline version
      // kept getting half right.
      expect(audio.allCalls, ['buttonTap']);
      expect(haptics.allCalls, ['buttonTap']);
    });
  });

  group('the controls the player reported as silent', () {
    /// The full app, so the assertions run against the real router, the real
    /// screens and the real handlers — a screen pumped in isolation would let
    /// a back arrow wired to nothing still pass.
    Future<void> pumpApp(WidgetTester tester) async {
      final content = await buildTestContentRepository();
      final testDb = await openMemoryDatabase();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appConfigProvider.overrideWithValue(AppConfig.dev()),
            appDatabaseProvider.overrideWithValue(testDb.database),
            contentRepositoryProvider.overrideWith((ref) => content),
            uiSettingsStoreProvider.overrideWithValue(
              InMemoryUiSettingsStore(),
            ),
            audioServiceProvider.overrideWithValue(audio),
            hapticsServiceProvider.overrideWithValue(haptics),
            ...fakeMetaOverrides(),
          ],
          child: const WordSearchMasterApp(),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> goTo(WidgetTester tester, String location) async {
      GoRouter.of(tester.element(find.byType(Navigator).first)).go(location);
      await tester.pumpAndSettle();
    }

    testWidgets('the AppBar back arrow clicks on every .go()-reached screen', (
      tester,
    ) async {
      await pumpApp(tester);

      // Every one of these is reached with `.go()`, so its arrow is a
      // `BackButton(onPressed: goHome)` rather than a Navigator pop — the
      // exact shape that shipped silent.
      final locations = <String>[
        const JourneyRoute().location,
        const DailyRoute().location,
        const ProfileRoute().location,
        const SettingsRoute().location,
        const LeaderboardRoute().location,
      ];

      for (final location in locations) {
        await goTo(tester, location);
        audio.allCalls.clear();
        haptics.allCalls.clear();

        final back = find.byType(BackButton);
        expect(back, findsOneWidget, reason: 'no back arrow on $location');
        await tester.tap(back);
        await tester.pumpAndSettle();

        expect(audio.allCalls, [
          'buttonTap',
        ], reason: 'the back arrow on $location played nothing');
        expect(haptics.allCalls, ['buttonTap'], reason: location);
      }
    });

    testWidgets('"Continue with Google" clicks', (tester) async {
      await pumpApp(tester);
      await goTo(tester, const ProfileRoute().location);

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final signIn = find.text(l10n.signInWithGoogle);
      expect(signIn, findsOneWidget);

      audio.allCalls.clear();
      haptics.allCalls.clear();
      await tester.tap(signIn);
      await tester.pump();

      expect(audio.allCalls, ['buttonTap']);
      expect(haptics.allCalls, ['buttonTap']);
    });

    testWidgets('the profile language tile clicks', (tester) async {
      await pumpApp(tester);
      await goTo(tester, const ProfileRoute().location);

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      audio.allCalls.clear();
      await tester.tap(find.text(l10n.languageSectionTitle));
      await tester.pumpAndSettle();

      expect(audio.allCalls, ['buttonTap']);
    });

    testWidgets('the Settings sound and music switches click', (tester) async {
      await pumpApp(tester);
      await goTo(tester, const SettingsRoute().location);

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      for (final label in [l10n.soundLabel, l10n.musicLabel]) {
        audio.allCalls.clear();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(audio.allCalls, ['buttonTap'], reason: label);
      }
    });
  });
}
