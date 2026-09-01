import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/app/theme/app_theme.dart';
import 'package:word_search_master/data/remote/friends_api.dart';
import 'package:word_search_master/l10n/app_localizations.dart';
import 'package:word_search_master/presentation/meta/friends_tab.dart';
import 'package:word_search_master/services/auth/auth_service.dart';

/// P17's third acceptance criterion, from the client side: "friends invite
/// code se kaam karta hai" — entering a code the fake server accepts ends in
/// the success copy, and every rejection path the server can return
/// (`functions/src/friends.ts`'s `RedeemOutcome`) reaches its own message
/// rather than a generic failure.
void main() {
  Widget wrap(FriendsApi api) => ProviderScope(
    overrides: [
      friendsApiProvider.overrideWithValue(api),
      authServiceProvider.overrideWithValue(
        const _FakeAuth(AuthAccount(uid: 'me', isAnonymous: true)),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: FriendsTab()),
    ),
  );

  testWidgets('shows the invite code once it resolves', (tester) async {
    await tester.pumpWidget(wrap(const _FakeFriendsApi(code: 'ABCD2345')));
    await tester.pump();

    expect(find.text('ABCD2345'), findsOneWidget);
  });

  testWidgets('an empty friends list shows the empty-state copy', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const _FakeFriendsApi()));
    await tester.pump();
    await tester.pump();

    expect(
      find.text("No friends yet — share your code to add one"),
      findsOneWidget,
    );
  });

  testWidgets('accepted friends render in the list', (tester) async {
    await tester.pumpWidget(
      wrap(
        const _FakeFriendsApi(
          friends: [FriendEntry(uid: 'f1', displayName: 'Ayesha')],
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Ayesha'), findsOneWidget);
  });

  testWidgets('redeeming a code that works shows the success message', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(const _FakeFriendsApi(outcome: RedeemFriended('them'))),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'WXYZ6789');
    await tester.tap(find.text('Add friend'));
    await tester.pump();
    await tester.pump();

    expect(find.text("You're now friends!"), findsOneWidget);
  });

  testWidgets('a code the server has never seen reports not-found', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(const _FakeFriendsApi(outcome: RedeemNotFound())),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'NOPE0000');
    await tester.tap(find.text('Add friend'));
    await tester.pump();
    await tester.pump();

    expect(find.text("That code doesn't match anyone"), findsOneWidget);
  });

  testWidgets('a network failure reports the generic try-again message', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(const _FakeFriendsApi(outcome: RedeemFailed('offline'))),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'AAAA1111');
    await tester.tap(find.text('Add friend'));
    await tester.pump();
    await tester.pump();

    expect(find.text("Couldn't add that friend — try again"), findsOneWidget);
  });
}

final class _FakeAuth implements AuthService {
  const _FakeAuth(this._account);

  final AuthAccount? _account;

  @override
  AuthAccount? get currentAccount => _account;

  @override
  Stream<AuthAccount?> watchAccount() =>
      _account == null ? const Stream.empty() : Stream.value(_account);

  @override
  Future<AuthAccount?> ensureSignedIn() async => _account;

  @override
  Future<LinkOutcome> linkWithGoogle() async => const LinkCancelled();

  @override
  Future<AuthAccount?> signOut() async => _account;
}

final class _FakeFriendsApi implements FriendsApi {
  const _FakeFriendsApi({
    this.code = 'AAAABBBB',
    this.friends = const [],
    this.outcome = const RedeemFailed('unset'),
  });

  final String code;
  final List<FriendEntry> friends;
  final RedeemOutcome outcome;

  @override
  Stream<List<FriendEntry>> watchFriends(String uid) => Stream.value(friends);

  @override
  Future<String?> createInviteCode() async => code;

  @override
  Future<RedeemOutcome> redeemInviteCode(String code) async => outcome;
}
