import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:word_search_master/app/app.dart';
import 'package:word_search_master/app/config/app_config.dart';
import 'package:word_search_master/data/content/content_repository.dart';
import 'package:word_search_master/data/local/app_database.dart';
import 'package:word_search_master/domain/text/language.dart';
import 'package:word_search_master/presentation/game/game_grid.dart';

import '../../support/fake_content.dart';
import '../../support/fake_meta.dart';
import '../../support/local_db.dart';

/// Ch02/P12: `LanguageScreen`'s two new behaviours — a sample of the
/// language's own words on each card, and "no Play tap required": picking a
/// card lands straight on level 1. `app_smoke_test.dart` already covers the
/// route-level proof of the second one end to end; this file is scoped to
/// what's specific to the screen itself.
void main() {
  Future<void> pumpLanguageScreen(WidgetTester tester) async {
    final content = await buildTestContentRepository();
    final testDb = await openMemoryDatabase();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(AppConfig.dev()),
          appDatabaseProvider.overrideWithValue(testDb.database),
          contentRepositoryProvider.overrideWith((ref) => content),
          ...fakeMetaOverrides(),
        ],
        child: const WordSearchMasterApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('each card shows a sample of that language\'s own words', (
    tester,
  ) async {
    await pumpLanguageScreen(tester);

    // English card: the fixture's first three words, in file order.
    expect(find.textContaining('WATER'), findsOneWidget);
    expect(find.textContaining('STONE'), findsOneWidget);
    expect(find.textContaining('RIVER'), findsOneWidget);
    // Urdu card, in its own script — proves the sample is per-card, not one
    // list reused everywhere.
    expect(find.textContaining('پانی'), findsOneWidget);
    expect(find.textContaining('بادل'), findsOneWidget);
  });

  testWidgets(
    'picking a language goes straight into level 1 — no Play tap, no Home '
    'stopover',
    (tester) async {
      await pumpLanguageScreen(tester);

      await tester.tap(find.text(Language.english.endonym));
      await tester.pumpAndSettle();

      expect(find.byType(GameGrid), findsOneWidget);
      expect(find.text('Level 1'), findsOneWidget);
      expect(
        find.text('Home'),
        findsNothing,
        reason: 'must not stop on Home on the way in',
      );
    },
  );

  testWidgets('the picked language reaches the game screen correctly', (
    tester,
  ) async {
    await pumpLanguageScreen(tester);

    await tester.tap(find.text(Language.urdu.endonym));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(Navigator).first);
    expect(
      GoRouter.of(context).routeInformationProvider.value.uri.path,
      '/game/1',
    );
    expect(Directionality.of(context), TextDirection.rtl);
  });
}
