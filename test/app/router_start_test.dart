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
/// The splash is no longer part of this answer. It runs in front of `runApp`
/// now (`BootSplash`, see `boot_splash_test.dart`), so it is finished and
/// gone before this router is built — leaving the router with the one
/// decision it started with: picker on a first launch, Home after that.
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

  test('a first launch opens on the language picker', () {
    expect(startLocationFor(), const LanguageRoute().location);
  });

  test('a returning player opens on Home, not the picker again', () {
    expect(
      startLocationFor(savedLanguage: Language.urdu),
      const HomeRoute().location,
    );
  });

  test('the language is READ, so picking one cannot rebuild the router out '
      'from under the session that tap just started', () {
    // `read`, deliberately not `watch`, and this is the case that makes the
    // difference visible: an FTUE player taps a language card, which writes
    // the choice — and a watching router would rebuild itself right then,
    // throwing them out of whatever that tap had just begun.
    //
    // Invalidating the OTHER provider here is the strongest form of the
    // assertion available: even when the thing it read is explicitly torn
    // down and recomputed, this provider is not rebuilt, because nothing
    // subscribed it to that.
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
      reason: 'the router was rebuilt out from under the running session',
    );
  });
}
