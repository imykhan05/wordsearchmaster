import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/app/config/app_config.dart';

void main() {
  group('AppConfig', () {
    test('dev flavor is test-mode ads with debug logging', () {
      final config = AppConfig.dev();

      expect(config.flavor, Flavor.dev);
      expect(config.flavorName, 'DEV');
      expect(config.adsTestMode, isTrue);
      expect(config.logLevel, AppLogLevel.debug);
    });

    test('stg flavor is test-mode ads with info logging', () {
      final config = AppConfig.stg();

      expect(config.flavor, Flavor.stg);
      expect(config.flavorName, 'STG');
      expect(config.adsTestMode, isTrue);
      expect(config.logLevel, AppLogLevel.info);
    });

    test('prod flavor is real ads with warning logging', () {
      final config = AppConfig.prod();

      expect(config.flavor, Flavor.prod);
      expect(config.flavorName, 'PROD');
      expect(
        config.adsTestMode,
        isFalse,
        reason: 'prod must never be test-mode — real ad units serve here',
      );
      expect(config.logLevel, AppLogLevel.warning);
    });

    test('dev and stg are always test-mode ads, never prod', () {
      // A regression here is the single most common cause of a permanent
      // account ban (CLAUDE.md → Never do) — guard it explicitly per flavor
      // rather than relying on the three tests above staying in sync.
      for (final config in [AppConfig.dev(), AppConfig.stg()]) {
        expect(
          config.adsTestMode,
          isTrue,
          reason: '${config.flavor} must be ad test-mode',
        );
      }
    });
  });

  test('appConfigProvider throws until overridden', () {
    // Reading it un-overridden is a programming error (a missing override
    // in main_*.dart), not a runtime condition — see app_config.dart. Riverpod
    // wraps the original throw in a ProviderException, so match on message
    // rather than the wrapper's exact (internal) type.
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      () => container.read(appConfigProvider),
      throwsA(
        predicate<Object>(
          (error) =>
              error.toString().contains('appConfigProvider must be overridden'),
        ),
      ),
    );
  });

  test('appConfigProvider yields the override', () {
    final container = ProviderContainer(
      overrides: [appConfigProvider.overrideWithValue(AppConfig.prod())],
    );
    addTearDown(container.dispose);

    expect(container.read(appConfigProvider).flavor, Flavor.prod);
  });
}
