/// The Friends tab's data + actions (P17).
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/remote/friends_api.dart';
import '../services/auth/auth_service.dart';

part 'friends_controller.g.dart';

/// LIVE, the same "only while the tab is visible" rule
/// `leaderboardTopProvider` follows — plain `@riverpod`, no `keepAlive`, so
/// leaving the Friends tab tears this down and closes the underlying
/// Firestore listener.
@riverpod
Stream<List<FriendEntry>> friendsList(Ref ref) {
  final uid = ref.watch(currentAccountProvider).value?.uid;
  if (uid == null) return const Stream.empty();
  return ref.watch(friendsApiProvider).watchFriends(uid);
}

/// The player's own invite code, minted on first read — `createInviteCode`
/// is idempotent server-side (`getOrCreateInviteCode`), so re-watching this
/// on every visit to the tab never mints a second one.
@riverpod
Future<String?> ownInviteCode(Ref ref) =>
    ref.watch(friendsApiProvider).createInviteCode();

/// Redeeming a code is an ACTION, not a value — a plain pass-through to
/// [FriendsApi.redeemInviteCode] so the widget has something to `ref.read`
/// without holding its own `FriendsApi` reference.
@riverpod
class FriendRedeemer extends _$FriendRedeemer {
  @override
  void build() {}

  Future<RedeemOutcome> redeem(String code) =>
      ref.read(friendsApiProvider).redeemInviteCode(code);
}
