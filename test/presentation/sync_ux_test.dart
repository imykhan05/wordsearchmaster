import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/app/theme/theme.dart';
import 'package:word_search_master/l10n/app_localizations.dart';
import 'package:word_search_master/presentation/widgets/sync_status.dart';
import 'package:word_search_master/services/connectivity/connectivity_service.dart';

import '../application/sync_worker_test.dart' show FakeConnectivityService;

/// Ch10's two remaining UX rules, measured rather than eyeballed:
/// a rewarded button that DISABLES IN PLACE, and a relative "last updated".
void main() {
  Future<FakeConnectivityService> pump(
    WidgetTester tester,
    Widget child, {
    bool online = true,
  }) async {
    final connectivity = FakeConnectivityService(online: online);
    addTearDown(connectivity.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectivityServiceProvider.overrideWithValue(connectivity),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          home: Scaffold(body: Center(child: child)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return connectivity;
  }

  group('a rewarded button disables in place', () {
    testWidgets('the rectangle is IDENTICAL online and offline', (
      tester,
    ) async {
      // The rule exists because of a finger already moving: a player reaches
      // for "double your coins" the instant the card settles, and a button
      // that vanishes lets that tap land on whatever reflows into its place.
      final connectivity = await pump(
        tester,
        RewardedActionButton(label: 'Double reward', onPressed: () {}),
      );
      final onlineRect = tester.getRect(find.byType(OutlinedButton));
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNotNull,
      );

      connectivity.setOnline(false);
      await tester.pumpAndSettle();

      expect(
        find.byType(OutlinedButton),
        findsOneWidget,
        reason: 'still there',
      );
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
        reason: 'but not tappable — an ad cannot be shown offline',
      );
      expect(
        tester.getRect(find.byType(OutlinedButton)),
        onlineRect,
        reason: 'and it occupies exactly the same space',
      );
    });

    testWidgets('the label and icon stay, so the width cannot change', (
      tester,
    ) async {
      final connectivity = await pump(
        tester,
        RewardedActionButton(label: 'Double reward', onPressed: () {}),
      );
      connectivity.setOnline(false);
      await tester.pumpAndSettle();

      expect(find.text('Double reward'), findsOneWidget);
      expect(find.byType(Icon), findsOneWidget);
    });

    testWidgets('a null callback disables it even while online', (
      tester,
    ) async {
      // The P18 case: the ad unit is not wired yet. Same rectangle either way.
      await pump(tester, const RewardedActionButton(label: 'Double reward'));
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
    });

    testWidgets('tapping it offline does nothing at all — no dialog', (
      tester,
    ) async {
      var taps = 0;
      final connectivity = await pump(
        tester,
        RewardedActionButton(label: 'Double reward', onPressed: () => taps++),
      );
      connectivity.setOnline(false);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(OutlinedButton));
      await tester.pumpAndSettle();

      expect(taps, 0);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('the last-updated label', () {
    final base = DateTime.utc(2026, 9, 1, 12);

    Future<void> pumpAt(WidgetTester tester, Duration ago) => pump(
      tester,
      LastUpdatedLabel(
        timestampMillis: base.subtract(ago).millisecondsSinceEpoch,
        now: base,
      ),
    );

    testWidgets('reads "just now" under a minute', (tester) async {
      await pumpAt(tester, const Duration(seconds: 40));
      expect(find.textContaining('just now'), findsOneWidget);
    });

    testWidgets('counts minutes, then hours, then days', (tester) async {
      await pumpAt(tester, const Duration(minutes: 5));
      expect(find.textContaining('5 minutes ago'), findsOneWidget);

      await pumpAt(tester, const Duration(hours: 3));
      expect(find.textContaining('3 hours ago'), findsOneWidget);

      await pumpAt(tester, const Duration(days: 3));
      expect(find.textContaining('3 days ago'), findsOneWidget);
    });

    testWidgets('uses the singular form at exactly one', (tester) async {
      await pumpAt(tester, const Duration(minutes: 1));
      expect(find.textContaining('1 minute ago'), findsOneWidget);
      expect(find.textContaining('1 minutes ago'), findsNothing);
    });

    testWidgets('a future timestamp reads as "just now", never negative', (
      tester,
    ) async {
      // `TrustedClock` already documents that a clock set forward offline is
      // the case it cannot prevent, so this label has to survive one.
      await pumpAt(tester, const Duration(hours: -5));
      expect(find.textContaining('just now'), findsOneWidget);
      expect(find.textContaining('-'), findsNothing);
    });

    testWidgets('coarsens rather than compounding units', (tester) async {
      // "3 days ago" and "3 days and 4 hours ago" answer the same question,
      // and the second invites the player to wonder what the extra means.
      await pumpAt(tester, const Duration(days: 3, hours: 4));
      expect(find.textContaining('3 days ago'), findsOneWidget);
      expect(find.textContaining('hours'), findsNothing);
    });
  });

  group('the offline indicator', () {
    testWidgets('is an icon offline and empty space online', (tester) async {
      final connectivity = await pump(
        tester,
        const SyncStatusIndicator(),
        online: false,
      );
      expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
      final offline = tester.getSize(find.byType(SyncStatusIndicator));

      connectivity.setOnline(true);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.cloud_off_outlined), findsNothing);
      expect(tester.getSize(find.byType(SyncStatusIndicator)), offline);
    });

    testWidgets('is not a button — there is nothing for a tap to do', (
      tester,
    ) async {
      await pump(tester, const SyncStatusIndicator(), online: false);
      expect(find.byType(ElevatedButton), findsNothing);
      expect(find.byType(TextButton), findsNothing);
      expect(find.byType(IconButton), findsNothing);
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('carries a semantics label so it is not silent to a reader', (
      tester,
    ) async {
      await pump(tester, const SyncStatusIndicator(), online: false);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.bySemanticsLabel(l10n.offlineIndicatorLabel), findsOneWidget);
    });
  });
}
