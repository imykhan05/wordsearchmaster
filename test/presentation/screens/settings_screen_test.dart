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
import 'package:word_search_master/services/audio/sound_settings.dart';
import 'package:word_search_master/services/settings/ui_settings_store.dart';

import '../../support/fake_content.dart';
import '../../support/fake_meta.dart';
import '../../support/local_db.dart';

/// Sound/music/haptics/language, all reachable from one screen (post-P17) —
/// see `profile_screen_test.dart` for the language tile's own round trip,
/// which this file does not repeat.
void main() {
  Future<ProviderContainer> pumpSettingsScreen(WidgetTester tester) async {
    final content = await buildTestContentRepository();
    final testDb = await openMemoryDatabase();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(AppConfig.dev()),
          appDatabaseProvider.overrideWithValue(testDb.database),
          contentRepositoryProvider.overrideWith((ref) => content),
          uiSettingsStoreProvider.overrideWithValue(
            InMemoryUiSettingsStore(selectedLanguage: Language.english),
          ),
          ...fakeMetaOverrides(),
        ],
        child: const WordSearchMasterApp(),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(Navigator).first),
    );
    GoRouter.of(tester.element(find.byType(Navigator).first))
        .go(const SettingsRoute().location);
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('shows sound, music, haptics and the current language', (
    tester,
  ) async {
    await pumpSettingsScreen(tester);

    expect(find.byType(SwitchListTile), findsNWidgets(3));
    expect(find.text(Language.english.endonym), findsOneWidget);
  });

  testWidgets('toggling sound flips soundEnabledProvider', (tester) async {
    final container = await pumpSettingsScreen(tester);
    expect(container.read(soundEnabledProvider), isTrue);

    await tester.tap(find.byType(SwitchListTile).first);
    await tester.pumpAndSettle();

    expect(container.read(soundEnabledProvider), isFalse);
  });

  testWidgets('the back arrow returns to Home', (tester) async {
    await pumpSettingsScreen(tester);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(Navigator).first);
    expect(
      GoRouter.of(context).routeInformationProvider.value.uri.path,
      '/home',
    );
  });

  testWidgets('tapping the language tile opens the picker', (tester) async {
    await pumpSettingsScreen(tester);

    await tester.tap(find.text(Language.english.endonym));
    await tester.pumpAndSettle();

    expect(find.text('Choose your language'), findsOneWidget);
  });
}
