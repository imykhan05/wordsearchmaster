import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/services/ads/ad_gateway.dart';

/// [NoopAdGateway] is the binding in every test, the Style Gallery, and any
/// flavor with no MAX account configured yet (pre-P18) — see the library
/// header for why that degradation needs no separate "ads off" flag
/// anywhere else in the app.
void main() {
  group('NoopAdGateway', () {
    const gateway = NoopAdGateway();

    test('nothing is ever ready', () {
      expect(gateway.isInterstitialReady, isFalse);
      expect(gateway.isRewardedReady, isFalse);
    });

    test('showInterstitial never shows one — false, never a throw', () async {
      expect(await gateway.showInterstitial(), isFalse);
    });

    test('showRewarded always resolves to unavailable — never a throw, never '
        'earned', () async {
      expect(
        await gateway.showRewarded(uid: 'u1'),
        RewardedAdOutcome.unavailable,
      );
    });
  });

  group('adGatewayProvider', () {
    test('defaults to NoopAdGateway with nothing overridden', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(adGatewayProvider), isA<NoopAdGateway>());
    });
  });
}
