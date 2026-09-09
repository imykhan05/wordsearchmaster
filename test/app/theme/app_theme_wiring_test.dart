import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/app/app.dart';
import 'package:word_search_master/app/config/app_config.dart';
import 'package:word_search_master/app/theme/app_tokens.dart';
import 'package:word_search_master/data/content/content_repository.dart';
import 'package:word_search_master/data/local/app_database.dart';
import 'package:word_search_master/domain/theme/app_theme_variant.dart';
import 'package:word_search_master/services/settings/ui_settings_store.dart';
import 'package:word_search_master/services/theme/theme_settings.dart';

import '../../support/fake_content.dart';
import '../../support/fake_meta.dart';
import '../../support/local_db.dart';

/// The app root's half of the theme feature: the palette the player picked is
/// the palette `MaterialApp` is handed, and nothing else gets a vote.
void main() {
  Future<MaterialApp> pumpAppWith(
    WidgetTester tester, {
    required AppThemeSelection selection,
    Brightness platformBrightness = Brightness.dark,
    DateTime? now,
  }) async {
    final content = await buildTestContentRepository();
    final testDb = await openMemoryDatabase();
    addTearDown(testDb.database.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(AppConfig.dev()),
          appDatabaseProvider.overrideWithValue(testDb.database),
          contentRepositoryProvider.overrideWith((ref) => content),
          uiSettingsStoreProvider.overrideWithValue(
            InMemoryUiSettingsStore(appTheme: selection),
          ),
          themeClockProvider.overrideWithValue(
            () => now ?? DateTime(2026, 9, 9, 12),
          ),
          ...fakeMetaOverrides(),
        ],
        child: MediaQuery(
          data: MediaQueryData(platformBrightness: platformBrightness),
          child: const WordSearchMasterApp(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    return tester.widget<MaterialApp>(find.byType(MaterialApp));
  }

  AppColors colorsOf(ThemeData? theme) => theme!.extension<AppTokens>()!.colors;

  testWidgets('a pinned palette is what the app is built with', (tester) async {
    final app = await pumpAppWith(
      tester,
      selection: const AppThemeSelection.fixed(AppThemeVariant.twilight),
    );

    expect(colorsOf(app.theme).background, AppTokens.twilightColors.background);
  });

  testWidgets('the OS dark-mode switch cannot override the player', (
    tester,
  ) async {
    // The reason `theme` and `darkTheme` are filled with the SAME object. A
    // player who pinned a light palette and whose phone flips to dark mode at
    // sunset must keep the palette they picked — Material's own light/dark
    // pair exists to follow the system, which is exactly the vote this app
    // does not give it.
    for (final brightness in Brightness.values) {
      final app = await pumpAppWith(
        tester,
        selection: const AppThemeSelection.fixed(AppThemeVariant.desertSand),
        platformBrightness: brightness,
      );

      expect(
        colorsOf(app.theme).background,
        AppTokens.desertSandColors.background,
        reason: 'platformBrightness $brightness changed the palette',
      );
      expect(
        colorsOf(app.darkTheme).background,
        AppTokens.desertSandColors.background,
        reason: 'the dark slot holds a different palette, so the OS has a vote',
      );
    }
  });

  testWidgets('AUTO builds the app from the clock', (tester) async {
    // 12:00 is the afternoon slot, which is a LIGHT palette — so this also
    // proves the light theme is reachable at all. It was not: `app.dart` hard
    // -coded `themeMode: ThemeMode.dark` from P02 until the theme picker
    // landed, and `AppTheme.light()` had never once been on screen.
    final noon = DateTime(2026, 9, 9, 12);
    final app = await pumpAppWith(
      tester,
      selection: const AppThemeSelection.auto(),
      now: noon,
    );

    final expected = AppTokens.colorsFor(AutoTheme.variantAt(noon));
    expect(colorsOf(app.theme).background, expected.background);
    expect(app.theme!.brightness, Brightness.light);
  });

  testWidgets('AUTO after dark builds a dark app', (tester) async {
    final app = await pumpAppWith(
      tester,
      selection: const AppThemeSelection.auto(),
      now: DateTime(2026, 9, 9, 21),
      platformBrightness: Brightness.light,
    );

    expect(app.theme!.brightness, Brightness.dark);
  });
}
