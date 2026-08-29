# Firebase setup runbook (P13)

Everything in `lib/` that talks to Firebase is written and tested. What is
**not** in this repository is the credentials, because generating them needs
an interactive Firebase login and three projects that only a human with the
account can create.

Until these steps are run, `FlavorFirebaseOptions.forFlavor` returns `null`,
`bootstrap.dart` skips `Firebase.initializeApp`, every Firebase-backed service
keeps its Noop binding, and the app runs as a fully playable local-only game.
That is the same code path as airplane mode, and it is covered by
`test/app/bootstrap_offline_test.dart` — so the unconfigured state is
exercised, not merely tolerated.

## 1. Create the three projects

Three separate Firebase projects, one per flavor (CLAUDE.md → Flavors). They
must be separate: a shared project means a dev build can write to production
Firestore and a staging test can move a real leaderboard.

| Flavor | Project ID | Android package name        |
| ------ | ---------- | --------------------------- |
| dev    | `wsm-dev`  | `com.wordsearchmaster.app.dev` |
| stg    | `wsm-stg`  | `com.wordsearchmaster.app.stg` |
| prod   | `wsm-prod` | `com.wordsearchmaster.app`     |

The package names come from the `applicationIdSuffix` values already set in
`android/app/build.gradle.kts`, which is what lets all three be installed on
one device at once.

Enable in each project: **Auth** (Anonymous + Google providers), **Firestore**,
**Functions**, **Analytics**, **Crashlytics**, **Remote Config**, **App Check**.

> Firestore rules: production rules from day one, never "test mode"
> (CLAUDE.md → Never do). P14 owns the rules themselves.

## 2. Generate the options files

```sh
dart pub global activate flutterfire_cli

flutterfire configure \
  --project=wsm-dev \
  --out=lib/app/config/firebase_options_dev.dart \
  --android-package-name=com.wordsearchmaster.app.dev \
  --platforms=android

flutterfire configure \
  --project=wsm-stg \
  --out=lib/app/config/firebase_options_stg.dart \
  --android-package-name=com.wordsearchmaster.app.stg \
  --platforms=android

flutterfire configure \
  --project=wsm-prod \
  --out=lib/app/config/firebase_options_prod.dart \
  --android-package-name=com.wordsearchmaster.app \
  --platforms=android
```

Each run writes a `DefaultFirebaseOptions` class. Rename each to
`DevFirebaseOptions` / `StgFirebaseOptions` / `ProdFirebaseOptions` (three
classes with the same name cannot coexist), then wire them into the three
`switch` arms in `lib/app/config/firebase_options.dart`. Nothing else in the
app reads credentials.

## 3. Google Sign-In server client id

For each project, open `google-services.json` and find the `oauth_client`
entry with `"client_type": 3` — the **web** client. Paste it into
`FlavorFirebaseOptions.googleServerClientId`.

Use the web client id, not the Android one. The Android client id produces an
id token with the wrong audience, and `linkWithCredential` then fails with an
error that reads like a generic sign-in failure rather than a config mistake.
This is the most common way to lose an afternoon on this step.

## 4. App Check — leave enforcement OFF

Register the Play Integrity provider for the prod app. Register a debug token
for dev/stg (run the app once; the debug provider prints a token to logcat —
paste it into the console's debug token list).

**Every App Check API stays Unenforced (monitor mode) for the first two weeks
post-launch.** The reasoning, the four-step ramp, and why P13's acceptance
criterion is satisfied by tokens *arriving* rather than by enforcement being
on, are all in the library header of
`lib/services/app_check/app_check_gateway.dart`. Read that before changing the
toggle.

## 5. Crashlytics + Functions region

- Crashlytics needs the Gradle plugin applied in `android/app/build.gradle.kts`
  and a first crash to appear in the console before it will show data.
- Functions are deployed to `asia-south1` (see `AppConfig.functionsRegion`) —
  P14 deploys them, but the region is pinned client-side now so the two cannot
  disagree later.

## Verifying the acceptance criteria

| Criterion | How to check |
| --- | --- |
| Airplane-mode cold start works and the game is playable | Covered automatically by `test/app/bootstrap_offline_test.dart`. On a device: enable airplane mode, force-stop, relaunch — level 1 must load and be playable. |
| Guest → Google link keeps progress | Merge rules covered by `test/domain/progression/account_merge_test.dart` and the write path by `test/data/repositories/account_merge_repository_test.dart`. On a device: play a few levels as a guest, sign in with a Google account that already has progress, confirm the union survives. |
| App Check tokens visible in the console | Requires a real device + real project. Firebase console → App Check → the request chart shows verified vs. unverified counts. |
