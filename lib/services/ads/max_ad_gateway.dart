/// The real AppLovin MAX binding for [AdGateway] (pre-P18).
///
/// Nothing outside this file may import `package:applovin_max` — CLAUDE.md
/// → Architecture: "Game code never imports `applovin_max` directly — only
/// `services/ads/max_ad_gateway.dart` may." `bootstrap.dart`'s ads.init step
/// is the only caller; every other file reaches ads through [AdGateway].
///
/// ---------------------------------------------------------------------------
/// BRIDGING A CALLBACK API TO A FUTURE-BASED ONE
///
/// The plugin's fullscreen-ad API is listener-based, and — this is the part
/// that shapes this whole file — there is exactly ONE listener slot per ad
/// FORMAT (`AppLovinMAX.setInterstitialListener`/`setRewardedAdListener`
/// each hold a single static field, not one per ad unit or per call). That
/// is fine here because [MaxAdGateway] itself is a `@Riverpod(keepAlive:
/// true)` singleton — there is only ever one instance to own those slots —
/// but it does mean the listener callbacks and this class's public methods
/// have to coordinate through instance state rather than each call getting
/// its own isolated response: a `Completer` captures whichever load/show is
/// currently pending, and the matching listener callback resolves it. Two
/// completers, not a queue, because [AdGateway] never asks this class to
/// show a second interstitial/rewarded ad before the first one's Future has
/// resolved (`RewardedActionButton`/the level-complete "Continue" seam both
/// only ever have one in flight at a time).
///
/// ---------------------------------------------------------------------------
/// WHY EVERY SHOW RE-ARMS THE NEXT LOAD IMMEDIATELY
///
/// A MAX fullscreen ad is single-use: once shown (or once it fails to
/// display), that instance is spent. `onAdHiddenCallback`/
/// `onAdDisplayFailedCallback` both immediately call `loadInterstitial`/
/// `loadRewardedAd` again, so the NEXT eligible moment already has a fresh
/// ad ready rather than starting a cold load right when a player wants one.
///
/// ---------------------------------------------------------------------------
/// THE REWARDED USER ID
///
/// `AppLovinMAX.setUserId` is called immediately before every
/// `showRewardedAd`, not once at startup — it is what makes AppLovin's own
/// S2S postback to `grantRewardedReward` (P14) carry the RIGHT uid via its
/// `{USER_ID}` macro, and [AdGateway.showRewarded] is handed a fresh uid on
/// every call rather than this class caching one at construction (the
/// account can change — guest today, linked tomorrow — and a stale cached
/// uid would credit the wrong player's reward).
library;

import 'dart:async';

import 'package:applovin_max/applovin_max.dart';

import '../../app/config/ad_config.dart';
import 'ad_gateway.dart';

final class MaxAdGateway implements AdGateway {
  MaxAdGateway({required this.adUnitIds, required this.testMode});

  final AdUnitIds adUnitIds;

  /// [AppConfig.adsTestMode] — true on dev/stg. Only gates verbose SDK
  /// logging here: the structural guarantee against a dev/stg build serving
  /// a real ad is [adUnitIds] itself being a SEPARATE MAX app's credentials
  /// (see `ad_config.dart`'s header) — AppLovin's own device-level test mode
  /// (`setTestDeviceAdvertisingIds`) needs a physical device's advertising
  /// id, which is a one-time manual step for whoever holds that device
  /// (`docs/applovin-max-setup.md`), not something resolvable from here.
  final bool testMode;

  bool _interstitialLoaded = false;
  bool _rewardedLoaded = false;
  Completer<bool>? _interstitialShowCompleter;
  Completer<RewardedAdOutcome>? _rewardedShowCompleter;
  bool _rewardEarnedThisShow = false;

