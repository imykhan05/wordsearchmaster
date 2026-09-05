/// Per-flavor AppLovin MAX credentials (pre-P18).
///
/// Same null-degrades-to-Noop shape `firebase_options.dart` established for
/// Firebase in P13: [FlavorAdConfig.forFlavor] returns null until a MAX
/// account exists and this file has been filled in — see
/// `docs/applovin-max-setup.md`. Until then `bootstrap.dart`'s ads.init step
/// never constructs a `MaxAdGateway`, and every ad-backed provider keeps its
/// `NoopAdGateway` binding: an unconfigured checkout is a supported state,
/// not an error, exactly like an unconfigured Firebase project.
///
/// ---------------------------------------------------------------------------
/// WHY THIS IS THREE SEPARATE CONFIGS, NOT ONE SHARED SET OF AD UNIT IDS
///
/// CLAUDE.md → Flavors: "dev/stg must never be able to serve a real ad unit —
/// that is the single most common cause of a permanent AdMob/MAX account
/// ban." AppLovin's own test-mode mechanism
/// (`AppLovinMAX.setTestDeviceAdvertisingIds`) is PER PHYSICAL DEVICE — it
/// needs that device's advertising id, discovered from the SDK's own logs
/// after the fact — so it is a manual step for whoever holds the test
/// device, not something this codebase can wire up unconditionally from
/// here. That leaves exactly one guarantee this file CAN make unconditional:
/// if dev, stg and prod each get their OWN MAX "app" registration (own SDK
/// key, own ad unit ids — the identical shape `docs/firebase-setup.md`
/// already uses for three separate Firebase projects), then prod's real,
/// revenue-generating ad unit ids are simply never PRESENT in a dev or stg
/// binary, structurally, regardless of whether test-mode was ever
/// configured on the device running it. Follow the runbook's registration
/// step for exactly this reason — do not paste prod's ids into dev's slot
/// "to see it work faster".
library;

import 'app_config.dart';

/// One flavor's worth of MAX credentials.
final class AdUnitIds {
  const AdUnitIds({
    required this.sdkKey,
    required this.interstitialAdUnitId,
    required this.rewardedAdUnitId,
  });

  /// From the MAX dashboard → Account → Keys. One per registered app, so
  /// this is what actually ties a build to ONE of the three separate apps
  /// the library header requires.
  final String sdkKey;

  final String interstitialAdUnitId;
  final String rewardedAdUnitId;

  @override
  bool operator ==(Object other) =>
      other is AdUnitIds &&
      other.sdkKey == sdkKey &&
      other.interstitialAdUnitId == interstitialAdUnitId &&
      other.rewardedAdUnitId == rewardedAdUnitId;

  @override
  int get hashCode =>
      Object.hash(sdkKey, interstitialAdUnitId, rewardedAdUnitId);

  @override
  String toString() =>
      'AdUnitIds(sdkKey: $sdkKey, interstitial: $interstitialAdUnitId, '
      'rewarded: $rewardedAdUnitId)';
}

/// Resolves the MAX credentials for a flavor.
abstract final class FlavorAdConfig {
  /// The credentials for [flavor], or null while no MAX account has been
  /// created yet — see the library header. All three arms return null
  /// today; `docs/applovin-max-setup.md` §2 is where real values land, one
  /// `switch` arm at a time, exactly like `FlavorFirebaseOptions.forFlavor`
  /// did for each Firebase project as it was created.
  static AdUnitIds? forFlavor(Flavor flavor) => switch (flavor) {
    Flavor.dev => null,
    Flavor.stg => null,
    Flavor.prod => null,
  };

  /// Whether [flavor] has real credentials — the ads equivalent of
  /// `FlavorFirebaseOptions.isConfigured`, so a dev-flavor screen can SAY
  /// which mode it is in rather than a tester inferring "ads configured"
  /// from a silent absence of interstitials.
  static bool isConfigured(Flavor flavor) => forFlavor(flavor) != null;
}
