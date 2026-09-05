import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:word_search_master/app/app.dart';
import 'package:word_search_master/app/app_route.dart';
import 'package:word_search_master/app/config/app_config.dart';
import 'package:word_search_master/data/local/app_database.dart';
import 'package:word_search_master/domain/progression/streak.dart';
import 'package:word_search_master/l10n/app_localizations.dart';
import 'package:word_search_master/services/notifications/notification_service.dart';
import 'package:word_search_master/services/settings/ui_settings_store.dart';

import '../../support/fake_meta.dart';
import '../../support/local_db.dart';

/// Ch02/P12: "Login is offered only after level 8, framed as 'save your
/// progress', and is dismissible."
void main() {
  Future<AppLocalizations> pumpHome(
    WidgetTester tester, {
    int highestCompletedLevel = 0,
    UiSettingsStore? settings,
    int streak = 0,
    NotificationService? notifications,
  }) async {
    // A real (in-memory) database, built OUTSIDE the pump before the fake
    // clock is in play — most tests in this file never touch it, since
    // `fakeMetaOverrides` bypasses every P11 repository Home itself reads.
    // The leaderboard-button test below is the exception: navigating into
    // `LeaderboardScreen` reaches `cachedLeaderboardProvider` ->
    // `LeaderboardCache`, which needs a real `appDatabaseProvider` — the
    // default `drift_flutter` connection never resolves under
    // `flutter_test`'s fake async, which otherwise hangs `pumpAndSettle`
    // exactly the way `ContentRepository`'s `rootBundle` reads do.
    final db = await openMemoryDatabase();
    addTearDown(db.database.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(AppConfig.dev()),
          appDatabaseProvider.overrideWithValue(db.database),
          if (settings != null)
            uiSettingsStoreProvider.overrideWithValue(settings),
          if (notifications != null)
            notificationServiceProvider.overrideWithValue(notifications),
          ...fakeMetaOverrides(
            highestCompletedLevel: highestCompletedLevel,
            streak: StreakState(current: streak),
          ),
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

  testWidgets(
    'the app bar settings icon is the only way to reach SettingsRoute, and it works',
    (tester) async {
      // Regression test: `SettingsRoute` rendered fine and every route-level
      // test could reach it by driving the router directly, but nothing in
      // the live app ever navigated there — `StubScreen`'s dev-only route
      // switcher is dead code (no route has built a `StubScreen` since P11/
      // P17 gave every screen its own builder), so a real player had no way
      // to open Settings at all.
      final l10n = await pumpHome(tester);

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();

      expect(find.text(l10n.navSettings), findsWidgets);
      expect(find.byType(SwitchListTile), findsNWidgets(4));
    },
  );

  testWidgets(
    'the leaderboard button on Home is the only way to reach LeaderboardRoute, and it works',
    (tester) async {
      // Same bug, same shape as the settings-icon regression above:
      // `LeaderboardRoute` rendered fine for any test driving the router
      // directly, but nothing in the live app ever navigated there.
      final l10n = await pumpHome(tester);

      await tester.tap(find.text(l10n.navLeaderboard));
      await tester.pumpAndSettle();

      expect(find.text(l10n.navLeaderboard), findsWidgets);
    },
  );

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

  testWidgets(
    'accepting when sign-in is unavailable KEEPS the offer — P13 changed '
    'this from P12',
    (tester) async {
      // P12's stub dismissed the banner on any tap. The real flow (P13)
      // dismisses only on success: a player whose sign-in failed has not
      // decided anything, and hiding the offer would take away the retry
      // they are most likely to want next.
      //
      // With no Firebase configured, `authServiceProvider` is the Noop, whose
      // `linkWithGoogle` returns `LinkFailed('auth-unavailable')` — the same
      // path a player in airplane mode takes.
      final settings = InMemoryUiSettingsStore();
      final l10n = await pumpHome(
        tester,
        highestCompletedLevel: 8,
        settings: settings,
      );

      await tester.tap(find.text(l10n.saveProgressPromptAction));
      await tester.pumpAndSettle();

      expect(
        find.text(l10n.saveProgressPromptMessage),
        findsOneWidget,
        reason: 'the offer stays so the player can try again',
      );
      expect(settings.loginPromptDismissed, isFalse);
      // And the failure is surfaced gently, leading with the reassurance.
      expect(find.text(l10n.signInFailedMessage), findsOneWidget);

      // Let the SnackBar's own auto-dismiss timer finish before the test
      // ends, the same reason `ftue_dda_test.dart` pumps past the particle
      // burst's delayed Future.
      await tester.pump(const Duration(seconds: 5));
    },
  );

  group('notification permission request (post-P17)', () {
    testWidgets('never asked with no streak at all', (tester) async {
      final notifications = _FakeNotificationService();
      final settings = InMemoryUiSettingsStore();

      await pumpHome(
        tester,
        streak: 0,
        settings: settings,
        notifications: notifications,
      );

      expect(notifications.requestCount, 0);
      expect(settings.notificationPermissionAsked, isFalse);
    });

    testWidgets('never asked with a streak of 1 — nothing worth losing yet', (
      tester,
    ) async {
      final notifications = _FakeNotificationService();
      final settings = InMemoryUiSettingsStore();

      await pumpHome(
        tester,
        streak: 1,
        settings: settings,
        notifications: notifications,
      );

      expect(notifications.requestCount, 0);
    });

    testWidgets('asks once a streak of 2 exists, and remembers it asked', (
      tester,
    ) async {
      final notifications = _FakeNotificationService();
      final settings = InMemoryUiSettingsStore();

      await pumpHome(
        tester,
        streak: 2,
        settings: settings,
        notifications: notifications,
      );

      expect(notifications.requestCount, 1);
      expect(settings.notificationPermissionAsked, isTrue);
    });

    testWidgets(
      'a returning session that already answered is never asked again',
      (tester) async {
        final notifications = _FakeNotificationService();
        final settings = InMemoryUiSettingsStore(
          notificationPermissionAsked: true,
        );

        await pumpHome(
          tester,
          streak: 10,
          settings: settings,
          notifications: notifications,
        );

        expect(notifications.requestCount, 0);
      },
    );
  });
}

final class _FakeNotificationService implements NotificationService {
  int requestCount = 0;

  @override
  Future<bool> requestPermission() async {
    requestCount++;
    return true;
  }

  @override
  Future<String?> getToken() async => null;

  @override
  Stream<String> get onTokenRefresh => const Stream.empty();
}
