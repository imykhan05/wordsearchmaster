import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:word_search_master/app/app.dart';
import 'package:word_search_master/app/app_route.dart';
import 'package:word_search_master/app/config/app_config.dart';
import 'package:word_search_master/data/content/content_repository.dart';
import 'package:word_search_master/data/local/app_database.dart';
import 'package:word_search_master/domain/audio/sound_theme.dart';
import 'package:word_search_master/domain/theme/background_style.dart';
import 'package:word_search_master/domain/text/language.dart';
import 'package:word_search_master/services/audio/sound_settings.dart';
import 'package:word_search_master/services/background/background_settings.dart';
import 'package:word_search_master/services/notifications/notification_settings.dart';
import 'package:word_search_master/services/settings/ui_settings_store.dart';

import '../../support/fake_content.dart';
import '../../support/fake_meta.dart';
import '../../support/local_db.dart';

/// Sound/music/haptics/language, all reachable from one screen (post-P17) —
/// see `profile_screen_test.dart` for the language tile's own round trip,
/// which this file does not repeat.
void main() {
  Future<ProviderContainer> pumpSettingsScreen(WidgetTester tester) async {
    // A TALLER SURFACE THAN THE DEFAULT 600dp. This screen is a `ListView`,
    // so anything below the fold is never built and `findsNothing` would mean
    // "scrolled past", not "absent" — which the background card pushed the
    // notifications section into. Sizing the window to fit the whole screen
    // keeps every assertion below about what EXISTS rather than about what
    // happens to be on screen.
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

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

  testWidgets(
    'shows sound, music, haptics, streak reminders and the current language',
    (tester) async {
      await pumpSettingsScreen(tester);

      expect(find.byType(SwitchListTile), findsNWidgets(4));
      expect(find.text(Language.english.endonym), findsOneWidget);
    },
  );

  testWidgets('toggling sound flips soundEnabledProvider', (tester) async {
    final container = await pumpSettingsScreen(tester);
    expect(container.read(soundEnabledProvider), isTrue);

    await tester.tap(find.byType(SwitchListTile).first);
    await tester.pumpAndSettle();

    expect(container.read(soundEnabledProvider), isFalse);
  });

  testWidgets('shows one chip per SoundTheme, with the current one selected', (
    tester,
  ) async {
    await pumpSettingsScreen(tester);

    // BY NAME, not by counting every chip on the screen: the background
    // section adds its own swatches, and a bare count would silently start
    // measuring both.
    const names = ['Soft Bells', 'Chimes', 'Minimal'];
    expect(
      names,
      hasLength(SoundTheme.values.length),
      reason: 'a new SoundTheme was added without a chip named here',
    );

    final selected = <String>[];
    for (final name in names) {
      final finder = find.widgetWithText(ChoiceChip, name);
      expect(finder, findsOneWidget, reason: '$name has no chip');
      if (tester.widget<ChoiceChip>(finder).selected) selected.add(name);
    }
    expect(
      selected,
      hasLength(1),
      reason: 'exactly the current theme, never zero or more than one',
    );
  });

  testWidgets(
    'picking a different theme chip updates soundThemeSettingProvider',
    (tester) async {
      final container = await pumpSettingsScreen(tester);
      expect(
        container.read(soundThemeSettingProvider),
        SoundTheme.defaultTheme,
      );

      // Tap the chip for a theme that is NOT already selected — the default
      // is softBells, so chimes is always a distinct, currently-unselected
      // option regardless of enum ordering.
      await tester.tap(find.widgetWithText(ChoiceChip, 'Chimes'));
      await tester.pumpAndSettle();

      expect(container.read(soundThemeSettingProvider), SoundTheme.chimes);
    },
  );

  testWidgets('offers a swatch per gradient plus a photo action', (
    tester,
  ) async {
    await pumpSettingsScreen(tester);

    for (final name in ['Calm', 'Ember', 'Lagoon']) {
      expect(find.widgetWithText(ChoiceChip, name), findsOneWidget);
    }
    // The photo is NOT a swatch — it is a file chooser, and an empty chip for
    // a player who has never picked an image would be a dead option.
    expect(find.byType(ActionChip), findsOneWidget);
  });

  testWidgets('picking a gradient updates the style AND drops the photo', (
    tester,
  ) async {
    final container = await pumpSettingsScreen(tester);
    expect(
      container.read(backgroundStyleSettingProvider),
      BackgroundStyle.defaultStyle,
    );

    await tester.tap(find.widgetWithText(ChoiceChip, 'Ember'));
    await tester.pumpAndSettle();

    expect(
      container.read(backgroundStyleSettingProvider),
      BackgroundStyle.ember,
    );
    expect(
      container.read(backgroundPhotoPathProvider),
      isNull,
      reason:
          'a picture the player stopped using has no business still sitting '
          'in the cache',
    );
  });

  testWidgets(
    'toggling streak reminders flips streakRemindersEnabledProvider',
    (tester) async {
      final container = await pumpSettingsScreen(tester);
      expect(container.read(streakRemindersEnabledProvider), isTrue);

      await tester.tap(find.widgetWithText(SwitchListTile, 'Streak reminders'));
      await tester.pumpAndSettle();

      expect(container.read(streakRemindersEnabledProvider), isFalse);
    },
  );

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
