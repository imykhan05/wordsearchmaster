import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/domain/progression/coin_economy.dart';
import 'package:word_search_master/domain/progression/dda.dart';
import 'package:word_search_master/services/remote_config/remote_config.dart';

void main() {
  group('the key table', () {
    test('every key has a distinct wire name', () {
      final names = RemoteConfigKeys.all.map((key) => key.name).toSet();
      expect(names, hasLength(RemoteConfigKeys.all.length));
    });

    test('wire names are snake_case, matching the Firebase console', () {
      for (final key in RemoteConfigKeys.all) {
        expect(
          key.name,
          matches(RegExp(r'^[a-z][a-z0-9_]*$')),
          reason: '${key.name} is not snake_case',
        );
      }
    });

    test('every default sits inside its own declared range', () {
      for (final key in RemoteConfigKeys.all) {
        expect(key.defaultValue, greaterThanOrEqualTo(key.min));
        expect(key.defaultValue, lessThanOrEqualTo(key.max));
        expect(key.min, lessThanOrEqualTo(key.max));
      }
    });

    test('the Ch02 defaults are what the bible says', () {
      expect(RemoteConfigKeys.hintCostCoins.defaultValue, 50);
      expect(RemoteConfigKeys.chestEveryNLevels.defaultValue, 5);
    });

    test('the Ch02/P12 DDA defaults are 25s / 60s', () {
      expect(RemoteConfigKeys.ddaStuckSeconds.defaultValue, 25);
      expect(RemoteConfigKeys.ddaHintOfferSeconds.defaultValue, 60);
    });
  });

  group('clamping — a console typo must not brick the economy', () {
    test('a value below the floor clamps up', () {
      const config = OverrideRemoteConfig({'hint_cost_coins': -999});

      expect(
        config.getInt(RemoteConfigKeys.hintCostCoins),
        RemoteConfigKeys.hintCostCoins.min,
      );
    });

    test('a value above the ceiling clamps down', () {
      const config = OverrideRemoteConfig({'hint_cost_coins': 2147483647});

      expect(
        config.getInt(RemoteConfigKeys.hintCostCoins),
        RemoteConfigKeys.hintCostCoins.max,
      );
    });

    test('a hint can never be free — the floor is 1, not 0', () {
      const config = OverrideRemoteConfig({'hint_cost_coins': 0});

      expect(config.getInt(RemoteConfigKeys.hintCostCoins), 1);
    });

    test('zero chests IS allowed — it is a legitimate live-ops position', () {
      const config = OverrideRemoteConfig({'chest_every_n_levels': 0});

      expect(config.getInt(RemoteConfigKeys.chestEveryNLevels), 0);
    });
  });

  group('DefaultRemoteConfig', () {
    test('returns every key at its shipped default', () {
      const config = DefaultRemoteConfig();

      for (final key in RemoteConfigKeys.all) {
        expect(config.getInt(key), key.defaultValue);
      }
    });
  });

  group('OverrideRemoteConfig', () {
    test('an unlisted key falls through to its default', () {
      const config = OverrideRemoteConfig({'hint_cost_coins': 25});

      expect(config.getInt(RemoteConfigKeys.hintCostCoins), 25);
      expect(
        config.getInt(RemoteConfigKeys.levelBaseCoins),
        RemoteConfigKeys.levelBaseCoins.defaultValue,
      );
    });
  });

  group('coinEconomyProvider', () {
    test('assembles CoinEconomy.defaults from the shipped levers', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final economy = container.read(coinEconomyProvider);

      expect(economy.hintCostCoins, CoinEconomy.defaults.hintCostCoins);
      expect(economy.levelBaseCoins, CoinEconomy.defaults.levelBaseCoins);
      expect(economy.coinsPerStar, CoinEconomy.defaults.coinsPerStar);
      expect(economy.chestEveryNLevels, CoinEconomy.defaults.chestEveryNLevels);
      expect(economy.starterGrantCoins, CoinEconomy.defaults.starterGrantCoins);
      expect(economy.chestTable, CoinEconomy.defaultChestTable);
    });

    test('a lever change actually reaches the economy', () {
      final container = ProviderContainer(
        overrides: [
          remoteConfigProvider.overrideWithValue(
            const OverrideRemoteConfig({
              'hint_cost_coins': 5,
              'chest_every_n_levels': 3,
            }),
          ),
        ],
      );
      addTearDown(container.dispose);

      final economy = container.read(coinEconomyProvider);

      expect(economy.hintCostCoins, 5);
      expect(economy.awardsChest(3), isTrue);
      expect(economy.awardsChest(5), isFalse);
    });
  });

  group('ddaConfigProvider', () {
    test('assembles DdaConfig.defaults from the shipped levers', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final config = container.read(ddaConfigProvider);

      expect(config, DdaConfig.defaults);
    });

    test('a lever change reaches the DDA config', () {
      final container = ProviderContainer(
        overrides: [
          remoteConfigProvider.overrideWithValue(
            const OverrideRemoteConfig({
              'dda_stuck_seconds': 10,
              'dda_hint_offer_seconds': 20,
            }),
          ),
        ],
      );
      addTearDown(container.dispose);

      final config = container.read(ddaConfigProvider);

      expect(config.stuckSeconds, 10);
      expect(config.hintOfferSeconds, 20);
    });
  });
}
