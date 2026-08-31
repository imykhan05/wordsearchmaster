import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/app/app_route.dart';
import 'package:word_search_master/app/config/app_config.dart';
import 'package:word_search_master/app/router.dart';
import 'package:word_search_master/app/theme/theme.dart';
import 'package:word_search_master/application/sync_controller.dart';
import 'package:word_search_master/data/local/app_database.dart';
import 'package:word_search_master/data/remote/sync_api.dart';
import 'package:word_search_master/data/repositories/outbox_repository.dart';
import 'package:word_search_master/data/repositories/progress_repository.dart';
import 'package:word_search_master/domain/scoring/score_event.dart';
import 'package:word_search_master/domain/sync/outbox_status.dart';
import 'package:word_search_master/domain/text/language.dart';
import 'package:word_search_master/l10n/app_localizations.dart';
import 'package:word_search_master/presentation/screens/sync_inspector_screen.dart';
import 'package:word_search_master/services/connectivity/connectivity_service.dart';

import '../../application/sync_worker_test.dart'
    show FakeConnectivityService, FakeSyncApi;
import '../../support/local_db.dart';

/// P16's dev toggle: the queue, why it is stuck, and a force-drain.
///
/// The screen is the only observable surface the sync engine has — everything
/// else about it is deliberately silent — so a test that it actually renders
/// the queue is worth more here than on a screen a player would notice was
/// broken.
void main() {
  late TestDatabase db;
  late FakeSyncApi api;
  late FakeConnectivityService connectivity;
  late ProviderContainer container;

  setUp(() async {
    db = await openMemoryDatabase();
    addTearDown(db.database.close);
    api = FakeSyncApi();
    connectivity = FakeConnectivityService();
    addTearDown(connectivity.dispose);
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db.database),
        syncApiProvider.overrideWithValue(api),
        connectivityServiceProvider.overrideWithValue(connectivity),
      ],
    );
    addTearDown(container.dispose);
  });

  /// Real Drift I/O, run OUTSIDE the fake-async zone.
  ///
  /// `testWidgets` installs a `FakeAsync`, and a bare `await` on a Drift
  /// future inside the test body deadlocks: Drift schedules real timers that
  /// only fire when fake time advances, and an `await` does not advance it.
  /// `runAsync` is the escape hatch for exactly this, and it is why every
  /// database call below goes through it rather than being awaited directly.
  Future<T> real<T>(WidgetTester tester, Future<T> Function() work) async {
    final result = await tester.runAsync(work);
    return result as T;
  }

  Future<void> queueLevel(WidgetTester tester, int level) =>
      real(tester, () async {
        final repo = await container.read(progressRepositoryProvider.future);
        await repo.recordLevelComplete(
          language: Language.english,
          level: level,
          stars: 3,
          score: 156,
          hintsUsed: 0,
          events: const [WordFound(graphemeCount: 3)],
        );
      });

  Future<void> drain(WidgetTester tester) => real(
    tester,
    () => container.read(syncControllerProvider.notifier).drain(),
  );

  Future<List<OutboxRow>> rows(WidgetTester tester) =>
      real(tester, () => db.database.select(db.database.outbox).get());

  /// Settles a tree whose data arrives through REAL async.
  ///
  /// `pumpAndSettle` cannot be used anywhere in this file: the screen shows a
  /// `CircularProgressIndicator` until the outbox stream delivers, and an
  /// indeterminate spinner schedules a frame forever, so `pumpAndSettle`
  /// times out by construction rather than by accident. Alternating `pump`
  /// with a real delay lets the Drift stream actually deliver.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pump();
  }

  Future<void> pumpInspector(WidgetTester tester) async {
    // Resolve the repository and its stream BEFORE the widget builds. The
    // screen shows a `CircularProgressIndicator` while the outbox provider is
    // loading, and a running indeterminate animation means `pumpAndSettle`
    // never settles — it waits for the frame scheduler to go idle, and a
    // spinner never lets it.
    await real(tester, () => container.read(outboxRepositoryProvider.future));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          home: const SyncInspectorScreen(),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('lists every queued row with its kind and attempt count', (
    tester,
  ) async {
    await queueLevel(tester, 1);
    await queueLevel(tester, 2);
    await pumpInspector(tester);

    expect(find.textContaining('levelComplete'), findsNWidgets(2));
    expect(find.textContaining('attempts: 0'), findsNWidgets(2));
    expect(find.textContaining('next retry: now'), findsNWidgets(2));
  });

  testWidgets('shows when a backed-off row becomes eligible again', (
    tester,
  ) async {
    api.outcome = (_, _) => const SyncTransientFailure('unavailable');
    await queueLevel(tester, 1);
    await drain(tester);
    await pumpInspector(tester);

    expect(find.textContaining('attempts: 1'), findsOneWidget);
    // Step 1 of the ladder is 5s +/-20%, so it renders in seconds.
    expect(find.textContaining('next retry: '), findsOneWidget);
    expect(find.textContaining('next retry: now'), findsNothing);
  });

  testWidgets('marks a permanently failed row and offers to requeue it', (
    tester,
  ) async {
    api.outcome = (_, _) => const SyncPermanentFailure('invalid-argument');
    await queueLevel(tester, 1);
    await drain(tester);
    await pumpInspector(tester);

    expect(find.textContaining('PERMANENTLY FAILED'), findsOneWidget);

    await tester.tap(find.byTooltip('Requeue'));
    await settle(tester);

    expect(outboxStatusOf((await rows(tester)).single), OutboxStatus.pending);
  });

  // The force-drain BUTTON's handler is two calls — `clearBackoff()` then
  // `drain(force: true)` — and both are exercised as plain tests below rather
  // than through a tap. Driving them through the widget opens a second live
  // Drift stream inside the tap handler, and cancelling a Drift stream
  // schedules a cleanup timer that outlives the widget tree: the same
  // "a Timer is still pending" failure CLAUDE.md already records from P11.
  // The rendering is what the widget tests above are for; the behaviour lives
  // where it can actually be asserted.

  testWidgets('says so plainly when the queue is empty', (tester) async {
    await pumpInspector(tester);
    expect(find.text('Queue is empty'), findsOneWidget);
  });

  testWidgets('shows the connectivity state and the backoff ladder', (
    tester,
  ) async {
    await pumpInspector(tester);
    expect(find.text('ONLINE'), findsOneWidget);
    expect(
      find.textContaining('Ladder: now · 5s · 30s · 5m · 30m · 6h'),
      findsOneWidget,
    );
    expect(find.textContaining('+/-20%'), findsOneWidget);

    connectivity.setOnline(false);
    await settle(tester);
    expect(find.text('OFFLINE'), findsOneWidget);
  });

  test('force-drain clears every backoff and then sends', () async {
    // What the button's handler does, in the order it does it. Clearing
    // without draining would leave the rows eligible but unsent; draining
    // without clearing would skip every row still inside its ladder step —
    // which is exactly when a developer reaches for this button.
    api.outcome = (_, _) => const SyncTransientFailure('unavailable');
    final progress = await container.read(progressRepositoryProvider.future);
    await progress.recordLevelComplete(
      language: Language.english,
      level: 1,
      stars: 3,
      score: 156,
      hintsUsed: 0,
      events: const [WordFound(graphemeCount: 3)],
    );
    await container.read(syncControllerProvider.notifier).drain();

    final parked = (await db.database.select(db.database.outbox).get()).single;
    expect(parked.nextRetryAt, isNotNull, reason: 'parked on the ladder');

    api.outcome = (_, _) => const SyncAccepted();
    api.calls.clear();

    final outbox = await container.read(outboxRepositoryProvider.future);
    await outbox.clearBackoff();
    await container.read(syncControllerProvider.notifier).drain(force: true);

    expect(api.calls, hasLength(1));
    expect(await db.database.select(db.database.outbox).get(), isEmpty);
  });

  test('force-drain sends even while offline', () async {
    // A force button that still respected the connectivity gate would be
    // useless exactly when it is needed.
    connectivity.setOnline(false);
    final progress = await container.read(progressRepositoryProvider.future);
    await progress.recordLevelComplete(
      language: Language.english,
      level: 1,
      stars: 3,
      score: 156,
      hintsUsed: 0,
      events: const [WordFound(graphemeCount: 3)],
    );

    expect(
      (await container.read(syncControllerProvider.notifier).drain()).attempted,
      0,
    );
    await container.read(syncControllerProvider.notifier).drain(force: true);
    expect(api.calls, hasLength(1));
  });

  test('is registered ONLY on the dev flavor', () {
    // The queue is a list of everything the game knows and has not yet told
    // the server; it must never ship. Asserted through the real router rather
    // than by reading `router.dart`, so moving the `if (isDev)` guard would
    // fail here.
    for (final config in [AppConfig.dev(), AppConfig.stg(), AppConfig.prod()]) {
      final scope = ProviderContainer(
        overrides: [appConfigProvider.overrideWithValue(config)],
      );
      addTearDown(scope.dispose);

      final paths = scope
          .read(routerProvider)
          .configuration
          .routes
          .whereType<GoRoute>()
          .map((route) => route.path)
          .toSet();

      expect(
        paths.contains(const SyncInspectorRoute().location),
        config.flavor == Flavor.dev,
        reason:
            '${config.flavorName} ${config.flavor == Flavor.dev ? "must" : "must not"} '
            'expose the Sync Inspector',
      );
    }
  });
}
