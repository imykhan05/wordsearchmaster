import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../services/diagnostics/error_reporter.dart';
import 'friends_api.dart';

/// The real [FriendsApi]. Reads `users/{uid}/friends` directly (rules allow
/// `get`/`list` to the owner) and calls the two P17 callables for everything
/// that writes.
final class FirestoreFriendsApi implements FriendsApi {
  const FirestoreFriendsApi({
    required FirebaseFirestore firestore,
    required FirebaseFunctions functions,
    required ErrorReporter reporter,
    // ignore: prefer_initializing_formals
  }) : _firestore = firestore,
       // ignore: prefer_initializing_formals
       _functions = functions,
       // ignore: prefer_initializing_formals
       _reporter = reporter;

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final ErrorReporter _reporter;

  @override
  Stream<List<FriendEntry>> watchFriends(String uid) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('friends')
        .snapshots()
        .map(
          (snapshot) => [
            for (final doc in snapshot.docs) _decode(doc.id, doc.data()),
          ],
        )
        .handleError((Object error, StackTrace stackTrace) {
          _reporter.nonFatal(
            error,
            stackTrace: stackTrace,
            context: const {'stage': 'friends.watchFriends'},
          );
        });
  }

  @override
  Future<String?> createInviteCode() async {
    try {
      final result = await _functions
          .httpsCallable('createInviteCode')
          .call<Map<Object?, Object?>>();
      final code = result.data['code'];
      return code is String && code.isNotEmpty ? code : null;
    } catch (error, stackTrace) {
      _reporter.nonFatal(
        error,
        stackTrace: stackTrace,
        context: const {'stage': 'friends.createInviteCode'},
      );
      return null;
    }
  }

  @override
  Future<RedeemOutcome> redeemInviteCode(String code) async {
    try {
      final result = await _functions
          .httpsCallable('redeemInviteCode')
          .call<Map<Object?, Object?>>({'code': code});
      final status = result.data['status'];
      final friendUid = result.data['friendUid'];
      return switch (status) {
        'friended' when friendUid is String => RedeemFriended(friendUid),
        'alreadyFriends' when friendUid is String => RedeemAlreadyFriends(
          friendUid,
        ),
        'notFound' => const RedeemNotFound(),
        'ownCode' => const RedeemOwnCode(),
        'friendLimitReached' => const RedeemLimitReached(),
        _ => const RedeemFailed('unexpected response'),
      };
    } on FirebaseFunctionsException catch (error) {
      return RedeemFailed(error.code);
    } catch (error, stackTrace) {
      _reporter.nonFatal(
        error,
        stackTrace: stackTrace,
        context: const {'stage': 'friends.redeemInviteCode'},
      );
      return RedeemFailed('$error');
    }
  }

  static FriendEntry _decode(String uid, Map<String, Object?> data) {
    final displayName = data['displayName'];
    return FriendEntry(
      uid: uid,
      displayName: displayName is String && displayName.isNotEmpty
          ? displayName
          : null,
    );
  }
}
