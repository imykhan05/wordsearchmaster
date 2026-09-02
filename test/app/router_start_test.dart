import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/app/app_route.dart';
import 'package:word_search_master/app/config/app_config.dart';
import 'package:word_search_master/app/language/selected_language.dart';
import 'package:word_search_master/app/router.dart';
import 'package:word_search_master/domain/text/language.dart';
import 'package:word_search_master/services/settings/ui_settings_store.dart';

/// Where the app OPENS, which is not the same question as which routes exist
/// (`app_smoke_test.dart` covers those).
///
/// Ch02 opens the FTUE on the language picker, and P12 then sends that pick
/// straight into level 1 with `.go()`. Every launch used to re-run that, so a
/// returning player was dropped back into a level with the journey map, the
/// daily and collections all unreachable — the app looked as though it had no
/// level select at all. A player who has already chosen a language now lands
/// on Home instead.
void main() {
  String startLocationFor({Language? savedLanguage}) {
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(AppConfig.dev()),
        uiSettingsStoreProvider.overrideWithValue(
          InMemoryUiSettingsStore(selectedLanguage: savedLanguage),
        ),
      ],
    );
    addTearDown(container.dispose);

    final router = container.read(routerProvider);
    addTearDown(router.dispose);
    return router.routeInformationProvider.value.uri.toString();
  }

  test('a first-ever launch still opens the language picker (Ch02 FTUE)', () {
    expect(startLocationFor(), const LanguageRoute().location);
  });

  test('a returning player opens on Home, not the picker', () {
    expect(
      startLocationFor(savedLanguage: Language.urdu),
      const HomeRoute().location,
    );
  });

  test('the choice is read once, so it cannot re-route a live session', () {
    // `routerProvider` reads `hasChosenLanguageProvider` rather than watching
    // it. Watching would rebuild the whole GoRouter the moment the FTUE
    // player taps a language card — throwing them out of the level that tap
    // just started. Same container, language chosen AFTER the router exists:
    // the router must be the same instance, still where it was.
    final settings = InMemoryUiSettingsStore();
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(AppConfig.dev()),
        uiSettingsStoreProvider.overrideWithValue(settings),
      ],
    );
    addTearDown(container.dispose);

    final router = container.read(routerProvider);
    addTearDown(router.dispose);
    expect(
      router.routeInformationProvider.value.uri.toString(),
      const LanguageRoute().location,
    );

    settings.selectedLanguage = Language.hindi;
    container.invalidate(hasChosenLanguageProvider);

    expect(
      container.read(routerProvider),
      same(router),
      reason: 'the router was not rebuilt out from under the running session',
    );
  });
}
