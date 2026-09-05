import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:word_search_master/app/app.dart';
import 'package:word_search_master/app/app_route.dart';
import 'package:word_search_master/app/config/app_config.dart';
import 'package:word_search_master/data/content/content_repository.dart';
import 'package:word_search_master/data/local/app_database.dart';
import 'package:word_search_master/domain/text/language.dart';
import 'package:word_search_master/presentation/game/game_grid.dart';

import '../support/fake_content.dart';
import '../support/fake_meta.dart';
import '../support/local_db.dart';

/// Covers the P01 acceptance criterion directly: each flavor must show its
/// own name starting on the very first screen — plus that every route in the
/// table still renders after P11 replaced four of them with real screens.
void main() {
  Future<void> pumpApp(WidgetTester tester, AppConfig config) async {
    // Content and database are injected already-resolved for the same reason
    // `game_screen_test.dart` injects them: since P10/P11 the game route
    // awaits `ContentRepository` (whose default reads `rootBundle`, which
    // never completes under `flutter_test`'s fake async) and writes awards
    // through `appDatabaseProvider` (whose default opens a real
    // `drift_flutter` connection that does not exist in a widget test).
    // Both are built OUTSIDE the pump, before the fake clock is in play.
    //
    // The meta providers are overridden on top of that — see
    // `fake_meta.dart` for why a route-level smoke test should not be driving
    // live Drift query streams.
    final content = await buildTestContentRepository();
    final testDb = await openMemoryDatabase();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(config),
          appDatabaseProvider.overrideWithValue(testDb.database),
          contentRepositoryProvider.overrideWith((ref) => content),
          ...fakeMetaOverrides(),
        ],
        child: const WordSearchMasterApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> goTo(WidgetTester tester, AppRoute route) async {
    GoRouter.of(tester.element(find.byType(Navigator).first))
        .go(route.location);
    await tester.pumpAndSettle();
  }

  /// The FTUE opens on language select, so reaching the rest of the app means
  /// picking a language first — which now (P12) lands straight on level 1,
  /// not `HomeRoute`; a test that wants `HomeRoute` itself navigates there
  /// explicitly afterward via [goTo].
  Future<void> enterApp(WidgetTester tester, AppConfig config) async {
    await pumpApp(tester, config);
    await tester.tap(find.text(Language.english.endonym));
    await tester.pumpAndSettle();
  }

  for (final config in [AppConfig.dev(), AppConfig.stg(), AppConfig.prod()]) {
    testWidgets(
      '${config.flavor.name} flavor shows its name on the first screen',
      (tester) async {
        await pumpApp(tester, config);

        expect(find.text(config.flavorName), findsOneWidget);
      },
    );
  }

  testWidgets('initial route is language select, per the FTUE spec', (
    tester,
  ) async {
    await pumpApp(tester, AppConfig.dev());

    // No login, no permission dialog, no ad — just the three cards.
    expect(find.text('Choose your language'), findsOneWidget);
    for (final language in Language.values) {
      expect(find.text(language.endonym), findsOneWidget);
    }
  });

  testWidgets(
    'picking a language enters the app straight into level 1 — Ch02: no '
    'Play tap required',
    (tester) async {
      await enterApp(tester, AppConfig.dev());

      expect(find.byType(GameGrid), findsOneWidget);
      expect(find.text('Level 1'), findsOneWidget);
    },
  );

  testWidgets(
    'the remaining stub routes still render and keep the flavor badge',
    (tester) async {
      await enterApp(tester, AppConfig.dev());

      // P11 turned home, journey, daily and profile into real screens, and
      // the post-P17 settings screen (sound/music/haptics/language) means
      // this stub route-nav row is gone from there too — navigate by route
      // instead of by tapping a button that no longer exists.
      for (final route in const [LeaderboardRoute()]) {
        await goTo(tester, route);

        expect(
          find.text('DEV'),
          findsOneWidget,
          reason: 'flavor badge must persist on ${route.location}',
        );
      }
    },
  );

  testWidgets('every P11 route renders its real screen', (tester) async {
    await enterApp(tester, AppConfig.dev());

    // Each of these replaced a StubScreen in P11; the assertion is simply
    // that the route resolves and paints its own title rather than throwing.
    for (final (route, title) in const [
      (JourneyRoute(), 'Journey'),
      (DailyRoute(), 'Daily Challenge'),
      (ProfileRoute(), 'Profile'),
      (HomeRoute(), 'Home'),
      (SettingsRoute(), 'Settings'),
    ]) {
      await goTo(tester, route);
      expect(find.text(title), findsWidgets, reason: route.location);
    }
  });

  testWidgets('the game route renders the real grid', (tester) async {
    await enterApp(tester, AppConfig.dev());

    await goTo(tester, const GameRoute('1'));

    expect(find.byType(GameGrid), findsOneWidget);
    expect(find.text('Level 1'), findsOneWidget);
  });
}
