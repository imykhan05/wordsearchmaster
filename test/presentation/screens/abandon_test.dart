import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:word_search_master/app/app.dart';
import 'package:word_search_master/app/app_route.dart';
import 'package:word_search_master/app/config/app_config.dart';
import 'package:word_search_master/data/content/content_repository.dart';
import 'package:word_search_master/data/local/app_database.dart';
import 'package:word_search_master/data/repositories/dda_repository.dart';
import 'package:word_search_master/domain/text/language.dart';
import 'package:word_search_master/l10n/app_localizations.dart';
import 'package:word_search_master/presentation/screens/game_screen.dart';

import '../../support/fake_content.dart';
import '../../support/fake_meta.dart';
import '../../support/local_db.dart';

/// Ch02/P12: "two consecutive abandons of the same level" — the signal this
/// build uses is an explicit leave (back button, or "Home" from the pause
/// sheet) while the level is not yet complete. See `game_screen.dart`'s
/// `_recordAbandonIfNeeded` for why backgrounding is out of scope.
///
/// Pumps the REAL app + router (not a bare `GameScreen`, unlike most other
/// P12 widget tests) — both the back button and the pause sheet's Home
/// button navigate via `context.go`, which needs an actual `GoRouter` in the
/// tree.
void main() {
  Future<TestDatabase> pumpGameScreen(WidgetTester tester) async {
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

    final context = tester.element(find.byType(Navigator).first);
    GoRouter.of(context).go(const GameRoute('1').location);
    await tester.pumpAndSettle();
    return testDb;
  }

  Future<DdaRepository> ddaRepoFor(TestDatabase db) async {
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db.database)],
    );
    addTearDown(container.dispose);
    return container.read(ddaRepositoryProvider.future);
  }

  testWidgets('tapping the back button while playing records an abandon', (
    tester,
  ) async {
    final db = await pumpGameScreen(tester);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    final ddaRepo = await ddaRepoFor(db);
    expect(await ddaRepo.abandonCount(Language.english, 1), 1);
  });

  testWidgets('choosing Home from the pause sheet records an abandon', (
    tester,
  ) async {
    final db = await pumpGameScreen(tester);
    final l10n = AppLocalizations.of(tester.element(find.byType(GameScreen)));

    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.navHome));
    await tester.pumpAndSettle();

    final ddaRepo = await ddaRepoFor(db);
    expect(await ddaRepo.abandonCount(Language.english, 1), 1);
  });

  testWidgets('resuming from the pause sheet does NOT record an abandon', (
    tester,
  ) async {
    final db = await pumpGameScreen(tester);

    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.pumpAndSettle();
    // Tapping the scrim dismisses the sheet as PauseAction.resume (`null`).
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    final ddaRepo = await ddaRepoFor(db);
    expect(await ddaRepo.abandonCount(Language.english, 1), 0);
  });

  testWidgets(
    'leaving twice accumulates — the repository-level counter this screen '
    'writes into, proven end to end in dda_repository_test.dart',
    (tester) async {
      final db = await pumpGameScreen(tester);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      final ddaRepo = await ddaRepoFor(db);
      await ddaRepo.recordAbandon(Language.english, 1);

      expect(await ddaRepo.abandonCount(Language.english, 1), 2);
    },
  );
}
