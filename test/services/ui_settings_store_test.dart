import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:word_search_master/app/language/selected_language.dart';
import 'package:word_search_master/domain/text/language.dart';
import 'package:word_search_master/services/audio/sound_settings.dart';
import 'package:word_search_master/services/settings/ui_settings_store.dart';

/// The `shared_preferences` carve-out (CLAUDE.md → Never do).
///
/// These five toggles, and nothing else, are allowed outside the
/// integrity-tagged database. The test at the bottom is the one that matters:
/// it pins the boundary so a future prompt cannot quietly park coins here.
/// The two P12 additions (`urduConnectedFormIntroShown`, `loginPromptDismissed`)
/// are UI "have I shown this" flags, the same class as `selectedLanguage` —
/// see `UiSettingsStore`'s own doc for why they belong here rather than in
/// `kv_settings`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PrefsUiSettingsStore', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('defaults are sound on, haptics on, no language chosen, both P12 '
        'one-time flags unshown', () async {
      final store = await PrefsUiSettingsStore.open();

      expect(store.soundEnabled, isTrue);
      expect(store.hapticsEnabled, isTrue);
      expect(
        store.selectedLanguage,
        isNull,
        reason: 'null is what sends a first-run player to the FTUE picker',
      );
      expect(store.urduConnectedFormIntroShown, isFalse);
      expect(store.loginPromptDismissed, isFalse);
    });

    test('values survive a reopen', () async {
      final store = await PrefsUiSettingsStore.open();
      await store.setSoundEnabled(false);
      await store.setHapticsEnabled(false);
      await store.setSelectedLanguage(Language.urdu);
      await store.setUrduConnectedFormIntroShown(true);
      await store.setLoginPromptDismissed(true);

      final reopened = await PrefsUiSettingsStore.open();
      expect(reopened.soundEnabled, isFalse);
      expect(reopened.hapticsEnabled, isFalse);
      expect(reopened.selectedLanguage, Language.urdu);
      expect(reopened.urduConnectedFormIntroShown, isTrue);
      expect(reopened.loginPromptDismissed, isTrue);
    });

    test('an unknown stored language code falls back to the picker', () async {
      // A downgrade from a build that shipped a fourth language must not throw
      // on startup.
      SharedPreferences.setMockInitialValues({'ui.selected_language': 'fr'});
      final store = await PrefsUiSettingsStore.open();

      expect(store.selectedLanguage, isNull);
    });

    test('the language is stored by its ISO code', () async {
      final store = await PrefsUiSettingsStore.open();
      await store.setSelectedLanguage(Language.hindi);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('ui.selected_language'), 'hi');
    });
  });

  group('providers read and write through the store', () {
    ProviderContainer containerWith(UiSettingsStore store) {
      final container = ProviderContainer(
        overrides: [uiSettingsStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('SoundEnabled starts from the stored value', () {
      final container = containerWith(
        InMemoryUiSettingsStore(soundEnabled: false),
      );

      expect(container.read(soundEnabledProvider), isFalse);
    });

    test('toggling sound writes back to the store', () {
      final store = InMemoryUiSettingsStore();
      final container = containerWith(store);

      container.read(soundEnabledProvider.notifier).toggle();

      expect(container.read(soundEnabledProvider), isFalse);
      expect(store.soundEnabled, isFalse);
    });

    test('toggling haptics writes back to the store', () {
      final store = InMemoryUiSettingsStore();
      final container = containerWith(store);

      container.read(hapticsEnabledProvider.notifier).toggle();

      expect(store.hapticsEnabled, isFalse);
    });

    test('SelectedLanguage restores the stored choice', () {
      final container = containerWith(
        InMemoryUiSettingsStore(selectedLanguage: Language.urdu),
      );

      expect(container.read(selectedLanguageProvider), Language.urdu);
      expect(container.read(hasChosenLanguageProvider), isTrue);
    });

    test('with nothing stored the app opens on English, unchosen', () {
      final container = containerWith(InMemoryUiSettingsStore());

      expect(container.read(selectedLanguageProvider), Language.english);
      expect(
        container.read(hasChosenLanguageProvider),
        isFalse,
        reason: 'defaulting to English is not the same as having picked it',
      );
    });

    test('selecting a language persists it', () {
      final store = InMemoryUiSettingsStore();
      final container = containerWith(store);

      container.read(selectedLanguageProvider.notifier).select(Language.hindi);

      expect(container.read(selectedLanguageProvider), Language.hindi);
      expect(store.selectedLanguage, Language.hindi);
    });
  });

  test('ONLY the six UI toggles are stored here — no game data', () async {
    // The boundary, pinned. Coins, progress and scores belong in Drift with
    // an HMAC tag; a plain preferences file is a one-line cheat.
    SharedPreferences.setMockInitialValues({});
    final store = await PrefsUiSettingsStore.open();
    await store.setSoundEnabled(false);
    await store.setHapticsEnabled(false);
    await store.setSelectedLanguage(Language.urdu);
    await store.setUrduConnectedFormIntroShown(true);
    await store.setLoginPromptDismissed(true);
    await store.markAchievementPopupSeen('first_word');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), <String>{
      'ui.sound_enabled',
      'ui.haptics_enabled',
      'ui.selected_language',
      'ui.urdu_connected_form_intro_shown',
      'ui.login_prompt_dismissed',
      'ui.seen_achievement_popup_ids',
    });
  });

  test('seenAchievementPopupIds accumulates rather than overwriting', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await PrefsUiSettingsStore.open();

    await store.markAchievementPopupSeen('first_word');
    await store.markAchievementPopupSeen('word_master');

    expect(store.seenAchievementPopupIds, {'first_word', 'word_master'});
  });

  test('marking the same id seen twice is a no-op, not a duplicate', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await PrefsUiSettingsStore.open();

    await store.markAchievementPopupSeen('first_word');
    await store.markAchievementPopupSeen('first_word');

    expect(store.seenAchievementPopupIds, {'first_word'});
  });

  test('starts empty on a fresh install', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await PrefsUiSettingsStore.open();
    expect(store.seenAchievementPopupIds, isEmpty);
  });
}
