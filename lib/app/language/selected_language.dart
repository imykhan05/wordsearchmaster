import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/text/language.dart';
import '../../services/settings/ui_settings_store.dart';

part 'selected_language.g.dart';

/// The language the player is currently playing in.
///
/// Drives the app's locale, its [Directionality], the theme's default font
/// family, and which content pack the grid engine loads.
///
/// PERSISTED THROUGH `shared_preferences`, not Drift (P08). It is a UI
/// preference rather than game state, which is the exact carve-out CLAUDE.md
/// allows — and it has to be readable before the database is open, because
/// the very first frame needs a locale and a text direction.
@riverpod
class SelectedLanguage extends _$SelectedLanguage {
  @override
  Language build() =>
      ref.watch(uiSettingsStoreProvider).selectedLanguage ?? Language.english;

  /// Called from the language-select screen (P12 builds the real one).
  void select(Language language) {
    state = language;
    ref.read(uiSettingsStoreProvider).setSelectedLanguage(language);
  }
}

/// Whether the player has ever chosen a language.
///
/// The FTUE opens on the picker (Ch02); a returning player must not see it
/// again. Read from the store rather than from [SelectedLanguage], which
/// cannot distinguish "chose English" from "has not chosen".
@riverpod
bool hasChosenLanguage(Ref ref) =>
    ref.watch(uiSettingsStoreProvider).selectedLanguage != null;
