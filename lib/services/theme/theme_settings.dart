import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/theme/app_theme_variant.dart';
import '../settings/ui_settings_store.dart';

part 'theme_settings.g.dart';

/// The wall clock AUTO mode reads.
///
/// Injectable for one reason: a test that wants to prove the evening palette
/// arrives at 16:00 must not have to run at 16:00. Everything else about the
/// switch — the boundary maths, the timer, the lifecycle re-check — is then
/// exercised against a clock the test moves itself.
///
/// LOCAL time, not UTC, and `AutoTheme`'s own header states why at length: a
/// streak has to mean the same thing for every player at once, a palette has
/// to match the light in one player's room.
@Riverpod(keepAlive: true)
DateTime Function() themeClock(Ref ref) => DateTime.now;

/// What the player picked in Settings — one fixed look, or AUTO.
///
/// State first, disk second, the same shape as [BackgroundStyleSetting]: a chip
/// must colour in under the finger, and a preference that fails to write is
/// not worth blocking a frame over.
@riverpod
class AppThemeSetting extends _$AppThemeSetting {
  @override
  AppThemeSelection build() => ref.watch(uiSettingsStoreProvider).appTheme;

  void set(AppThemeSelection value) {
    state = value;
    ref.read(uiSettingsStoreProvider).setAppTheme(value);
  }
}

/// The look actually on screen right now — a fixed pick, or whatever AUTO
/// resolves to at this moment.
///
/// Watched once, by `app.dart`, which builds the whole `MaterialApp` theme
/// from it.
///
/// UNDER AUTO THIS HAS TO KEEP UP ON ITS OWN, and there are two ways a
/// boundary gets crossed:
///
///  * The app is open when it happens. A player who starts a level at 18:55
///    should be in the evening palette by 19:05, so ONE timer is armed for
///    the next boundary. One timer, not a poll: a per-second (or per-minute)
///    tick would rebuild the entire `MaterialApp` theme forever to discover
///    that nothing changed, which is the same mistake P12 refused to make
///    when it kept the DDA idle clock out of `GameState`.
///  * The app was in the background when it happened — a phone in a pocket
///    for three hours. Timers do not reliably fire there, so
///    [AppLifecycleListener.onShow] re-resolves on the way back in. Between
///    them the two cover every case; neither alone does.
///
/// The timer is only ever a HINT. Every resolution re-reads the clock, so a
/// timer that fires early (a clock change, a long doze, a 23-hour local day)
/// costs one redundant recomputation rather than a wrong palette.
@Riverpod(keepAlive: true)
class ResolvedThemeVariant extends _$ResolvedThemeVariant {
  Timer? _timer;

  @override
  AppThemeVariant build() {
    final selection = ref.watch(appThemeSettingProvider);
    final clock = ref.watch(themeClockProvider);

    // Registered on every build; Riverpod runs these before recomputing, so a
    // selection change tears down the previous build's timer and listener
    // rather than stacking a second pair on top.
    ref.onDispose(_cancelTimer);

    if (selection.isAuto) {
      final lifecycle = AppLifecycleListener(onShow: _refresh);
      ref.onDispose(lifecycle.dispose);
      _arm(clock());
    }

    return selection.resolve(clock());
  }

  /// Re-resolves from the clock as it is NOW and re-arms. Safe to call at any
  /// time and any number of times: it writes the same answer twice rather
  /// than drifting.
  void _refresh() {
    final selection = ref.read(appThemeSettingProvider);
    if (!selection.isAuto) return;
    final now = ref.read(themeClockProvider)();
    state = selection.resolve(now);
    _arm(now);
  }

  void _arm(DateTime now) {
    _cancelTimer();
    _timer = Timer(AutoTheme.timeUntilNextSlot(now), _refresh);
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }
}
