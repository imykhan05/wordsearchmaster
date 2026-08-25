import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'sound_settings.g.dart';

/// Whether game sound effects play.
///
/// A UI toggle, not game data — CLAUDE.md's `shared_preferences` ban is for
/// coins/progress/scores, and explicitly carves out sound/haptics/selected
/// language as the exception.
///
/// NOT PERSISTED YET, same as `SelectedLanguage`: resets to `true` on a cold
/// start until P08 wires local persistence.
@riverpod
class SoundEnabled extends _$SoundEnabled {
  @override
  bool build() => true;

  void toggle() => state = !state;
}
