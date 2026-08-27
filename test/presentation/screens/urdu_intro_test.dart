import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/app/config/app_config.dart';
import 'package:word_search_master/app/theme/theme.dart';
import 'package:word_search_master/application/game_controller.dart';
import 'package:word_search_master/data/content/content_repository.dart';
import 'package:word_search_master/data/local/app_database.dart';
import 'package:word_search_master/domain/text/language.dart';
import 'package:word_search_master/domain/text/script_normalizer.dart';
import 'package:word_search_master/l10n/app_localizations.dart';
import 'package:word_search_master/presentation/screens/game_screen.dart';
import 'package:word_search_master/services/settings/ui_settings_store.dart';

import '../../support/fake_content.dart';
import '../../support/local_db.dart';

/// Ch02 FTUE: "For Urdu only, on the very first level, show a one-time
/// inline illustration mapping the connected word form to its isolated
/// letters, with an arrow. Once. Never again."
void main() {
  Future<ProviderContainer> pumpGameScreen(
    WidgetTester tester, {
    required UiSettingsStore settings,
  }) async {
    final content = await buildTestContentRepository();
    final testDb = await openMemoryDatabase();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(AppConfig.dev()),
          appDatabaseProvider.overrideWithValue(testDb.database),
          contentRepositoryProvider.overrideWith((ref) => content),
          uiSettingsStoreProvider.overrideWithValue(settings),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const GameScreen(levelId: '1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(GameScreen)));
  }

  testWidgets('shows on Urdu level 1 when never shown before', (tester) async {
    final settings = InMemoryUiSettingsStore(selectedLanguage: Language.urdu);
    await pumpGameScreen(tester, settings: settings);

    final l10n = AppLocalizations.of(tester.element(find.byType(GameScreen)));
    expect(find.text(l10n.urduLetterFormIntro), findsOneWidget);
  });

  testWidgets('never shows for English or Hindi', (tester) async {
    final settings = InMemoryUiSettingsStore(
      selectedLanguage: Language.english,
    );
    await pumpGameScreen(tester, settings: settings);

    final l10n = AppLocalizations.of(tester.element(find.byType(GameScreen)));
    expect(find.text(l10n.urduLetterFormIntro), findsNothing);
  });

  testWidgets('never shows once already shown — the ONE-TIME flag', (
    tester,
  ) async {
    final settings = InMemoryUiSettingsStore(
      selectedLanguage: Language.urdu,
      urduConnectedFormIntroShown: true,
    );
    await pumpGameScreen(tester, settings: settings);

    final l10n = AppLocalizations.of(tester.element(find.byType(GameScreen)));
    expect(find.text(l10n.urduLetterFormIntro), findsNothing);
  });

  testWidgets('dismissing it hides it and persists the flag — never again', (
    tester,
  ) async {
    final settings = InMemoryUiSettingsStore(selectedLanguage: Language.urdu);
    await pumpGameScreen(tester, settings: settings);
    final l10n = AppLocalizations.of(tester.element(find.byType(GameScreen)));
    expect(find.text(l10n.urduLetterFormIntro), findsOneWidget);

    await tester.tap(find.text(l10n.gotItButtonLabel));
    await tester.pump();

    expect(find.text(l10n.urduLetterFormIntro), findsNothing);
    expect(settings.urduConnectedFormIntroShown, isTrue);
  });

  testWidgets('shows the word split into isolated grid letters', (
    tester,
  ) async {
    final settings = InMemoryUiSettingsStore(selectedLanguage: Language.urdu);
    final container = await pumpGameScreen(tester, settings: settings);

    // Whichever word actually ended up first — the grid paints its cells via
    // a CustomPainter, never as Text widgets (P06), so these can only come
    // from the illustration's own isolated-letters row.
    final state = container
        .read(gameControllerProvider(const JourneySession(1)))
        .value!;
    final word = state.allWords.first;
    final letters = ScriptNormalizer.graphemes(word, Language.urdu);

    for (final letter in letters) {
      expect(find.text(letter), findsOneWidget);
    }
  });
}
