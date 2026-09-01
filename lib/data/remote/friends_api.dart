/// The friend graph, from the client's side (P17).
///
/// ---------------------------------------------------------------------------
/// BUILT BEFORE ANY FRIEND NOTIFICATION EXISTS
///
/// Same audit item (#11) `functions/src/friends.ts` names: this file gives the
/// UI a way to invite, redeem and list friends, and nothing here pushes,
/// badges or messages anyone about it. P20 is the prompt that may turn a
/// notification on, once this graph exists to notify about.
///
/// ---------------------------------------------------------------------------
/// REDEMPTION IS SERVER-ONLY, AND THIS INTERFACE REFLECTS THAT
///
/// There is no `addFriend(uid)` here — `firestore.rules` denies every client
/// write to `users/{uid}/friends` (P17's rules tests prove it), because a
/// mutual friendship has to be written on BOTH sides atomically, which only
/// the `redeemInviteCode`/`createInviteCode` callables (`functions/src/
/// friends.ts`) can do. This file only ever READS the graph and forwards a
/// redemption attempt to the server that owns it.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'friends_api.g.dart';

/// One accepted friend, as `users/{uid}/friends/{friendUid}` stores it.
final class FriendEntry {
  const FriendEntry({required this.uid, this.displayName});

  final String uid;
  final String? displayName;

  @override
  bool operator ==(Object other) =>
      other is FriendEntry &&
      other.uid == uid &&
      other.displayName == displayName;

  @override
  int get hashCode => Object.hash(uid, displayName);

  @override
  String toString() => 'FriendEntry($uid, $displayName)';
}

/// What happened when a code was redeemed — mirrors
/// `functions/src/friends.ts`'s `RedeemOutcome` exactly, plus [RedeemFailed]
/// for everything that never reached the server (offline, a thrown
/// `FirebaseFunctionsException`).
sealed class RedeemOutcome {
  const RedeemOutcome();
}

final class RedeemFriended extends RedeemOutcome {
  const RedeemFriended(this.friendUid);
  final String friendUid;
}

final class RedeemAlreadyFriends extends RedeemOutcome {
  const RedeemAlreadyFriends(this.friendUid);
  final String friendUid;
}

final class RedeemNotFound extends RedeemOutcome {
  const RedeemNotFound();
}

final class RedeemOwnCode extends RedeemOutcome {
  const RedeemOwnCode();
}

final class RedeemLimitReached extends RedeemOutcome {
  const RedeemLimitReached();
}

final class RedeemFailed extends RedeemOutcome {
  const RedeemFailed(this.reason);
  final String reason;
}

abstract interface class FriendsApi {
  /// LIVE, the same "only while the Friends tab is visible" rule the
  /// leaderboard tabs follow (`LeaderboardApi.watchTop`'s own header) — an
  /// `autoDispose` family provider is what actually closes it.
  Stream<List<FriendEntry>> watchFriends(String uid);

  /// The caller's own invite code, minting one on first call. Null when it
  /// could not be reached — never a thrown exception into a share-sheet tap.
  Future<String?> createInviteCode();

  /// Redeems [code] via the server. Never throws; a network failure or an
  /// unexpected server error both come back as [RedeemFailed].
  Future<RedeemOutcome> redeemInviteCode(String code);
}

/// No graph, ever. The binding whenever Firebase is unavailable.
final class NoopFriendsApi implements FriendsApi {
  const NoopFriendsApi();

  @override
  Stream<List<FriendEntry>> watchFriends(String uid) => const Stream.empty();

  @override
  Future<String?> createInviteCode() async => null;

  @override
  Future<RedeemOutcome> redeemInviteCode(String code) async =>
      const RedeemFailed('no backend configured');
}

/// Defaults to Noop; `bootstrap.dart` upgrades it once Firebase initialises.
@Riverpod(keepAlive: true)
FriendsApi friendsApi(Ref ref) => const NoopFriendsApi();
