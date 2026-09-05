/// Registers this device's push-notification token and language preference
/// on the player's own `users/{uid}` document (post-P17).
///
/// A thin writer, same shape as `NameReportApi` — one method, no read path,
/// because nothing client-side ever needs its own registration back.
/// `firestore.rules` is what actually shapes this write (`fcmToken`/
/// `language` joined `profileFields()` for exactly this); this interface
/// just keeps `cloud_firestore` out of every file that wants to call it.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'notification_registration_api.g.dart';

abstract interface class NotificationRegistrationApi {
  /// Merges [fcmToken] (null clears it) and [language] onto `users/{uid}`.
  ///
  /// Never throws — a failed registration degrades to "no push reaches this
  /// device today," not a player-visible error, matching the "never block on
  /// a network call" posture every other write in this app takes.
  Future<void> register({
    required String uid,
    required String? fcmToken,
    required String language,
  });
}

/// No registration, ever. The binding whenever Firebase is unavailable.
final class NoopNotificationRegistrationApi
    implements NotificationRegistrationApi {
  const NoopNotificationRegistrationApi();

  @override
  Future<void> register({
    required String uid,
    required String? fcmToken,
    required String language,
  }) async {}
}

/// Defaults to Noop; `bootstrap.dart` upgrades it once Firebase initialises.
@Riverpod(keepAlive: true)
NotificationRegistrationApi notificationRegistrationApi(Ref ref) =>
    const NoopNotificationRegistrationApi();
