import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/app/config/app_config.dart';
import 'package:word_search_master/app/theme/app_theme.dart';
import 'package:word_search_master/data/local/app_database.dart';
import 'package:word_search_master/data/remote/leaderboard_api.dart';
import 'package:word_search_master/data/remote/name_report_api.dart';
import 'package:word_search_master/data/repositories/leaderboard_cache.dart';
import 'package:word_search_master/l10n/app_localizations.dart';
import 'package:word_search_master/presentation/screens/leaderboard_screen.dart';
import 'package:word_search_master/services/auth/auth_service.dart';
import 'package:word_search_master/services/connectivity/connectivity_service.dart';

import '../../support/local_db.dart';

/// The two literal P17 acceptance criteria that touch the CLIENT (the third,
/// "friends invite code se kaam karta hai", is covered by
/// `friends_tab_test.dart`):
///
///  - a rank outside the top 100 still shows correctly, via the pinned row
///  - leaving a tab detaches ITS snapshot listener — proven here by counting
///    active subscriptions on a fake [LeaderboardApi], not by inspecting
///    Riverpod internals, so the test fails the same way a real Firestore
///    bill-surprise would: a listener nobody is reading from anymore.
void main() {
  Widget wrap({
    required LeaderboardApi api,
    required AppDatabase database,
    String? uid,
    NameReportApi? nameReportApi,
  }) => ProviderScope(
    overrides: [
      appConfigProvider.overrideWithValue(AppConfig.dev()),
      leaderboardApiProvider.overrideWithValue(api),
      appDatabaseProvider.overrideWithValue(database),
      authServiceProvider.overrideWithValue(_FakeAuth(uid)),
      connectivityServiceProvider.overrideWithValue(
        const AssumeOnlineConnectivityService(),
      ),
      if (nameReportApi != null)
        nameReportApiProvider.overrideWithValue(nameReportApi),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const LeaderboardScreen(),
    ),
  );

  testWidgets('switching tabs detaches the previous tab\'s listener', (
    tester,
  ) async {
    final db = await openMemoryDatabase();
    addTearDown(db.database.close);
    final api = _CountingLeaderboardApi();

    await tester.pumpWidget(wrap(api: api, database: db.database));
    await tester.pump();

    expect(api.activeListeners['global'], 1);
    expect(api.activeListeners['ur'], anyOf(isNull, 0));

    // The Urdu endonym is the tab's own label (CLAUDE.md: language names are
    // never localized) — see `_TabStrip`.
    await tester.tap(find.text('اردو'));
    await tester.pump();
    // One microtask turn for the old provider's autoDispose to actually run
    // — Riverpod tears a provider down asynchronously after its last
    // listener is removed, not synchronously inside the same frame.
    await tester.pump();

    expect(
      api.activeListeners['global'],
      0,
      reason: 'the Global tab is no longer visible; its listener must close',
    );
    expect(api.activeListeners['ur'], 1);
  });

  testWidgets('a rank outside the top 100 still shows, pinned at the bottom', (
    tester,
  ) async {
    final db = await openMemoryDatabase();
    addTearDown(db.database.close);
    // 100 entries, none of them "me" — the exact shape of "outside the top
    // 100" the acceptance criterion names.
    final top100 = [
      for (var i = 0; i < 100; i++)
        LeaderboardEntry(uid: 'p$i', score: 1000 - i, displayName: 'P$i'),
    ];
    final api = _CountingLeaderboardApi(
      seed: {'global': top100},
      ownEntries: {
        'global': const LeaderboardEntry(uid: 'me', score: 5, rank: 4213),
      },
    );

    await tester.pumpWidget(wrap(api: api, database: db.database, uid: 'me'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Your rank: 4213'), findsOneWidget);
  });

  testWidgets('the report action is hidden on the player\'s own row', (
    tester,
  ) async {
    final db = await openMemoryDatabase();
    addTearDown(db.database.close);
    final api = _CountingLeaderboardApi(
      seed: {
        'global': const [
          LeaderboardEntry(uid: 'me', score: 10, displayName: 'Me'),
        ],
      },
    );

    await tester.pumpWidget(wrap(api: api, database: db.database, uid: 'me'));
    await tester.pump();
    await tester.pump();

    expect(find.byIcon(Icons.flag_outlined), findsNothing);
  });

  testWidgets(
    'reporting a name asks for confirmation, then submits the report',
    (tester) async {
      final db = await openMemoryDatabase();
      addTearDown(db.database.close);
      final api = _CountingLeaderboardApi(
        seed: {
          'global': const [
            LeaderboardEntry(uid: 'rival', score: 99, displayName: 'Rival'),
          ],
        },
      );
      final reports = _FakeNameReportApi();

      await tester.pumpWidget(
        wrap(
          api: api,
          database: db.database,
          uid: 'me',
          nameReportApi: reports,
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byIcon(Icons.flag_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Report this name?'), findsOneWidget);

      // Cancelling must not submit anything — the confirm step exists
      // precisely so an accidental tap cannot report someone.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(reports.calls, isEmpty);

      await tester.tap(find.byIcon(Icons.flag_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report'));
      await tester.pumpAndSettle();

      expect(reports.calls, [(reporterUid: 'me', reportedUid: 'rival')]);
      expect(find.text("Thanks — your report was sent."), findsOneWidget);
    },
  );
}

final class _FakeAuth implements AuthService {
  const _FakeAuth(this._uid);

  final String? _uid;

  @override
  AuthAccount? get currentAccount =>
      _uid == null ? null : AuthAccount(uid: _uid, isAnonymous: true);

  @override
  Stream<AuthAccount?> watchAccount() =>
      _uid == null ? const Stream.empty() : Stream.value(currentAccount);

  @override
  Future<AuthAccount?> ensureSignedIn() async => currentAccount;

  @override
  Future<LinkOutcome> linkWithGoogle() async => const LinkCancelled();

  @override
  String? get lastGoogleSignInDiagnostic => null;

  @override
  Future<AuthAccount?> signOut() async => currentAccount;
}

final class _CountingLeaderboardApi implements LeaderboardApi {
  _CountingLeaderboardApi({
    Map<String, List<LeaderboardEntry>>? seed,
    Map<String, LeaderboardEntry>? ownEntries,
  }) : _seed = seed ?? const {},
       _ownEntries = ownEntries ?? const {};

  final Map<String, List<LeaderboardEntry>> _seed;
  final Map<String, LeaderboardEntry> _ownEntries;

  /// How many live subscriptions are open right now, per board.
  final Map<String, int> activeListeners = {};

  @override
  Stream<List<LeaderboardEntry>> watchTop(String board, {int limit = 100}) {
    late final StreamController<List<LeaderboardEntry>> controller;
    controller = StreamController<List<LeaderboardEntry>>(
      onListen: () {
        activeListeners[board] = (activeListeners[board] ?? 0) + 1;
        controller.add(_seed[board] ?? const []);
      },
      onCancel: () {
        activeListeners[board] = (activeListeners[board] ?? 1) - 1;
      },
    );
    return controller.stream;
  }

  @override
  Future<LeaderboardEntry?> fetchOwnEntry(String uid, String board) async =>
      _ownEntries[board];
}

final class _FakeNameReportApi implements NameReportApi {
  final List<({String reporterUid, String reportedUid})> calls = [];

  @override
  Future<bool> reportDisplayName({
    required String reporterUid,
    required String reportedUid,
  }) async {
    calls.add((reporterUid: reporterUid, reportedUid: reportedUid));
    return true;
  }
}
