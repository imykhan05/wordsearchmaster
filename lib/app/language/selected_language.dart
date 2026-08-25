import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/text/language.dart';

part 'selected_language.g.dart';

/// The language the player is currently playing in.
///
/// Drives the app's locale, its [Directionality], the theme's default font
/// family, and which content pack the grid engine loads.
///
/// NOT PERSISTED YET: this resets to [Language.english] on a cold start.
/// P08 owns local persistence and will restore it from `kv_settings` —
/// selected language is one of the few things CLAUDE.md allows outside the
/// integrity-tagged tables, since it is a UI preference, not game state.
@riverpod
class SelectedLanguage extends _$SelectedLanguage {
  @override
  Language build() => Language.english;

  /// Called from the language-select screen (P12 builds the real one).
  void select(Language language) => state = language;
}
