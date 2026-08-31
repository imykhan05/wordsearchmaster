# Word Search Master — Cloud Functions

Server-authoritative scoring, leaderboards, account deletion and the rewarded-ad
callback. Chapter 08 / build prompt P14.

Everything here runs in **`asia-south1`** (Mumbai), matching
`AppConfig.functionsRegion` on the client. Those two constants are a matched
pair: a callable deployed to a region the client is not pointed at fails at
runtime with an opaque `internal`/`not-found` that names nothing.

Every **callable** sets `enforceAppCheck: true`. The one **HTTPS endpoint**
cannot — it is called by AppLovin's servers, which hold no app instance — and
substitutes an HMAC shared secret instead. That is the only exception, and
`grantRewardedReward.ts`'s header explains it.

---

## The one rule everything else follows

**The client's score is never read.** It is not even sent: the outbox payload
(`lib/data/repositories/progress_repository.dart`) carries the ordered
`ScoreEvent` list and no total. The server replays those events through its own
port of the scoring spec and writes the number *it* computes.

That is why `functions/src/scoring.ts` exists and why it is a port rather than
an approximation. The normative text is the header of
`lib/domain/scoring/scoring.dart`; both implementations use the same integer
points-per-grapheme table (`[10, 12, 14, 16, 18, 20]`) rather than a float
multiply, because `10 * 1.2` is the classic way two languages disagree by one
point — and one point of disagreement is a rejected submission.

The two are kept in step by a committed fixture:

| Step | Where | Fails when |
| --- | --- | --- |
| Generate | `dart run tool/generate_scoring_fixtures.dart` | — |
| Pin | `test/tool/scoring_fixtures_test.dart` | the fixture no longer matches `scoring.dart` |
| Check | `functions/test/scoring_parity.test.ts` | the TypeScript port disagrees with the fixture |

210 cases (10 hand-picked edges + 200 seeded random replays), including the
worked example from the spec header: `computeScore = 103`, `computeStars = 2`.

---

## Callables

### `submitScore`

A finished journey level.

**Request** — the `levelComplete` outbox row, verbatim:

| Field | Type | Notes |
| --- | --- | --- |
| `language` | `'ur' \| 'hi' \| 'en'` | matches `Language.code` |
| `level` | `int` | 1–300 |
| `completedAt` | `int` | client epoch millis |
| `specVersion` | `int` | `Scoring.specVersion` |
| `events` | `[{t:'w',g:int} \| {t:'x'} \| {t:'h'}]` | `ScoreEventCodec`'s wire form |
| `nonce` | `string` | `level:{lang}:{level}:{completedAt}`; derived server-side if absent |
| `stars` | `int` | read **only** as a tamper signal |
| `hintsUsed` | `int` | read **only** as a tamper signal |

**Response** — identical in shape whether the submission was accepted or
flagged. There is no `suspicious` field and no flag list, deliberately:

```jsonc
{ "score": 156, "stars": 3, "bestScore": 156, "bestStars": 3,
  "specVersion": 1, "alreadyRecorded": false }
```

`alreadyRecorded` is `true` for a replayed nonce or a spent daily. It says
nothing about whether anything was flagged.

### `submitDaily`

A finished Daily Challenge. Same request shape with `date` (`YYYY-MM-DD`, the
`DayKey` string) instead of `level`, and the same response.

**One entry per uid per (language, date), enforced server-side.** A second,
differently-nonced attempt returns the *first* result and writes nothing — "one
attempt per day" with a best-of write would let a player grind the daily
leaderboard. The rule is per language as well as per date because a date has
three different daily puzzles (`DailyRepository` keys its rows the same way);
the single `daily_{date}` board keeps the best of them.

### `deleteAccount`

Required by Play policy. Takes no arguments.

Deletes, **in this order**: every `leaderboards/*/entries/{uid}` (found by
collection-group query), `moderation/{uid}` and its flags, `users/{uid}` and
every subcollection, then the Firebase Auth record. Auth is last on purpose — a
player whose auth record is gone cannot retry, so the step that removes the
ability to retry has to be the step that runs when there is nothing left to
retry. Calling it twice is safe.

```jsonc
{ "deleted": true, "uid": "...", "leaderboardEntriesRemoved": 4,
  "moderationRecordsRemoved": 1, "deletedAt": "2026-08-31T12:00:00.000Z" }
```

Local data is untouched, because this function cannot reach it — the same
property `FirebaseAuthService.signOut` has. The player asked to delete their
account, not to be wiped.

### Error codes

