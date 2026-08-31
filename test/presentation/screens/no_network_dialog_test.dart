import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:word_search_master/app/app.dart';
import 'package:word_search_master/app/app_route.dart';
import 'package:word_search_master/app/config/app_config.dart';
import 'package:word_search_master/data/content/content_repository.dart';
import 'package:word_search_master/data/local/app_database.dart';
import 'package:word_search_master/data/remote/sync_api.dart';
import 'package:word_search_master/data/repositories/leaderboard_cache.dart';
import 'package:word_search_master/l10n/app_localizations.dart';
import 'package:word_search_master/presentation/widgets/sync_status.dart';
import 'package:word_search_master/services/connectivity/connectivity_service.dart';

import '../../application/sync_worker_test.dart' show FakeConnectivityService;
import '../../support/fake_content.dart';
import '../../support/fake_meta.dart';
import '../../support/local_db.dart';

/// P16's THIRD acceptance criterion: "koi network dialog kabhi nahi dikhta."
///
/// ---------------------------------------------------------------------------
/// PROVED FROM THE OUTSIDE, NOT BY READING THE SOURCE
///
/// A grep for `showDialog` would pass the moment someone routed a network
/// error through a `SnackBar`, a `MaterialBanner` or a pushed route instead —
/// all of which are the same interruption wearing a different widget. So this
/// walks a real offline session across the screens a player actually visits
/// and asserts that NONE of those ever appears.
///
/// The list of forbidden widgets is deliberately broader than "dialog",
/// because Ch10's rule is about interruption rather than about a class name.
void main() {
  /// Every widget that takes the screen, or the bottom of it, to say something
  /// the player did not ask for.
  final forbidden = <Type>[
    AlertDialog,
    SimpleDialog,
    Dialog,
    SnackBar,
    MaterialBanner,
    BottomSheet,
  ];

  void expectNoInterruption(WidgetTester tester, String where) {
    for (final type in forbidden) {
      expect(
        find.byType(type),
        findsNothing,
        reason: 'a $type appeared on $where while offline — Ch10 forbids it',
      );
    }
  }

  Future<(TestDatabase, FakeConnectivityService)> pumpOfflineApp(
    WidgetTester tester, {
    CachedLeaderboard? cachedBoard,
  }) async {
    final content = await buildTestContentRepository();
    final db = await openMemoryDatabase();
    addTearDown(db.database.close);
    final connectivity = FakeConnectivityService(online: false);
    addTearDown(connectivity.dispose);

    if (cachedBoard != null) {
      final cache = LeaderboardCache(
        database: db.database,
        integrity: db.integrity,
        reporter: db.reporter,
      );
      await cache.write(cachedBoard);
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(AppConfig.dev()),
          appDatabaseProvider.overrideWithValue(db.database),
          contentRepositoryProvider.overrideWith((ref) => content),
          connectivityServiceProvider.overrideWithValue(connectivity),
          // The binding a player has in airplane mode AND on an unconfigured
          // build: every submission answers transient, so the queue holds.
          syncApiProvider.overrideWithValue(const NoopSyncApi()),
          ...fakeMetaOverrides(),
        ],
        child: const WordSearchMasterApp(),
      ),
    );
    await tester.pumpAndSettle();
    return (db, connectivity);
  }

  Future<void> goTo(WidgetTester tester, String location) async {
    final context = tester.element(find.byType(Navigator).first);
    GoRouter.of(context).go(location);
    await tester.pumpAndSettle();
  }

  testWidgets('a whole offline session never interrupts the player', (
    tester,
  ) async {
    await pumpOfflineApp(tester);
    expectNoInterruption(tester, 'the language screen');

    // Picking a language routes straight into level 1 (P12's FTUE).
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expectNoInterruption(tester, 'level 1');

    for (final route in [
      const HomeRoute().location,
      const JourneyRoute().location,
      const DailyRoute().location,
      const LeaderboardRoute().location,
      const ProfileRoute().location,
      const SettingsRoute().location,
    ]) {
      await goTo(tester, route);
      expectNoInterruption(tester, route);
    }
  });

  testWidgets('coming back online does not interrupt either', (tester) async {
    // The other half of the rule: a "you are back online" toast would be just
    // as unwanted as the one announcing the loss.
    final (_, connectivity) = await pumpOfflineApp(tester);
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    connectivity.setOnline(true);
    await tester.pumpAndSettle();
    expectNoInterruption(tester, 'reconnecting');

    connectivity.setOnline(false);
    await tester.pumpAndSettle();
    expectNoInterruption(tester, 'disconnecting again');
  });

  testWidgets('the home screen shows a small static indicator instead', (
    tester,
  ) async {
    final (_, connectivity) = await pumpOfflineApp(tester);
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    await goTo(tester, const HomeRoute().location);

    // Present, and it is an icon — not a button, not a banner.
    expect(find.byType(SyncStatusIndicator), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
    expectNoInterruption(tester, 'the home screen');

    // Its footprint is IDENTICAL online, so nothing beside it reflows.
    final offlineSize = tester.getSize(find.byType(SyncStatusIndicator).first);
    connectivity.setOnline(true);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.cloud_off_outlined), findsNothing);
    expect(
      tester.getSize(find.byType(SyncStatusIndicator).first),
      offlineSize,
      reason: 'the indicator reserves its space in both states',
    );
  });

  testWidgets('the leaderboard shows its cached copy and when it was saved', (
    tester,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await pumpOfflineApp(
      tester,
      cachedBoard: CachedLeaderboard(
        board: 'global',
        fetchedAtMillis: now - const Duration(minutes: 5).inMilliseconds,
        entries: const [
          LeaderboardEntry(uid: 'a', displayName: 'Ayesha', score: 1560),
          LeaderboardEntry(uid: 'b', displayName: 'Rahul', score: 980),
        ],
      ),
    );
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    await goTo(tester, const LeaderboardRoute().location);

    // Cached data, not an empty state and not a spinner.
    expect(find.text('Ayesha'), findsOneWidget);
    expect(find.text('1560'), findsOneWidget);

    // A relative staleness stamp, so showing yesterday's board is honest.
    expect(find.textContaining('5 minutes ago'), findsOneWidget);

    // And the offline note, which is a line of text — never a dialog.
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.leaderboardOfflineNote), findsOneWidget);
    expectNoInterruption(tester, 'the leaderboard');
  });

  testWidgets('an empty leaderboard is a sentence, not an error', (
    tester,
  ) async {
    await pumpOfflineApp(tester);
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    await goTo(tester, const LeaderboardRoute().location);

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.leaderboardEmpty), findsOneWidget);
    // No retry button: there is nothing for the player to retry, and offering
    // one would imply the empty board is their problem to solve.
    expect(find.byType(ElevatedButton), findsNothing);
    expectNoInterruption(tester, 'an empty leaderboard');
  });
}
