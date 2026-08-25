import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/app/app.dart';
import 'package:word_search_master/app/config/app_config.dart';
import 'package:word_search_master/domain/text/language.dart';
import 'package:word_search_master/presentation/game/game_grid.dart';

/// Covers the P01 acceptance criterion directly: each flavor must show its
/// own name starting on the very first screen.
void main() {
  Future<void> pumpApp(WidgetTester tester, AppConfig config) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appConfigProvider.overrideWithValue(config)],
        child: const WordSearchMasterApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The FTUE opens on language select, so reaching the rest of the app means
  /// picking a language first.
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

  testWidgets('picking a language enters the app', (tester) async {
    await enterApp(tester, AppConfig.dev());

    expect(find.text('Home'), findsWidgets);
  });

  testWidgets(
    'every stub route is reachable and keeps showing the flavor badge',
    (tester) async {
      await enterApp(tester, AppConfig.dev());

      // Game is excluded: since P06 it is a real screen with the grid on it,
      // not a StubScreen, so it carries no flavor badge or route nav. It gets
      // its own test below.
      const labels = [
        'Home',
        'Journey',
        'Daily',
        'Leaderboard',
        'Profile',
        'Settings',
      ];
      for (final label in labels) {
        await tester.tap(find.widgetWithText(OutlinedButton, label));
        await tester.pumpAndSettle();

        expect(
          find.text('DEV'),
          findsOneWidget,
          reason: 'flavor badge must persist on $label',
        );
      }
    },
  );

  testWidgets('the game route renders the real grid', (tester) async {
    await enterApp(tester, AppConfig.dev());

    await tester.tap(find.widgetWithText(OutlinedButton, 'Game'));
    await tester.pumpAndSettle();

    expect(find.byType(GameGrid), findsOneWidget);
    expect(find.text('Level 1'), findsOneWidget);
  });
}