  /// Wires the two global listeners, initializes the SDK, and kicks off the
  /// first preload of each format. Called once, from `bootstrap.dart`'s
  /// ads.init step — like every other bootstrap step, a throw here is
  /// caught there and degrades to `NoopAdGateway` staying bound, so this
  /// method itself does not need its own try/catch.
  Future<void> initialize() async {
    AppLovinMAX.setVerboseLogging(testMode);

    AppLovinMAX.setInterstitialListener(
      InterstitialListener(
        onAdLoadedCallback: (ad) => _interstitialLoaded = true,
        onAdLoadFailedCallback: (adUnitId, error) =>
            _interstitialLoaded = false,
        onAdClickedCallback: (ad) {},
        onAdDisplayedCallback: (ad) {},
        onAdDisplayFailedCallback: (ad, error) {
          _interstitialLoaded = false;
          _interstitialShowCompleter?.complete(false);
          _interstitialShowCompleter = null;
          AppLovinMAX.loadInterstitial(adUnitIds.interstitialAdUnitId);
        },
        onAdHiddenCallback: (ad) {
          _interstitialLoaded = false;
          _interstitialShowCompleter?.complete(true);
          _interstitialShowCompleter = null;
          AppLovinMAX.loadInterstitial(adUnitIds.interstitialAdUnitId);
        },
      ),
    );

    AppLovinMAX.setRewardedAdListener(
      RewardedAdListener(
        onAdLoadedCallback: (ad) => _rewardedLoaded = true,
        onAdLoadFailedCallback: (adUnitId, error) => _rewardedLoaded = false,
        onAdClickedCallback: (ad) {},
        onAdDisplayedCallback: (ad) => _rewardEarnedThisShow = false,
        onAdDisplayFailedCallback: (ad, error) {
          _rewardedLoaded = false;
          _rewardedShowCompleter?.complete(RewardedAdOutcome.unavailable);
          _rewardedShowCompleter = null;
          AppLovinMAX.loadRewardedAd(adUnitIds.rewardedAdUnitId);
        },
        onAdHiddenCallback: (ad) {
          _rewardedLoaded = false;
          _rewardedShowCompleter?.complete(
            _rewardEarnedThisShow
                ? RewardedAdOutcome.earned
                : RewardedAdOutcome.dismissed,
          );
          _rewardedShowCompleter = null;
          AppLovinMAX.loadRewardedAd(adUnitIds.rewardedAdUnitId);
        },
        onAdReceivedRewardCallback: (ad, reward) =>
            _rewardEarnedThisShow = true,
      ),
    );

    await AppLovinMAX.initialize(adUnitIds.sdkKey);
    AppLovinMAX.loadInterstitial(adUnitIds.interstitialAdUnitId);
    AppLovinMAX.loadRewardedAd(adUnitIds.rewardedAdUnitId);
  }

  @override
  bool get isInterstitialReady => _interstitialLoaded;

  @override
  Future<bool> showInterstitial() async {
    // CLAUDE.md: never show a failed/blank ad — the local flag is exactly
    // what `onAdLoadedCallback`/`onAdDisplayFailedCallback` keep current, so
    // trusting it here (rather than also awaiting the platform's own
    // `isInterstitialReady` check) is what keeps this method from ever
    // asking the SDK to show something it just told us was not ready.
    if (!_interstitialLoaded) return false;

    final completer = Completer<bool>();
    _interstitialShowCompleter = completer;
    AppLovinMAX.showInterstitial(adUnitIds.interstitialAdUnitId);
    return completer.future;
  }

  @override
  bool get isRewardedReady => _rewardedLoaded;

  @override
  Future<RewardedAdOutcome> showRewarded({required String uid}) async {
    if (!_rewardedLoaded) return RewardedAdOutcome.unavailable;

    AppLovinMAX.setUserId(uid);
    final completer = Completer<RewardedAdOutcome>();
    _rewardedShowCompleter = completer;
    AppLovinMAX.showRewardedAd(adUnitIds.rewardedAdUnitId);
    return completer.future;
  }
}
