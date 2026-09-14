import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:word_search_master/app/app_route.dart';
import 'package:word_search_master/app/theme/app_theme.dart';
import 'package:word_search_master/domain/text/language.dart';
import 'package:word_search_master/l10n/app_localizations.dart';
import 'package:word_search_master/presentation/screens/splash_screen.dart';
import 'package:word_search_master/services/settings/ui_settings_store.dart';

/// The splash's own scope: its first frame, its fixed display duration, and
/// which of [LanguageRoute]/[HomeRoute] it hands off to.
///
/// A minimal router rather than the real `WordSearchMasterApp` — the splash
/// only ever reads `selectedLanguageProvider`/`hasChosenLanguageProvider`
/// (both backed by `uiSettingsStoreProvider`), so pulling in content,
/// database and meta overrides the way `app_smoke_test.dart` does would test
/// nothing this file needs and only make its own timing assertions ride on
/// more machinery than necessary. The full splash-then-screen journey via
/// `pumpAndSettle()` on the REAL app is `app_smoke_test.dart`'s job and its
/// siblings'; this file is what proves the screen's own contract, with
/// `tester.pump(duration)` driving the clock directly rather than trusting
/// `pumpAndSettle()`'s "stop once nothing is scheduled" heuristic to land on
/// the right moment.
void main() {
  // Kept in one place — every timing assertion below is phrased relative to
  // this instead of a repeated literal, so a future duration change (still
  // somewhere in the 15-20s range the brief asked for) only moves one line.
  const displayDuration = Duration(seconds: 18);

  Future<void> pumpSplash(
    WidgetTester tester, {
    Language? savedLanguage,
    bool reduceMotion = false,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          uiSettingsStoreProvider.overrideWithValue(
            InMemoryUiSettingsStore(selectedLanguage: savedLanguage),
          ),
        ],
        child: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: MaterialApp.router(
            theme: AppTheme.dark(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: GoRouter(
              initialLocation: const SplashRoute().location,
              routes: [
                GoRoute(
                  path: const SplashRoute().location,
                  builder: (context, state) => const SplashScreen(),
                ),
                // Marker screens — this file only needs to know WHICH one
                // the splash handed off to, never what either actually
                // renders (that is `language_screen_test.dart`'s and
                // `home_screen_test.dart`'s job).
                GoRoute(
                  path: const LanguageRoute().location,
                  builder: (context, state) => const Text('LANGUAGE SCREEN'),
                ),
                GoRoute(
                  path: const HomeRoute().location,
                  builder: (context, state) => const Text('HOME SCREEN'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'the first frame shows the bundled artwork and a 0% progress readout',
    (tester) async {
      await pumpSplash(tester);
      await tester.pump();

      // The wordmark and the decorative word-search grids are painted
      // directly into `assets/branding/splash_background.png` now — this
      // screen no longer renders a separate name widget, so the only thing
      // left to assert about the art itself is that it is there at all.
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('0%'), findsOneWidget);
    },
  );

  testWidgets('the progress readout climbs toward 100% as the hold runs', (
    tester,
  ) async {
    await pumpSplash(tester);
    await tester.pump();

    await tester.pump(displayDuration * 0.5);
    expect(find.text('50%'), findsOneWidget);

    // 98% of the full 18s hold — comfortably short of the 100% a value very
    // close to 1.0 would round up to.
    await tester.pump(
      Duration(milliseconds: (displayDuration.inMilliseconds * 0.48).round()),
    );
    expect(find.text('98%'), findsOneWidget);
  });

  testWidgets(
    'a first-time player hands off to the language picker after the full '
    'display duration, not before',
    (tester) async {
      await pumpSplash(tester);
      await tester.pump();

      await tester.pump(displayDuration - const Duration(milliseconds: 500));
      expect(
        find.text('LANGUAGE SCREEN'),
        findsNothing,
        reason:
            'the brand is still meant to be on screen just before the '
            'hold ends',
      );

      // A few ms PAST the exact duration, not pumped to land on it exactly:
      // `AnimationController.status` flips to `completed` a hair after its
      // `Ticker`'s `elapsed` reaches `duration` in this fake-clock harness
      // (the same reason the 98%-not-100% pump above stops short rather than
      // landing on the boundary), so asserting exactly at `displayDuration`
      // is a coin flip on that epsilon rather than a statement about the
      // screen's own timing.
      await tester.pump(const Duration(milliseconds: 550));
      expect(find.text('LANGUAGE SCREEN'), findsOneWidget);
    },
  );

  testWidgets(
    'a returning player hands off to Home instead, after the same duration',
    (tester) async {
      await pumpSplash(tester, savedLanguage: Language.urdu);
      await tester.pump();

      await tester.pump(displayDuration - const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 550));
      expect(find.text('HOME SCREEN'), findsOneWidget);
      expect(find.text('LANGUAGE SCREEN'), findsNothing);
    },
  );

  testWidgets(
    'reduce-motion does not shorten or lengthen the hold — the progress '
    'fill is load information, not decoration, so it is never gated by it',
    (tester) async {
      await pumpSplash(tester, reduceMotion: true);
      await tester.pump();

      await tester.pump(displayDuration - const Duration(milliseconds: 500));
      expect(find.text('LANGUAGE SCREEN'), findsNothing);

      await tester.pump(const Duration(milliseconds: 550));
      expect(find.text('LANGUAGE SCREEN'), findsOneWidget);
    },
  );

  testWidgets(
    'a full pumpAndSettle() ride reaches the language picker on its own',
    (tester) async {
      // Regression guard: an earlier version of this screen ran a separate
      // `Timer` alongside a SHORTER entrance animation. Once the entrance
      // settled, nothing was left scheduling frames for the remaining hold,
      // so `pumpAndSettle()` — which stops the instant no frame is
      // scheduled, not when every pending `Timer` has fired — returned
      // control before the hand-off ever ran. Every test that pumps the real
      // app root (`app_smoke_test.dart` and its siblings) depends on this
      // NOT happening.
      await pumpSplash(tester);
      await tester.pumpAndSettle();

      expect(find.text('LANGUAGE SCREEN'), findsOneWidget);
    },
  );
}
