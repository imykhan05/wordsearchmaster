import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../settings/ui_settings_store.dart';

part 'sound_settings.g.dart';

/// Whether game sound effects play.
///
/// A UI toggle, not game data — CLAUDE.md's `shared_preferences` ban is for
/// coins/progress/scores, and explicitly carves out sound/haptics/selected
/// language as the exception. Persisted through [UiSettingsStore] (P08).
@riverpod
class SoundEnabled extends _$SoundEnabled {
  @override
  bool build() => ref.watch(uiSettingsStoreProvider).soundEnabled;

  void toggle() => _set(!state);

  void set(bool value) => _set(value);

  /// State first, disk second: a toggle must feel instant, and a preference
  /// that fails to write is not worth blocking the UI thread over.
  void _set(bool value) {
    state = value;
    ref.read(uiSettingsStoreProvider).setSoundEnabled(value);
  }
}

/// Whether the soft background loop plays.
///
/// Its own toggle rather than a branch of [SoundEnabled], for the reason
/// `UiSettingsStore.musicEnabled` states: a player who wants the found-word
/// chime and nothing else is the common case, not an edge one.
@riverpod
class MusicEnabled extends _$MusicEnabled {
  @override
  bool build() => ref.watch(uiSettingsStoreProvider).musicEnabled;

  void toggle() => _set(!state);

  void set(bool value) => _set(value);

  void _set(bool value) {
    state = value;
    ref.read(uiSettingsStoreProvider).setMusicEnabled(value);
  }
}

/// Whether the grid buzzes as a selection crosses each new cell (P06).
///
/// Separate from sound on purpose: Ch03 notes that players who mute a game in
/// public usually still want the haptic confirmation.
@riverpod
class HapticsEnabled extends _$HapticsEnabled {
  @override
  bool build() => ref.watch(uiSettingsStoreProvider).hapticsEnabled;

  void toggle() => _set(!state);

  void set(bool value) => _set(value);

  void _set(bool value) {
    state = value;
    ref.read(uiSettingsStoreProvider).setHapticsEnabled(value);
  }
}
