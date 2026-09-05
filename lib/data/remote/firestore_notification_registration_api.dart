import 'package:cloud_firestore/cloud_firestore.dart';

import '../../services/diagnostics/error_reporter.dart';
import 'notification_registration_api.dart';

/// The real [NotificationRegistrationApi]. A bare merge-write onto the
/// caller's own `users/{uid}` — `firestore.rules` refuses this write for any
/// uid other than the signed-in caller's own.
final class FirestoreNotificationRegistrationApi
    implements NotificationRegistrationApi {
  const FirestoreNotificationRegistrationApi({
    required FirebaseFirestore firestore,
    required ErrorReporter reporter,
    // ignore: prefer_initializing_formals
  }) : _firestore = firestore,
       // ignore: prefer_initializing_formals
       _reporter = reporter;

  final FirebaseFirestore _firestore;
  final ErrorReporter _reporter;

  @override
  Future<void> register({
    required String uid,
    required String? fcmToken,
    required String language,
  }) async {
    try {
      await _firestore.collection('users').doc(uid).set({
        'fcmToken': fcmToken,
        'language': language,
      }, SetOptions(merge: true));
    } catch (error, stackTrace) {
      _reporter.nonFatal(
        error,
        stackTrace: stackTrace,
        context: const {'stage': 'notificationRegistration.register'},
      );
    }
  }
}
