import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../settings/ui_settings_store.dart';

part 'notification_settings.g.dart';

/// Whether this device wants the streak-expiring re-engagement push
/// (`sendDueStreakReminders`, post-P17).
///
/// A UI toggle, not game data — the same `UiSettingsStore` carve-out
/// [SoundEnabled] and friends already use. Turning this off does not touch
/// the OS notification permission (that stays answered, either way); it is
/// the in-app "stop sending me these specifically" switch on top of it.
/// `notificationRegistrationSync` is the one reader: it registers a null
/// `fcmToken` while this is false, which the server's own existing
/// no-token-no-push guard already handles, so no new server-side field was
/// needed for this feature.
@riverpod
class StreakRemindersEnabled extends _$StreakRemindersEnabled {
  @override
  bool build() => ref.watch(uiSettingsStoreProvider).streakRemindersEnabled;

  void toggle() => _set(!state);

  void set(bool value) => _set(value);

  /// State first, disk second: a toggle must feel instant, and a preference
  /// that fails to write is not worth blocking the UI thread over.
  void _set(bool value) {
    state = value;
    ref.read(uiSettingsStoreProvider).setStreakRemindersEnabled(value);
  }
}
