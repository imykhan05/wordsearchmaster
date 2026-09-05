# AppLovin MAX setup runbook (pre-P18)

Everything in `lib/` that talks to AppLovin MAX is written and tested against
the real `applovin_max` plugin API. What is **not** in this repository is a
MAX account or any real ad unit ids, because creating those needs an
interactive AppLovin login that only a human with the account can do.

Until these steps are run, `FlavorAdConfig.forFlavor` returns `null` for
every flavor, `AppConfig.adUnitIds` is `null`, `bootstrap.dart`'s `ads.init`
step is a genuine no-op, and every `AdGateway`-backed provider keeps its
`NoopAdGateway` binding. That is the same "unconfigured is a supported
state" shape `docs/firebase-setup.md` already established for Firebase, and
it is covered by `test/app/bootstrap_offline_test.dart`'s "pre-P18: ads.init
never blocks or crashes startup either" group — the unconfigured state is
exercised, not merely tolerated.

**Status: not started.** Nothing below has been run yet.

## Why this needs THREE separate MAX apps, not one

CLAUDE.md → Flavors: "dev/stg must never be able to serve a real ad unit —
that is the single most common cause of a permanent AdMob/MAX account ban."

AppLovin's own device-level test mode
(`AppLovinMAX.setTestDeviceAdvertisingIds`) needs a physical device's
advertising id, discovered from that device's own logs after the SDK is
already running on it — a one-time manual step for whoever holds the test
device, not something this repository can wire up unconditionally. The one
guarantee that CAN be made unconditional is structural: if dev, stg and prod
each get their own MAX "app" registration — own SDK key, own ad unit ids,
mirroring the three separate Firebase projects `docs/firebase-setup.md`
already uses — then prod's real, revenue-generating ad unit ids are simply
never PRESENT in a dev or stg binary, regardless of whether test-device mode
was ever configured on the phone running it.

**Do not paste prod's ids into dev's slot "to see it working faster."** That
is exactly the mistake this three-app split exists to make impossible.

## 1. Create the AppLovin MAX account and three apps

1. Sign up at [applovin.com](https://www.applovin.com) if there is no
   account yet.
2. In the MAX dashboard, register three separate apps — one per flavor,
   matching the same `applicationId` values `docs/firebase-setup.md` already
   uses:

   | Flavor | Android package name                  |
   | ------ | -------------------------------------- |
   | dev    | `com.educativz.wordsearchmaster.dev`   |
   | stg    | `com.educativz.wordsearchmaster.stg`   |
   | prod   | `com.educativz.wordsearchmaster`       |

3. For each app, create two ad units: an **Interstitial** and a **Rewarded**
   ad unit. (A banner/MREC unit is not needed yet — `LevelCompleteCard`'s MREC
   slot is still a placeholder, unrelated to this prompt's scope.)
4. Each app has its own **SDK Key**, under that app's Account → Keys page.

## 2. Fill in `lib/app/config/ad_config.dart`

Replace each `null` arm of `FlavorAdConfig.forFlavor` with the real
credentials for that flavor's app:

```dart
static AdUnitIds? forFlavor(Flavor flavor) => switch (flavor) {
  Flavor.dev => const AdUnitIds(
      sdkKey: '<dev app's SDK key>',
      interstitialAdUnitId: '<dev interstitial ad unit id>',
      rewardedAdUnitId: '<dev rewarded ad unit id>',
    ),
  Flavor.stg => const AdUnitIds(/* stg's own ids */),
  Flavor.prod => const AdUnitIds(/* prod's own ids */),
};
```

These values are client-embedded identifiers shipped inside the compiled
app — the same category `firebase_options_dev.dart`'s API key already is —
not server secrets, so committing them directly here is the same choice
already made for Firebase.

## 3. Register your test device (once you have one)

AppLovin's test mode is per PHYSICAL DEVICE, not per ad unit. Run the app
once on a real device with `setVerboseLogging` on (already wired — see
`MaxAdGateway.initialize`, gated on `AppConfig.adsTestMode`, true on
dev/stg), find that device's advertising id in the SDK's own logcat output,
and add it wherever `MaxAdGateway.initialize` calls
`AppLovinMAX.setTestDeviceAdvertisingIds([...])` — **not yet wired**, since
there is no device in this environment to discover an id from. This is the
one piece of real-device setup this repository cannot do for you.

## 4. Android manifest

The plugin's current version (`applovin_max: ^4.6.4`) takes the SDK key
programmatically via `AppLovinMAX.initialize(sdkKey)` — no
`applovin.sdk.key` manifest meta-data tag is required. If a
`flutter build appbundle` on a real checkout reports a manifest merge
conflict once this is filled in, check the plugin's own
`android/build.gradle`/manifest for anything version-specific that changed
since this runbook was written, and update this note.

## What is already done, and does not need to change

- `AdGateway` (`lib/services/ads/ad_gateway.dart`) and `NoopAdGateway` — the
  interface every other file in the app is written against.
- `AdFrequencyPolicy` (`lib/domain/progression/ad_policy.dart`) — pure,
  RemoteConfig-backed interstitial pacing, already enforcing CLAUDE.md's
  "never escalate ad frequency" rule.
- `AdRepository` — the two pacing counters, persisted and tagged like every
  other `kv_settings` row.
- `MaxAdGateway` (`lib/services/ads/max_ad_gateway.dart`) — the real
  integration, written against the actual `applovin_max` v4.6.4 API
  (verified by reading the installed package source, not from memory).
- `bootstrap.dart`'s `ads.init` step, `game_screen.dart`'s interstitial call
  at the level-complete "Continue" seam, and `LevelCompleteCard`'s rewarded
  "double reward" button — all wired end to end, Noop-backed until step 2
  above lands.

Once step 2 is done, ads should start working with NO further code changes —
the whole point of building this scaffolding ahead of the account existing.

## Verifying the acceptance criteria

| Criterion | How to check |
| --- | --- |
| Ads never show before the player's first completed level, never after a failed/abandoned level, never escalate in frequency | `test/domain/progression/ad_policy_test.dart` (pure) and `test/presentation/screens/game_screen_test.dart`'s "pre-P18: ads at the level-complete seam" group (integration) — both pass today against `NoopAdGateway` and a fake. On a device, play through several levels and confirm interstitials appear no more often than `RemoteConfigKeys.minLevelsBetweenInterstitials` (default 4). |
| dev/stg never serve a real ad unit | Structural, by the three-separate-apps split above — not testable from this repository once real credentials exist, since a "real" ad on a low-stakes dev app is not distinguishable in code from a real ad on prod. Verify manually: confirm the dev/stg MAX apps' own dashboards, not prod's, show the test traffic. |
| Rewarded double-reward credits coins | `functions/test/*.test.ts`'s existing `grantRewardedReward` suite (P14) already covers the server side. Requires a real device + the MAX dashboard's S2S postback configured with `grantRewardedReward`'s URL and the shared secret — outside what this repository can verify alone. |