| Code | When | Returned to a suspected cheater? |
| --- | --- | --- |
| `unauthenticated` | no auth context | n/a — guest-first means every real player has a uid |
| `invalid-argument` | the payload is **malformed**: missing or wrong-typed field, unknown language, unreadable event, `events` past 500 entries | yes — an honest client cannot produce it, and there is no player behaviour to attribute |
| `resource-exhausted` | more than 240 submissions in one hour | yes — it is backend protection, not a cheat signal, and an honest client wedged in a retry loop needs the answer |
| `internal` | `deleteAccount` could not remove the auth record | n/a |
| `failed-precondition` | App Check token missing or invalid (raised by the runtime) | n/a |

**Nothing else is an error.** Every cheat signal resolves to a flagged write and
a normal-looking success — see below.

---

## The validation pipeline (Ch08)

`src/validation.ts` is pure and fully unit-tested without an emulator. In order:

1. **Nonce replay** — a repeat returns the stored result and writes nothing.
   *A replay is a success, not an error*: the outbox is at-least-once, so a row
   whose response was lost to a dropped connection is retried, and refusing it
   would strand a level the player really finished.
2. **Level existence** — 1–300, from the Ch07 curve. `src/levels.ts` derives the
   shape rather than shipping `assets/content/levels.json`, and
   `levels.test.ts` checks the derivation against all 900 real rows.
3. **Word-count bounds** — `[wordCount - 1, wordCount]`. The floor allows one
   fewer word because P12's anti-frustration downshift genuinely hands a
   struggling player one; insisting on an exact match would silently flag the
   players the DDA exists to help.
4. **Grapheme plausibility** — 2 to `min(9, gridSize)` per word.
5. **Timing plausibility** — a cumulative, order-independent bound: the span of
   client completion times an account claims must cover the minimum time its
   submitted work could take. Order independent because a retried outbox row
   can land behind a newer one; cumulative because relaxed mode has **no timer**
   to send a per-level duration from.
6. **Clock sanity** — more than 10 minutes in the future, or more than 400 days
   in the past. Out-of-window timestamps are excluded from the timing
   accumulator, because the cheapest attack on a cumulative bound is to inflate
   the bound.
7. **Progression continuity** — `level <= highestCompleted + 1`, the server
   saying what `JourneyMap` derives on the client.
8. **Rate limiting** — 240/hour, sized for an **offline backlog drain**: twenty
   levels played on a plane arrive within seconds of the radio returning, and a
   limit tuned to interactive play would reject real progress.
9. **Server-side recomputation** — always. The written score is the replayed one.

### What the timing check does not catch

Stated as plainly as `integrity.dart` states its own limits: it catches the
naive forgery — fifty completions with adjacent timestamps — because that span
is seconds wide and the work claimed inside it is hours. It does **not** catch a
forger who spaces fake timestamps plausibly. Nothing measured from
client-supplied time can, because there is no clock to measure with. That
ceiling is acceptable because of what it is one signal among: a
perfectly-paced forgery still has to pass progression continuity and word-count
bounds, and it still only earns whatever score its own events justify.

---

## Suspicious handling

A flagged submission is **never** answered with an error.

- The response is byte-identical in shape to an accepted one.
- The score document carries `suspicious: true` and the flag list.
- `updateLeaderboards` skips it, so it reaches no public board.
- The full payload — including the raw events, so a moderator can replay it by
  hand — lands in `moderation/{uid}/flags/{autoId}`.
- A flagged submission **never overwrites an honest best score**. If a clean
  result already exists for that level it is left alone and only a
  `flaggedSubmissions` counter moves, so one false positive cannot destroy
  something a player earned.

| Flag | Meaning |
| --- | --- |
| `spec_version_mismatch` | client scored under different rules |
| `unknown_level` | level id outside 1–300 |
| `word_count_out_of_bounds` | more or fewer words than the level has |
| `grapheme_count_implausible` | a word longer than the board, or shorter than 2 |
| `hint_count_implausible` | more hints than the level has words |
| `timing_floor` | claimed play span cannot cover the work submitted |
| `clock_ahead` | completion stamped in the future |
| `clock_rewound` | completion stamped from before the game existed |
| `progression_gap` | level reached without the one before it |
| `client_stars_mismatch` | declared stars disagree with the events |
| `client_hints_mismatch` | declared hints disagree with the events |

---

## `updateLeaderboards`

Firestore trigger on `users/{uid}/scores/{scoreId}`.

**It copies; it never accumulates.** A Firestore trigger is at-least-once, so
"add this score to the total" silently double-counts — rarely enough to be
discovered months later on a leaderboard nobody can explain. The totals are
accumulated inside `recordSubmission`'s transaction, which is exactly-once
because the nonce guards it; this function only mirrors them. Running it twice
writes the same bytes twice.

| Board id | Score it holds |
| --- | --- |
| `global` | sum of the player's best score on every puzzle |
| `ur` / `hi` / `en` | the same, per script |
| `weekly_{ISO week}` | points **earned** in that week, keyed by when the level was *played*, not synced |
| `daily_{YYYY-MM-DD}` | the player's best daily for that date |

