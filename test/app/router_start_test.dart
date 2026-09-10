import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/app/app_route.dart';
import 'package:word_search_master/app/config/app_config.dart';
import 'package:word_search_master/app/language/selected_language.dart';
import 'package:word_search_master/app/router.dart';
import 'package:word_search_master/domain/text/language.dart';
import 'package:word_search_master/services/settings/ui_settings_store.dart';

/// Where the app OPENS, which is not the same question as which routes exist
/// (`app_smoke_test.dart` covers those) — and, since the splash landed, not
/// the same question as where a launch ENDS UP either. That second question
/// is `splash_screen_test.dart`'s: it is the splash, not the router, that now
/// decides FTUE-picker vs. Home, once, right before its own one-shot
/// navigation. This file is scoped to what `routerProvider` itself controls:
/// a single, unconditional entry point.
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

  test('every launch opens on the splash, FTUE or returning alike', () {
    expect(startLocationFor(), const SplashRoute().location);
    expect(
      startLocationFor(savedLanguage: Language.urdu),
      const SplashRoute().location,
    );
  });

  test('the router never reads hasChosenLanguageProvider, so it cannot be '
      'rebuilt out from under a running session by it', () {
    // The previous shape had `routerProvider` itself read this provider to
    // build `initialLocation` — `read`, deliberately not `watch`, and ONLY
    // safe because that read happened once, at construction. Moving the
    // FTUE-vs-returning decision into the splash screen (which reads it
    // once, right before its own one-shot navigation — see
    // `splash_screen_test.dart`) removes the dependency from the router
    // entirely, which is a strictly stronger guarantee than "read once":
    // the router provider cannot be invalidated by a change to a provider
    // it never touches, so this asserts exactly that — build the router,
    // change the language, invalidate the OTHER provider, and confirm the
    // router instance never moved.
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
      const SplashRoute().location,
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
