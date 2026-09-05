/// Keeps this device's push-registration on `users/{uid}` in step with the
/// signed-in account, the selected language, and FCM's own token rotation
/// (post-P17 re-engagement pushes).
///
/// A listener, not a direct call beside `ref.watch` — the same shape
/// `audioMuteSync`/`musicSync` (`services/audio/audio_service.dart`) already
/// use, because a provider's `build` is supposed to stay free of side
/// effects. Watched once, at the app root, alongside those two.
///
/// Registration is silent and asks nothing of the player: [NotificationService
/// .getToken] does not itself prompt for permission on Android (only
/// [NotificationService.requestPermission] does, called separately once a
/// streak exists worth protecting — see `HomeScreen`'s own doc), so this
/// keeps the server's copy of "which device, which language" current whether
/// or not the player has ever seen — let alone answered — the OS prompt.
library;

import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../app/language/selected_language.dart';
import '../data/remote/notification_registration_api.dart';
import '../services/auth/auth_service.dart';
import '../services/notifications/notification_service.dart';

part 'notification_sync.g.dart';

@Riverpod(keepAlive: true)
void notificationRegistrationSync(Ref ref) {
  Future<void> register() async {
    final uid = ref.read(currentAccountProvider).value?.uid;
    if (uid == null) return;
    final language = ref.read(selectedLanguageProvider).code;
    final token = await ref.read(notificationServiceProvider).getToken();
    await ref
        .read(notificationRegistrationApiProvider)
        .register(uid: uid, fcmToken: token, language: language);
  }

  // Re-registers whenever the account resolves (guest → linked, sign-out →
  // fresh guest) or the player switches language — `fireImmediately` on the
  // account listener is what covers the ordinary cold start, where an
  // account already exists by the time this provider is first watched.
  ref.listen(currentAccountProvider, (_, _) {
    unawaited(register());
  }, fireImmediately: true);
  ref.listen(selectedLanguageProvider, (_, _) {
    unawaited(register());
  });

  final sub = ref.watch(notificationServiceProvider).onTokenRefresh.listen((_) {
    unawaited(register());
  });
  ref.onDispose(sub.cancel);
}
