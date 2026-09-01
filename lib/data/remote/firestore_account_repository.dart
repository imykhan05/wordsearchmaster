import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/progression/account_merge.dart';
import '../../services/diagnostics/error_reporter.dart';
import 'cloud_account_repository.dart';

/// The real [CloudAccountRepository]. One of a small, deliberate set of files
/// allowed to import `cloud_firestore` directly — alongside
/// `firestore_user_stats_api.dart`, `firestore_leaderboard_api.dart` and
/// `firestore_friends_api.dart` (P17) — each reading a narrow, named slice of
/// `users/{uid}` or `leaderboards/*` rather than a general-purpose client
/// anything else in the app reaches for.
///
/// One document read per merge — see `cloud_account_repository.dart`'s header
/// for why the shape is flat rather than a per-level subcollection, and for
/// what P14 owns instead.
final class FirestoreAccountRepository implements CloudAccountRepository {
  const FirestoreAccountRepository({
    required FirebaseFirestore firestore,
    required ErrorReporter reporter,
    // ignore: prefer_initializing_formals
  }) : _firestore = firestore,
       // ignore: prefer_initializing_formals
       _reporter = reporter;

  final FirebaseFirestore _firestore;
  final ErrorReporter _reporter;

  /// The collection the merge reads from. P14 owns the rules that guard it;
  /// they must scope every document to `request.auth.uid == uid`, since a
  /// readable neighbour document is a readable neighbour's progress.
  static const String collection = 'users';

  @override
  Future<AccountSnapshot> readSnapshot(String uid) async {
    try {
      final doc = await _firestore
          .collection(collection)
          .doc(uid)
          .get(
            // The merge wants the SERVER's copy: a cached document could be this
            // device's own stale write, which would merge the account with itself
            // and quietly skip whatever the other device had.
            const GetOptions(source: Source.server),
          );
      return CloudAccountCodec.decode(doc.data());
    } catch (error, stackTrace) {
      // Offline, permission-denied, App Check refused — all end the same way:
      // an empty remote, which `AccountMerge` treats as a no-op. The player
      // keeps everything local, which is the safe direction (Ch02: never
      // wipe; if merging fails, keep local data and retry).
      _reporter.nonFatal(
        error,
        stackTrace: stackTrace,
        context: const {'stage': 'cloudAccount.readSnapshot'},
      );
      return AccountSnapshot.empty;
    }
  }
}
