import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../audio/sound_settings.dart';

part 'haptics_service.g.dart';

/// The full Ch03 haptic map, behind an interface for the same reason
/// `AudioService` is: nothing outside `services/` calls `HapticFeedback`
/// directly, and tests get a service they can assert on.
///
/// There is deliberately NO method for a wrong selection. Ch03 is explicit —
/// "no buzz" — so the absence of a call here IS the wrong-selection spec,
/// not an oversight.
abstract interface class HapticsService {
  /// One tick per newly-reached cell while dragging. Unchanged from the
  /// `HapticFeedback.selectionClick()` `GestureLayer` already called
  /// directly pre-P09 — this just routes it through the master toggle.
  void selectionTick();

  /// 0ms of the correct-word sequence — "0ms audio + lightImpact" (Ch03).
  void wordFound();

  void levelComplete();

  void buttonTap();

  /// Master toggle. Gates every call above instantly — the next call after
  /// `setEnabled(false)` is silent, no in-flight feedback to interrupt the
  /// way `AudioService.setMuted` has to.
  void setEnabled(bool enabled);
}

/// Drops every call on the floor. Used by tests and by anything that wants
/// to assert "no haptic fired" without stubbing a platform channel.
final class NoopHapticsService implements HapticsService {
  const NoopHapticsService();

  @override
  void selectionTick() {}

  @override
  void wordFound() {}

  @override
  void levelComplete() {}

  @override
  void buttonTap() {}

  @override
  void setEnabled(bool enabled) {}
}

/// Wraps `package:flutter/services.dart`'s [HapticFeedback]. Needs no async
/// setup — unlike [AudioService], there is no asset to decode or vendor SDK
/// to initialise — so this is the provider's default binding directly,
/// rather than something `bootstrap.dart` has to remember to wire in.
final class SystemHapticsService implements HapticsService {
  bool _enabled = true;

  @override
  void selectionTick() {
    if (_enabled) HapticFeedback.selectionClick();
  }

  @override
  void wordFound() {
    if (_enabled) HapticFeedback.lightImpact();
  }

  @override
  void levelComplete() {
    if (_enabled) HapticFeedback.mediumImpact();
  }

  @override
  void buttonTap() {
    if (_enabled) HapticFeedback.selectionClick();
  }

  @override
  void setEnabled(bool enabled) {
    _enabled = enabled;
  }
}

@Riverpod(keepAlive: true)
HapticsService hapticsService(Ref ref) => SystemHapticsService();

/// Keeps [HapticsService.setEnabled] in sync with the player's haptics
/// toggle. Same `ref.listen` + `fireImmediately` shape as
/// `audio_service.dart`'s `audioMuteSync` — see that doc comment for why a
/// listener, not a direct call beside `ref.watch`, is the correct one.
///
/// Watched once, at the app root (`app.dart`).
@Riverpod(keepAlive: true)
void hapticsEnabledSync(Ref ref) {
  ref.listen<bool>(hapticsEnabledProvider, (previous, enabled) {
    ref.read(hapticsServiceProvider).setEnabled(enabled);
  }, fireImmediately: true);
}
