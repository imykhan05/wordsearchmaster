/// A thin wrap over `firebase_messaging` (post-P17 re-engagement pushes).
///
/// Same containment rule every other vendor SDK in this codebase follows —
/// `max_ad_gateway.dart` for AppLovin, `audio_service.dart` for
/// `audioplayers`, `firebase_auth_service.dart` for Firebase Auth: nothing
/// outside `services/notifications/` may import `package:firebase_messaging`.
///
/// This interface only wraps the DEVICE half — asking for permission, and
/// reading the token that identifies this install. What the server does with
/// that token (`sendStreakReminders`, `functions/src/streakReminders.ts`) has
/// nothing to do with this file; the seam here is purely "can this app reach
/// this device," matching `AuthService`'s own separation from
/// `AccountMergeRepository`.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'notification_service.g.dart';

abstract interface class NotificationService {
  /// Shows the OS permission prompt if it has not been answered yet, and
  /// returns whether notifications are authorized afterward.
  ///
  /// Never throws — a player who denies, or a platform that cannot ask at
  /// all, both resolve to `false` rather than an exception reaching the
  /// caller. Idempotent: calling this after the OS has already recorded an
  /// answer does not re-prompt.
  Future<bool> requestPermission();

  /// This installation's current FCM registration token, or null if one
  /// could not be obtained. Available independently of [requestPermission]
  /// on Android — a token identifies the install; the permission only gates
  /// whether a notification is actually shown for it.
  Future<String?> getToken();

  /// Emits a new token whenever the platform rotates one, so a long-lived
  /// install's registration does not silently go stale.
  Stream<String> get onTokenRefresh;
}

/// No permission, no token, ever. The binding whenever Firebase is
/// unavailable — the same degradation as every other Firebase-backed service.
final class NoopNotificationService implements NotificationService {
  const NoopNotificationService();

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<String?> getToken() async => null;

  @override
  Stream<String> get onTokenRefresh => const Stream.empty();
}

/// Defaults to Noop; `bootstrap.dart` upgrades it once Firebase initialises.
@Riverpod(keepAlive: true)
NotificationService notificationService(Ref ref) =>
    const NoopNotificationService();
