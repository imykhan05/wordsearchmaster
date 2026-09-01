# Play Console — Data Safety form answer sheet

Fill this in at Play Console → App content → Data safety. Every row below is
mapped to an actual data collection point in the codebase, not guessed —
cross-check against `lib/services/`, `lib/data/remote/`, and
`functions/src/` if anything looks off before submitting.

**Re-check this sheet when P18 (ads) ships** — the AppLovin MAX rows are
marked below and are the one section that goes from "not collected" to
"collected" the moment that prompt lands.

## Does your app collect or share any of the required user data types?

**Yes.**

## Data types collected

| Data type | Collected? | Shared? | Purpose | Optional? | Source |
|---|---|---|---|---|---|
| Name (display name) | Yes | Yes (public leaderboard) | Account management, App functionality | Yes — only if you sign in with Google and opt into leaderboards | `lib/services/auth/`, `functions/src/submissions.ts` |
| Email address | Yes | No | Account management | Yes — only if you sign in with Google | `lib/services/auth/firebase_auth_service.dart` |
| User IDs | Yes | Yes (public leaderboard entries reference a uid) | App functionality, Analytics | No — an anonymous id is always created | `lib/services/auth/` |
| Photo (profile photo URL) | Yes | Yes (public leaderboard) | App functionality | Yes — only via Google sign-in | Google Sign-In profile |
| App activity (in-app actions, other app activity) | Yes | No | App functionality, Analytics | No | `lib/services/analytics/`, `lib/application/` |
| App info and performance (crash logs, diagnostics) | Yes | No | Analytics | No | Firebase Crashlytics, `lib/services/error/` |
| Device or other IDs | Yes | No (Yes once ads ship — see below) | Analytics | No | Firebase installation ID |

## Data types NOT collected

Location, financial info, health/fitness, messages, photos/videos beyond
the optional profile photo, contacts (explicitly never accessed — see
`lib/presentation/meta/friends_tab.dart`'s own header comment), calendar,
web browsing history, files/docs.

## Security practices

- **Data is encrypted in transit**: Yes (Firestore/Functions traffic is TLS).
- **You can request that data be deleted**: Yes — in-app Delete Account
  button (`functions/src/deleteAccount.ts`) plus the email fallback on
  `docs/account-deletion.html`.
- **Committed to the Play Families Policy**: No — this app does not target
  children primarily; leave the Families section unchecked.

## Once P18 (AppLovin MAX rewarded ads) ships — ADD these rows

| Data type | Collected? | Shared? | Purpose | Optional? |
|---|---|---|---|---|
| Advertising ID | Yes | Yes (with AppLovin, an ad network) | Advertising or marketing | No, if ads are shown at all — but the game itself stays playable with the rewarded button simply disabled offline/if declined |
| Device or other IDs | Yes | Yes (with AppLovin) | Advertising or marketing | No |
| Approximate location (if the device permits) | Possibly | Yes (with AppLovin) | Advertising or marketing | Depends on AppLovin MAX SDK's own data collection — **confirm the exact fields against the MAX SDK's own Data Safety mapping in the AppLovin dashboard before submitting**, the same "must confirm against the MAX dashboard" caveat CLAUDE.md's P14 section already flags for the reward signature. |

## Third parties data is shared with

- Google Firebase (Authentication, Firestore, Crashlytics, Analytics, Remote Config, App Check) — infrastructure processor.
- AppLovin (ad network) — **once P18 ships**, for ad serving and measurement.

## Notes for whoever fills the live form

- Every "collected" row above traces to a real service binding under
  `lib/services/` or `lib/data/remote/` — if a row here doesn't match code
  you can find, don't submit it as-is; find the actual code path first.
- The Google Play Data Safety form's exact category names shift between
  console versions; match by *meaning* (e.g. "User IDs", "App activity") to
  whatever the current console shows, don't expect verbatim string matches.
