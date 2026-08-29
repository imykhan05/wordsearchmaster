/// App Check attestation policy (Ch13 / P13).
///
/// ---------------------------------------------------------------------------
/// WHY THE CHOICE IS A PURE FUNCTION IN ITS OWN FILE
///
/// Picking the wrong provider is a silent, total outage: a debug provider on
/// a production build means every install ships a debug token that the console
/// will never have registered, so once enforcement is on, EVERY request from
/// EVERY real player is rejected at once. That is a decision worth being able
/// to unit-test without a Firebase app, so [AppCheckPolicy.forFlavor] takes a
/// flavor and returns an enum, and `firebase_app_check_gateway.dart` is the
/// only thing that turns that enum into an SDK call.
///
/// ---------------------------------------------------------------------------
/// ENFORCEMENT STAYS IN **MONITOR MODE** FOR THE FIRST TWO WEEKS POST-LAUNCH
///
/// This is a console setting, not code — nothing in this repository can turn
/// it on or off, which is exactly why it is written down here.
///
/// Turning enforcement on at launch is how a launch becomes an outage. The
/// failure it protects against (an unattested client) is indistinguishable,
/// from the console, from the failure it CAUSES (a real player on an old
/// Android build, a rooted-but-honest phone, a device whose Play Integrity
/// verdict is unavailable because the Play Store is out of date). Monitor
/// mode reports both without blocking either.
///
/// The runbook, in order:
///
///   1. Ship with every App Check API in the console set to **Unenforced**
///      (monitor mode). Tokens still flow and the console still counts them.
///   2. Watch the "verified vs. unverified requests" chart for 14 days across
///      Firestore, Functions and Auth.
///   3. Enforce only when the unverified share has flattened out at the
///      floor — a couple of percent from unavoidable device diversity, not a
///      trend still coming down. A number still falling means real players
///      are still in it.
///   4. Enforce ONE API at a time, Functions first (P14's `submitScore` is
///      the thing worth protecting; a rejected score is recoverable, a
///      rejected read is a blank game).
///
/// P13's acceptance criterion — "App Check tokens console mein nazar aate
/// hain" — is satisfied by step 1, tokens ARRIVING and being counted. It is
/// explicitly NOT satisfied by turning enforcement on.
library;

import '../../app/config/app_config.dart';

/// Which attestation provider a build should present.
enum AppCheckPolicy {
  /// Play Integrity (Android) / App Attest (iOS). Real attestation, real
  /// devices, production only.
  playIntegrity,

  /// The debug provider. Prints a token that a human pastes into the console's
  /// debug-token allowlist. Dev and staging only — see [forFlavor].
  debug;

  /// The provider for [flavor].
  ///
  /// PROD IS THE ONLY FLAVOR THAT ATTESTS FOR REAL, and dev/stg are the only
  /// ones allowed a debug token. This mirrors the ads rule CLAUDE.md already
  /// states in the strongest terms ("dev/stg must never be able to serve a
  /// real ad unit"): both are cases where a build pointing at the wrong
  /// environment is expensive and silent, so the mapping lives in one
  /// switch that a test can enumerate rather than in an `if (kDebugMode)`
  /// scattered through bootstrap.
  ///
  /// Note this keys off the FLAVOR, never off `kDebugMode`: a release-mode
  /// build of the dev flavor (what QA actually installs) still needs the
  /// debug provider, and a debug-mode build of prod must never get one.
  static AppCheckPolicy forFlavor(Flavor flavor) => switch (flavor) {
    Flavor.prod => AppCheckPolicy.playIntegrity,
    Flavor.dev || Flavor.stg => AppCheckPolicy.debug,
  };
}

/// Activates App Check. Behind an interface for the usual reason: the SDK
/// call is untestable, the decision around it is not.
abstract interface class AppCheckGateway {
  /// Must run BEFORE any other Firebase call that could be attested —
  /// `bootstrap.dart` step 3, immediately after `initializeApp` and before
  /// auth. Activating late means the first auth/Firestore call of the session
  /// goes out unattested, which is precisely the request an attacker would
  /// choose to imitate.
  ///
  /// Never throws: App Check failing must not take startup down with it.
  Future<void> activate(AppCheckPolicy policy);
}

/// Does nothing. The binding in tests and on any build where Firebase never
/// initialised.
final class NoopAppCheckGateway implements AppCheckGateway {
  const NoopAppCheckGateway();

  @override
  Future<void> activate(AppCheckPolicy policy) async {}
}
