import 'package:firebase_messaging/firebase_messaging.dart';

import '../diagnostics/error_reporter.dart';
import 'notification_service.dart';

/// The real [NotificationService], over `firebase_messaging`.
///
/// EVERY METHOD SWALLOWS ITS FAILURE — the same policy
/// `firebase_auth_service.dart`'s header states and every method here keeps:
/// a player with no signal, a platform with no notification support, or a
/// permission the OS refuses to even ask about again must all still get a
/// fully playable game back, never an exception.
final class FirebaseNotificationService implements NotificationService {
  FirebaseNotificationService({
    required FirebaseMessaging messaging,
    required ErrorReporter reporter,
    // ignore: prefer_initializing_formals
  }) : _messaging = messaging,
       // ignore: prefer_initializing_formals
       _reporter = reporter;

  final FirebaseMessaging _messaging;
  final ErrorReporter _reporter;

  @override
  Future<bool> requestPermission() async {
    try {
      final settings = await _messaging.requestPermission();
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (error, stackTrace) {
      _reporter.nonFatal(
        error,
        stackTrace: stackTrace,
        context: const {'stage': 'notifications.requestPermission'},
      );
      return false;
    }
  }

  @override
  Future<String?> getToken() async {
    try {
      return await _messaging.getToken();
    } catch (error, stackTrace) {
      _reporter.nonFatal(
        error,
        stackTrace: stackTrace,
        context: const {'stage': 'notifications.getToken'},
      );
      return null;
    }
  }

  @override
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh.handleError((
    Object error,
    StackTrace stackTrace,
  ) {
    _reporter.nonFatal(
      error,
      stackTrace: stackTrace,
      context: const {'stage': 'notifications.onTokenRefresh'},
    );
  });
}
