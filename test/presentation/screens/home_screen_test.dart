import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:word_search_master/app/app.dart';
import 'package:word_search_master/app/app_route.dart';
import 'package:word_search_master/app/config/app_config.dart';
import 'package:word_search_master/l10n/app_localizations.dart';
import 'package:word_search_master/services/settings/ui_settings_store.dart';

import '../../support/fake_meta.dart';

/// Ch02/P12: "Login is offered only after level 8, framed as 'save your
/// progress', and is dismissible."
void main() {
  Future<AppLocalizations> pumpHome(
    WidgetTester tester, {
    int highestCompletedLevel = 0,
    UiSettingsStore? settings,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(AppConfig.dev()),
          if (settings != null)
            uiSettingsStoreProvider.overrideWithValue(settings),
          ...fakeMetaOverrides(highestCompletedLevel: highestCompletedLevel),
        ],
        child: const WordSearchMasterApp(),
      ),
    );
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(Navigator).first);
    GoRouter.of(context).go(const HomeRoute().location);
    await tester.pumpAndSettle();
    return AppLocalizations.of(context);
  }

  testWidgets('hidden before level 8', (tester) async {
    final l10n = await pumpHome(tester, highestCompletedLevel: 7);

    expect(find.text(l10n.saveProgressPromptMessage), findsNothing);
  });

  testWidgets('shown once level 8 is completed', (tester) async {
    final l10n = await pumpHome(tester, highestCompletedLevel: 8);

    expect(find.text(l10n.saveProgressPromptMessage), findsOneWidget);
    expect(find.text(l10n.saveProgressPromptAction), findsOneWidget);
  });

  testWidgets('dismissing it hides it and persists the choice', (tester) async {
    final settings = InMemoryUiSettingsStore();
    final l10n = await pumpHome(
      tester,
      highestCompletedLevel: 10,
      settings: settings,
    );
    expect(find.text(l10n.saveProgressPromptMessage), findsOneWidget);

    await tester.tap(find.byTooltip(l10n.saveProgressPromptDismiss));
    await tester.pump();

    expect(find.text(l10n.saveProgressPromptMessage), findsNothing);
    expect(settings.loginPromptDismissed, isTrue);
  });

  testWidgets('already-dismissed (a returning session) never shows it', (
    tester,
  ) async {
    final settings = InMemoryUiSettingsStore(loginPromptDismissed: true);
    final l10n = await pumpHome(
      tester,
      highestCompletedLevel: 20,
      settings: settings,
    );

    expect(find.text(l10n.saveProgressPromptMessage), findsNothing);
  });

  testWidgets('accepting the stub offer dismisses it too', (tester) async {
    final settings = InMemoryUiSettingsStore();
    final l10n = await pumpHome(
      tester,
      highestCompletedLevel: 8,
      settings: settings,
    );

    await tester.tap(find.text(l10n.saveProgressPromptAction));
    await tester.pump();

    expect(find.text(l10n.saveProgressPromptMessage), findsNothing);
    expect(settings.loginPromptDismissed, isTrue);

    // Lets the stub's SnackBar finish its own animation/auto-dismiss timer
    // before the test ends, the same reason `ftue_dda_test.dart` pumps past
    // the particle burst's delayed Future.
    await tester.pump(const Duration(seconds: 5));
  });
}
