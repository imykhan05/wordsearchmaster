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

  /// Whether the soft background loop plays. SEPARATE from [soundEnabled]
  /// rather than folded into it: the two are wanted independently — a player
  /// who keeps the found-word chime (it is the feedback that a word landed)
  /// often still wants silence otherwise, and Ch03's own reasoning for
  /// splitting haptics out of sound applies unchanged here.
  bool get musicEnabled;
  Future<void> setMusicEnabled(bool value);

  /// Null until the player picks one on the FTUE language screen.
  Language? get selectedLanguage;
  Future<void> setSelectedLanguage(Language value);

  /// Ch02/P12: has the one-time Urdu connected-form→isolated-letters
  /// illustration already been shown? A UI-only "have I shown this tutorial"
  /// flag, not game state — the same carve-out as [selectedLanguage] — so it
  /// belongs here rather than in `kv_settings`.
  bool get urduConnectedFormIntroShown;
  Future<void> setUrduConnectedFormIntroShown(bool value);

  /// Ch02/P12: has the player dismissed the post-level-8 "save your
  /// progress" login prompt? Framing, not an account — no auth exists yet
  /// (P13) — so this is purely "stop showing me this", the same class of
  /// toggle as the two above.
  bool get loginPromptDismissed;
  Future<void> setLoginPromptDismissed(bool value);

  /// Achievement ids a POPUP has already been shown for (P17).
  ///
  /// The unlocks themselves live server-side (`users/{uid}.stats.achievements`
  /// — see `AchievementsController`), reached through a live Firestore
  /// listener. That listener replays the FULL current set on every cold
  /// start, and without this, a player who unlocked "First Word" last week
  /// would see its popup again the next time they open the app. This is
  /// exactly the same "have I shown this" carve-out as
  /// [urduConnectedFormIntroShown]: UI bookkeeping, not game data — the
  /// achievement itself is never at risk of being un-shown by clearing it.
  Set<String> get seenAchievementPopupIds;
  Future<void> markAchievementPopupSeen(String id);
}

/// Defaults only, forgotten on restart. The binding in tests.
final class InMemoryUiSettingsStore implements UiSettingsStore {
  InMemoryUiSettingsStore({
    this.soundEnabled = true,
    this.hapticsEnabled = true,
    this.musicEnabled = true,
    this.selectedLanguage,
    this.urduConnectedFormIntroShown = false,
    this.loginPromptDismissed = false,
    Set<String>? seenAchievementPopupIds,
  }) : seenAchievementPopupIds = seenAchievementPopupIds ?? {};

  @override
  bool soundEnabled;
  @override
  bool hapticsEnabled;
  @override
  bool musicEnabled;
  @override
  Language? selectedLanguage;
  @override
  bool urduConnectedFormIntroShown;
  @override
  bool loginPromptDismissed;
  @override
  Set<String> seenAchievementPopupIds;

  @override
  Future<void> setSoundEnabled(bool value) async => soundEnabled = value;
  @override
  Future<void> setHapticsEnabled(bool value) async => hapticsEnabled = value;
  @override
  Future<void> setMusicEnabled(bool value) async => musicEnabled = value;
  @override
  Future<void> setSelectedLanguage(Language value) async =>
      selectedLanguage = value;
  @override
  Future<void> setUrduConnectedFormIntroShown(bool value) async =>
      urduConnectedFormIntroShown = value;
  @override
  Future<void> setLoginPromptDismissed(bool value) async =>
      loginPromptDismissed = value;
  @override
  Future<void> markAchievementPopupSeen(String id) async =>
      seenAchievementPopupIds = {...seenAchievementPopupIds, id};
}

/// The real one. Values are read once at startup and cached in memory, so
/// every call site stays synchronous.
final class PrefsUiSettingsStore implements UiSettingsStore {
  PrefsUiSettingsStore(this._prefs);

  static const String _soundKey = 'ui.sound_enabled';
  static const String _hapticsKey = 'ui.haptics_enabled';
  static const String _musicKey = 'ui.music_enabled';
  static const String _languageKey = 'ui.selected_language';
  static const String _urduIntroKey = 'ui.urdu_connected_form_intro_shown';
  static const String _loginPromptKey = 'ui.login_prompt_dismissed';
  static const String _seenAchievementPopupsKey =
      'ui.seen_achievement_popup_ids';

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
  bool get musicEnabled => _prefs.getBool(_musicKey) ?? true;

  @override
  Future<void> setMusicEnabled(bool value) => _prefs.setBool(_musicKey, value);

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

  @override
  bool get urduConnectedFormIntroShown =>
      _prefs.getBool(_urduIntroKey) ?? false;

  @override
  Future<void> setUrduConnectedFormIntroShown(bool value) =>
      _prefs.setBool(_urduIntroKey, value);

  @override
  bool get loginPromptDismissed => _prefs.getBool(_loginPromptKey) ?? false;

  @override
  Future<void> setLoginPromptDismissed(bool value) =>
      _prefs.setBool(_loginPromptKey, value);

  @override
  Set<String> get seenAchievementPopupIds =>
      (_prefs.getStringList(_seenAchievementPopupsKey) ?? const []).toSet();

  @override
  Future<void> markAchievementPopupSeen(String id) => _prefs.setStringList(
    _seenAchievementPopupsKey,
    {...seenAchievementPopupIds, id}.toList(),
  );
}

/// Overridden in `bootstrap.dart` with the prefs-backed store.
///
/// Defaults to in-memory rather than throwing so that every widget test —
/// and the Style Gallery — keeps working with no plugin registered.
@Riverpod(keepAlive: true)
UiSettingsStore uiSettingsStore(Ref ref) => InMemoryUiSettingsStore();
