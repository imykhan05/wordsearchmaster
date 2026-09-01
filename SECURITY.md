# Security

The Chapter 08 threat model for Word Search Master, what is actually
implemented against each threat, and — the part that matters most — what is
**explicitly accepted** and why.

This file is a record, not a plan. If a row says "accepted", that is a decision
someone made on purpose and can be argued with; if it says "implemented", there
is a file and a test behind it.

---

## Standing assumptions

Three things shape every row below.

1. **The client is hostile by construction.** It is an APK on a device the
   player controls. It can be decompiled, its database opened in a SQLite
   editor, its network traffic replayed. Nothing that runs there is a control;
   at best it is evidence.
2. **The game must work with the radio off.** Ch12 promises an offline Daily
   and Ch10 makes the local database the source of truth. So no defence may
   depend on being online at the moment of play — only at the moment of
   *submission*. This rules out the simplest version of almost every check
   below and is the reason the outbox exists.
3. **A false positive is invisible and permanent.** A flagged player is never
   shown an error (P14's rule), so a check tuned too tight does not produce a
   support ticket — it produces a player who quietly stops appearing on a
   leaderboard and never learns why. Every threshold in
   `functions/src/config.ts` is therefore a false-positive budget, not a
   detection target.

---

## Threat model

| # | Threat | Mitigation | Where | Status |
|---|---|---|---|---|
| T1 | Client submits an inflated **score** | The score is never sent and never read; the server replays the submitted events and writes its own number | `functions/src/submissions.ts`, `functions/src/scoring.ts` | **Implemented** |
| T2 | Client submits a **fabricated but plausible** event list | Word-count bounds, grapheme plausibility, progression continuity, timing floor — all flags, never errors | `functions/src/validation.ts` | **Partial** — see AR-1 |
| T3 | The two scoring implementations **disagree**, so honest submissions are rejected | Integer points-per-grapheme table on both sides; 210-case parity fixture locked from both ends | `lib/domain/scoring/scoring.dart`, `functions/src/scoring.ts`, `functions/test/scoring_parity.test.ts` | **Implemented** |
| T4 | **Replay** — one result submitted twice and counted twice | Per-attempt nonce, checked and written in the same transaction as the score; a repeat returns the stored result and writes nothing | `lib/data/local/submission_nonce.dart`, `functions/src/submissions.ts` | **Implemented** |
| T5 | **Progression skipping** — submit level 250 without playing 1–249 | Server compares against the recorded high-water mark; unlocking is derived, never a stored flag | `functions/src/validation.ts`, `lib/domain/progression/journey_region.dart` | **Implemented** |
| T6 | **Local database tampering** — edit coins, stars, streak in the `.db` file | HMAC-SHA256 tag per row, bound to the row's address; append-only ledger enforced by SQLite triggers; failed rows dropped and reported | `lib/data/local/integrity.dart`, `lib/data/local/tables.dart` | **Partial** — see AR-2 |
| T7 | **Device clock manipulation** — reach tomorrow's Daily, forge a streak | UTC day keys everywhere; server time preferred, local floored at the highest day already seen; server flags completions in the future or older than 400 days | `lib/services/time/trusted_clock.dart`, `functions/src/validation.ts` | **Partial** — see AR-3 |
| T8 | **Direct Firestore writes**, bypassing the Cloud Functions entirely | Rules deny every client write to `scores`, `nonces`, `coinGrants`, `leaderboards`, `moderation` and `rewardCallbacks` | `firestore.rules` | **Implemented** |
| T9 | **Server-authored fields edited** on the player's own user document | Update rule restricted to a three-key diff set; create rule restricted to the same keys | `firestore.rules` | **Implemented** — see AR-8 for the exact guarantee |
| T10 | **Enumerating other players** — listing `/users` for names and photos | `allow list: if false` on `/users`; `get` is owner-only | `firestore.rules` | **Implemented** |
| T11 | **Leaderboard pollution** — forged entries, inflated totals | Entries are written only by the Admin SDK; totals move by the improvement over the previous best, so replays cannot pump a board; flagged scores never reach a board | `functions/src/updateLeaderboards.ts` | **Implemented** |
| T12 | **Abusive or oversized display names** published to every player | 24-character cap and a string type check, on create and update alike | `firestore.rules` | **Partial** — see AR-4 |
| T13 | **Rewarded-ad fraud** — client grants itself coins | Coins are minted only by an endpoint the client cannot invoke: HMAC-SHA256 over the callback parameters with `timingSafeEqual`, a 15-minute freshness window, idempotency per `event_id`, and a hard ceiling per grant | `functions/src/grantRewardedReward.ts` | **Implemented** — see AR-5 |
| T14 | **Calls from outside the app** — a script hitting the callables directly | `enforceAppCheck: true` on every callable; Play Integrity in production, debug provider on dev/stg | `functions/src/index.ts`, `lib/services/app_check/app_check_gateway.dart` | **Partial** — see AR-6 |
| T15 | **Submission flood** against the backend | Fixed-window rate limit, 240/hour/uid, sized for an offline backlog drain | `functions/src/config.ts` | **Implemented** |
| T16 | **Cheater learns which check caught them** and iterates | No error is ever returned for a cheat signal; the response is byte-identical in shape to an accepted one; `moderation/` is unreadable by every client | `functions/src/submissions.ts`, `firestore.rules` | **Implemented** |
| T17 | **PII exposure** on a public board | Entries hold exactly `{uid, displayName, photoUrl, score, updatedAt}` — nothing else, ever | `functions/src/updateLeaderboards.ts` | **Implemented** |
| T18 | **Incomplete account deletion** (Play policy) | One callable removes the user doc, every subcollection, every board entry, the moderation trail and the auth record; Firestore first, auth last, so a partial failure stays resumable | `functions/src/deleteAccount.ts` | **Implemented** — see AR-7 |
| T19 | **Secrets committed to the repository** | No Firebase credentials in the repo at all (`FlavorFirebaseOptions` returns null and `docs/firebase-setup.md` is the runbook); the MAX shared secret is a Secret Manager secret; the keystore is gitignored | `lib/app/config/firebase_options.dart`, `.gitignore` | **Implemented** |
| T20 | **Real ad units served from dev/stg** — the usual cause of a permanent ad-network ban | Ads only behind `AdGateway`; dev/stg use MAX test mode and an `applicationIdSuffix` | CLAUDE.md § Flavors | **Planned (P18)** |
| T21 | **Forged Collector claim** — a client asserting it finished a category it never played | Bounded plausibility check (known category, known language, meaningful `progress`); a failing claim is flagged to `moderation/`, never granted, never an error | `functions/src/submitAchievement.ts` | **Partial** — see AR-9 (the same content-porting gap) |
| T22 | **Cheap achievements minted directly by the client** | The six counter-backed achievements are written ONLY inside `recordSubmission`'s own transaction, never by a client write; `firestore.rules` denies every client write to `users/{uid}` outside the two profile fields | `functions/src/stats.ts`, `firestore.rules` | **Implemented** |
| T23 | **Invite-code enumeration** — a client brute-forcing codes to find real accounts | `inviteCodes/{code}` is unreadable by any client (server-only, via `redeemInviteCode`); a dedicated, tighter rate limit on redemption attempts, separate from the submission rate window | `functions/src/friends.ts`, `firestore.rules` | **Implemented** |
| T24 | **A forged one-directional "friendship"** | Both sides of `users/*/friends/*` are written in ONE server transaction; the client cannot write either side directly | `functions/src/friends.ts`, `firestore.rules` | **Implemented** |
| T25 | **Rank data staleness or spoofing** | Ranks are computed and written ONLY by the periodic `recomputeLeaderboardRanks` job (Admin SDK); the client cannot write `stats.ranks.*` or an entry's `rank` field | `functions/src/ranks.ts`, `firestore.rules` | **Implemented** — see AR-10 (freshness) |
| T26 | **Surprise Firestore bill from an abandoned snapshot listener** | The leaderboard screen holds a live snapshot ONLY on the currently visible tab; switching tabs or leaving the screen unmounts the subtree that watches it, which Riverpod's `autoDispose` turns into an automatic unsubscribe | `lib/presentation/screens/leaderboard_screen.dart` | **Implemented** |
| T27 | **Contact-book harvesting** to find friends | No contact permission is ever requested; the only path to a friend is a code the OWNER chose to share through the native share sheet | `lib/services/friends/friends_service.dart` | **Implemented** |

---

## Accepted risks

Each of these is a real gap. They are listed because a threat model that only
records wins is a marketing document.

### AR-1 — A well-paced forged replay passes every plausibility check

The timing check compares the span of client completion times an account claims
against the minimum time its submitted work could take. It catches the naive
forgery — fifty completions with adjacent timestamps — and it does not catch a
forger who spaces fake timestamps like a human.

Nothing measured from client-supplied time can, because relaxed mode has **no
timer**: `Scoring.computeStars` takes no elapsed parameter on purpose, so there
is no honest duration for the client to send, and anything it did send would be
client-controlled.

**Why this is acceptable:** the forgery still only earns what its own events
justify, because the score is always recomputed. Beating the timing check does
not buy points; it avoids a flag.

**What would close it:** see AR-9.

### AR-2 — Local integrity tags are tamper evidence, not tamper proof

The HMAC key is derived from a constant compiled into the APK plus the install
id, and both live on the player's device. Anyone willing to decompile the app
can forge a tag. `integrity.dart`'s own header says so.

**Why this is acceptable:** it is not the anti-cheat. It catches the SQLite-editor
player, catches corruption from a bad restore for free, and turns every
rejection into a Crashlytics signal so a cheat that does get written shows up in
aggregate. The real control is server-side replay.

**What would close it:** nothing available on-device. Key material that a rooted
device cannot read does not exist in a Flutter app.

### AR-3 — A clock set forward offline still reaches tomorrow's Daily

`TrustedClock` prefers server time when online, falls back to local time
offline, and floors local time at the highest day already seen. The floor stops
a clock being wound *back*; it cannot stop one wound *forward* before the first
sync.

**Why this is acceptable:** the player pays for it. The floor then holds them at
the day they invented until real time catches up, and their streak breaks across
the gap. The submission itself is still adjudicated server-side.

### AR-4 — Display names are length-checked, not moderated

A 24-character cap and a string type check. No profanity filter, no
homoglyph normalisation, no reporting flow — so a player can put an offensive
name on a public leaderboard until someone notices.

**Why this is acceptable *for now*:** it is a launch-scale problem, and a bad
filter is worse than none (they reject real names in Urdu and Hindi far more
often than they catch abuse in either).

**What is still owed before a public leaderboard ships:** a report action on a
leaderboard row and a moderation queue that can blank a `displayName`
server-side. Tracked here, not implemented.

### AR-5 — The MAX callback signature scheme is unverified against the real dashboard

`canonicalString` signs `user_id|event_id|amount|ts`. The other side of that
contract is typed into the AppLovin MAX dashboard, which is not reachable from
this repository, and ad networks differ on what they sign and in what order.

**Why this is acceptable:** everything around it — freshness, idempotency, the
coin ceiling, the write path — is independent of the choice, and a mismatch
fails closed (every callback is rejected with a 403 and nobody is paid). P18
must confirm the scheme and change that one function if it differs.

### AR-6 — App Check runs in monitor mode for the first two weeks

A console setting nothing in this repository can change. During that window an
unattested caller is *recorded* rather than blocked.

**Why this is acceptable:** turning enforcement on before the metrics show
legitimate traffic passing is how a release locks out every real player at once
— usually the ones on older devices where Play Integrity is flakiest, which is
exactly this game's audience. The four-step ramp is written into
`app_check_gateway.dart`'s header.

### AR-7 — Account deletion also deletes the moderation trail

Deleting an account removes its `moderation/` records, so a cheater can launder
their history by deleting and re-creating.

**Why this is acceptable:** those records are unambiguously data about a person
who asked for their data to be deleted, and Play policy carves out no exception
for records the developer finds useful. The deterrent that remains is the one
that was always doing the work — deleting the account also deletes every level,
coin and streak.

### AR-8 — A server-authored field may be *restated*, though never *moved*

The update rule uses `request.resource.data.diff(resource.data).affectedKeys()`,
which is a **value** diff. A write that includes `suspiciousCount` at the value
it already holds does not "affect" it and is allowed.

**Why this is acceptable:** it changes nothing. There is no Firestore v2
primitive for "which fields did the client mention" — `writeFields` was v1 and
is gone — so a value diff is the only tool, and it gives exactly the guarantee
that matters: no server-authored value can be changed. Both halves are pinned in
`rules_test/firestore_rules.test.ts` so a future reader meets this as a
documented property rather than a suspected hole.

### AR-9 — The server does not verify that the submitted words were in the grid

This is the largest remaining gap, and it is worth stating precisely.

`submitScore` checks that the number of words is right for the level, that each
claimed grapheme count could belong to a word on that board, and that the score
follows from the events. It does **not** check that those words were actually in
that puzzle. A forger who knows the bounds can submit the maximum-scoring
plausible replay for a level they did play.

The score that buys is bounded — the checks cap it near what an honest perfect
run on that level would earn — so this is leaderboard-shaping, not
score-minting.

**What would close it:** the grid is deterministic from the level seed (P04), so
the server *could* regenerate it and confirm each claimed word. That needs the
word packs shipped into the function bundle and `GridGenerator`, `WordSelector`
and `ScriptNormalizer` ported to TypeScript — a third language-sensitive port to
keep in step with Dart, on top of the scoring one. Deliberately not attempted
here; it is a prompt of its own, and it should be weighed against just capping
per-level scores at the honest maximum, which is far cheaper and catches most of
the value.

**The same gap reappears in P17's Collector achievement**, for the identical
reason: the server cannot check that a claimed category was actually completed
without the same word-pack port. `submitAchievement.ts` accepts what it can
check — a real category name, a real language, meaningful `progress` — and
flags the rest to `moderation/` without granting it. The stakes are lower here
by design: a forged Collector claim costs a cosmetic badge, never a
leaderboard position or a coin, so this file makes the same
cheap-mitigation-over-expensive-completeness call AR-9 already makes for
scoring, on purpose.

### AR-10 — A leaderboard rank is never more current than the last periodic run

Ranks (P17) are written by `recomputeLeaderboardRanks`, a scheduled function
that reads a whole board and writes every entry's position, on a fixed
interval (`RUN_INTERVAL_MINUTES` in `functions/src/ranks.ts`'s header — 15
minutes at the time of writing). Between runs, a player who climbs past
several rivals sees their OLD rank until the next run lands.

**Why this is acceptable:** the alternative is computing a rank on every
`submitScore` call by reading the whole board first, which is precisely the
"download 100k docs to count" cost this design exists to avoid — paid on every
level completion instead of amortised across every leaderboard view between
runs. A rank fifteen minutes stale answers the question a player is actually
asking ("roughly where do I stand") without that cost.

**What is NOT covered:** the rank-writing job itself could not be exercised
under the scheduler in this sandbox, for the same outbound-proxy restriction
that already prevented registering the P14 Firestore trigger — see
`functions/README.md`. The function BODY (`recomputeRanksForBoard`) is
exercised directly against the Firestore emulator; the schedule wiring that
calls it every 15 minutes is not.

---

## Firestore rules

`firestore.rules` is the deployed ruleset. It has never been in test mode.

Every rule has **at least one ALLOW test and one DENY test** in
`rules_test/firestore_rules.test.ts`, which runs against the emulator in CI
(the `rules` job in `.github/workflows/ci.yaml`). A rules regression fails the
build, which matters more here than anywhere else in the repo: a loosened rule
breaks nothing visible. The app keeps working. It just stops being safe.

```bash
npm ci
npm run test:rules      # firebase emulators:exec --only firestore
npm run typecheck:rules
```

The suite loads the real `firestore.rules` file rather than a copy, uses the
emulator-only project id `demo-wsm-rules` so it can never touch a real project,
and seeds server-authored state through `withSecurityRulesDisabled` — which is
also how it proves the allow half of rules whose client answer is always "no"
(the server really can delete a user document; a moderator really can read
`moderation/`).

---

## Reporting a vulnerability

**REQUIRED BEFORE PUBLIC RELEASE: this section needs a real contact address.**

There is deliberately no invented address here. Before the app is listed, add a
monitored security contact (an alias, not a personal inbox) and a statement of
expected response time. Until then, report issues through the repository's issue
tracker and mark them clearly.
