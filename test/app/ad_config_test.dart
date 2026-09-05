import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/app/config/ad_config.dart';
import 'package:word_search_master/app/config/app_config.dart';

/// `FlavorAdConfig` mirrors `FlavorFirebaseOptions`'s null-degrades-to-Noop
/// shape exactly — see `ad_config.dart`'s header for why. All three flavors
/// return null today (no MAX account exists yet); this file pins that as an
/// explicit, checked fact rather than an assumption every other test quietly
/// depends on.
void main() {
  group('FlavorAdConfig.forFlavor', () {
    test('every flavor is unconfigured until a MAX account exists', () {
      for (final flavor in Flavor.values) {
        expect(
          FlavorAdConfig.forFlavor(flavor),
          isNull,
          reason: '$flavor should have no real MAX credentials yet',
        );
        expect(FlavorAdConfig.isConfigured(flavor), isFalse);
      }
    });
  });

  group('AdUnitIds value semantics', () {
    const a = AdUnitIds(
      sdkKey: 'key-1',
      interstitialAdUnitId: 'int-1',
      rewardedAdUnitId: 'rew-1',
    );

    test('equal fields are equal', () {
      expect(
        a,
        const AdUnitIds(
          sdkKey: 'key-1',
          interstitialAdUnitId: 'int-1',
          rewardedAdUnitId: 'rew-1',
        ),
      );
    });

    test('a different sdk key is not equal', () {
      expect(
        a,
        isNot(
          const AdUnitIds(
            sdkKey: 'key-2',
            interstitialAdUnitId: 'int-1',
            rewardedAdUnitId: 'rew-1',
          ),
        ),
      );
    });

    test('toString is useful for debugging, not masked', () {
      // Like `FirebaseOptions`'s own apiKey, an AppLovin SDK key is a
      // client-embedded identifier shipped inside the compiled app, not a
      // server-side secret — `firebase_options_dev.dart` already commits its
      // equivalent value directly for the identical reason, so masking this
      // one would be an inconsistency, not extra safety.
      expect(a.toString(), contains('key-1'));
    });
  });
}