Entries hold **exactly** `{ uid, displayName, photoUrl, score, updatedAt }` and
nothing else. A leaderboard is the only collection other players read, so every
field on it is a publication decision; `displayName` and `photoUrl` are there
because the player chose to display them.

Totals move by the **improvement** over the previous best, never by the raw
score, so replaying a level cannot pump a board.

**Known open question.** `daily_{date}` is keyed by the date alone, per the
Ch08 contract, so one board holds all three languages. That is defensible
today: `DailyPuzzle` fixes an identical shape for all three (10x10, 8 words,
diagonal tier) and `Scoring` is language-blind, so the boards compare like with
like and only the word pack differs. If a future prompt establishes that the
packs are not equally hard, the split is `daily_{date}_{lang}` plus a
migration.

---

## `grantRewardedReward` (HTTPS)

The AppLovin MAX server-side reward callback. **The client can never grant
itself a reward** — the only path that mints coins is one the client cannot
invoke, cannot sign, and cannot observe.

```
GET /grantRewardedReward?user_id=&event_id=&amount=&ts=&signature=
```

Three defences, each covering the others' gap:

1. **HMAC-SHA256** over `user_id|event_id|amount|ts`, compared with
   `timingSafeEqual`. A plain `===` on a hex digest leaks the correct prefix
   through response timing.
2. **A 15-minute freshness window.** A signature is valid forever; a captured
   URL replayed next month must not still pay out.
3. **Idempotency on `event_id`.** AppLovin retries on a non-2xx — documented
   behaviour, not an edge case — and a retry must not pay twice.

| Response | When |
| --- | --- |
| `200 OK` | granted, or a duplicate that was already granted |
| `400 malformed` | a parameter is missing or not a positive integer |
| `403 bad_signature` | HMAC mismatch |
| `403 stale` | outside the freshness window |
| `404 unknown_user` | no such account |

An honest error is right here: the caller is an ad network, not a player, and
the only thing that reaches a 4xx is a misconfigured callback URL whose owner
needs to know.

Coins are clamped to 500 per callback, so a mis-configured ad unit cannot mint a
fortune, and are written as a **grant record** (`users/{uid}/coinGrants/{eventId}`)
rather than a balance — the client's `coins_ledger` is append-only and locally
signed, so a server-set balance would have nowhere to land.

> **P18 must confirm the signature scheme.** The canonical string is this side
> of a contract whose other side is typed into the MAX dashboard, which is not
> reachable from this repository. Ad networks differ on what they sign and in
> what order; if MAX's differs, change `canonicalString` and nothing else.
> Everything around it — freshness, idempotency, the ceiling, the write path —
> is independent of that choice.

---

## Firestore layout

```
users/{uid}
  displayName, photoUrl              ← the only client-writable fields
  createdAt, updatedAt
  totals: { global, ur, hi, en }     ← server-computed
  weekly: { "2026-W36": n }
  progress: { en: { highestLevel } }
  timing: { submissionCount, earliestCompletedAt, latestCompletedAt, minRequiredMillis }
  rate:   { windowStartMillis, count }
  coinsGranted, suspiciousCount

users/{uid}/scores/{level_en_47 | daily_en_2026-08-31}
users/{uid}/nonces/{base64url(nonce)}
users/{uid}/coinGrants/{base64url(eventId)}
leaderboards/{board}/entries/{uid}   ← the only publicly readable collection
moderation/{uid}/flags/{autoId}
rewardCallbacks/{base64url(eventId)}
```

`firestore.rules` is production-grade from day one (never test mode). The client
may read its own documents and any leaderboard entry, and may write exactly two
fields on its own user document. Everything a score depends on is server-only —
if a rule had to be loosened for a function to work, the function would be doing
something the client could do too.

---

## Working on this

```bash
npm ci
npm run build          # tsc -> lib/
npm run typecheck      # tsc over src AND test
npm run lint           # eslint, type-aware
npm run format:check   # prettier
npm test               # pure unit suites, no emulator
npm run test:emulator  # integration suite under firebase emulators:exec
npm run test:all       # both
```

`npm run test:emulator` needs the Firebase CLI and a JRE (the Firestore
emulator is a Java program). It creates a fresh uid per test, so nothing in it
depends on run order or on cleanup.

### Deploying

```bash
firebase use dev        # or stg / prod, from .firebaserc
firebase functions:secrets:set MAX_REWARD_SECRET
firebase deploy --only functions,firestore:rules,firestore:indexes
```

The collection-group index on `entries.uid` is **not optional**: without it
`deleteAccount` cannot find a player's board entries, and the failure mode is a
player who asked to be deleted staying visible on a public leaderboard.
