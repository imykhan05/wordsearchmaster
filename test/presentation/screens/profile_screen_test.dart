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
import 'package:word_search_master/services/settings/ui_settings_store.dart';

import '../../support/fake_content.dart';
import '../../support/fake_meta.dart';
import '../../support/local_db.dart';

/// The profile screen's language tile — the only reachable way for a
/// returning player to switch languages (post-P17; see
/// `language_screen_test.dart` for the picker's own side of this).
void main() {
  Future<void> pumpProfileScreen(
    WidgetTester tester, {
    Language selectedLanguage = Language.english,
  }) async {
    final content = await buildTestContentRepository();
    final testDb = await openMemoryDatabase();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(AppConfig.dev()),
          appDatabaseProvider.overrideWithValue(testDb.database),
          contentRepositoryProvider.overrideWith((ref) => content),
          uiSettingsStoreProvider.overrideWithValue(
            InMemoryUiSettingsStore(selectedLanguage: selectedLanguage),
          ),
          ...fakeMetaOverrides(),
        ],
        child: const WordSearchMasterApp(),
      ),
    );
    await tester.pumpAndSettle();

    GoRouter.of(tester.element(find.byType(Navigator).first))
        .go(const ProfileRoute().location);
    await tester.pumpAndSettle();
  }

  testWidgets('shows the currently selected language', (tester) async {
    await pumpProfileScreen(tester, selectedLanguage: Language.urdu);

    expect(find.text(Language.urdu.endonym), findsOneWidget);
  });

  testWidgets(
    'tapping the language tile opens the picker, and switching languages '
    'returns to Home rather than dropping into a level',
    (tester) async {
      await pumpProfileScreen(tester, selectedLanguage: Language.english);

      await tester.tap(find.text(Language.english.endonym));
      await tester.pumpAndSettle();

      // Reached the picker, not some other screen — the FTUE heading proves
      // it, and the back arrow proves `LanguageScreen` recognised this as a
      // returning player rather than treating it as first launch.
      expect(find.text('Choose your language'), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);

      await tester.tap(find.text(Language.hindi.endonym));
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(Navigator).first);
      expect(
        GoRouter.of(context).routeInformationProvider.value.uri.path,
        '/home',
      );
    },
  );
}
