import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/text/language.dart';

part 'ui_settings_store.g.dart';

/// The ONLY things allowed outside the integrity-tagged database.
///
/// CLAUDE.md → Never do: `shared_preferences` must never hold game data —
/// coins, progress, scores. Those live in Drift with an HMAC tag, because a
/// plain XML file on disk is a one-line cheat. What is allowed here is exactly
/// the Ch10 carve-out: non-sensitive UI toggles, where the worst case of a
/// tamper is that a player who edits their own phone gets their sound turned
/// off.
///
/// The interface exists so the default binding can be in-memory: a widget test
/// pumping a screen should not have to stand up a platform plugin to find out
/// whether sound is on.
abstract interface class UiSettingsStore {
  bool get soundEnabled;
  Future<void> setSoundEnabled(bool value);

  bool get hapticsEnabled;
  Future<void> setHapticsEnabled(bool value);

  /// Null until the player picks one on the FTUE language screen.
  Language? get selectedLanguage;
  Future<void> setSelectedLanguage(Language value);
}

/// Defaults only, forgotten on restart. The binding in tests.
final class InMemoryUiSettingsStore implements UiSettingsStore {
  InMemoryUiSettingsStore({
    this.soundEnabled = true,
    this.hapticsEnabled = true,
    this.selectedLanguage,
  });

  @override
  bool soundEnabled;
  @override
  bool hapticsEnabled;
  @override
  Language? selectedLanguage;

  @override
  Future<void> setSoundEnabled(bool value) async => soundEnabled = value;
  @override
  Future<void> setHapticsEnabled(bool value) async => hapticsEnabled = value;
  @override
  Future<void> setSelectedLanguage(Language value) async =>
      selectedLanguage = value;
}

/// The real one. Values are read once at startup and cached in memory, so
/// every call site stays synchronous.
final class PrefsUiSettingsStore implements UiSettingsStore {
  PrefsUiSettingsStore(this._prefs);

  static const String _soundKey = 'ui.sound_enabled';
  static const String _hapticsKey = 'ui.haptics_enabled';
  static const String _languageKey = 'ui.selected_language';

  final SharedPreferences _prefs;

  static Future<PrefsUiSettingsStore> open() async =>
      PrefsUiSettingsStore(await SharedPreferences.getInstance());

  @override
  bool get soundEnabled => _prefs.getBool(_soundKey) ?? true;

  @override
  Future<void> setSoundEnabled(bool value) => _prefs.setBool(_soundKey, value);

  @override
  bool get hapticsEnabled => _prefs.getBool(_hapticsKey) ?? true;

  @override
  Future<void> setHapticsEnabled(bool value) =>
      _prefs.setBool(_hapticsKey, value);

  @override
  Language? get selectedLanguage {
    final code = _prefs.getString(_languageKey);
    if (code == null) return null;
    // An unknown code means a downgrade from a build that shipped a fourth
    // language. Fall back to the picker rather than throwing on startup.
    for (final language in Language.values) {
      if (language.code == code) return language;
    }
    return null;
  }

  @override
  Future<void> setSelectedLanguage(Language value) =>
      _prefs.setString(_languageKey, value.code);
}

/// Overridden in `bootstrap.dart` with the prefs-backed store.
///
/// Defaults to in-memory rather than throwing so that every widget test —
/// and the Style Gallery — keeps working with no plugin registered.
@Riverpod(keepAlive: true)
UiSettingsStore uiSettingsStore(Ref ref) => InMemoryUiSettingsStore();
