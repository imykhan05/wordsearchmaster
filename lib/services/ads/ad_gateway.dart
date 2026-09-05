/// Ads, behind ONE interface (pre-P18/P18).
///
/// Same containment rule as every other vendor SDK in this codebase —
/// `NotificationService` for `firebase_messaging`, `AudioService` for
/// `audioplayers`, `FirebaseAuthService` for Firebase Auth: nothing outside
/// `services/ads/` may import `applovin_max` directly (CLAUDE.md →
/// Architecture, "Game code never imports `applovin_max` directly — only
/// `services/ads/max_ad_gateway.dart` may"). [NoopAdGateway] is the binding
/// in every test, the Style Gallery, and any flavor that has not configured
/// a MAX account yet — there is no separate "ads off" flag anywhere else in
/// the app, because a build with no ad unit IDs configured already degrades
/// to this by construction, the identical shape
/// `FlavorFirebaseOptions.forFlavor` returning null already established for
/// Firebase in P13.
///
/// `AdFrequencyPolicy` (`domain/progression/ad_policy.dart`) decides WHETHER
/// an interstitial should show; this interface only knows HOW to show one
/// once that question is already answered — kept as two separate files for
/// the same reason `CoinEconomy` and the code that reads it are separate:
/// one is pure and trivially testable, the other needs a real SDK and a
/// device to fully verify.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'ad_gateway.g.dart';

/// What happened when a rewarded ad was offered.
enum RewardedAdOutcome {
  /// The player watched to completion. This means the AD EXPERIENCE
  /// finished — it does NOT mean coins were credited. Crediting is
  /// server-authoritative, via AppLovin's S2S postback to
  /// `grantRewardedReward` (P14/CLAUDE.md: "the only path that mints coins
  /// is one the client cannot invoke, sign or observe"), so this value only
  /// ever drives UI (e.g. a "reward on the way" toast), never a local
  /// ledger write.
  earned,

  /// An ad was shown but the player closed it before finishing.
  dismissed,

  /// Nothing was shown at all — no ad was loaded, or platform/network state
  /// made showing one impossible. CLAUDE.md: never show a failed or blank
  /// ad, so this is a silent "continue exactly as if it was never offered",
  /// never an error surfaced to the player.
  unavailable,
}

abstract interface class AdGateway {
  /// Whether a preloaded interstitial is ready to show right now. Callers
  /// check this (alongside `AdFrequencyPolicy`) before offering one —
  /// [showInterstitial] also degrades gracefully on its own, but a caller
  /// that wants to skip the whole transition (no pause, no flash of a
  /// control that would do nothing) can check this first.
  bool get isInterstitialReady;

  /// Shows a preloaded interstitial. Returns whether one actually showed —
  /// false, never an exception, if none was ready: CLAUDE.md's "never show
  /// a failed/blank ad" means the right response to nothing being loaded is
  /// silence, not an empty ad view.
  Future<bool> showInterstitial();

  /// Whether a preloaded rewarded ad is ready to show right now.
  bool get isRewardedReady;

  /// Shows a preloaded rewarded ad for [uid] — the signed-in (possibly
  /// anonymous) account the reward, once server-granted, belongs to. Passed
  /// explicitly rather than read internally, the same choice
  /// `NotificationRegistrationApi.register` already made: the caller
  /// already has it, and a gateway that reached into auth itself would be
  /// one more dependency every test of this interface has to stand up.
  Future<RewardedAdOutcome> showRewarded({required String uid});
}

/// No ads, ever — nothing is ever "ready", every call resolves to the
/// unavailable/false case. The binding in every test, the Style Gallery, and
/// any flavor with no MAX account configured yet.
final class NoopAdGateway implements AdGateway {
  const NoopAdGateway();

  @override
  bool get isInterstitialReady => false;

  @override
  Future<bool> showInterstitial() async => false;

  @override
  bool get isRewardedReady => false;

  @override
  Future<RewardedAdOutcome> showRewarded({required String uid}) async =>
      RewardedAdOutcome.unavailable;
}

/// Defaults to Noop; `bootstrap.dart` upgrades it once a MAX account exists
/// and the ads-init step (P18) has actually initialised the SDK — mirroring
/// every other vendor-backed provider in this codebase
/// (`notificationServiceProvider`, `authServiceProvider`).
@Riverpod(keepAlive: true)
AdGateway adGateway(Ref ref) => const NoopAdGateway();
