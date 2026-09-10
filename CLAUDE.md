# Word Search Master — Engineering Rules

## Product

Relaxed, offline-first word puzzle. Urdu (RTL) + Hindi + English, each rendered
in its correct script. Target device: 2GB RAM Android, Android 7+ (API 24).
Default = NO timer ("Blitz" timed mode is opt-in only, post-v1.0).

One-line thesis: **a relaxed, offline-first word puzzle that renders Urdu,
Hindi and English correctly in their own scripts, playable by a 45-year-old
on a 2GB-RAM phone with no internet.** Every word in that sentence is an
engineering constraint — when a feature decision is unclear, come back to it.

Full product/engineering spec: see the Production Bible (16 chapters, 24
build prompts across 6 waves) this repo is being built from. Prompts are run
one at a time, in order (P01 → P24); each prompt's acceptance criteria must
pass — `flutter analyze` clean, `flutter test` green, criteria met, commit —
before the next prompt starts.

## Architecture (mandatory)

- Layers: `presentation` → `application` (Riverpod) → `domain` (PURE DART) → `data`
- `lib/domain/**` must NOT import `package:flutter`. Ever. Enforced in CI via
  `tool/check_domain_purity.dart`.
- UI never touches Firestore directly. Repositories only.
- Local DB (Drift) is the source of truth. Network is background sync only
  (outbox pattern) — the game is 100% playable offline.
- Ads only behind the `AdGateway` interface. Game code never imports
  `applovin_max` directly — only `services/ads/max_ad_gateway.dart` may.
- No `setState` in game screens — Riverpod only. Grid repaints inside a
  `RepaintBoundary`.
- Models are `freezed` + `json_serializable`. No hand-written `toJson`.
- Client never writes scores directly to Firestore — a Cloud Function
  recomputes and writes them server-side (anti-cheat).

### Folder structure

```
lib/
├── main_dev.dart · main_stg.dart · main_prod.dart   ← 3 flavors
├── app/
│   ├── router.dart              go_router, deep links
│   ├── theme/                   tokens, typography, motion constants
│   ├── config/                  AppConfig, flavor definitions
│   └── bootstrap.dart           init order: Firebase → RemoteConfig → Ads → App
│
├── domain/                      ★ PURE DART — no flutter import, ever
│   ├── grid/
│   │   ├── grid_generator.dart      seeded placement algorithm
│   │   ├── word_placer.dart         backtracking + overlap scoring
│   │   ├── filler_strategy.dart     frequency-weighted fillers
│   │   └── selection_resolver.dart  drag → direction lock → word match
│   ├── scoring/                     score, stars, combo, streak rules
│   ├── progression/                 level unlock, DDA, chest tables
│   ├── text/
│   │   ├── script_normalizer.dart   Ch 04 rules (Urdu/Hindi normalization)
│   │   └── grapheme.dart            .characters helpers
│   └── models/                      freezed immutable models
│
├── data/
│   ├── local/                   Drift DB: profile, progress, outbox, cache
│   ├── remote/                  Firestore + Functions clients
│   ├── repositories/            local-first, sync-backed
│   └── content/                 words JSON loader + level defs
│
├── application/                 Riverpod notifiers (use cases)
│   ├── game_controller.dart
│   ├── progression_controller.dart
│   ├── sync_controller.dart     the outbox drain (P16)
│   └── ad_controller.dart
│
├── services/
│   ├── ads/
│   │   ├── ad_gateway.dart      ★ abstract interface
│   │   ├── max_ad_gateway.dart  AppLovin MAX implementation
│   │   └── noop_ad_gateway.dart tests + "ads off" state
│   ├── analytics/               event taxonomy, typed events
│   ├── remote_config/           live-ops levers
│   ├── audio/
│   └── haptics/
│
└── presentation/
    ├── screens/                 language, home, journey, game, daily, leaderboard, profile, settings
    ├── game/
    │   ├── grid_painter.dart    ★ one CustomPainter — not 144 widgets
    │   ├── gesture_layer.dart
    │   └── particles.dart
    └── widgets/
```

The server half lives outside `lib/` entirely:

```
functions/                      ★ TypeScript, region asia-south1 (P14)
├── src/
│   ├── scoring.ts              the TS half of the scoring contract
│   ├── validation.ts           the Ch08 pipeline — PURE, no Firestore
│   ├── levels.ts               the Ch07 curve, ported; checked against the asset
│   ├── submissions.ts          submitScore/submitDaily's shared transaction
│   ├── updateLeaderboards.ts · deleteAccount.ts · grantRewardedReward.ts
│   └── index.ts                the exported callables and the trigger
└── test/                       pure suites + an emulator-backed integration suite

firestore.rules · firestore.indexes.json · firebase.json · .firebaserc
```

## Flavors — three separate worlds

| Flavor | Firebase project | Ads          | Analytics       |
|--------|-------------------|--------------|------------------|
| dev    | wsm-dev            | MAX test mode | DebugView        |
| stg    | wsm-stg            | MAX test mode | separate property|
| prod   | wsm-prod           | Real ad units | Production       |

`dev` and `stg` use an `applicationIdSuffix` so all three can be installed on
one device at once. `dev`/`stg` must never be able to serve a real ad unit —
that is the single most common cause of a permanent AdMob/MAX account ban.

## Design system

All tokens live in `lib/app/theme/` — import the `theme.dart` barrel.

- **Colours**: `lib/app/theme/app_tokens.dart` is the ONLY file in `lib/` that
  may contain a colour literal. Everywhere else reads
  `AppTokens.of(context).colors.*`. Enforced by
  `tool/check_no_raw_colors.dart` in CI, which rejects `Color(0x...)`,
  `Color.fromARGB/fromRGBO` and `Colors.*`.
- **Spacing** `AppTokens.space4..space48` (4/8/12/16/24/32/48);
  **radii** `AppTokens.radius4/8/16`. No bare numbers in `EdgeInsets`.
- **Elevation**: `AppTokens.elevation1/2/3` — each is a tinted surface AND
  shadows. Never shadow alone; on the dark theme a shadow against a near-black
  ground is invisible.
- **Found-word palette**: `colors.foundWord` (6) with matching
  `AppTokens.foundWordBorderWidths`. Colour is never the only cue. The palette
  was chosen by maximising minimum pairwise CIE ΔE under normal, protanopic
  and deuteranopic vision; `found_word_palette_test.dart` re-runs that
  simulation, so substituting a colour is checked, not assumed.
- **Motion**: `Motion.instant/quick/base/slow` + `Motion.punch/settle/fade`.
  Never a raw `Duration` or bare `Curves.*` at a call site. Use
  `Motion.of(context)` so reduce-motion collapses every duration to zero.
- **Style Gallery**: `/dev/style-gallery`, registered only on the dev flavor.
  Every token, both themes, all three scripts on one page — check it after any
  theme or font change.

## Grid engine (P04)

- `GridGenerator.generate` is pure Dart and DETERMINISTIC: one `Random(seed)`
  drives everything. Levels store a seed, never a grid — that is what makes
  level 47 identical everywhere and the Daily Challenge work offline. Nothing
  in `lib/domain/grid/` may use any other source of randomness.
- It never throws and never loops forever. A word set it cannot satisfy comes
  back in `GridResult.unplacedWords`; P10's validator fails the build on that.
- Placements are found by *crossing-seeded* randomised search: an attempt
  aligns a letter of the incoming word onto a cell already holding that
  grapheme. Uniform sampling almost never hits an existing letter and left the
  intersection ratio well below the Ch06 band.
- Fillers come from `FillerStrategy` — frequency-weighted per language, 60%
  biased toward the target words' own graphemes. Uniform fillers make the
  answers visibly different from the noise.
- After filling, the blocklist scan re-rolls accidental words. Only filler
  cells are re-rolled; a cell belonging to a placed word is never touched.
  Blocklists are assets (`assets/content/blocklist_*.txt`) so a native speaker
  can fix them without touching code. **The Urdu and Hindi lists are empty and
  flagged — they need a native speaker before release.**

## Rendering (P06)

- The grid is ONE painter per logical pass, never 144 widgets, and the passes
  are separate `CustomPaint`s behind `RepaintBoundary`s so that **only the live
  selection may repaint per frame**. Measured on a 12×12: a full letters
  repaint costs 0.956ms, the selection capsule 0.013ms — a 76× ratio, and the
  reason the split exists.
- `GraphemePainterCache` lays out a `TextPainter` once per unique
  grapheme+style. NEVER call `layout()` inside `paint()` for a grapheme
  already seen — 144 layouts a frame is the single biggest perf trap here.
  The cache is instrumented; `hitRate` is asserted in tests, not assumed.
- The live selection is published through a `ValueNotifier` handed to
  `CustomPaint.repaint`. A moving finger must repaint one capsule and rebuild
  **no widgets** — `setState` per pointer move would give back everything the
  pass split buys.
- Gestures come from a raw `Listener` on `localPosition` through
  `GridGeometry`, the same geometry the painters use. No `GlobalKey`, no
  per-cell hit-testing widget, so touch and paint cannot disagree.
- Found-word highlights are a rounded capsule through the cells, not a square
  per cell, and carry their palette border weight as well as colour.

## Selection and scoring (P05)

- `SelectionResolver` is pure Dart and takes a `GridPoint` in CELL UNITS, not
  a `dart:ui` `Offset`. The presentation layer converts pixels → cell units.
  Sub-cell precision is kept deliberately: projecting a continuous pointer
  onto the locked line is what makes the drag feel sticky.
- Direction locks on the second cell to one of the eight vectors, then the
  pointer is PROJECTED onto that line. Dragging off-line must never break the
  selection — that is a required feel property, not a nicety. Returning to the
  anchor unlocks the direction so a player can re-aim without lifting.
- On release, a run of fewer than two cells never matches (a tap is not an
  attempt). Both the forward and reversed sequences are tested, and a
  backwards trace returns its cells re-oriented to the WORD, so animations run
  along the word rather than along the finger.

### `lib/domain/scoring/scoring.dart` is a normative contract

Its file header is the **scoring spec**, and P14's `submitScore.ts`
re-implements it in TypeScript. The two must agree exactly on every input, so:

- Change the spec, the Dart, and the TypeScript port together, and bump
  `Scoring.specVersion`.
- Scoring multiplies by an **integer** points-per-grapheme table
  (`[10, 12, 14, 16, 18, 20]`), never by the displayed float multipliers.
  Float rounding is the classic way two languages silently disagree by one
  point, and one point means a rejected submission.
- Score is computed by REPLAYING an ordered `List<ScoreEvent>`, because the
  combo ladder depends on the sequence of correct and wrong selections. This
  is also the anti-cheat shape from Ch08: the client submits its work, the
  server replays it and computes the number itself.
- `computeStars` takes **no** elapsed-time parameter. Relaxed mode cannot grow
  a time dependency because there is no time to pass in. Blitz (v1.2) gets its
  own function, never a flag on this one.
- The worked example in the header (score 103, 2 stars) is the cross-language
  parity fixture; it is asserted in `scoring_test.dart` and must be asserted in
  the TypeScript tests too.

### Known content constraint: Hindi words rarely intersect

Measured, not assumed. A crossing needs two words to share an IDENTICAL
grapheme, and a Hindi cell holds an akshara drawn from a far larger set than
the Latin alphabet. With words picked at random, only **17–38%** of Hindi
words share a grapheme with anything already placed, against **91–97%** in
English and 75–90% in Urdu.

No generator can cross words that share nothing, so **P10 must assemble level
word sets with shared aksharas in mind for Hindi**, or Hindi levels will be
measurably easier than English and Urdu ones at the same level number. The
test fixture's `pickCohesive` shows the shape of the fix; the real one belongs
in the content pipeline.

## Game state machine (P07)

`lib/application/game_controller.dart` is a `@riverpod` `AsyncNotifier`
family, keyed by the level the screen was OPENED with — advancing a level
(including via the debug panel) mutates `GameState.level` in place rather
than creating a new provider instance, so a screen never has to remount to
keep playing.

- **`GameState` stores events, not counters.** `score`, `combo`, `hintsUsed`
  and `stars` are all derived getters that replay `events: List<ScoreEvent>`
  through `Scoring.*`. This is the same reason P05's `ScoreEvent` exists:
  there is exactly one code path from events to a number, which is what lets
  a future server replay a submission and get the same answer.
- **No live `selection` field.** The bible's GameState shape names one; it is
  deliberately absent. Routing a per-frame drag through Riverpod would
  rebuild the top bar and word list 60 times a second and undo P06's
  three-pass paint split. `GameGridState` keeps owning the live drag in its
  own `ValueNotifier`, unchanged from P06. `GameController.processSelection`
  only ever sees a FINISHED drag, and returns the `SelectionOutcome` directly
  to the caller (for the particle burst) instead of parking it in state —
  nothing else needs to remember it.
- **The Zeigarnik swap (Ch02) is one atomic state update.** The moment a
  level is won, the controller freezes a `LevelCompletionSummary` of the
  level just finished AND regenerates the next level's grid in the same
  `copyWith` — `phase` becomes `levelComplete` while `level`/`grid`/word list
  already describe the level after it. Dismissing the card is only ever a
  phase flip. The dev debug panel's "force levelComplete" runs this exact
  path too, never a stub, so it is a faithful preview.
- **`Positioned` must be a direct `Stack` child.** Wrapping it in
  `RepaintBoundary` (`RepaintBoundary(child: Positioned(...))` instead of
  `Positioned(child: RepaintBoundary(...))`) breaks its `StackParentData`
  silently — `flutter analyze`/`flutter run` release builds do not catch
  this, only an assertion during widget-tree mounting does. The visible
  symptom is worse than a crash: the mis-parented child just expands to fill
  the whole `Stack`. `game_grid_test.dart`'s hint-highlight test pins the
  rendered size specifically so this cannot regress silently again.
- **A tight-constrained `FractionallySizedBox` overrides its child's own
  size.** `Positioned.fill` hands down TIGHT constraints; a
  `FractionallySizedBox` with `heightFactor: null` passes that tightness
  straight through, so a child with an explicit small height (the word-chip
  strike-through's `Container(height: 2)`) gets stretched to fill the whole
  box instead — the same failure shape as the `Positioned` gotcha above, one
  level down. An `Align` between them loosens the constraint so the child's
  own size wins again. Same lesson either way: something in this chain has
  to loosen a tight constraint before a `FractionallySizedBox` with a null
  factor is safe to use.
- **`coinsEarned` is a placeholder formula** (`stars * 10`), flagged
  `TODO(P15/P16)` — the real coin economy lives in `lib/domain/progression/`,
  which does not exist yet.

## Local persistence + integrity (P08)

Drift is the SOURCE OF TRUTH. Every read path in the app resolves against
`lib/data/local/`; the network is background sync only, carried by the outbox.

- **Seven tables** (Ch10): `profile`, `level_progress`, `daily_results`,
  `coins_ledger`, `achievements`, `outbox`, `kv_settings`. `level_progress`
  and `daily_results` are keyed by (language, level/date) — level 47 in Urdu
  is a different puzzle from level 47 in Hindi and earns its stars
  separately.
- **Every mutation writes its game-state row AND its outbox row in ONE
  transaction.** Never one without the other: a progress row with no outbox
  row never syncs, and an outbox row with no progress row submits a level
  nobody played. `outbox_atomicity_test.dart` proves it by installing a
  SQLite trigger that aborts outbox inserts, then checking the progress row
  rolled back too — the real repository path, no mocks.
- **`coins_ledger` is append-only, enforced by SQLite triggers**, not by the
  repository declining to expose an update. The balance is the SUM of
  verified rows, never a stored number, so a wrong balance is traceable to
  the row that caused it.
- **Every row carries an HMAC-SHA256 tag**, keyed by an app constant + the
  install id. Read `integrity.dart`'s header before touching any of it — it
  states honestly that this is tamper EVIDENCE, not tamper proof. The real
  anti-cheat is Ch08's server-side replay (P14); this keeps the local DB
  honest between submissions.
- **The tag binds to the row's ADDRESS** (table + primary key), not just its
  contents. Without that, level 1's finished row can be pasted onto level 50
  and still verify.
- **The canonical encoding is length-prefixed and type-tagged.** A plain
  `join('|')` gives `['a|b','c']` and `['a','b|c']` the same bytes; untagged
  fields let `1` and `'1'` collide. Both are forgeries.
- **`RowTags` is the ONE definition of which columns each table signs.** If
  the repository and the migration disagree by one field, every migrated row
  fails on the next read and the player silently loses their progress.
- **A failed check drops the row, reports a Crashlytics non-fatal, and NEVER
  shows the player an error.** Reports are deduped per row address — a Drift
  stream re-emits on every write, and one bad row would otherwise file
  thousands of identical reports. Tampered rows are excluded but NOT deleted:
  deleting inside a stream's map is re-entrant, and a forged row is evidence.
- **`schemaVersion` is 3.** v2→v3 adds the outbox's `status`/`next_retry_at`
  (P16) as a pure `ADD COLUMN` pair — the row tag signs the submission, never
  the delivery bookkeeping, so nothing is re-tagged.
- **v1→v2:** v1 stored coins as a column on `profile`; the
  migration converts that balance into an opening ledger row. It verifies the
  v1 tag under the v1 field shape FIRST — migrating without checking would
  re-sign a forged balance into a valid v2 ledger entry, a free amnesty for
  anyone who cheated before upgrading.
- **`beforeOpen` must not await `AppDatabase.integrity()`.** That getter
  memoises a Future whose query cannot complete until the database finishes
  opening, and `beforeOpen` is part of opening it — awaiting it there
  deadlocks the connection with no error and no timeout. Resolve the install
  id locally inside the callback instead.
- **Auto-increment ids are allocated explicitly** (`nextRowId`), because the
  id is the row's address and the tag binds to it. Letting SQLite assign it
  would mean inserting first and patching the tag after — which the
  append-only trigger forbids outright.
- `shared_preferences` holds exactly three things: sound, haptics, selected
  language (`UiSettingsStore`). Anything touching game state or sync goes in
  `kv_settings` instead. `ui_settings_store_test.dart` pins that boundary by
  asserting the full key set.

## Juice — audio, haptics, choreography (P09)

Every millisecond below is a literal from Ch03, not a rounded-off estimate.
Where a number happens to already be one of `Motion`'s named durations
(`instant` 90ms, `quick` 140ms) the call site reaches for that constant
instead of repeating the literal; where it doesn't (120ms strike, 160ms score
roll, the reveal's own 90/60/120ms), it is pinned as its own local
`static const Duration`, the same pattern `ParticleLayer.lifetime` set in P06.

- **`AudioService`** (`services/audio/audio_service.dart`) is the interface +
  `NoopAudioService` + `AudioPlayersAudioService` triple, same shape as
  `ErrorReporter`. Each `AudioClip` gets its own small ROTATING POOL of
  `AudioPlayer`s (not `AudioPool`, which has no per-play rate control) so a
  fast player finding two words in one clip's ~100ms lifetime doesn't cut the
  first sound off. Every player is preloaded via `setSource` at startup and
  kept at `ReleaseMode.stop` (never the default `release`), which is what
  makes a play call cheap — `setPlaybackRate` + `resume`, no re-fetch.
  `PlayerMode.lowLatency` is deliberately NOT used: it silences the
  completion/state events the rare same-slot-overlap guard depends on, and
  disables `seek` outright.
- **`ComboPitchLadder`** (`services/audio/combo_pitch_ladder.dart`) is a pure
  Dart, backend-agnostic table of playback-RATE multipliers — semitone
  offsets `[0,2,4,7,9,12]` (C D E G A C-octave) via
  `2^(semitones/12)` — deliberately its OWN table rather than a reuse of
  `Scoring.comboPointsPerGrapheme`, even though both are 1-based and capped
  at 6: scoring is a cross-language normative contract (Ch08/P14); pitch is
  presentation-only and must never be coupled to it. `AudioService.playFound`
  is the one caller, mapping `GameState.combo` straight through.
- **`HapticsService`** (`services/haptics/haptics_service.dart`) wraps
  `HapticFeedback`: `selectionTick`→`selectionClick` (unchanged from P06),
  `wordFound`→`lightImpact`, `levelComplete`→`mediumImpact`,
  `buttonTap`→`selectionClick`. THERE IS NO wrong-selection method — Ch03's
  "no buzz" means the absence of a call, not a method nobody happens to call.
  Unlike `AudioService`, its real binding (`SystemHapticsService`) is the
  PROVIDER DEFAULT, not something `bootstrap.dart` has to remember to wire
  in — there is no vendor SDK or asset to preload, so gating it behind Noop
  until an override lands would only risk silently-dead haptics in
  production if that wiring were ever forgotten.
- **Master mute / haptics toggle** are synced by `audioMuteSyncProvider` /
  `hapticsEnabledSyncProvider`, each a `ref.listen(..., fireImmediately:
  true)` inside a `@riverpod void` provider — a listener, not a direct call
  beside `ref.watch`, because a provider's `build` is supposed to stay free
  of side effects. Watched once, at the app root (`app.dart`).
  `AudioService.setMuted` both gates future `play*` calls AND stops whatever
  is audible right now (`Ch03: "instantly, mid-playback"`); haptics need no
  such stop — there is no in-flight haptic to interrupt.
- **The correct-word sequence** is orchestrated entirely from
  `game_screen.dart`'s `_onSelectionReleased`, never from `GameController` —
  the established P07 seam. At 0ms: audio (`playFound(combo:)`), haptic
  (`wordFound`), and `FoundWordRevealController.reveal(...)`, all
  synchronous with the match. Particles are pushed to start at
  `Motion.instant` (90ms) via `Future.delayed` — skipped entirely, not just
  shortened, when that resolves to `Duration.zero` under reduce-motion, so
  there is no async gap to schedule at all. The word chip's own flip to
  "found" (`_WordChip`, now stateful) waits `Motion.quick` (140ms) before
  starting its existing 120ms strike, via a `ValueNotifier` + `Timer` — never
  `setState`, matching the ValueNotifier-over-setState idiom the rest of the
  gameplay UI already uses. The top-bar score roll
  (`RollingCounter.scoreRollDelay`, 160ms) works the same way, one level
  down inside `RollingCounter` itself: a `_target` ValueNotifier that only
  catches up to the real `value` once the delay elapses, so the counter
  holds at the OLD number until then rather than lying about a live score
  it hasn't earned to show yet.
- **`FoundWordRevealLayer`** (`presentation/game/found_word_reveal.dart`) is
  the 0–120ms flash/punch, mirroring `ParticleLayer`'s spawn/tick/auto-stop
  ticker shape exactly. It is PURELY a transient handoff drawn on top of the
  grid's existing, unmodified `FoundWordsPainter` (pass 2) — pass 2 already
  shows the word's steady capsule the instant `GameState.foundWords` grows,
  so this layer only owns the first 120ms: fill colour eases from
  `AppColors.foundWordFlash` to the word's assigned hue over 90ms, fill alpha
  eases from a bright 0.9 down to pass 2's own steady 0.28 across the full
  120ms (so the handoff at removal is invisible, not a pop), and
  `paintCapsule` gained an optional `scale` param for the 60–120ms
  1.0→1.12→1.0 punch (`1.0 + 0.12·sin(π·t)`, not `Motion.punch` —
  `easeOutBack`'s asymmetric overshoot is the wrong shape for a spec that
  peaks exactly at the window's midpoint). `foundWordFlash` is the one
  `AppColors` field deliberately IDENTICAL between `darkColors` and
  `lightColors` — Ch03 names it literally "white", not a themed tone.
- **Wrong-selection is a fade, never a different reaction.** `GestureLayer`'s
  `onReleased` now returns whether the drag matched, and — this is the
  important part — no longer clears `selection.value` itself on a miss; it
  only clears on a MATCH. `GameGridState` owns the miss case: a raw `Ticker`
  ramps a `_fadeAlpha` ValueNotifier 1.0→0.0 over 180ms, which
  `SelectionPainter` blends into the SAME selection-colour capsule that was
  already on screen (never a new colour, shape, or a shake) before finally
  clearing `selection.value`. A NEW drag starting mid-fade
  (`GestureLayer.onStarted`) snaps `_fadeAlpha` back to 1.0 immediately, so
  it can never inherit a stale, partly-transparent alpha. Reduce-motion
  skips the ticker and clears on the spot.
- **Level complete**: the audio/haptic pair fires once, from a
  `ref.listen(gameControllerProvider(...))` in `GameScreen.build` that fires
  only on the phase TRANSITION into `levelComplete` (Riverpod's own
  `fireImmediately: false` default already rules out a spurious fire on
  first mount). Confetti is NOT a second ticker system — `LevelCompleteCard`
  already redraws continuously off ONE `TweenAnimationBuilder`
  (`masterT`), so 24 confetti pieces are generated once, seeded, and
  painted as a pure function of that same `masterT`, gone entirely (not
  just static) under reduce-motion. "Coin fly-to-counter" is scoped to what
  actually exists on screen: there is no persistent coin-balance HUD yet
  (the real coin economy is P15/P16 — see `coinsEarned`'s own TODO), so the
  coin glyph flies straight into the card's OWN coins stat line rather than
  across a HUD this prompt has no business inventing.
- **Everything above respects `Motion.reduced()`.** Under reduce-motion:
  particles and confetti are skipped outright (never spawned, not just
  shortened to instant); the reveal layer and the wrong-selection fade
  both collapse to an immediate state change with no ticker; the word chip
  and the score roll both skip their pre-delay AND their own animation.
  Audio and haptics are the one exception by design — Ch03 is explicit that
  reduce-motion removes movement, not feedback, and every `audioService`/
  `hapticsService` call sits OUTSIDE any `Motion.reduced` branch.

Environment note: `audioplayers_linux` needs GStreamer's RUNTIME plugin
packages (`gstreamer1.0-plugins-good`/`-base`, `gstreamer1.0-pulseaudio`), not
just the `-dev` headers the build itself needs — without them,
`AudioPlayer.setSource` throws a native (non-Dart) exception during
`bootstrap.dart`'s preload step on Linux desktop specifically, which no
Dart-level `try/catch` can catch. This is a container/sandbox-only gap for
visual verification on this platform; Android ships its own complete codec
stack via ExoPlayer and is unaffected.

## Content pipeline + validator (P10)

Word content and level definitions are ASSETS, never Dart source — this is
what lets a native-speaker review or a level-curve retune ship without a code
change, and what lets `tool/validate_content.dart` check them independently
of the app.

- **`assets/content/words_{ur,hi,en}.json`** — 320 entries each, schema
  `{id, lang, word, display, roman, en, category, graphemes, difficulty,
  hint}`, spread across 12 categories (nature, animals, food, colors, family,
  body, home, school, sports, weather, professions, numbers) with at least 24
  words per category per language. `word` is already `ScriptNormalizer`-
  normalized (Ch04 rules) and `graphemes` is the precomputed, validator-
  checked `ScriptNormalizer.graphemeCount` — every word is 2–9 graphemes.
  `difficulty` (1–5) is derived from `graphemes` alone (2–3→1, 4–5→2, 6–7→3,
  8→4, 9→5) and is presentation-only, never fed into `Scoring`. **Both files
  carry a `_comment` banner: REQUIRES NATIVE SPEAKER REVIEW BEFORE RELEASE**
  — the Urdu/Hindi word lists (and their `roman` transliterations) are
  machine-drafted, same status as the P10-adjacent ARB files.
  - Devanagari caught a real bug during authoring: a consonant+matra pair is
    ONE grapheme cluster, so short words like माँ/लू/दो/नौ/सौ came out at 1
    grapheme — below the minimum. They were swapped for longer synonyms
    (माता, गर्मी, दोनों, नवां/NINTH, सैकड़ा) rather than hand-waved, and the
    generation script computes every `graphemes` value through the real
    `ScriptNormalizer` rather than by hand-counting, specifically because
    this class of mistake is easy to miss by eye.
- **`assets/content/levels.json` has 900 entries, not 300** — one per
  `(id 1–300, language)` pair, matching how `level_progress`/`daily_results`
  already key completion by `(language, level)`: level 47 in Urdu and level
  47 in Hindi are different levels. Each row is `{id, lang, seed, gridSize,
  wordCount, categoryPool, directionTier, theme}`, generated from the Ch07
  curve (`1-5→grid6/words4`, `6-20→grid8/words6`, `21-60→grid10/words8`,
  `61-150→grid10/words10`, `151-300→grid12/words12` — the same table
  `test/domain/grid/word_fixtures.dart`'s `ch07Curve` fixture already
  encoded). The breather rule (every 7th level) only reduces `wordCount`
  (floored at 3) — `gridSize` and `directionTier` are untouched. `seed` is a
  Knuth multiplicative hash of `id`, and is DELIBERATELY the same across a
  given id's 3 language rows: `GridGenerator` and `WordSelector` each draw
  their own independent `Random(seed)`, so sharing one seed does not
  entangle them, and it is what makes a level id alone (no extra stored
  field) enough to describe an identical seed across languages.
- **`WordSelector.selectForLevel`** (`lib/domain/content/word_selector.dart`)
  is the production port of `word_fixtures.dart`'s test-only `pickCohesive`,
  and is CLAUDE.md's own Hindi-intersection problem being fixed, not worked
  around: it filters the language's word pool to the level's
  `categoryPool`/`gridSize`, then grows the chosen set by preferring a
  candidate that shares a grapheme with what's already chosen, falling back
  to the next eligible word when none does. It returns fewer than
  `wordCount` rather than throwing if the filtered pool is too small —
  `validate_content.dart` is where that shortfall is a build-breaking error,
  never a runtime one.
- **`WordEntry` / `LevelDefinition`** (`lib/domain/models/`) are plain final
  classes with hand-written `==`/`hashCode`/`fromJson`, NOT `@freezed` —
  a deliberate deviation from this doc's usual "freezed for all models"
  rule. The codebase's own majority precedent (`Cell`, `WordPlacement`,
  `ScoreEvent`, `LevelCompletionSummary`) already reaches for a plain class
  over freezed for a small, read-only value with no `copyWith` need
  (`GameState` is the one exception, specifically for its heavy `copyWith`
  surface) — these two are exactly that shape, parsed once from a bundled
  asset and never mutated. Only `fromJson` is implemented; content flows one
  way, asset into the app, so `toJson` would be dead code. This also avoids
  adding `json_serializable`/`json_annotation` as new dependencies.
- **`ContentRepository`** (`lib/data/content/content_repository.dart`) loads
  and caches all four JSON assets ONCE, in `load()`; every other method is a
  synchronous lookup over the parsed maps.
  - `getLevel(id, language)` CLAMPS `id` into 1–300 rather than throwing —
    the same defensive shape `DirectionTier.forLevel` already uses — so a
    corrupt or out-of-range id degrades to the nearest real level instead of
    crashing a session.
  - `getWordsForLevel(level)` delegates straight to `WordSelector`.
  - `getDailySeed(date, language)` is `sha256(dateString + langCode)` folded
    into a 31-bit non-negative int via the first 4 digest bytes. `date` is
    read through `.toUtc()` FIRST — "the same grid on three devices" only
    holds if every device agrees on what calendar day it is, and a LOCAL
    calendar day disagrees near midnight depending on timezone while the UTC
    calendar day does not; every device can compute it identically with no
    server. `content_repository_test.dart` proves this directly: the seed is
    identical across three independently-loaded `ContentRepository`
    instances, stable across all 24 UTC wall-clock hours of one day, and
    changes the instant the UTC day rolls over.
  - Wired at `bootstrap.dart` step 7 (`content.load`), eagerly — unlike
    `progressRepository` (lazy, watched only once a game actually starts),
    the word/level packs are needed as soon as the home/journey screen shows
    a single level card. There is no Noop fallback binding, unlike
    `AudioService`/`HapticsService`: a failed load leaves the
    `@Riverpod(keepAlive: true)` provider's own body to run (and fail the
    same way) on first watch, surfacing as that provider's error state
    rather than a game that silently pretends it has content.
- **`BlocklistParser`** (`lib/domain/content/blocklist_parser.dart`) is the
  accidental-word-list line parser, moved out of
  `data/content/blocklist_loader.dart` into pure Dart (`BlocklistLoader.parse`
  now just delegates to it) for exactly one reason: `tool/validate_content.dart`
  is a plain-Dart CLI run via `dart run`, and cannot resolve anything that
  transitively imports `package:flutter` — ultimately `dart:ui`, which the
  standalone Dart SDK does not ship. One definition, read from both the
  Flutter-side loader and the CLI, rather than a second copy of the same four
  lines.
- **`tool/validate_content.dart`** runs every Ch07 content check and exits
  non-zero on failure, wired into `.github/workflows/ci.yaml` right after the
  `localized-strings check` step. Because everything it needs
  (`WordEntry`/`LevelDefinition`/`WordSelector`/`GridGenerator`/
  `ScriptNormalizer`/`BlocklistParser`) lives under `lib/domain/`, it imports
  all of it via `package:word_search_master/domain/...` with zero Flutter
  exposure — the same guarantee `check_domain_purity.dart` already enforces
  for the whole directory.
  - Schema checks: per-word (unique id, `lang` matches the file, `word`
    already normalized, stored `graphemes` agrees with a live
    `ScriptNormalizer` recompute, 2–9 range, known category, `difficulty`
    matches the graphemes band, no empty display/roman/en/hint fields) and
    pack-wide (exactly 320 entries, ≥24 per category); per-level (id 1–300,
    no duplicate `(id, language)`, `gridSize`/`wordCount` match the Ch07
    curve including the breather reduction, `directionTier` matches
    `DirectionTier.forLevel`, known `categoryPool` entries, non-empty theme,
    non-negative seed, one shared seed per id across languages, full
    900-combination coverage); then a cross-check that every level's
    filtered-eligible word pool (`category ∈ categoryPool` AND
    `graphemes ≤ gridSize`) actually reaches `wordCount`, so a level
    `WordSelector` cannot fill is caught here, not by a player.
  - Only once the content is schema-clean does it exercise the real
    generator, loading the real (deliberately incomplete for Urdu/Hindi —
    see below) blocklists via `BlocklistParser` so every placement check
    matches runtime behavior exactly: first, all 900 `(level, language)`
    combinations on their own canonical seed; then — "generate this level
    500 times" — 500 FRESHLY-RESEEDED generations sampled across the real
    curve shape (a random real level's `gridSize`/`wordCount`/`categoryPool`/
    `directionTier`, a brand new seed), rather than the intractable literal
    reading of 500 runs × 900 combinations. `metaSeed: 20260826` makes the
    sample itself reproducible run to run. Both passes currently complete in
    under 4 seconds end to end.
  - `test/tool/validate_content_test.dart` unit-tests every pure check
    function against hand-built fixtures (including a programmatically-built,
    schema-valid 320-entry pack, since the count checks are meaningless
    against a small fixture), AND re-runs the full schema + 900-combination +
    500-fuzz passes against the real shipped `assets/content/` inside
    `flutter test` itself — so `flutter test` alone, with no separate `dart
    run`, already proves all three P10 acceptance criteria.
- **Blocklist status, confirmed for P10**: `blocklist_en.txt` is populated;
  `blocklist_ur.txt`/`blocklist_hi.txt` are deliberately near-empty and
  flagged `REQUIRES A NATIVE ... SPEAKER` — matching-is-substring-based, so a
  wrong entry produces false-positive re-rolls, and an incomplete-but-honest
  list beats a guessed one. `validate_content.dart` only checks that all
  three files exist and parse; it does not require the Urdu/Hindi lists to
  be non-empty, since that gap is real content work for a future prompt, not
  a P10 defect.

## Meta-game — journey, coins, chests, streaks, daily (P11)

Ch02's five retention systems. They are CORE, not extras: the grid engine is
what makes the game good, and this is what makes it worth opening tomorrow.

### The pure rules live in `lib/domain/progression/`

Every rule below is plain Dart with no clock, no I/O and no randomness it did
not receive as an argument — so all of it is walked in a loop by
`test/domain/progression/`, and none of it needs a device to be checked.

- **`DayKey`** is a UTC calendar day. Both day-counting systems (streak, daily)
  use it, and both use UTC for the same reason `getDailySeed` already did
  (P10): a LOCAL calendar day disagrees across timezones, so "the same puzzle
  for everyone" and "one attempt per day" would both be negotiable. `daysSince`
  subtracts UTC MIDNIGHTS, never local ones — local days are 23 or 25 hours
  long twice a year, and a naive subtraction drops or doubles a streak day for
  half the world.
- **`StreakRules`** is a state machine, and `settle` is the whole trick. A
  streak decays with time passing rather than with anything the player does,
  so the stored state goes stale on its own and EVERY reader has to age it
  forward first. `settle` is that ageing: pure, idempotent, and called on both
  paths — the home screen renders through it without writing, `registerPlay`
  runs it before extending. One definition, so the number shown and the number
  stored cannot disagree.
  - Three things Ch02 leaves open, decided here: a freeze PRESERVES the streak
    rather than extending it (coming back to 8 after a day away would be the
    game claiming you played on a day you did not); freezes are only spent when
    they FULLY cover the gap (one freeze cannot save a three-day absence, so it
    is not burned trying); and a broken streak KEEPS its freezes (they were
    earned, and `maxFreezes` already stops them accumulating).
- **`CoinEconomy`** holds every tunable on an INSTANCE, not as `static const`s,
  because the live-ops levers arrive from Remote Config at runtime — and
  because "tuned so a player runs low every ~4 levels" is only checkable if the
  tuning is data a simulation can be handed.
- **`EconomySimulation`** is that simulation: it replays a described player
  against a described economy and reports how often they reached for a hint
  they could not afford. "Runs low" deliberately means WANTED A HINT AND COULD
  NOT PAY, not "balance hit zero" — a player who never hints can sit at zero
  forever and feel nothing, and the wanted-but-unaffordable moment is the exact
  one P18's rewarded ad has to be worth showing at.
  - **The shipped tuning is measured, not guessed.** `levelBaseCoins: 10,
    coinsPerStar: 5` puts the `typical` profile at **one dry level every 4.00**
    across 400 twenty-level runs, median 5 dry levels per run, median ending
    balance ~130 — so the wallet oscillates rather than draining or filling.
    The surface is smooth either side (perStar 4 → 3.6, perStar 6 → 4.5), so
    this is a tuning with room, not a knife edge. `coin_economy_test.dart`
    re-runs the measurement and fails the build outside 3.5–4.5.
  - The economy test asserts the AGGREGATE, not one seeded run, and says so:
    a single 20-level run swings between 3 and 6 dry levels purely on its
    seed, so pinning one seed would pass for exactly one tuning and prove
    nothing about the economy.
  - Coins are STAR-WEIGHTED, which gives a hint a second cost beyond its
    price: using one drops a star, which drops the payout, which makes the next
    hint harder to afford. That coupling is what turns the wallet into a
    difficulty dial.
  - The chest table is weighted toward the bottom (40/35/20/5 over 20–40 /
    41–80 / 81–140 / 141–200). A flat 20–200 roll has the same mean and no
    memorable outcomes — every chest becomes "about 110" and the open animation
    is a loading spinner.
  - `starterGrantCoins` is exactly one hint's worth. The first hint is free and
    the second is not, so the cost of a hint is learned by using one.
- **`JourneyRegion`/`JourneyMap`** — ten levels a region, six accents cycling
  (thirty visually distinct accents do not exist, and a player sees two or
  three regions at once). A region knows its ACCENT INDEX, never a `Color`;
  `lib/domain/` cannot import `dart:ui`, and the indirection is right anyway.
  **UNLOCKING IS DERIVED, NEVER STORED**: `level <= highestCompleted + 1`,
  computed from the same verified `level_progress` rows everything else reads,
  so there is no "unlocked" flag anywhere to forge.
- **`Collections`** derives a badge per (category, language) from level
  progress; the `achievements` row is a CACHE of that plus an unlock
  timestamp, never its source. Editing the row buys a timestamp and nothing
  else, because the grid still asks `level_progress` whether the category is
  actually complete.
  - `newlyEarnedBy` takes `completedBefore` — THE SET AS IT WAS BEFORE THE
    WRITE — and the caller must read it before writing the new progress row.
    An earlier version took the after-set and subtracted `justCompleted` to
    reconstruct "before", which is wrong for a REPLAY: subtracting a level the
    player had already finished makes the category look incomplete, so
    finishing an old level in a completed category re-fired its badge every
    time. There is no way to tell those cases apart from the after-set alone.
- **`DailyPuzzle`** gives the daily a FIXED shape (10x10, 8 words, diagonals)
  rather than borrowing a level from the Ch07 curve. It is a leaderboard
  puzzle, so every player must get the same board; borrowing would compare a
  player at level 3 and one at level 280 across a 6x6 and a 12x12. Only the
  seed and the category move with the date. Its `LevelDefinition.id` is 0,
  which is never a real journey level — so a daily can never be mistaken for
  one, including by `ProgressRepository`.

### Trusted time (`services/time/trusted_clock.dart`)

Both retention systems that count days are worth cheating, and both are cheated
the same way. So the day boundary is resolved in ONE place, in a stated order
of trust: server time when online (authoritative in BOTH directions — a server
saying "earlier" is correcting a clock that was set forward); local time
offline (Ch12 requires the Daily playable with the radio off, so refusing to
answer is not an option); and local time FLOORED AT THE HIGHEST DAY ALREADY
SEEN, persisted in `kv_settings`.

Stated as honestly as `integrity.dart` states its own limits: this does not
stop a clock set FORWARD offline. That player reaches tomorrow's Daily early
and pays for it — the floor then holds them there until real time catches up,
and their streak breaks across the gap they invented. Blocking it outright
needs a server, which is what makes this defence in depth and not the defence;
Ch08's server-side replay (P14) is where a submission is adjudicated.

The server offset is cached for the session, so the home screen's streak
counter does not make a network call every time it rebuilds.

### Live-ops levers (`services/remote_config/`)

P20 owns the Firebase binding; P11 owns the SHAPE — a typed key table with the
default and the sane range living ON the key, not at each call site. Every
lookup can fail (no network on first launch, a fetch timeout, a key a newer
console added), and all of those have to resolve to the same number. A fetched
value is CLAMPED, never trusted: a console typo setting `hint_cost_coins` to 0
must not hand out free hints, and `chest_every_n_levels: 0` IS allowed because
"chests off" is a legitimate A/B arm.

`coinEconomyProvider` is the one place `CoinEconomy` is built for the running
app — gameplay reads it rather than `CoinEconomy.defaults`, which is what makes
a Remote Config change reach the wallet without a code change.

### Persistence

- **Streak state is a `kv_settings` row, not an eighth table.** It is a single
  value with no key space to query, so a table would buy nothing and cost a
  schema migration. It carries an integrity tag like any other row — Ch02 makes
  the streak prominent enough to be worth forging, which is exactly why
  CLAUDE.md forbids `shared_preferences` for it. A forged row reads as EMPTY
  (the Ch10 rule for a failed check) and stays on disk as evidence.
- `LocalRepository` grew `readKv`/`writeKv` so the three things that now need
  tagged KV rows cannot each get the field list subtly wrong — the same
  argument `RowTags` makes.
- **`DailyRepository` records the FIRST attempt, not the best.** One attempt
  per day with a best-of write would let a player grind the daily leaderboard.
  The check runs inside the transaction so a double tap cannot land twice.
- **Never `watch(...).first` for a snapshot.** `ProgressRepository.completedLevels`
  and `CollectionsRepository.unlockedRows` exist because taking the first event
  of a Drift stream OPENS a live query and then cancels it — and cancelling
  schedules Drift's cleanup timer, which outlives the caller. In a widget test
  that surfaces as "a Timer is still pending after the widget tree was
  disposed"; in the app it is a subscription's worth of work for a value
  nobody is watching. A caller that wants a value asks for a value.

### `GameController`'s family key became a sealed `GameSession` (P11)

P07 keyed it by level number, which was right while a level number described
every puzzle that existed. The Daily is a puzzle no level number describes: it
is seeded by a DATE, has a fixed shape, is playable once, and — the part that
actually forces the fork — **must not perform the Zeigarnik swap**, because
there is no next daily today.

The alternatives were a second controller duplicating the state machine, or a
reserved level number smuggling a mode through an `int`. Both hide the fork;
a sealed key names it, and every `switch` over it is exhaustive, so Blitz
(v1.2) cannot be added without the compiler pointing at each place that has to
decide.

`GameController` also finally reads REAL CONTENT: P07's `_demoWords` constant
and inline size ladder are gone, replaced by `ContentRepository` (P10). A
level's identity now lives in the same validated pack `validate_content.dart`
checks.

### `ProgressionController` — awards, and why they are not in `GameController`

`GameController` is synchronous and purely derived on purpose. Coins, chests,
the streak and badges all need the database, and the database is async; mixing
them in would make the moment a word is found await a transaction. So the fork
is exact: `GameController` freezes the GAMEPLAY facts the instant a level is
won (`LevelCompletionSummary` carries no coins), and `ProgressionController`
turns that into everything touching a repository. `game_screen.dart`'s existing
`ref.listen` on the `levelComplete` transition is the seam.

**EVERY `ref` READ HAPPENS BEFORE THE FIRST `await`, and this is load-bearing.**
Nothing WATCHES this controller — it is reached through `ref.read(...notifier)`
and called — so a read placed after an `await` races its own disposal and
throws `UnmountedRefException`. That is not theoretical: it is what happens
when a player taps back out of the game screen while the award for the level
they just finished is still being written, and the visible symptom is coins
that silently never arrive. `keepAlive: true` guards it, and every method
resolves its entire dependency set synchronously at the top as well — belt and
braces, because `keepAlive` is one annotation away from being tidied off.

`tryBuyHint` is the ONLY path allowed to call `GameController.useHint`: it
debits the ledger first and reveals only if the debit succeeded. A caller that
skips it gets a free hint.

### Presentation

- **The journey map is a `SliverList` of REGIONS, not a `ListView` of 300
  nodes.** Ch02 wants locked nodes visible but dimmed, so the map genuinely
  holds all 300; on the 2GB target that rules out building them eagerly.
  Auto-scroll uses a FIXED per-region extent rather than measuring, because
  the current node's offset has to be known before layout — `initialScrollOffset`
  then opens the map at the player's node with no visible jump, where a
  post-mount `ensureVisible` would animate away from them.
- Locked nodes stay in the tree, dimmed, and keep a `Locked` semantics label
  in their own `container: true` node — "visible future" has to include
  non-visually.
- **The chest takes the screen BEFORE the level-complete card**, and dismissing
  it reveals the card underneath with the chest's coins already in the figure.
  The chest is the rarer, louder moment; stacking it on an already-celebrating
  card would bury it.
- `ChestOpenCard` follows `LevelCompleteCard`'s P09 shape exactly — ONE
  `TweenAnimationBuilder`, one painter, no ticker of its own — and under
  reduce-motion the burst is skipped outright rather than shortened.
- `AppColors.regionAccent` is a SEPARATE six-colour list from `foundWord`.
  Reusing that palette would couple a decorative map accent to a set chosen by
  maximising pairwise CIE ΔE under three kinds of colour vision, and guarded by
  `found_word_palette_test.dart` — a region accent has no such job, and tying
  them together would make every future map restyle re-run an accessibility
  search it does not need.
- Category names in the collections grid are still the raw content keys
  ("animals"), flagged `TODO(P17/P21)`: localizing them means twelve more ARB
  entries per language for the same native speaker who still owes a review on
  the word packs, so they are flagged WITH that work rather than machine-drafted
  here.

### Testing notes that will bite again

- A widget test must not drive a live Drift query stream. `test/support/fake_meta.dart`
  overrides the meta providers with settled values for route-level tests; the
  joins are covered in the domain and repository tests instead.
- `ContentRepository`'s default reads `rootBundle`, whose asset reads never
  complete under `flutter_test`'s fake async — `pumpAndSettle` just times out
  with the screen stuck on its spinner. `test/support/fake_content.dart` builds
  an in-memory pack OUTSIDE the pump and injects it already-resolved.

## FTUE + anti-frustration / DDA (P12)

Ch02's first-60-seconds sequence and the silent difficulty assist. Both are
explicitly SILENT systems — CLAUDE.md's own instruction for this prompt was
"the player should never be told they exist," which shapes almost every
decision below.

### `lib/domain/progression/dda.dart` — pure Dart, no clock, no I/O

- `DdaConfig` (`stuckSeconds`/`hintOfferSeconds`, RemoteConfig-backed,
  defaults 25/60) and `DdaEngine.stateFor(idleFor:, config:)` are the whole
  decision function: below `stuckSeconds` → `DdaState.none`; at or past it →
  `pulse`; at or past `hintOfferSeconds` → `hintOffer`. Total, deterministic,
  no third state past `hintOffer` no matter how long idling continues.
- **This is NOT a field on `GameState`.** `GameState`'s getters are all
  replays of `events` (`game_controller.dart`'s decision 1) — DDA is a
  function of TIME PASSING WITH NO PLAYER ACTION, the one thing that shape
  cannot express. Folding it in would mean either ticking Riverpod state
  every second (rebuilding the top bar and word list for nothing, the exact
  mistake P06/P07 spent two prompts avoiding) or a stale timestamp
  `GameState` cannot keep current on its own. So the idle `Timer` and the
  countdown it drives live entirely in `game_screen.dart`
  (`_GameScreenBodyState`), and `dda.dart` only ever answers a pure question
  about a `Duration` it is handed.
- `DdaAbandonRules.shouldDownshift` (2 consecutive abandons) and
  `DdaDownshift.dropOneWord` (drop the LAST word, never shrink `gridSize` —
  fewer words can only make `GridGenerator` succeed more easily, never less,
  where a smaller grid risks a word that no longer fits) are the other half:
  the pure rule for "two consecutive abandons of the same level → next
  attempt uses one fewer word."

### The idle timer counts TICKS, not `DateTime.now()` deltas

`_GameScreenBodyState._idleSeconds` is incremented once per firing of a
`Timer.periodic(Duration(seconds: 1), ...)`, never computed as
`DateTime.now().difference(lastActivity)`. A `Timer` fires on simulated time
under `flutter_test`'s fake clock — this codebase already depends on that for
every P09 choreography delay — but a raw `DateTime.now()` call made INSIDE
the callback is not guaranteed to agree with that simulated clock. Counting
ticks sidesteps the question entirely: it is a count of "how many times has
the timer fired since the last reset," provable with nothing but
`tester.pump(duration)`, which is exactly how `ftue_dda_test.dart` proves the
15-second acceptance criterion — pump 2 real seconds, assert the glow fired,
release the glowed word's selection, done.

### FTUE glow (2s, repeat 6s) and the DDA pulse (25s) share ONE mechanism

`PulseController`/`PulseSignal` (`game_grid.dart`) are a small, ValueNotifier-
driven "glow this cell" primitive — deliberately NOT the same slot as
`GameGrid.hintedCell`, because it must never append a `HintUsed` event or cost
a star; it is silent and free by construction, not by a UI convention someone
could forget. `_PulseHighlight`'s own visual (a soft filled disc) is
deliberately different from `_HintHighlight`'s outlined ring, so a player can
never mistake a free nudge for the ring a spent hint draws. Under
reduce-motion it renders a STATIC translucent disc rather than collapsing to
an instantaneous animation — `Motion.reduced`'s usual zero-duration trick
would land a fade-in-fade-out on its own final (invisible) frame, which is
exactly backwards for something meant to convey information.

Both `_tickFtueGlow` (level 1, before the first word is found — always the
SAME word, `allWords.first`, because the FTUE moment is teaching the player
to find ONE thing) and `_tickDda` (25s idle, any level, a RANDOM remaining
word — Ch02's own distinction) write into the same `PulseController`; a
`PulseSignal` carries a `nonce` that changes on every call even for the
identical cell, because `ValueNotifier` only notifies on inequality and
without it the FTUE glow's 6s repeat would silently stop replaying its
animation after the first cycle. FTUE OWNS the idle clock while it is armed
— DDA's broader thresholds do not race it during the exact window FTUE
already covers; once the first word is found (or the player is past level
1), DDA takes over as normal.

### The 60s free hint offer

A soft inline banner (`_DdaHintOfferBanner`), never a dialog — the grid stays
fully visible and playable underneath it. Accepting it calls
`GameController.useHint()` DIRECTLY, never `ProgressionController.tryBuyHint`
— Ch02 is explicit this hint is free, never a rewarded ad ("monetising
frustration is how you get uninstalls"), so it must not touch the coin
ledger the paid hint button spends from. Copy is deliberately neutral ("Want
a hint?" / "Show hint" / "Not now") — no mention of being stuck, of
difficulty, or of the game doing anything different, per CLAUDE.md's "never
surface any message implying the game was made easier." `ftue_dda_test.dart`
proves this both by widget-tree assertion (a banned-substring scan over
every `Text` in the tree, explicitly excluding `GameDebugPanel`'s own "DDA"
section header — dev-only tooling a player never sees, allowlisted from the
l10n check for the identical reason) and is why a raw SOURCE grep for the
same substrings was tried and abandoned: `dda.dart`'s own doc comments
legitimately say "stuck" and "downshift" everywhere, and a comment is not a
message shown to a player.

### Two consecutive abandons → the next attempt drops a word

**An ABANDON, in this build, is an explicit leave** — the AppBar back button,
or "Home" from the pause sheet — while `GameState.phase != levelComplete`.
There is no reliable, testable signal for "the app was backgrounded" within
this prompt's scope (Android lifecycle callbacks, `AppLifecycleState`
plumbing) so that case is deliberately NOT covered; resuming from the pause
sheet, or finishing the level, is not an abandon.
`DdaRepository` (`data/repositories/`) persists the per-`(language, level)`
count as a tagged `kv_settings` row (`dda_abandon:{lang}:{level}`), the same
carve-out `KvKeys.streakState` already uses — a small, sparse counter set
with no need to be queried as one, so a table would buy nothing and cost a
migration. `ProgressionController.recordCompletion`'s journey branch clears
it the moment the level is actually finished, since the pattern this counts
is specifically "never manages to finish this one."

**`GameController` stays database-free — this is load-bearing, not a
nicety.** The obvious place to check-and-consume the downshift is inside
`GameController.build`, and that is exactly where it was first written — and
it broke 27 existing tests, because `build` gaining ANY dependency on
`ddaRepositoryProvider` → `appDatabaseProvider` means every bare
`ProviderContainer` test that constructs a `JourneySession` directly (most of
`game_controller_test.dart`) now hangs on `appDatabaseProvider`'s default
`driftDatabase()` connection, which never resolves under `flutter_test`. The
fix mirrors the Daily branch's own existing shape: `journeyDownshiftProvider`
(`game_controller.dart`) is the ONE place `DdaRepository` is read, consumed
and the `dda_applied` analytics event fired — resolved by `GameScreen`'s
outer widget via a `Consumer`, exactly like it already resolves
`currentDayProvider` before building a `DailySession`, BEFORE constructing
`JourneySession(level, downshift: ...)`. `GameController.build` reads that
flag straight off its own family key, synchronously, and never touches the
database. `JourneySession.downshift` is deliberately EXCLUDED from `==`/
`hashCode`: the family key names WHICH puzzle this is (the starting level),
not how this one attempt happens to be tuned, and including it would let
`GameDebugPanel` — which reconstructs a plain `JourneySession(widget.level)`
to reach the mounted controller — silently talk to a different provider
instance than the one actually on screen. `GameState.downshifted` (a real,
freezed field) is the live truth for everything AFTER the initial load —
`restart()` reads it off the current state rather than re-consulting the
session, and the Zeigarnik swap's next-level generation always sets it
`false` explicitly, since that swap advances `state.level` without
remounting and so never passes through the `journeyDownshiftProvider` gate at
all.

### Language-select: sample words + no Play tap

`LanguageScreen` now shows three of each language's own words
(`ContentRepository.sampleWords`, first-N-in-file-order — decoration for
onboarding, never gameplay content, so no seed is needed the way
`getWordsForLevel` needs one) under each endonym, and picking a card routes
straight into `GameRoute('1')`, never `HomeRoute` — Ch02: "Level 1 auto-loads.
No 'Play' tap required." There is no other route into `/language` today, so
this is unconditional rather than gated on "is this the first-ever pick";
`app_smoke_test.dart` and `style_gallery_test.dart` both needed their
`enterApp` helpers updated for this, since reaching ANY route past language
select now touches the game screen first.

### The one-time Urdu illustration

`_UrduConnectedFormIntro` (`game_screen.dart`) shows once, ever, only for
Urdu on level 1: the connected word (a plain `Text(word)` — Arabic-script
shaping joins the letters automatically when rendered as one run, exactly as
the word-list chip below the grid already shows it) above an arrow above the
SAME word re-split through `ScriptNormalizer.graphemes` — the identical call
`GridGenerator` used to place it — so each letter renders alone, in the
isolated presentation form the grid itself shows. The "have I shown this"
flag lives in `UiSettingsStore` (`urduConnectedFormIntroShown`), not
`kv_settings` — a UI-only tutorial flag is exactly the shared_preferences
carve-out CLAUDE.md already makes for `selectedLanguage`, not game state.

### Post-level-8 login offer

A dismissible `MetaCard` banner on the home screen (`_SaveProgressBanner`),
gated on a new `highestCompletedLevelProvider`
(`presentation/meta/journey_providers.dart`, the same
`ProgressRepository.watchHighestCompletedLevel` join the journey map already
uses). No real auth exists yet (P13), so accepting it is a stub — a
`SnackBar` plus dismissal, the same status as P18's `doubleRewardPlaceholder`/
`adPlaceholderLabel` ad placeholders. Its own "dismissed" flag
(`UiSettingsStore.loginPromptDismissed`) is the same UI-toggle carve-out as
the Urdu intro's.

### Analytics — the minimal shape this prompt actually needs

`services/analytics/analytics_service.dart` is the first thing written into
that folder (previously just a `.gitkeep`): `AnalyticsService` (one method,
`logEvent(name, params)`), `NoopAnalyticsService` as the binding on every
flavor until Firebase Analytics lands (P19/P20, mirroring
`error_reporter.dart`'s identical call), and a `DdaAnalytics` extension
supplying the one typed event this prompt needs, `ddaApplied(type:,
language:, level:)`. Deliberately NOT a typed `AnalyticsEvent` hierarchy for
a taxonomy of one entry — that is exactly the premature abstraction
CLAUDE.md's "Never do" section warns against; a future prompt that needs a
second event widens the interface or adds its own extension alongside
`DdaAnalytics` rather than this file guessing today at a shape nothing calls
yet.

### Dev toggle

`GameDebugPanel` gained a `DDA` row — one `ActionChip` per `DdaState`,
wired through `onForceDda` into `game_screen.dart`'s `_debugForceDda`, which
drives the exact same `PulseController`/`_ddaState` the real idle timer would
rather than a stub — the same "no faithful-preview shortcuts" discipline
`GameController.debugForcePhase` already keeps for level-complete. This row
is P12's own acceptance criterion 2, verbatim.

## Firebase, App Check, guest-first auth (P13)

### Credentials are NOT in this repository, and that is a visible state

`flutterfire configure` needs an interactive Firebase login and three
projects that only a human with the account can create, so
`FlavorFirebaseOptions.forFlavor` returns **null** for all three flavors and
`docs/firebase-setup.md` is the runbook that fills it in. Everything else —
the bootstrap order, App Check, auth, the merge — is written and tested.

The important consequence: **"unconfigured" and "airplane mode" are ONE code
path, not two.** A null options object makes `LiveFirebaseGateway.initialize`
return null, every Firebase-backed service keeps its Noop binding, and the
app runs as a local-only guest. That is the same path a plane produces, so
the degraded path is exercised every time anyone runs the app locally instead
of being discovered by the first player in the air. Placeholder credentials
would have compiled and then failed at the first network call with an
authentication error that looks like an app bug — and could have shipped.

### Bootstrap: the order is the point, and two pairs are load-bearing

`initializeServices` implements Ch13's nine steps exactly. Two orderings are
not stylistic:

- **3 before 4** (App Check before auth) because App Check attests the
  requests auth makes. Activate it afterwards and the first sign-in of every
  session goes out unattested — the one request an attacker would imitate.
- **1 before 2** (error handlers before `initializeApp`) because the
  exception most worth catching is the one initialisation itself throws.
  Crashlytics buffers to disk, so a handler installed before the SDK exists
  still records.

Every step runs inside `_step`, which catches everything. `ErrorReporter`
starts as a Noop and is UPGRADED to Crashlytics the moment step 2 lands —
steps 1–2 have nowhere else to report to, by definition.

**`bootstrap()` is `initializeServices()` + `runApp`.** The split exists so
the airplane-mode criterion is testable: `Firebase.initializeApp` cannot run
under `flutter_test`, so a bootstrap that called it inline would be
untestable by construction. `FirebaseGateway` is the seam, and
`bootstrap_offline_test.dart` injects one that fails the way a plane does —
plus a THROWING one, because "returns null" and "raises" are different bugs.
`openDatabase`/`loadContent`/`loadAudio` are injectable for the same reason
(the P11/P12 lesson: `rootBundle` and `drift_flutter` both hang under fake
async).

### The merge is where a player's progress is actually at risk

`lib/domain/progression/account_merge.dart` is pure Dart implementing Ch02's
four rules — levels max(), coins summed, achievements unioned, streak max —
plus four decisions Ch02 leaves open:

1. **A LEVEL ROW IS MERGED WHOLE, NOT FIELD BY FIELD.** max(stars) from one
   side and max(bestScore) from the other synthesises a row describing a run
   that never happened: 3 stars (so, no hints) beside a score only reachable
   with one. The better row wins entire, so `hintsUsed`/`completedAt` still
   belong to the attempt that scored those stars.
2. **COINS COME BACK AS A DELTA, NOT A BALANCE**, because `coins_ledger` is
   append-only and the balance is SUM(rows) — "set the balance to X" is not
   expressible. `coinsToCredit` is the REMOTE balance (the local rows are
   already in the ledger; crediting the sum would pay the guest's own coins
   twice). Summing is not idempotent, so the guard lives in
   `AccountMergeRepository`: a ledger reason of `merge:<uid>`, checked before
   appending. It cannot live in the domain — deciding "have I already
   credited this" requires reading the ledger.
3. **An achievement keeps its EARLIEST `unlockedAt`** — it is a fact about
   the past.
4. **The streak merges PER FIELD** (unlike rule 1) with the later day winning
   each stamp: both sides are the same real person, so if they played on
   device A yesterday and B today, both days happened. Freezes are capped at
   `StreakRules.maxFreezes` so linking is not a way to hoard them.

`AccountMerge.merge` is TOTAL — a failed cloud read is passed in as
`AccountSnapshot.empty`, which makes the merge exactly a no-op. That is the
degradation that keeps "never wipe" true offline.

### `applyMerge` is ONE transaction, and there is no delete path

A merge touches four tables. One-at-a-time means a failure halfway leaves an
account that is neither the guest's nor the cloud's. So it is a single Drift
transaction: all of it lands or none does, and "none" is the pre-merge state
the player already had. There is no statement in the file that removes a row,
so Ch02's "never wipe" is a property of the code rather than a promise about
it. Rows are RE-SIGNED on write — a tag binds to the install id, so a row
from another device could never carry one this device accepts.

### Auth: guest-first, and `LinkOutcome` is sealed for one reason

Anonymous sign-in is silent, in bootstrap step 4, and returns null rather
than throwing when offline — "playing offline as a guest" is a supported
state, not an error. `linkWithGoogle` returns a sealed `LinkOutcome` so the
compiler forces every call site to handle **`LinkRequiresMerge`**, the
`credential-already-in-use` case. That is the branch where forgetting to
merge silently discards the guest's progress, and a bool-plus-error return
would have made forgetting it easy.

`AccountController` owns the whole sequence (sheet → link-or-fallback → cloud
read → merge) rather than a button handler, because spreading it out is how
the merge step gets skipped on one of the two paths. It keeps
`ProgressionController`'s **every-ref-read-before-the-first-await** rule, and
here it is not theoretical: the Google sheet owns the screen for seconds.

`AccountLinkResult.linkedMergePending` is deliberately distinct from
`failed`: the player IS signed in, so saying sign-in failed is a lie they can
disprove by looking, and their local progress is untouched, so anything
alarming would be worse than the truth.

Sign-out returns to a fresh anonymous session and clears only
`profile.cloudUserId`. `FirebaseAuthService.signOut` has no database handle,
so it *cannot* delete local data — again a property, not a promise.

### App Check: the provider is a pure function, enforcement is a console rule

`AppCheckPolicy.forFlavor` keys off the FLAVOR, never `kDebugMode`: a
release build of the dev flavor (what QA installs) still needs the debug
provider, and a debug build of prod must never get one. A debug provider in
production is a silent total outage the day enforcement turns on, which is
why it is a switch a test enumerates rather than an `if` in bootstrap.

**Enforcement stays in monitor mode for the first two weeks post-launch** —
a console setting nothing in this repo can change, which is exactly why the
four-step ramp is written into `app_check_gateway.dart`'s header. P13's
acceptance criterion is satisfied by tokens ARRIVING and being counted, not
by enforcement being on.

### Firestore reads are P13's, writes are P14's

`CloudAccountRepository` reads one `users/{uid}` document, only so the merge
has something to merge. A per-level subcollection is the natural Firestore
modelling and is likely what P14 wants for incremental sync — but it would
be a fan-out of hundreds of reads on the one screen where the player is
already waiting on a sign-in sheet. `CloudAccountCodec` is split out from the
Firestore client so the parsing — where the bugs are — is testable without a
Firestore instance, and every field degrades rather than throwing: a parse
that threw would abort the merge, which is how one bad field loses everything.

### What could not be verified here

`flutterfire configure`, a real device, and the App Check console are all
outside this environment. So criterion 3 ("App Check tokens console mein
nazar aate hain") is **not** verified — the provider selection and activation
call are tested, the console is not. Criteria 1 and 2 ARE verified, by
`bootstrap_offline_test.dart` and by
`account_merge_test.dart`/`account_merge_repository_test.dart`/
`account_controller_test.dart` respectively.

## Cloud Functions — server-authoritative scoring (P14)

`functions/` is a TypeScript Firebase Functions v2 project in **`asia-south1`**,
matching `AppConfig.functionsRegion`. Every callable sets
`enforceAppCheck: true`. Full contracts, payload shapes and error codes are in
`functions/README.md`; this section is the reasoning.

### The scoring port is a two-way lock, not a copy

`functions/src/scoring.ts` is the TypeScript half of the contract whose
normative text is `lib/domain/scoring/scoring.dart`'s header — same integer
`[10, 12, 14, 16, 18, 20]` table, same replay-an-ordered-list shape, same
`computeStars` with no elapsed-time parameter. Neither side can move alone,
because a committed fixture sits between them:

1. `tool/generate_scoring_fixtures.dart` computes 210 cases (10 hand-picked
   edges + 200 seeded random replays) with the REAL `Scoring`, and writes
   `functions/test/fixtures/scoring_parity.json`.
2. `test/tool/scoring_fixtures_test.dart` regenerates it in memory and fails on
   a byte difference — so the fixture cannot go stale relative to the Dart spec.
3. `functions/test/scoring_parity.test.ts` reads it and asserts the port
   reproduces every number.

Change the Dart rules and (2) fails until the fixture is regenerated;
regenerate it and (3) fails until the port is updated. The obvious alternative
— one test process running both languages — needs a Dart VM inside vitest or a
Node process inside `flutter test`, which makes the parity claim depend on a
toolchain being installed rather than on the two implementations agreeing.

The generator is seeded (`Random(20260831)`), so re-running it on an unchanged
spec is a no-op in `git status` — the same determinism discipline
`GridGenerator` keeps.

### Two rejection classes, and the line between them is the design

- **MALFORMED → `invalid-argument`.** Payloads an honest client CANNOT produce:
  a missing field, a level id that is not a number, an unreadable event, an
  events array past 500 entries. There is no player behaviour to attribute them
  to and nothing to flag, so answering honestly costs nothing.
- **SUSPICIOUS → a flag on a SUCCESSFUL response.** Well-formed payloads whose
  contents do not add up. P14's rule is literal: never return an error to a
  suspected cheater. The response is byte-identical in shape to an accepted one
  — no `suspicious` field, no flag list, not even a different key set — because
  a cheater who learns which check caught them iterates until it does not.

`resource-exhausted` (the rate limit) is the one error that is not a cheat
signal: it protects the backend, and an honest client wedged in a retry loop
needs that answer too.

**`server-side recomputation` is the only check that always runs.** The client's
score is never read because `ScoreEventCodec` never sends one; `stars` and
`hintsUsed` ARE read, but only as tamper signals — the values written are
always the replayed ones.

### A replayed nonce is a SUCCESS, not an error

The obvious reading of "nonce replay check" is to refuse the second submission.
That is wrong here, and the reason is Ch10's outbox: a row whose response was
lost to a dropped connection is retried, and it is the SAME row. Refusing it
would strand a level the player really finished. So a repeat returns the stored
result verbatim and writes nothing — idempotent, which is what an at-least-once
delivery pipeline actually needs, and which happens to tell a replay attacker
nothing either.

`SubmissionNonce` (`lib/data/local/submission_nonce.dart`, P14's one client
change) is therefore DERIVED, not random: `level:{lang}:{level}:{completedAt}`.
`completedAt` is written once, inside the same transaction as the progress row,
so every retry of one attempt carries the same value while a genuine replay of
the level carries a different one. The server derives the identical string for
rows queued by a pre-P14 build (`validation.ts`'s `parseNonce`), so upgrading a
device with a full queue does not strand it. Both sides must change together.

### The timing check is cumulative and order-independent, because it has to be

Relaxed mode has NO timer — `Scoring.computeStars` takes no elapsed parameter on
purpose — so there is no honest per-level duration for a client to send, and
anything it did send would be client-controlled and worthless as a bound.

What is checkable is the whole account at once: the SPAN of client completion
times the player has claimed, against the minimum time the work they submitted
could take. That comparison must be order-independent, because the outbox can
deliver a retried row behind a newer one; a check written as "this submission
minus the previous one" would flag honest players every time the queue retried.
The earliest submission contributes no requirement, since nothing bounds how
long the first level took.

Two consequences worth stating:

- **A timestamp already known to be nonsense is NOT folded into the
  accumulator.** One completion stamped in 2099 would stretch the span far
  enough to make everything after it plausible; the cheapest forgery of a
  cumulative bound is to inflate the bound.
- **`clockRewound` is measured against the SERVER clock (400 days), never
  against the account's creation time.** The tempting check — "a completion
  cannot predate the account" — flags an entirely normal case: `users/{uid}` is
  first written by the first SUBMISSION, while the levels in it were played
  before that, offline, possibly for days. That was found by an emulator test
  failing, not by reading the code.

`timingIsPlausible`'s header states its limit as plainly as `integrity.dart`
does: it catches the naive forgery (fifty completions with adjacent
timestamps), not a forger who spaces fake timestamps plausibly. That ceiling is
acceptable because of what it is one signal among — a perfectly-paced forgery
still faces progression continuity and word-count bounds, and still only earns
what its own events justify.

### The bounds have to allow for P12

`wordCountBounds` is `[wordCount - 1, wordCount]`, not an exact match, because
the anti-frustration downshift genuinely hands a struggling player one fewer
word (`DdaDownshift.dropOneWord`). A server insisting on the exact curve value
would silently flag precisely the players the DDA exists to help — silently,
because a flagged score shows no error. Two systems written eight prompts apart
have to agree here, which is why `levels.test.ts` checks the ported Ch07 curve
against all 900 real rows of `assets/content/levels.json` rather than trusting
that it was transcribed correctly.

The server derives level shapes from that ported curve instead of shipping
`levels.json` into the function bundle: every field it needs is a pure function
of the level id — which is exactly what `tool/validate_content.dart` already
asserts about all 900 of them on every CI run.

### The leaderboard trigger COPIES, it never accumulates

A Firestore trigger is at-least-once. It fires twice for one write eventually,
so "add this score to the player's total" silently double-counts — rarely
enough to be discovered months later on a leaderboard nobody can explain. So the
totals are accumulated in `recordSubmission`'s single transaction, which is
exactly-once because the nonce guards it, and `updateLeaderboards` only mirrors
the already-correct numbers. Running it twice writes the same bytes twice.

Totals move by the IMPROVEMENT over the previous best, never by the raw score,
so replaying a level cannot pump a board.

Boards: `global`, `ur`, `hi`, `en`, `weekly_{ISO week}`, `daily_{date}`. The
weekly key is derived from when the level was PLAYED, not when it synced — a
queued row draining on Monday belongs to the week it was played in. ISO weeks
pivot on Thursday, which is why `isoWeekKey` does that explicitly rather than
dividing day-of-year by seven; getting it wrong resets the weekly board three
days early, once a year.

Entries hold EXACTLY `{uid, displayName, photoUrl, score, updatedAt}`. A
leaderboard is the only collection other players read, so every field on it is
a publication decision.

**`daily_{date}` is keyed by the date alone, and that is a flagged trade-off.**
A date has three daily puzzles (`DailyRepository` keys rows by `(date,
language)`), and they share one board. Defensible today because `DailyPuzzle`
fixes an identical shape for all three (10x10, 8 words, diagonal tier) and
`Scoring` is language-blind — only the word pack differs. The board therefore
takes the BEST of a player's dailies for that date, in a transaction, so
whichever language syncs last the entry ends up the same; a plain `set` would
publish whichever arrived last, which is not a rule anyone could explain. If a
future prompt establishes the packs are not equally hard, the split is
`daily_{date}_{lang}` plus a migration.

### A flagged submission never overwrites an honest best score

The score document is only CREATED by a flagged submission. If a clean result is
already stored for that level, the flagged one leaves it alone and only moves a
`flaggedSubmissions` counter — otherwise one false positive would quietly
destroy a score a player earned. Either way the full payload, INCLUDING the raw
events so a moderator can replay it by hand, lands in
`moderation/{uid}/flags/{autoId}`.

### `deleteAccount` deletes Firestore first and auth LAST

Deleting the auth record first is a one-way door: the moment it is gone the
player cannot authenticate, so a Firestore failure afterwards would leave their
data with nobody able to ask for it again. Auth last makes a partial failure
RESUMABLE. Calling it twice is safe, and `auth/user-not-found` is treated as
success because it means a previous call got that far.

Board entries are found with a collection-group query on `entries.uid` rather
than by walking the board list, because that list is open-ended (`weekly_*` and
`daily_*` grow forever) and a player missed here stays visible on a PUBLIC board
after asking to be deleted — the only failure mode of this function that other
people can see. The index for it is in `firestore.indexes.json` and is not
optional.

Moderation records are deleted too. They are anti-abuse evidence and deleting
them lets a cheater launder their history — but they are also unambiguously
data about a person who asked for their data to be deleted, and Play policy
carves out no exception for records the developer finds useful. The deterrent
that remains is the one that was always doing the work: deleting the account
also deletes every level, coin and streak. Local data is untouched because this
function cannot reach it — a property, not a promise, exactly like
`FirebaseAuthService.signOut`.

### `grantRewardedReward` is the only function without App Check, by necessity

It is called by AppLovin's servers, which have no app instance and can never
hold an App Check token, so attestation comes from a shared secret
(`defineSecret('MAX_REWARD_SECRET')`) instead. That substitution is the whole
point: the client could perfectly well claim "I watched an ad" — and a modified
client would claim it constantly — so THE ONLY PATH THAT MINTS COINS IS ONE THE
CLIENT CANNOT INVOKE, SIGN OR OBSERVE.

Three defences, each covering the others' gap: HMAC-SHA256 over
`user_id|event_id|amount|ts` compared with `timingSafeEqual` (a `===` on a hex
digest leaks the correct prefix through response timing); a 15-minute freshness
window (a signature is valid forever, a captured URL must not be); and
idempotency on `event_id` (AppLovin retrying on a non-2xx is documented
behaviour, not an edge case). An honest 4xx IS right here — the caller is an ad
network, not a player, and the only thing that reaches one is a misconfigured
callback URL whose owner needs to know.

Coins are clamped at 500 per callback and written as a GRANT RECORD
(`users/{uid}/coinGrants/{eventId}`), never a balance: the client's
`coins_ledger` is append-only and locally HMAC-signed (Ch10), so a server-set
balance would have nowhere to land.

**P18 must confirm the signature scheme** against the MAX dashboard, which is
not reachable from this repository; ad networks differ on what they sign and in
what order. If it differs, change `canonicalString` and nothing else — freshness,
idempotency, the ceiling and the write path are all independent of that choice.

### Firestore rules are production-grade from day one

`firestore.rules` denies almost everything. The client may read its own
documents and any leaderboard entry, and may write exactly two fields
(`displayName`, `photoUrl`) on its own user document — the only data in the
system the player authors rather than earns. `moderation/` and
`rewardCallbacks/` are unreachable by any client, including the flagged player:
someone who can read `moderation/` learns exactly which check caught them.

The Admin SDK bypasses rules, so the functions keep working against a file that
denies nearly all of it. That asymmetry IS the design — if a rule had to be
loosened for a function to work, the function would be doing something the
client could do too.

### Testing shape, and what could not be verified here

- `functions/test/*.test.ts` (106 tests) is pure: scoring, the parity fixture,
  the ported curve against the real 900-row asset, the whole validation
  pipeline, ISO week keys, and the reward signature. No emulator, no network.
- `functions/test/integration/pipeline.test.ts` (21 tests) runs under
  `firebase emulators:exec --only firestore,auth` against a REAL Firestore —
  transactions, `FieldValue` increments, `recursiveDelete` and collection-group
  queries all genuinely exercised. It drives `recordSubmission` /
  `mirrorScoreToLeaderboards` / `deleteAccountFor` / `creditReward` directly
  rather than the callable transport: what the wrappers add is an auth check, a
  parse and an App Check flag, and the first two are already covered without an
  emulator while the third is a deploy-time property no emulator enforces.
  Those four inner functions are split out of their wrappers FOR that reason.
- **Acceptance criteria 1 and 3 are verified on the emulator** (a fake score
  submission is flagged and kept off every board while still returning success;
  `deleteAccount` empties the user doc, all subcollections, all board entries,
  the moderation trail and the auth record). **Criterion 2 is verified** by the
  fixture pair above.
- **NOT verified here**: the functions emulator loads all five definitions
  (`updateLeaderboards, deleteAccount, grantRewardedReward, submitScore,
  submitDaily`) but cannot register the Firestore trigger in this sandbox — the
  registration call is blocked by the container's outbound proxy. So the
  TRIGGER WIRING itself is unexercised; its body is not. Nor is anything that
  needs a real Firebase project: App Check enforcement, a deployed region, or
  the MAX callback against the real dashboard.


## Firestore rules + rules tests (P15)

`firestore.rules` is the deployed ruleset and has never been in test mode.
`rules_test/firestore_rules.test.ts` exercises it against the emulator with 64
cases, and `SECURITY.md` records the Ch08 threat model, what is implemented,
and what is an accepted risk.

### Every rule gets an ALLOW test as well as a DENY test

This is the acceptance criterion, and it is not symmetry for its own sake: a
rules file that denies everything passes every deny test ever written, and
ships an app where nothing works. The deny tests say the door is locked; the
ALLOW tests say it is a door. Where a rule's client answer is always "no"
(`users` delete, `moderation` read), the allow half is the SERVER path through
`withSecurityRulesDisabled` — `deleteAccount` really can delete a user
document, and a suite that only proved the client cannot would not have shown
that anyone can.

### Three ways a rules test passes for the wrong reason

Each of these was designed around, not discovered afterwards:

- **`updateDoc` on a document that does not exist fails with `not-found`, not
  `permission-denied`** — so `assertFails` goes green against a rules file that
  would have allowed the write. Every update and delete case seeds its document
  first through `withSecurityRulesDisabled`, which is also the only honest way
  to create the server-authored fields (`totals`, `progress`,
  `suspiciousCount`) a client must not be able to touch.
- **`getDoc` on a missing document SUCCEEDS when the rule allows it.** A read
  test that only checks "no error" is testing the rule; one that checks the
  DATA needs the document to exist. Both shapes appear, deliberately.
- **`get` and `list` are different operations.** `list` is evaluated against a
  QUERY before any document is fetched, so the engine has no `uid` to bind —
  which means `allow read` on `/users/{uid}` reads as "owner only" and behaves
  as "nobody can enumerate". Right answer, unguessable reason, so the file
  spells out `allow get` and `allow list: if false` separately and the suite
  tests both (including a query narrowed to the caller's own uid, which is
  still a list).

The suite loads the REAL `firestore.rules` rather than a copy — a test against
a copy is a statement about a file nobody deploys — and runs under the
emulator-only project id `demo-wsm-rules`, whose `demo-` prefix tells the
Firebase tooling it can never reach a real project or need credentials.

### Two rules bugs the suite caught immediately

Both were found by the tests failing, not by reading the file:

- **`updateDoc(ref, {displayName: null})` was denied.** Writing null does not
  REMOVE the key (that is `deleteField()`), so `displayName is string` refused
  a player clearing their name — and the refusal would reach them as a silent
  permission error on a screen that, per Ch10, must never show one. The rule
  now accepts null or a string; `updateLeaderboards.readProfile` already
  normalised both to "no name", so nothing downstream changed.
- **A write including a server field at its CURRENT value was allowed.**
  `diff().affectedKeys()` is a VALUE diff, not a list of the keys the client
  mentioned, so `{displayName: 'x', suspiciousCount: 0}` on a document already
  holding `suspiciousCount: 0` does not "affect" it. That is correct — it
  changes nothing — but it is not what the rule looks like it says, and there
  is no v2 primitive for the other reading (`writeFields` was v1 and is gone).
  The guarantee is therefore "no server-authored value can be MOVED, though one
  can be restated"; both halves are pinned by tests and the trade-off is
  written up as SECURITY.md's AR-8, so a future reader meets it as a documented
  property rather than a suspected hole.

### `displayName` is capped at 24 characters on CREATE as well as UPDATE

Checking length on only one of the two is the classic hole: a client that
cannot update a 200-character name simply creates the document with one, and
the leaderboard renders it either way. So `validProfileValues()` is called from
both rules, and the suite tests 24-vs-25 on both paths.

The cap is a layout constraint on a screen the rule has never seen — a
`displayName` is published to every other player through
`leaderboards/*/entries/*`, and 24 characters is what an entry row fits.

### The rules suite is its own CI job

Separate from the `functions` job on purpose: `firestore.rules` protects the
CLIENT, and it must keep failing the build even if the functions project is
ever removed, split out or skipped. A rules regression is silent in every other
check — the app keeps working, it just stops being safe.

The suite lives in a ROOT npm project (`package.json`, `rules_test/`) rather
than inside `functions/`, because it tests a root artefact and because
`npm run test:rules` should work from the repo root with no `--prefix`. That is
also why the emulator ports live in `firebase.json` rather than on each command
line: two npm projects now drive the emulators, and they must agree.

### SECURITY.md records the accepted risks, not just the wins

Nine of them, each with why it is acceptable and what would close it. The two
worth knowing before touching this area:

- **AR-9 — the server does not verify that the submitted words were actually in
  the grid.** It checks the count, the plausible grapheme lengths and the score
  that follows, so a forger can submit the maximum-scoring PLAUSIBLE replay for
  a level they did play. The score that buys is bounded near an honest perfect
  run, so this is leaderboard-shaping rather than score-minting. Closing it
  means shipping the word packs into the function bundle and porting
  `GridGenerator`/`WordSelector`/`ScriptNormalizer` to TypeScript — a third
  language-sensitive port to keep in step with Dart — and should be weighed
  against simply capping per-level scores at the honest maximum, which is far
  cheaper and catches most of the value.
- **AR-4 — display names are length-checked, not moderated.** No profanity
  filter, no reporting flow. A bad filter is worse than none (they reject real
  Urdu and Hindi names far more often than they catch abuse), but a public
  leaderboard still owes a report action and a moderation queue that can blank
  a name server-side.

A threat model that only records wins is a marketing document, so the file
opens with the three standing assumptions that shape every row — the client is
hostile by construction, no defence may require being online at the moment of
PLAY, and a false positive is invisible and permanent because a flagged player
is never shown an error.


## Sync engine — outbox, backoff, conflicts (P16)

Ch10's offline-first courier. Everything below runs BEHIND the game: by the
time any of it executes, the player's progress is already safe, because every
mutation writes its game-state row and its outbox row in one transaction (P08).
That is what lets the drain be as lazy, as jittered and as silent as it is —
nothing is waiting on it.

### The three ordering rules, and why each exists

`SyncController.drain` processes rows OLDEST FIRST, ONE KIND AT A TIME, at most
`syncConcurrency` (2) in flight — and a third rule the prompt does not name:

**At most one row per CONFLICT KEY in flight.** With a concurrency of 2, two
submissions of the same level could otherwise be in flight together, each
returning a `bestScore` computed before the other landed, and the reply that
arrived last would win with the staler number. Serialising by key
(`level:{lang}:{level}`, `daily:{lang}:{date}`) costs nothing — two rows for one
puzzle are rare — and closes it completely. Oldest-first is load-bearing for the
same reason: `ConflictResolver` rule 1 is only correct once every earlier
submission for that level has landed.

Two is the concurrency limit because a third request on a 2G link buys almost no
wall-clock time and costs a third socket, handshake and slice of a small radio
budget. Two is enough to hide one request's latency behind another's, which is
all concurrency is here to do.

### `summary = summary + await _send(...)` was a real bug, caught by a test

Dart evaluates the LEFT operand before awaiting the right, so with two rows in
flight both captured the same `summary` and the second write discarded the first
row's result — the 16-row drain reported 9. Fixed by reading `summary` after the
await; Dart being single-threaded is what makes the read-then-write safe once
there is no `await` between them. The three-days-offline test found it, which is
the argument for testing the drain against a real database rather than a mock.

### Backoff: the ladder never gives up, and the jitter matters more than the delays

`BackoffSchedule` is Ch10's table verbatim — immediate, 5s, 30s, 5m, 30m, 6h —
clamped at the top rather than expiring. A 5xx or an offline device is transient
BY DEFINITION and the row it stranded is a level the player really finished;
Ch01's audience goes weeks without a usable connection, so a queue that expired
its rows would lose real progress from exactly the players this game is for.
Rows leave the queue only by succeeding or by being refused permanently.

Every device that lost connectivity in one outage regains it at roughly the same
moment and then walks the same fixed ladder, so without jitter the retries stay
in lockstep and arrive as synchronised spikes on a backend still recovering from
the outage that caused them. +/-20% is wide enough to flatten that and narrow
enough that a 6h step still means six hours. The jitter is a `nextDouble()`
transform rather than an integer percentage, because 41 buckets is a smaller herd
but still a herd.

### "4xx means permanent" is the right instinct and the wrong rule

Two 4xx codes this system produces on purpose must be RETRIED:
`resource-exhausted` is P14's rate limit and literally means "later" — treating
it as permanent would discard levels from the player whose backlog is largest,
who is the offline player this subsystem exists for. `unauthenticated` is an
expired ID token or an App Check token that has not minted yet; the next attempt
carries a fresh one. So `FunctionsSyncApi.outcomeForCode` maps by MEANING, is a
pure function, and has its own test. An unrecognised code retries: the cheap
mistake is retrying something unretryable, not giving up on something that would
have worked.

`SyncDeferred` is a fourth outcome, not a failure. P14 shipped `submitScore` and
`submitDaily`; the server halves of the coin ledger and achievements are owed by
a later prompt, and those rows are HELD — no attempt counted, no backoff burned,
nothing reported. Permanent would discard a record the player earned; transient
would walk the ladder to six hours on a call that was never going to be made.

### `OutboxStatus` has three states, and the absent fourth is the point

There is no `inFlight`. An in-flight marker has to be written before the request
leaves and cleared after it returns, so a process that dies in between strands
the row forever with nothing to clear it — a level the player finished and will
never see credited, the exact failure the queue exists to prevent. The claim is
held in memory for one drain, and the durable guard against a genuine double-send
is the SERVER's replay nonce (P14), which is the side of the system that can
actually keep one.

### Schema v3 adds two columns and re-tags nothing

`RowTags.outbox` signs the SUBMISSION (`kind`, `payload`, `createdAt`, bound to
the id) and has never signed the DELIVERY BOOKKEEPING (`attempts`,
`lastAttemptAt`, now `status` and `nextRetryAt`). The line is deliberate:
forging the payload is the attack and is signed; forging the schedule is
self-harm — marking your own row `failedPermanent` stops your own score from
counting, and resetting `attempts` buys nothing the server's rate limit does not
already cap. So v2→v3 is a pure `ADD COLUMN` pair, every pre-P16 row arrives as
`pending` with a null retry (which is what it already was), and
`migration_test.dart` proves an existing queued row still verifies afterwards.

### `ConflictResolver` — Ch10's table, one function per row, coverage asserted

Nine rules in `lib/domain/sync/conflict_resolver.dart`, each a `ConflictRule`
enum value. `conflict_resolver_test.dart` registers the rule each group covers
and its final test asserts the registered set equals `ConflictRule.values` — so
a row added without a test fails the build rather than shipping untested.

Rules 2, 5 and 6 DELEGATE to `AccountMerge`, so a level, an achievement or a
streak resolved at sync time and the same pair resolved at account-link time
cannot pick different winners (`AccountMerge.mergeAchievement` was made public
for this). Rule 3 deliberately DISAGREES with `AccountMerge` and the test says
so: linking joins two separate histories where neither played "first", so taking
the better daily is the never-lose-progress rule; syncing reconciles against a
server that already decided which attempt counted, and local must match the
board. Pinned in both directions so neither gets "fixed" into the other.

**Rule 1 is the only rule in the codebase that resolves AGAINST the player.**
Everything else takes the max, sums, or unions; a recomputed score comes back as
the truth even when the truth is smaller, because the server's number is not a
second opinion — it is the only one that was ever authoritative (Ch08), and
"keep the bigger" would make a tampered client a working exploit. It reconciles
to `bestScore`, never to this attempt's `score`, so replaying a level for fun and
doing worse cannot cost a player their best. In practice it changes nothing:
client and server run the same rules over the same events, and P14's parity
fixture keeps them identical. The case where it does change something is the
case it was written for.

`reconcileFromServer` NEVER ENQUEUES — a reconcile that queued its own row would
sync in a loop forever — and rebuilds a missing or tamper-dropped row from the
server's values, recovering `hintsUsed` exactly from the star count.

### The UX rules are enforced structurally, not by convention

- **No network dialog, ever.** Nothing in the sync subsystem holds a
  `BuildContext`, so there is no code path from a failed drain to a dialog.
  `no_network_dialog_test.dart` proves it from the other end: a whole offline
  session across every screen, asserting that no `AlertDialog`, `Dialog`,
  `SnackBar`, `MaterialBanner` or `BottomSheet` is ever built — a broader list
  than "dialog", because the rule is about interruption rather than a class
  name. Reconnecting is checked too: a "you are back online" toast would be
  just as unwanted.
- **A small static indicator.** `SyncStatusIndicator` reserves the SAME
  footprint online and offline, so nothing beside it reflows, and it is not a
  button — tapping it would imply the player can do something about it.
  An earlier version also showed the queue depth, which opened a LIVE DRIFT
  QUERY from a widget in every app bar; every widget test that visited any
  screen then died on "a Timer is still pending after the widget tree was
  disposed" — the same trap CLAUDE.md already records from P11. It was also
  more than Ch10 asks for, and the Sync Inspector answers that question
  properly.
- **Cached leaderboard.** `LeaderboardScreen` reads `LeaderboardCache` in BOTH
  states rather than switching data sources when offline — one path, so the
  offline case is correct by construction instead of being an untested branch
  that only fires on the connection this audience mostly has. The relative
  "Updated 5 minutes ago" shows in both states too, since a label that appeared
  only when the connection dropped would itself be an offline notification.
  P17 owns filling the cache.
- **Rewarded buttons disable in place.** `RewardedActionButton` renders the
  same subtree at the same size in both states; only `onPressed` and the
  colours change. `sync_ux_test.dart` MEASURES the rect online and offline and
  asserts equality, because "looks about the same" is not a property a refactor
  preserves. The reason is a finger already moving: a player reaches for
  "double your coins" the instant the card settles, and a button that vanishes
  lets that tap land on whatever reflowed into its place.

### The Sync Inspector is why the engine can afford to say nothing

Dev-flavor only, registered in the route table rather than gated inside the
widget (the Style Gallery's treatment), and asserted for all three flavors
through the real router. It lists every row with its attempt count and next
retry, shows the ladder itself so a tester can tell whether a delay is on the
curve, requeues a permanently-failed row, and force-drains past BOTH gates —
clearing every backoff and skipping the connectivity check, because a force
button that still respected the ladder would be useless six hours in.

Its strings are hardcoded English and it is allowlisted from
`check_localized_strings.dart`, for the reason `GameDebugPanel` already is:
translating "next retry" would spend the native-speaker review budget the ARB
files are already waiting on (Ch07) on text no player can reach.

### Testing notes that will bite again

- **A widget test cannot `await` Drift directly.** `testWidgets` installs a
  `FakeAsync`; Drift schedules real timers that only fire when fake time
  advances, and an `await` does not advance it. `sync_inspector_test.dart`
  routes every database call through `tester.runAsync`, and replaces
  `pumpAndSettle` with an alternating pump/real-delay `settle` — the screen
  shows a `CircularProgressIndicator` until its stream delivers, and an
  indeterminate spinner schedules a frame forever, so `pumpAndSettle` times out
  by construction rather than by accident.
- **The force-drain and flavor-registration cases are plain `test`s**, not
  widget tests: driving them through a tap opens a second live Drift stream
  inside the handler, and cancelling one schedules a cleanup timer that
  outlives the tree. The button's handler is two calls, and both are asserted
  where they actually live.
- `level_complete_card_test.dart` now needs a `ProviderScope`, because the
  card's rewarded action reads connectivity. That is honest rather than
  incidental — the card is part of a Riverpod app.


## Leaderboards, achievements, friends (P17)

The social layer on top of P14's server-authoritative data. Every write in
this prompt is server-only — the client never mints a rank, an achievement or
a friendship, only reads what the server already decided, exactly the Ch08
posture P14 established.

### Server: ranks are a periodic batch job, never per-submission

`functions/src/ranks.ts`'s `recomputeRanksForBoard` is the ONE place in this
codebase allowed to read a leaderboard beyond `.limit(100)` — a full,
`orderBy('score', 'desc')` scan of one board, run on a schedule
(`recomputeLeaderboardRanks`, every 15 minutes) rather than inside
`submitScore`. Computing a rank live, on every submission, would mean reading
the WHOLE board just to place one row — the exact "download 100k docs to
count" the prompt forbids, except paid for on every level completion instead
of every leaderboard view. A rank is therefore never real-time; it is as
fresh as the last run, and `SECURITY.md`'s AR-10 records that trade
explicitly. Two writes per entry: `leaderboards/{board}/entries/{uid}.rank`
(the public row already carries public data) and `users/{uid}.stats.ranks.
{board}` (the one the prompt names, and the one the client's PINNED row
actually reads — a player outside the top 100 never appears in the query
above, so their rank has to come from somewhere that does not require being
in it). `liveBoardsFor` is `global`/`ur`/`hi`/`en`/the current
`weekly_*`/the current `daily_*` — the six live tabs. Like P14's Firestore
trigger, the scheduler's WIRING cannot be registered inside this sandbox's
outbound-proxy-restricted emulator run; the body (`recomputeRanksForBoard`)
is fully exercised on the emulator instead, split from its `onSchedule`
wrapper for exactly that reason.

### Server: six achievements are computed inside `recordSubmission`, one is a claim

`functions/src/stats.ts`'s `advanceStats` is a pure function threaded into
`submissions.ts`'s existing non-suspicious write branch — First Word, Word
Master (500 words), Trilingual (all three languages), On Fire (5 hint-free
levels), Streak Keeper (7-day `advanceEngagementStreak`) and Daily Devotee
(10 dailies) all fall out of counters already being maintained on
`users/{uid}.stats`, at ZERO new transactions: the same write that already
updates `progress` now also computes and writes `stats`. Speed Runner is
defined in the shared `ACHIEVEMENTS` map but never granted anywhere in this
build — it needs Blitz mode (v1.2), which does not exist, and its slot is
flagged `TODO(v1.2)` rather than half-wired.

**`advanceEngagementStreak` has to be order-aware, the same problem
`timingIsPlausible` (P14) already solved.** The outbox is at-least-once and
can deliver rows out of order, so "extend the streak if this completion is
the day after the last one" cannot trust the arrival order of submissions —
it has to reason from `completedAtMillis` alone, tolerating a late-arriving
row from yesterday without corrupting a streak already advanced past it.

**Collector has no fixed id and is CLIENT-CLAIMED, not server-computed.** It
is one of 36 (12 categories x 3 languages) sub-badges P11's `Collections`
already derives locally from `level_progress` — the server has no cheap way
to know a category just filled without shipping the whole content pack and
re-deriving `Collections` itself (the AR-9 gap this section's own header
warns about). So the client submits a CLAIM (`submitAchievement.ts`), and the
server applies BOUNDED PLAUSIBILITY rather than full verification: the
category must be real, the language must be real, and `highestLevel` for that
language must be at least `MIN_PLAUSIBLE_LEVEL` (5) — enough to catch a
claim an honest client could never produce, not enough to re-derive the
truth. An implausible claim is logged to `moderation/` and still returns
`{recorded: true}` — Ch08's "never error a suspected cheater" rule, unchanged
from P14. `achievementIdFor` produces `collection:{language}:{category}`,
matching `CategoryBadge.achievementIdFor` — a format the CLIENT chose back in
P11, six prompts before this one; the server was written to match the
pre-existing client convention rather than the reverse, once the mismatch was
caught by inspection before anything shipped.

### Server: friends are an immediate, mutual, code-based graph

`functions/src/friends.ts` is built to the audit's explicit ordering
(Chapter audit #11): the graph has to exist and be queryable BEFORE any
friend notification is safe to send, because a notification about an empty
graph is a promise this build cannot keep. That is also why redemption is an
IMMEDIATE, SYMMETRIC friendship rather than a request/accept flow — a
pending request nobody can be told about (no notification channel yet) would
just sit forever. Possessing the code is treated as consent, because the code
only ever travels through a channel the OWNER chose (the native share sheet
— see the client section below), never a contact-book scrape.

A code is ONE STABLE STRING PER PLAYER (`getOrCreateInviteCode`,
idempotent), not single-use — single-use would turn "share your code" into
"generate, share, invalidate, repeat" for a player inviting several people
from one group chat. Redemption (`redeemCode`) is one transaction: look up
the code's owner, refuse a self-redemption and a full friend list on EITHER
side (`LIMITS.maxFriends`, 200, via a `.count()` aggregation query inside the
transaction), then write BOTH sides of `users/*/friends/*` so neither account
can ever hold a one-directional "friendship" the other side does not see.
`redeemCodeRateLimited` wraps it with its OWN rate window
(`friendRedeemRate`), deliberately separate from `submissions.ts`'s
submission rate limit — redeeming a friend code must never eat into the
budget an offline backlog drain needs, or vice versa.

### Firestore rules: `friends` and `inviteCodes` are unreachable by any client write

`firestore.rules` adds `users/{uid}/friends`: owner `get`/`list`, `allow
write: if false` — a mutual friendship can only be written by the two-sided
transaction above, never by one side unilaterally. `inviteCodes/{document=**}`
is denied outright to every client, the same treatment `moderation/` and
`rewardCallbacks/` already get: a client that could read its own invite-code
document would learn nothing dangerous, but a client that could WRITE one
could mint an unlimited supply, bypassing `inviteCodeMaxAttempts`'s collision
handling and the whole point of a server-issued code. Both rules carry an
ALLOW half through `withSecurityRulesDisabled` (the server path really can
write `users/{uid}/friends/{friendUid}`) and a DENY half from the client SDK,
the same two-sided discipline P15 established.

### Client: the achievement popup queue is fed by two sources, one FIFO

`lib/application/achievements_controller.dart`'s `AchievementPopupQueue` is
the single queue "two unlocks never overlap" (the prompt's own words) is
built against. It has two feeds, because the six named achievements and
Collector become known to the client in genuinely different ways:

- The six named ones arrive on a LIVE Firestore listener
  (`UserStatsApi.watchAchievementIds`, diffed by `achievementPopupSyncProvider`)
  — the outbox decouples playing from syncing, so the moment one crosses its
  threshold is a SERVER event, potentially minutes after the level that
  earned it.
- Collector is known LOCALLY, synchronously, the instant
  `ProgressionController.recordCompletion` returns its `newBadges` —
  `game_screen.dart`'s existing `.then((reward) => ...)` callback (the same
  one that already sets `_reward.value`) is where it gets pushed into the
  SAME queue. No server round trip needed to know a category shelf just
  filled.

Both paths check `UiSettingsStore.seenAchievementPopupIds` BEFORE enqueueing,
not before dequeuing — a duplicate stream event for an id already sitting in
the queue is filtered too, so a re-emitted Firestore snapshot (which replays
the FULL current set on every listener attach, including a cold start) can
never queue the same popup twice in one session.

**`watchedAchievementIdsProvider` reads `currentAccountProvider`'s
`AsyncValue`, never its `.future`.** The first version awaited `.future`, and
every widget test that reached the app root — which now watches
`achievementPopupSyncProvider` — started throwing `StateError: disposed
during loading state, yet no value could be emitted` on teardown.
`NoopAuthService.watchAccount()` returns `Stream.empty()`, which never emits
and never resolves `currentAccountProvider`'s `.future`; Riverpod throws
rather than silently swallowing a provider that gets disposed mid-await.
Watching the synchronous `AsyncValue` — the same "watch inside a Stream
provider" shape `currentAccountProvider` itself already uses — degrades to
"no uid yet" instead of hanging, and is the fix.

The popup card (`AchievementUnlockCard`) follows `ChestOpenCard`'s P11 shape
exactly: one `TweenAnimationBuilder`, no ticker of its own.
`AchievementPopupOverlay` sits in `app.dart`'s `MaterialApp.router.builder`,
ABOVE every routed screen and above the RTL `Directionality` wrapper — an
achievement can unlock while the player is browsing ANY screen, not just the
game screen.

### Client: the leaderboard screen is deliberately not a `TabBarView`

"Real-time snapshots ONLY on the currently visible tab, detached on navigate
away" is one of the three literal acceptance criteria, and `TabBarView`'s
`PageView` keeps neighbouring pages BUILT for swipe smoothness — the exact
opposite of what a per-tab Firestore listener needs. So `LeaderboardScreen`
has no `TabController`/`TabBarView` anywhere: the selected tab is plain local
`State`, and the body is a `switch` that constructs ONLY the selected tab's
subtree, keyed per tab so Flutter cannot reuse the old element across a
board-id change. Switching tabs unmounts the previous one outright.

`leaderboardTopProvider(board)` (`lib/application/leaderboard_controller.dart`)
is a PLAIN `@riverpod` family — no `keepAlive`, unlike almost every other
provider in this codebase — for exactly the reason the prompt gives:
"snapshot listeners left running are the main cause of surprise Firestore
bills." The moment nothing watches a given board id, Riverpod tears the
provider down, cancelling the `StreamSubscription` and closing the Firestore
listener with it — `FirestoreLeaderboardApi.watchTop` is a bare `snapshots()`
map with nothing else holding a reference. `leaderboard_screen_test.dart`
proves this directly with a fake `LeaderboardApi` that counts active
subscriptions per board: switching from Global to Urdu drives Global's count
to zero.

**A player's own rank is a ONE-SHOT read, never live** —
`LeaderboardApi.fetchOwnEntry`, backing `ownLeaderboardEntryProvider`. A rank
is only ever as fresh as `recomputeLeaderboardRanks`'s own 15-minute cadence
(the server section above), so a live listener on it would hold a connection
open for a number that moves at most every 15 minutes. The pinned row renders
only when the signed-in uid is NOT already present in the live top-100 list
— `leaderboard_screen_test.dart` seeds exactly that shape (100 entries, none
of them "me") and asserts the pinned row shows the fetched rank.

Every live snapshot `leaderboardTopProvider` receives writes through to
`LeaderboardCache` (P16) — best-effort, fire-and-forget, the same "nothing
waits on it" shape the outbox drain uses — which is what makes
`cachedLeaderboardProvider(board)` (P16's single `cachedGlobalLeaderboard`
generalised to a family, one cache slot per board) a genuinely LAST-SEEN
copy for the offline fallback rather than permanently empty on a build that
never had a writer for it.

Weekly and Daily tabs resolve their board id through
`lib/domain/leaderboard/leaderboard_keys.dart`, a byte-for-byte Dart port of
`functions/src/leaderboardKeys.ts` — `isoWeekKey`'s Thursday-pivot logic
included, because a naive day-of-year/7 division gets the ISO year wrong
once a year at exactly the boundary the server's own test fixture catches.
The client's `leaderboard_keys_test.dart` reuses those same fixture dates
(`2027-01-01` → `2026-W53`) by inspection rather than a generated file — the
stakes here are "wrong tab shows the wrong board," not a rejected
submission, so this did not earn P14's fixture-generator machinery.
`dailyBoardId`/`currentDailyBoardId` reuse `DayKey.toString()` directly
rather than re-deriving `yyyy-MM-dd` formatting a second time.

### Client: friends — no contact-book access, ever

`lib/presentation/meta/friends_tab.dart` and its two backing providers
(`ownInviteCodeProvider`, `friendsListProvider`,
`lib/application/friends_controller.dart`) go through a share CODE and the
platform's native share sheet (`share_plus`, wrapped exactly like every other
vendor SDK this codebase keeps behind an interface — `FriendsApi` is
interface + Noop + `FirestoreFriendsApi`, the same triad `CloudAccountRepository`
established in P13) — never a contacts picker, per the prompt's own
reasoning: that permission scares this audience and hurts install-to-open
rate. `createInviteCode` is idempotent server-side, so `ownInviteCodeProvider`
re-minting nothing on every tab revisit is a property of the SERVER, not a
client-side cache the widget has to maintain.

`friendsListProvider` follows `leaderboardTopProvider`'s identical shape —
plain `@riverpod`, no `keepAlive`, torn down the instant the Friends tab is
no longer the selected one. `FriendsApi.watchFriends` reads
`users/{uid}/friends` directly (the rules above allow owner `get`/`list`);
nothing in this file ever writes there, matching the "friends is server-only"
rule the rules section states.

`_RedeemCodeCard`'s redeem flow switches on every `RedeemOutcome` the server
can return — `friended`, `alreadyFriends`, `notFound`, `ownCode`,
`friendLimitReached` — into its own localized message, plus a client-only
`RedeemFailed` for anything that never reached the server at all (offline, a
thrown `FirebaseFunctionsException`). `friends_tab_test.dart` drives every
branch through a fake `FriendsApi`, which is what actually proves the third
acceptance criterion ("friends invite code se kaam karta hai") end to end
from the UI, rather than only server-side.

### What could not be verified here

Same standing limitation as P14's Firestore trigger: `recomputeLeaderboardRanks`'s
`onSchedule` WIRING cannot be registered inside this sandbox's
outbound-proxy-restricted emulator run. Its body, `recomputeRanksForBoard`,
is fully exercised against the real Firestore emulator instead — including
the literal acceptance-criterion shape (130 accounts, a scan, a pinned rank
read back correctly for an account outside the top 100).


## Notification preferences (post-P17)

A player-requested addition on top of the streak-reminder push (the
previous section): an in-app opt-out that does not touch the OS permission
at all.

`UiSettingsStore.streakRemindersEnabled` (default true) is the same
UI-toggle carve-out as `soundEnabled`/`musicEnabled`/`hapticsEnabled` — a
preference, not game data, so `shared_preferences` is the right home for
it. `notificationRegistrationSync` reads it and registers a **null**
`fcmToken` while it is off rather than skipping registration outright, so
`language` stays current either way; `sendDueStreakReminders`'s own
existing "no token, no push" guard (post-P17) is what actually stops the
send, which is why this needed no new server-side field. `SettingsScreen`
gained a matching "Notifications" section, parallel to the existing "Sound
& haptics" one.

## Ads scaffolding, ahead of an AppLovin MAX account (pre-P18)

The Production Bible's P18 is "wire in real interstitial + rewarded ads."
No MAX account exists yet, so this could not be that prompt — what follows
instead is everything P18 needs BUT the account itself: the interface, the
pacing policy, the wiring into gameplay, and the real vendor integration,
all Noop-backed until `docs/applovin-max-setup.md`'s steps are run. The
precedent is exactly P13's: `FlavorFirebaseOptions.forFlavor` returned null
for months before three real Firebase projects existed, and the whole app
ran correctly in that state the entire time because "unconfigured" was
written as a first-class, tested path rather than assumed away.

### The three rules, mined from two 100M+-install competitors' reviews

Before any ad code was written, CLAUDE.md's `## Never do` gained three
rules (pre-dating the code, not backfilled after it): never increase
interstitial frequency as the player advances, never show an ad that
failed to load, and never show a fullscreen ad with no working skip/close.
All three came from reading real 1-star reviews of PlaySimple's Word Search
and Bluetile's Word Search Journey — escalating ad pressure, blank/broken
ad views, and forced-watch interstitials were the recurring complaints, not
difficulty or bugs. Every decision below exists to make those three rules
structurally true rather than conventionally true.

### `AdFrequencyPolicy` — one tunable, and that is what makes "never escalate" true by construction

`lib/domain/progression/ad_policy.dart` is pure Dart, RemoteConfig-backed
like `CoinEconomy`/`DdaConfig`: `canShowInterstitial` takes
`totalLevelsCompleted` (gates the very first ad — CLAUDE.md's existing
"never before the player's first completed level" rule) and
`levelsSinceLastInterstitial` (compared against
`RemoteConfigKeys.minLevelsBetweenInterstitials`, default 4, floored at 1
so a console typo cannot turn every completion into an ad). There is
deliberately no third input: the gap is the SAME at level 4 and at level
300, because nothing in the function's signature lets a caller make it
otherwise without editing this file. "Never after a failed or abandoned
level" is enforced the same way DDA's abandon rule is — by the CALLER never
consulting this policy on that path, not by a parameter here a future
caller could pass wrong.

### `AdRepository` — two global counters, journey-only

`lib/data/repositories/ad_repository.dart` persists
`totalLevelsCompleted`/`levelsSinceLastInterstitial` as tagged
`kv_settings` rows, the same carve-out `DdaRepository`'s abandon counters
already use — except GLOBAL, not per-(language, level): ad pacing is about
how many puzzles this PLAYER has just finished, not which language track,
so switching languages must not open a second, independent ad budget.
`ProgressionController.recordCompletion`'s `JourneySession` branch advances
both counters; the Daily never does, because it is a once-a-day mode with
its own economics and no Zeigarnik "Continue" seam to show an interstitial
at in the first place. Recording a SHOWN interstitial resets only the gap
counter, never the lifetime total — and a failed/skipped show is never
recorded as shown at all, so an ad that could not load never costs the
player their pacing budget (CLAUDE.md's "never show a failed ad" rule,
extended to "and never charge them for one nobody saw").

### `AdGateway` — the interface every other file is written against

`lib/services/ads/ad_gateway.dart` follows the identical
interface-Noop-real triad every other vendor SDK in this codebase uses
(`AuthService`, `NotificationService`, `AudioService`). `RewardedAdOutcome`
is a three-value enum (`earned`/`dismissed`/`unavailable`) rather than a
bool, because a caller (`game_screen.dart`) genuinely reacts differently to
"the ad experience finished" versus "nothing was ever shown" — CLAUDE.md's
"never show a failed/blank ad" rule needs the caller to be able to tell
those apart. `earned` means only that the AD finished; it does NOT mean
coins were credited — see the S2S section below.

### Wired at the level-complete seam, not inside `ProgressionController`

`game_screen.dart`'s `_continueFromLevelComplete` (the level-complete
card's "Continue" handler) checks `AdRepository.canShowInterstitial` and
calls `AdGateway.showInterstitial()` BEFORE the Zeigarnik phase flip
becomes visible — so the grid screen itself is never the thing an
interstitial appears on top of, extending "never a banner on the grid
screen" to fullscreen ads in spirit even though the letter of that rule is
about banners specifically. `ProgressionController.recordCompletion` only
ever advances the PACING counters (a repository write); showing the ad is
a presentation action and stays out of that controller, consistent with
its own header's "coins/chest/streak/badges only" scope.

`LevelCompleteCard`'s rewarded "double reward" button
(`doubleRewardPlaceholder` since P09, disabled the whole time) now takes a
real `onWatchAd` callback. `_GameContent` gates whether it is even passed
through (`AdGateway.isRewardedReady && a resolvable account exists`)
rather than handing through a callback that would silently no-op when
tapped — `RewardedActionButton.onPressed == null` is its own "not
available" contract (P16), and a button that LOOKS enabled but does
nothing on tap is worse than one that looks disabled. A successful watch
shows only a reassuring "reward on the way" message, never a doubled coin
figure this screen has no authority to promise — see the next section for
why.

### The client still cannot mint its own coins

P14's `grantRewardedReward` is unchanged and remains the ONLY path that
credits a rewarded watch, via AppLovin's S2S postback — `showRewarded`
calls `AppLovinMAX.setUserId(uid)` immediately before showing the ad
specifically so that postback's `{USER_ID}` macro carries the right
account, but the crediting itself still happens entirely outside this
client's control. `RewardedAdOutcome.earned` is therefore purely a UI
signal, never a ledger write.

### `MaxAdGateway` — real, verified against the actual plugin source

`lib/services/ads/max_ad_gateway.dart` is written against `applovin_max`
v4.6.4's real API — read directly from the installed package source in
this sandbox rather than from memory, the same discipline P13 applied to
Firebase. The plugin's fullscreen-ad API is listener-based with exactly
ONE listener slot per ad FORMAT (a static field on `AppLovinMAX`, not one
per ad unit), which only works cleanly because `MaxAdGateway` itself is a
single, `keepAlive` instance: a `Completer` captures whichever load/show is
currently in flight, and the matching listener callback resolves it. Every
show re-arms the next load immediately in
`onAdHiddenCallback`/`onAdDisplayFailedCallback`, since a MAX fullscreen ad
is single-use.

### Three separate MAX apps, not one shared set of ad unit ids

`AppConfig.adUnitIds` (`AdUnitIds?`, from the new
`FlavorAdConfig.forFlavor` in `app/config/ad_config.dart`) mirrors
`FlavorFirebaseOptions`'s exact null-degrades-to-Noop shape — all three
flavors return null today. Unlike Firebase, though, there is no way to test
AppLovin's per-DEVICE test mode from here (`setTestDeviceAdvertisingIds`
needs a real device's advertising id, discovered from that device's own
logs), so the one guarantee this repo CAN make unconditional instead is
structural: dev, stg and prod each get their OWN MAX app registration —
own SDK key, own ad units — so prod's real, revenue-generating ids are
simply never PRESENT in a dev/stg binary, regardless of whether device
test-mode was ever configured on the phone running it.
`docs/applovin-max-setup.md` is the step-by-step runbook, mirroring
`docs/firebase-setup.md`'s.

### `ads.init` is awaited with a bounded 3s ceiling, not fire-and-forget

The original P07-era `TODO(P18)` comment called this step "deferred, never
blocks the first frame," matching every other unawaited step in
`bootstrap.dart`. That shape turned out not to compose with actually
returning a working gateway: `runApp` happens immediately after
`initializeServices` returns, so a truly fire-and-forget step's result has
no `ProviderContainer` to reach once the tree is already built. Rather than
inventing a second, reactive-after-the-fact provider mechanism for a
feature with no real account to exercise it, `ads.init` is AWAITED like
steps 1-7, but bounded at the same 3-second ceiling `remoteConfig.fetch`
already uses two steps up — a hung SDK init degrades to `NoopAdGateway`
exactly like a hung Remote Config fetch degrades to shipped defaults,
rather than stalling startup. `initAds` is a new injectable seam
(alongside `openDatabase`/`loadContent`/`loadAudio`) so
`bootstrap_offline_test.dart` can prove both the throw and the timeout
paths degrade correctly without a real SDK.

### What could not be verified here

The standing limitation from every earlier prompt that touched a vendor
SDK (P13's Firebase, P14's MAX reward signature) applies again, doubled: no
MAX account exists, and there is no physical device in this sandbox even
if one did. Specifically unverified: `MaxAdGateway` against a live SDK
(the listener wiring is written against the real plugin source, but never
actually exercised against AppLovin's servers); AppLovin's device-level
test mode (needs a real device's advertising id — see
`docs/applovin-max-setup.md` §3); whether a real interstitial/rewarded ad
actually appears, is skippable within AppLovin's own minimum window, and
never blank — the CLAUDE.md rules this whole effort was built to satisfy
can only be confirmed by playing the real thing; and the MAX dashboard's
S2S postback signature scheme against `grantRewardedReward` (P14's own
"must confirm... not reachable from this repository" note, unchanged).
Everything pure — `AdFrequencyPolicy`, `AdRepository`'s counters, the
Noop/interface layer, and the level-complete/rewarded-button wiring
against a fake gateway — is fully tested and green.

## Localization

- Every user-facing string comes from `AppLocalizations.of(context)`. ARB
  files in `lib/l10n/` (`app_en.arb` is the template; `ur` and `hi` follow).
  Enforced by `tool/check_localized_strings.dart` in CI, which flags literals
  passed to `Text(...)` or to a user-facing named argument (`title:`,
  `label:`, `tooltip:`, …). Dev-only surfaces — the Style Gallery and
  `StubScreen`'s route nav — are allowlisted; they never ship.
- The generated `app_localizations*.dart` is gitignored. CI runs
  `flutter gen-l10n` before analyze, and fails if
  `l10n_untranslated.json` is non-empty — a missing translation must not
  silently ship English to an Urdu player.
- The Urdu and Hindi ARB files are machine-drafted and carry an
  `@@x-review-status` marker. **A native speaker must review them before
  release**, same rule as the word content (Ch07).
- Language names on the picker (`Language.endonym`) are deliberately NOT
  localized — a player who reads only Urdu has to find the Urdu card.

## Text handling (critical)

- ALWAYS use `.characters` (grapheme clusters from `package:characters`),
  never `.split('')` or raw `.length`, on any user-facing word/letter. In
  practice: call `ScriptNormalizer.graphemes(word, language)`, which
  normalizes first so placement and matching agree on what a "letter" is.
- Normalize via `ScriptNormalizer.normalize` BEFORE any compare and BEFORE
  grid placement — never compare raw strings. Urdu maps Yeh/Kaf/Heh variants
  and strips harakat + ZW*; Hindi is NFC + ZWJ/ZWNJ stripped; English is
  uppercase + trim. Alef Madda (آ) is deliberately never merged into ا.
- Reading direction is a language property, not a rendering fix-up:
  `Language.primaryDirection` is west for Urdu, so a horizontal word makes
  the column index DECREASE. `GridDirections.forLanguage(language, tier)`
  gives the allowed vectors, mirrored per script.
- Grid cells: Noto Naskh Arabic (Urdu), Noto Sans Devanagari (Hindi) — never
  Nastaliq in a grid cell. Nastaliq is for Urdu UI/headings/word-list only.
  Get styles from `AppTypography.gridTextStyle` / `uiTextStyle`; never build a
  `TextStyle` with a `fontFamily` by hand.
- Grid cells opt out of system text scaling
  (`AppTypography.gridTextScaler`) — the grid scales via cell size. EVERY
  other piece of text respects the system scale; the 45+ audience this game
  targets often runs a large system font.
- Fonts are bundled assets (`assets/fonts/`), subset with `fonttools` in P22.
  Never rely on the device having a Urdu-capable font installed.
- Urdu grid direction is language-aware, not a rendering hack: horizontal
  primary direction is `Offset(-1, 0)` (column index decreases).

## Code standards

- `freezed` + `json_serializable` for all models.
- `riverpod_generator` for providers; no `setState` in game screens.
- Every domain class gets unit tests in the same commit that adds it.
- No magic numbers — tunable values live in `RemoteConfigKeys`.
- Wrap every Firebase call in try/catch → Crashlytics non-fatal, never a
  user-visible error for a background/sync failure.
- Resolve dependencies with `flutter pub add` — do not hand-pin versions in
  `pubspec.yaml`.
- Lints: `flutter_lints` plus `prefer_final_locals`, `avoid_print`,
  `require_trailing_commas`.

## Never do

- Never write scores directly from client to Firestore.
- Never use Firestore "test mode" rules — production rules from day one.
- Never show an interstitial after a failed or abandoned level.
- Never show any ad before the player's first completed level.
- Never increase interstitial frequency as the player advances (more levels
  completed, a higher region, a longer streak). The Ch07 curve is allowed to
  get harder; how often the player is interrupted is not — competitor review
  mining (pre-P18) shows escalating ad pressure, not difficulty, is what
  drives a 1-star review and an uninstall. Any frequency change must be a
  deliberate, explicit remote-config value read the same way at every level,
  never a function of progress.
- Never show an ad (interstitial or rewarded) that failed to load. Fail
  silently and let the player continue exactly as if no ad had been offered —
  a blank, frozen or broken ad view is worse than skipping the ad entirely.
- Never show an interstitial or rewarded ad with no working skip/close
  control reachable within the network's own minimum skip window, regardless
  of what the ad network's default template does. A forced-interaction ad
  (no back, no skip, must watch to completion) is not shipped even if the
  mediation SDK makes it the path of least resistance.
- Never block gameplay on a network call.
- Never put a banner on the game grid screen.
- Never use `shared_preferences` for game data (coins/progress/scores) — only
  for non-sensitive UI toggles (sound, haptics, selected language). Game data
  goes in Drift with an HMAC integrity tag.
- Never show a "no internet" dialog. A small static status icon only.
- Never send more than one push notification per day.

## Definition of done for any task

Code + unit tests + `flutter analyze` clean + `dart format` clean + all three
CI checks clean (`tool/check_domain_purity.dart`,
`tool/check_no_raw_colors.dart`, `tool/check_localized_strings.dart`) +
`dart run tool/validate_content.dart` clean + updated CLAUDE.md if
architecture changed + acceptance criteria for the prompt met + committed.

If the change touches `functions/`, add: `npm run format:check`, `npm run
lint`, `npm run typecheck`, `npm test` and `npm run test:emulator`, all from
`functions/`. If it touches `lib/domain/scoring/`, regenerate the parity
fixture (`dart run tool/generate_scoring_fixtures.dart`) and update
`functions/src/scoring.ts` in the SAME commit — the two are one contract, and
`Scoring.specVersion` moves with them.

If the change touches the Drift schema, bump `schemaVersion`, add the
`onUpgrade` branch, and add a migration test that opens a database at the
PREVIOUS version and asserts an existing row still verifies — a migration that
silently invalidates tags looks to the player like lost progress.

If the change touches `firestore.rules`, add `npm run test:rules` from the repo
root, and add BOTH an allow test and a deny test for whatever moved — a rule
with only a deny test is indistinguishable from a rule that denies everything.
If it changes what the client may do, or what a threat is mitigated by, update
`SECURITY.md` in the same commit; a gap that is known and unrecorded is the one
that ships.

Note on `lib/domain/`: it must stay runnable as plain Dart, so it uses
`GridVector` rather than `dart:ui`'s `Offset`, and knows nothing about
`Locale`, `TextDirection` or font families. The Flutter-typed views of a
`Language` live in the `LanguageX` extension in `lib/app/language/`.

## Player-reported fixes and the music bed (post-P17)

Three changes driven by playing the real closed-testing build rather than by
a prompt. Each is small; each was invisible to the existing suite for a
reason worth keeping.

### The grid grew and the last rows stopped responding

`GestureLayer` held its `SelectionResolver` in a **`late final`** field, so
`size` froze at whatever grid the player first dragged on. P07's Zeigarnik
swap advances the level IN PLACE without remounting, so crossing a Ch07
curve step (5→6 takes the grid 6x6→8x8) handed the layer a new geometry on a
live `State` — and `SelectionResolver.begin` then rejected every cell
outside the old bounds. The last two rows AND columns were painted and
completely untouchable, in every language. It is rebuilt in
`didUpdateWidget` now.

**The regression test drags once on the 6x6 before growing it, and that step
is load-bearing.** `late` defers construction to first READ: a test that
grew an untouched grid builds the resolver at the new size and passes
against the bug it exists to catch. That version was written first, passed
with the fix reverted, and is why the test now warms the resolver up the way
a player who has played levels 1–5 already has.

### Back closed the app, and the level map was unreachable

Every forward navigation is `.go()`, which REPLACES the stack — deliberately,
since the app is a hub plus one-deep screens and pushing would let Home →
Journey → Game → Home stack without bound. The cost is that the Navigator has
nothing to pop, so Android's back fell through to the OS and closed the app
mid-level. Journey/Daily/Profile/Leaderboard were worse: reached with `.go()`,
`automaticallyImplyLeading` found nothing to imply, so they had no arrow
either and were dead ends by both routes out.

`SystemBackHandler` (`presentation/widgets/`) is a `PopScope` that never pops
and navigates explicitly. The game leaves to the **level map**, not Home —
a player leaving a level is usually picking another one — through a single
`_leaveGame` shared by the AppBar arrow and the system back, so the two
cannot drift apart.

Compounding it, the router always opened on the language picker and P12
sends that pick straight into level 1, so every launch dropped a returning
player back into a level with the map, the daily and collections all
unreachable. That is why the app looked as though it had no level select and
no memory of finished levels: **both already existed** — `JourneyScreen`
renders all 300 nodes with unlocking derived from the verified
`level_progress` rows, and `hasChosenLanguageProvider` was written for
exactly this and never wired up. The router now opens a returning player on
Home and **READS** that flag rather than watching it: watching rebuilds the
whole `GoRouter` the moment an FTUE player taps a language card, throwing
them out of the level that tap just started. `router_start_test.dart` pins
all three of those.

Ch02's FTUE is untouched — a first launch still opens the picker and still
auto-loads level 1 with no Play tap.

### Background music

A separate `AudioPlayer` at `ReleaseMode.loop`, NOT a sixth `AudioClip`: the
pooled clips are `ReleaseMode.stop`, last ~100ms, and `preload` would build
three players for a track that needs one.

- **`musicEnabled` is its own `UiSettingsStore` key and its own switch**, not
  a branch of `soundEnabled` — the same argument Ch03 already makes for
  splitting haptics out of sound. A player who keeps the found-word chime
  (it is the feedback that a word landed) and wants nothing else is the
  common case. `audio_service_test.dart` asserts muting the SFX leaves the
  bed exactly as it was.
- **`musicSyncProvider` also watches the app lifecycle.** Not politeness:
  a bed that keeps playing over a phone call or another app is how an app
  gets muted at the OS level permanently. `setMusicPlaying` is idempotent
  because the toggle and the lifecycle both drive it, and it `pause`s rather
  than `stop`s so returning resumes mid-loop instead of restarting.
- **The loop is seamless by construction, not by fading.** Every partial in
  `tool/generate_audio_assets.py`'s `_music_loop` is snapped to a whole
  multiple of the loop's own fundamental (1/8s), so each sine completes an
  integer number of cycles across the loop and the wrap is exactly
  continuous — which also lets note tails be written modulo the buffer
  instead of being cut off. The generator MEASURES the seam against the
  largest internal sample step and asserts, rather than trusting it.
- 16kHz mono, 8 seconds, 250KB; total audio 332KB against the 400KB budget.

**Not verified here**: the sound itself. This container has no audio device,
and `audioplayers_linux` needs GStreamer runtime plugins it does not have
(the same gap this file's P09 section already records). The loop's seam is
proven numerically and the wiring by tests; whether the bed is pleasant is a
judgement only a device can make.

### Switching language after FTUE

`LanguageScreen` was reachable exactly once — the FTUE — and every card's
`onTap` went straight into `GameRoute('1')` unconditionally. A player who
picked a language on first launch had no way back to that screen at all, so
there was no way to switch languages short of reinstalling the app.

The profile screen's new language tile (above the account card — the two are
the profile's two identity settings) opens `LanguageScreen` a second way, and
`LanguageScreen` now tells the two entries apart with the SAME
`hasChosenLanguageProvider` the router already uses to tell FTUE from a
returning player: read once at build, never watched, for the identical
reason `router.dart`'s own copy of that read gives — watching it would flip
the screen's own back arrow on mid-tap, the moment `select()` writes the new
choice.

- **First launch**: no back arrow (there is nothing valid to go back to yet),
  and picking a card still goes straight into level 1 — Ch02's FTUE is
  unchanged.
- **Reached from Profile**: a back arrow appears, wrapped in the same
  `SystemBackHandler` every other `.go()`-reached screen already uses (the
  screen has replaced Profile in the stack, so system back needs an explicit
  target too), and picking a card returns to Home instead of a level — a
  returning player switching languages wants to see their new language's
  map, not be dropped into a fresh level 1 as though this were day one.
  Nothing about the switch touches `level_progress`: that table is keyed by
  `(language, level)` already, so the OTHER language's progress was always
  sitting there untouched, just unreachable.

## Leaderboard moderation and re-engagement notifications (post-P17)

Two user-requested features, plus a decision on a third request this repo
declined to fake.

### The Urdu/Hindi content review request was NOT attempted here

`blocklist_ur.txt`/`blocklist_hi.txt` remain exactly as P10 left them —
header-only, flagged `REQUIRES A NATIVE SPEAKER`. Their own file header
already states the reason precisely: "Guessing at another language's
profanity produces exactly that kind of false positive... a native reader
must review the list." Adding a small set of guessed entries would have
traded an honest, visible gap for a false sense of coverage — CLAUDE.md's own
P10 rule ("an incomplete-but-honest list beats a guessed one") already
settles this. The word packs' `_comment` review-status banners are untouched
for the identical reason. This is real content work for an actual native
speaker, not a prompt a coding session can responsibly complete.

### Leaderboard display-name reports (AR-4 / T12)

`nameReports/{reportId}` is the one client-initiated write in this codebase
that is a bare Firestore `create` rather than a callable — see
`functions/src/nameReports.ts`'s header for why a report needs no computed
response, and therefore no callable. `firestore.rules` allows nothing else on
the collection, not even a read by the reporter: telling a reporter how close
a name is to being blanked is the identical mistake Ch08 already rules out
for a suspected cheater.

`onNameReportCreated` (a Firestore trigger, same "wiring unverified in this
sandbox" gap as `updateLeaderboards`/`recomputeLeaderboardRanks`) blanks the
reported `displayName` to `null` once `LIMITS.nameReportThreshold` (3)
DISTINCT players have reported it — `FieldValue.arrayUnion` on the reporter's
own uid is what makes a repeat report from one account count once, so the
report button itself cannot become a griefing tool. Every report is logged to
`moderation/{uid}/flags/{autoId}` (kind `name_report`), the same subcollection
`submissions.ts` and `submitAchievement.ts` already write evidence into.

Still owed, and tracked honestly rather than silently: no profanity filter
(SECURITY.md's AR-4 already argues a bad one is worse than none for Urdu/
Hindi names specifically), no human moderation queue yet, and nothing stops a
blanked player immediately re-setting the same name. The client side
(`lib/presentation/screens/leaderboard_screen.dart`'s `_EntryRow`) adds one
`IconButton` per row (hidden on the player's own entry), a confirm dialog,
and a `NameReportApi` following the same interface-Noop-Firestore triad as
every other vendor-touching service in this codebase.

### Streak-expiring re-engagement push (max one push a day)

Reuses `users/{uid}.stats.engagementStreak` — P17's existing, ALREADY-SERVER-
DERIVED streak counter for the Streak Keeper achievement — rather than
building a second sync path for the player-facing local streak
(`lib/domain/progression/streak.dart`), which CLAUDE.md's own P11 section
already establishes as permanently device-only. `stats.ts`'s header already
admits the two numbers can disagree because of sync lag; that is exactly as
acceptable here, where the cost is a slightly early or late reminder, not a
wrongly-granted achievement. The one new honesty required: a player with an
unspent streak FREEZE (local-only, never synced) can still get a reminder on
a day they are actually already safe — an accepted false positive, the same
class of trade `SECURITY.md`'s standing assumption #3 already licenses for
every threshold in this codebase.

`functions/src/streakReminders.ts`'s `sendDueStreakReminders` runs once daily
(`0 13 * * *` UTC — 6pm PKT/6:30pm IST, Ch01's primary audience; a stated
simplification, since nothing anywhere stores a per-account timezone), scans
`users` for `stats.engagementStreak.lastDay == yesterday` (a plain
single-field equality query — no composite index needed, unlike the
collection-group query `deleteAccount` requires), and sends at most one push
per account. `users/{uid}.notifications.lastPushSentDay` is written ONLY by
this function and gates every future push type the same way, not just this
one — the max-one-push-a-day rule is enforced server-side, per account,
type-agnostically, rather than trusted to each caller separately.

The send TRANSPORT is injectable (`StreakReminderSender`) for the same reason
`bootstrap.dart`'s `openDatabase`/`loadContent` seams exist: there is no FCM
emulator, so the integration test proves the query/skip/write-back logic
against a real Firestore with a fake transport, never a real send.

**Client-side additions, kept intentionally small:**

- `fcmToken` and `language` joined `profileFields()` in `firestore.rules` —
  the identical "data the player's own device hands the server about itself"
  category `displayName`/`photoUrl` already occupy, not a new kind of trust.
- `NotificationService` (`services/notifications/`) wraps `firebase_messaging`
  behind the same interface-Noop-real triad as every other vendor SDK in this
  codebase; `notificationRegistrationSyncProvider` keeps the token and
  language current, watched once at the app root next to `audioMuteSync`/
  `musicSync`.
- The OS permission prompt is requested from `HomeScreen`, gated on a streak
  of 2 (`_NotificationPermissionRequester`, entirely invisible — it never
  renders anything) — not on first launch, which `app_smoke_test.dart`
  already pins as permission-free, and not the instant a returning player
  reaches Home, which would be the identical mistake one screen later. A
  streak of 2 is the earliest point there is something concrete for the
  reminder to protect. Asked at most once ever
  (`UiSettingsStore.notificationPermissionAsked`), whether granted or denied.

### What could not be verified here

Same standing limitation as every other Firestore trigger and scheduled
function in this codebase (P14, P17): `onNameReportCreated`'s and
`sendStreakReminders`'s WIRING cannot be registered under this sandbox's
outbound-proxy-restricted emulator run. Both function BODIES
(`applyNameReport`, `sendDueStreakReminders`) are fully exercised against a
real Firestore emulator instead. Nor could an actual push notification be
delivered to a device — there is no FCM emulator and no service account here;
the transport is proven only via the injectable fake, matching this
codebase's existing standard for anything that needs a real device or a real
external network to confirm (App Check enforcement, the MAX callback, the
background-music loop's audibility).

## Competitor-driven polish (post-P18)

Driven by `docs/competitor-analysis.md` — a measured teardown of three
100M+-install word games, from video the player recorded. Shipped one task at
a time, each its own commit: the grid card, the found-word praise banner and
ribbon title, the capsule sweep, the login coin bonus, the letter flight, the
level's category in the header, the curated sound themes, the rotate button,
and the background picker below.

### Letter flight — the one animation whose two ends are in different subtrees

`lib/presentation/game/word_flight.dart` follows the established
Controller + Layer + Ticker + `ValueNotifier<double>` shape exactly
(`ParticleController`/`ParticleLayer`, `FoundWordRevealController`/
`FoundWordRevealLayer`) and departs from it in one place, for one reason:
every other layer draws inside the GRID's own box, from positions
`GridGeometry` computes. This one starts at a grid cell and lands on the
word's chip, which lives in the `Wrap` below the grid card — a sibling
subtree with no shared geometry and a layout that reflows as chips wrap.

So the two ends are MEASURED, not computed, and `WordFlightAnchors` is the
whole of that: a `GlobalKey` on `GameGrid` (whose local space is exactly the
one `cellCenter` returns) and a live word→`BuildContext` map that chips
register themselves into on mount and out of on dispose. Unregistration is
IDENTITY-CHECKED, because a chip for the same word can dispose AFTER its
replacement registered and would otherwise delete the live entry. Only the
contexts are held; render boxes are resolved at flight time, which is always
inside a pointer callback and therefore always after layout.

- **The layer sits in `_GameContent`'s outer `Stack`, not inside `GameGrid`**
  — it has to paint over the grid AND the word list — and it is placed BELOW
  the level-complete `Positioned.fill`, so the card covers a flight still in
  the air rather than the other way round.
- **Graphemes are recomputed from the matched word, never read back out of
  `state.grid.cells`.** On the LAST word of a journey level the Zeigarnik
  swap has already replaced `state.grid` with the next level's, so those
  cells hold different letters entirely. `ScriptNormalizer.graphemes(
  outcome.matchedWord, language)` is the same call `GridGenerator` used to
  place the word, and `outcome.cells` is oriented to the word (P05), so
  index i of one really is index i of the other even on a backwards trace.
- **Opacity is a `saveLayer`, not a colour on the `TextStyle`.**
  `GraphemePainterCache` keys on the style, so fading by colour would mint a
  fresh `TextPainter` — and a fresh `layout()` — on every frame of every
  letter, which is the exact trap P06's cache exists to close. The layer
  paint's colour is the letter's own token colour with a new alpha; only the
  alpha is read.
- Decorative, so reduce-motion SKIPS it outright rather than collapsing it
  to zero — same rule as particles and confetti.

### A real bug this found: a restarted `Ticker` re-measures elapsed from zero

`ParticleLayer` and `FoundWordRevealLayer` both stamped each new spawn with
`_clockMs.value` — the clock left holding the PREVIOUS run's final value —
and then restarted a stopped `Ticker`, whose `elapsed` begins at zero again.
So the second found word of a level sat frozen at `t = 0` for exactly as long
as the first animation had lasted, the third for twice that, and so on: by
the end of a twelve-word level the burst arrived seconds after the word.
Measured, not inferred — `word_flight_test.dart`'s regression case times both
runs, and against the unfixed code the second takes 864ms where the first
takes 432ms, exactly double.

The fix is one line in each of the three layers: rezero the clock when a
spawn arrives while the ticker is stopped. Only safe there — mid-run the
value is live and everything in flight is measured against it.

### Level theme in the game header

`levels.json` has always carried a `theme` per row, and nothing displayed it
— every level looked like an identical grid with a number on it, where all
three competitor apps show a category for the level a player is on.

`GameState` gained `category` (`String?`), set from
`LevelDefinition.categoryPool.firstOrNull`, NOT from `.theme` — and that
distinction matters. `DailyPuzzle.definitionFor`'s own header already
explains why: a daily's `theme` is deliberately its DATE string, to avoid
colliding with a journey region header, so reading `.theme` here would have
put "2026-08-26" under the AppBar title on the one mode that actually has a
category worth showing. `categoryPool` carries the real answer either way —
a journey level's single pool entry, or the day's picked category (or
`null`, for the genuinely-empty-pool degrade `DailyPuzzle` already handles).

It is set in exactly the two places `GameState` is otherwise built:
`_loadSession` (every fresh mount) and the Zeigarnik swap's `JourneySession`
branch (the next level's own definition, alongside the next grid and word
list it already re-derives). No third place needed it — `restart()` reuses
the current state's `category` unchanged, matching how it already treats
`language`.

Rendering reuses `categoryLabel()` (P17's own single localization point for
a content-pack category key, already shared by the collections grid and the
achievement popup) rather than inventing a second way to spell "nature" —
`AppBar.title` becomes a two-line `Column` (level line + `UiRole.caption`
category line), and the category line is skipped outright when `null` rather
than reserving blank space for it, the same "decorative, not a loading
state" treatment this file's other optional UI already gets.

### Curated sound themes (SoundTheme)

Task 4 of the competitor-driven polish list started as "regenerate the SFX
warmer" and grew, on request, into a small PICKER — three hand-designed
audio palettes rather than a knob for every individual clip. That distinction
is load-bearing: the competitor teardown found Music/Sound as separate
toggles converging across all three apps, and NOT ONE of them exposes more
than that pair — no sound-pack chooser. A free-form "10-12 sounds" picker
would be choice-fatigue this app's 45+ audience does not want, on top of
tripling the audio asset budget for options nobody asked for by name. Three
curated, pre-mixed options is the shape that keeps both costs bounded.

`lib/domain/audio/sound_theme.dart` — `SoundTheme` (`softBells` default,
`chimes`, `minimal`) — is PURE DART: the enum value is nothing but an [id],
which doubles as BOTH the persisted preference string and the
`assets/audio/{id}/` folder name, so a mismatch between what is stored and
what `tool/generate_audio_assets.py` wrote to disk cannot happen silently.
`fromId` degrades an unrecognised stored value to `defaultTheme` — the same
shape `UiSettingsStore.selectedLanguage` already uses for a downgrade.

**The competitor recipe, actually applied.** `docs/competitor-analysis.md`'s
measured recipe — fundamental + octave + fifth partials (the harmonic
series' own 1x/2x/3x) plus a 5-7kHz shimmer on celebration moments — was
recorded but not yet implemented before this task. `tool/generate_audio_
assets.py`'s `_tone()` now takes an explicit `harmonics` dict
(`{1: fundamental, 2: octave, 3: fifth}`) instead of a single bare-harmonic
float, and a new `_shimmer()` layer mixes onto `chest_open`/`level_complete`'s
final note via `_mix()`. `found.wav`'s FUNDAMENTAL stays fixed at C6 across
every theme — only the harmonics mixed onto it vary — because
`ComboPitchLadder` multiplies its playback rate by fixed ratios; moving the
fundamental per theme would move where those ratios land.

**Every tap got softer, not just the celebrations.** The player's actual
request ("jo b click ya action krta hai uska b bht soft aur interactive
awaaz") extends past the SFX the competitor doc named:
`button_tap.wav` gained a soft second harmonic and a gentler attack across
all three themes (previously a bare single-partial click), and each
`ThemeProfile` tunes its own duration/harmonic strength rather than sharing
one fixed shape.

**`ThemeProfile`** (`generate_audio_assets.py`) is the one dataclass all
three themes are generated from, so a new theme is new field values, never a
new code path: `bell_harmonics` (the fundamental/octave/fifth mix shared by
found/coin/chest_open/level_complete), `tap_*`, `shimmer_enabled`/
`shimmer_amplitude`, and the music bed's `note_gap_s`/`figure_amplitude`/
`figure_enabled`/`pad_amplitude_scale`. `minimal` sets `figure_enabled=False`
— the bed becomes JUST the sustained pad with no moving pentatonic figure at
all, the same "skip outright, don't shrink" treatment reduce-motion gives a
disabled animation elsewhere in this codebase, because a bed that is only
quieter still reads as "something is happening."

**A real edge case the loop-seam assertion did not originally cover.** The
seamless-loop proof (`generate_music`'s own assertion, documented where it
lives) checks that the wrap-around step is no bigger than the largest
internal step. That holds trivially whenever a moving figure's own attack
ramps dwarf everything else in the buffer — which was every theme until
`minimal` removed the figure. With NOTHING but the smooth sustained pad, the
seam step and the largest sampled internal step are the SAME mathematical
quantity by the snapping construction, and the only way they can differ at
all is float-rounding noise in `sin(2*pi*f*t)` at t=0 versus
t=MUSIC_LOOP_SECONDS — not a real discontinuity, which would be orders of
magnitude larger. The assertion now allows a `1e-9` epsilon for exactly that
reason, with the reasoning written at the call site so a future reader does
not mistake it for a loosened correctness check.

**Runtime theme switching without a second preload.** `AudioService` gained
`setTheme(SoundTheme)`: `AudioPlayersAudioService` re-points every
already-preloaded pooled `AudioPlayer` (and the music player) at the new
theme's files via `setSource` alone — no dispose/rebuild, since the players
and their platform channels are otherwise unchanged. The music player is
`pause`d before the source change and `resume`d after only if it was already
playing, so a switch never audibly restarts a bed that was off. `preload`
itself gained a `{SoundTheme theme = SoundTheme.defaultTheme}` parameter,
threaded from `bootstrap.dart`'s already-loaded `settings.soundTheme` (step
5b, well before step 7b's `audio.preload`) — the FIRST preload already loads
the player's own persisted theme, so `setTheme` only has to handle a
mid-session change from Settings.

**Persistence and wiring follow the exact `soundEnabled`/`musicEnabled`
shape**: `UiSettingsStore.soundTheme` (defaults to `SoundTheme.defaultTheme`,
same "a real preference from first launch" treatment), `SoundThemeSetting`
(`@riverpod` class, `services/audio/sound_settings.dart`), and
`soundThemeSyncProvider` (`ref.listen` + `fireImmediately: true`, the same
shape as `audioMuteSync`/`musicSync`) watched once at the app root next to
the other two. `SettingsScreen` renders one `ChoiceChip` per `SoundTheme`
under a new "Sound style" row, localized through a `switch` (compile-error,
not a silent fallback, if a theme is ever added without a case).

**The asset budget moved on purpose.** Three theme folders instead of one
flat set is a real ~3x jump (~332KB → ~996KB total, `pubspec.yaml`'s own
comment records the exact split) — a curated picker is only a picker if more
than one option actually ships. `pubspec.yaml` lists each `assets/audio/
{id}/` folder as its own entry rather than the parent `assets/audio/`,
because a Flutter asset directory entry only bundles the files directly
inside it, never subdirectories.

**Still not verified here**: the same standing limitation as every earlier
audio prompt (P09, the post-P17 music bed) — this container has no audio
device, and `audioplayers_linux` needs GStreamer runtime plugins it does not
have. The harmonic mix, the shimmer layer, and the three themes' actual
character are proven only by the generator's own measured assertions (loop
seam continuity, fixed C6 fundamental, file sizes) and by the wiring tests;
whether `chimes` genuinely sounds "livelier" than `soft_bells` is a judgement
only a device can make.

### The rotate button — a 180° VIEW flip, and why it is in `GridGeometry`

Asked for from a player's own recording of a competitor board (the video is
where the spec came from, not a guess): an orange circular button under the
board's corner; tapping it turns the whole grid 180° with the letters
sweeping around the centre — and each glyph staying UPRIGHT the whole way,
never appearing upside down. Frame-by-frame against that recording: the
arrangement is exactly a half turn (checked letter by letter, `G C A K E`'s
row arriving reversed at the far side), the swing runs ~350ms, and the board
dips slightly in scale at the midpoint. `Motion.slow` (340ms) and
`Motion.fade` land inside measurement error of that, so the animation is
named constants rather than fresh literals.

What it buys is real and cheap: a word running the "wrong" way is the one a
player stares straight past, and seeing the same grid from the other side
breaks that. `docs/competitor-analysis.md` already recorded a shuffle/rotate
tool sitting beside the hint button in a competitor's own anti-frustration
tutorial; this is that, built.

**It is a VIEW transform and nothing else.** No cell moves, no placement
changes, no seed is re-rolled, nothing is written. So Ch06's determinism
("level 47 is identical everywhere"), the Daily's "same board for everyone",
and P14's server-side replay all stay true by construction rather than by a
promise — there is no code path from this button to `GameState`, to
`events`, or to a repository. It is also FREE and unlimited: no coin, no
hint, no star. `_rotateBoard` deliberately does NOT call `_resetIdleClock`
either — reaching for rotate is what being stuck looks like, so postponing
the DDA nudge (Ch02/P12) on it would silence the anti-frustration help for
exactly the player it was written for.

**The rotation lives in `GridGeometry`, and that placement is the whole
design.** That class is already the one place pixels and cells meet: every
painter asks it where a cell is, and `GestureLayer` asks the same object
which cell a finger is on (P06). Rotating there means touch and paint cannot
disagree, because there is only one rotation and both read it. A
`Transform` wrapped around the widget would have rotated the glyphs too —
wrong per the video — and would have left hit-testing to be fixed
separately, which is precisely the shape of the bug this codebase already
shipped once (`GestureLayer`'s `late final` resolver silently made the last
two rows untouchable).

**Two fields, split on purpose:**

- **`rotated` (bool) — settled, and the only one hit-testing consults.** 180°
  is a REFLECTION through the grid's centre (`2c - p`), so the settled
  mapping needs no trigonometry and is its own inverse: one function serves
  both "where is this cell drawn" and "which cell is under this finger",
  with no forward/inverse pair to get backwards. Keeping the touch path free
  of `cos`/`sin` is deliberate — a rounding error there decides a cell index,
  where on the painting side it is invisible.
- **`paintSpin` (radians) — transient, and `toGridPoint` IGNORES IT.** During
  the swing the letters are mid-flight and mean nothing as targets, so
  hit-testing keeps answering against the settled layout throughout. Built
  inside `paint()` via `withPaintSpin`, once a frame, so the animation never
  travels through a widget rebuild.

**The spin rotates POSITIONS, never glyphs.** Each letter is drawn upright at
a rotated point, and a capsule is defined by its first and last cell centres
— so rotating those two points swings the whole found-word highlight with
the letters it covers, with no separate handling and no frame where a found
word comes loose from its own word. The midpoint scale dip is a
`canvas.scale`, NOT a change to `cellSize`: baking it into the font size
would mint a new `TextStyle` per frame and miss `GraphemePainterCache` 144
times a frame, which is the exact trap that cache exists to close.

**`GameGridState` owns the state; the button does not.**
`GridRotationController` (`game_grid.dart`) is a bare counter — "the player
tapped" — following `PulseController`'s shape for the identical reason: the
control sits in the screen's own corner while the state belongs to the
board. A counter rather than a bool so a second tap fires the notifier at
all, the same nonce trick `PulseSignal` uses. `_rotated`/`_spin` are
`ValueNotifier`s, so a tap rebuilds the grid subtree ONCE and the 340ms
animation rebuilds nothing at all — it reaches the two painters through
`CustomPaint.repaint`. Pass 1 (letters) therefore does repaint per frame,
but only for a spin the player asked for by tapping; P06's bargain outside
that window is unchanged.

Three things that would otherwise bite:

- **`SingleTickerProviderStateMixin` had to become `TickerProviderStateMixin`.**
  The wrong-selection fade and the spin are independent and can overlap, and
  the single-ticker mixin throws outright on the second `createTicker`.
- **A NEW LEVEL ARRIVES UPRIGHT.** P07's Zeigarnik swap advances the level in
  place without remounting `GameGrid`, so nothing else would ever clear the
  flip and the player would land on the next level already upside down.
  `didUpdateWidget` resets on a new `cells` IDENTITY — the same "a fresh
  `GridResult` per level is what 'different board' means" test
  `GridLettersPainter.shouldRepaint` already makes.
- **A live drag is cleared when the board turns**, or its capsule would be
  left running through cells that just moved.

Reduce-motion drops the SWING and keeps the ROTATION — the board really has
turned over, and a player who asked for that still needs to see it. Same
call `_PulseHighlight` already makes for the same reason: remove the
movement, keep the information.

`test/presentation/game/grid_rotation_test.dart` asserts the property that
actually matters — TOUCH FOLLOWS PAINT, over every cell of a 12x12 in both
orientations — plus an end-to-end widget case that rotates, checks the
letters genuinely moved, then drags along their NEW screen positions and
expects the same logical cells back. Both were confirmed to FAIL against a
deliberately broken `toGridPoint` that rotated paint but not touch, which is
the one way this feature could have looked perfect and been unplayable.

The button is `PositionedDirectional(end:)`, so it sits under the right
thumb in English and Hindi and the left in Urdu, following the reading
direction the screen is already mirrored to. The dev debug panel moved up to
`space48` rather than the button moving: dev-only tooling is what yields
when two things want the same corner.

### The background picker — three token-derived gradients, or the player's own photo

`docs/competitor-analysis.md`'s recording shows every competitor floating the
grid and word list as opaque cards over a full-screen scene, which is what
makes their boards read as a place rather than a form. This is that, over this
app's own tokens — plus the one thing none of them offer, a picture from the
player's own phone. `AppBackground` sits behind the game screen and Home; both
Scaffolds went transparent (a token at zero alpha, since
`check_no_raw_colors` rejects `Colors.transparent`).

**THE THREE GRADIENTS ADD NO COLOUR LITERALS AND NO ASSETS.** Each is the page
colour blended halfway toward a hue the palette already defines —
`surfaceHigh`, `primaryDim`, `regionAccent.first` — so the light theme gets
its own correct "ember" for free and a future palette retune moves the
backgrounds with it instead of stranding three hand-picked stops.
`AppColors.backgroundGradients` is a GETTER rather than a field only because
`Color.lerp` is not `const` and that class is; it is read when the chosen
style changes, not per frame.

`BackgroundStyle` (`lib/domain/theme/`) is pure Dart and names no colour: the
three gradients are a `gradientIndex`, the same indirection `JourneyRegion`
already uses for its accent. `photo` carries an index too, and that is not
redundant — it is the FALLBACK, because the file can go missing on its own.

**The player's constraint was "the photo must not become part of the app", and
it does not.** Nothing is bundled, nothing reaches the database, the APK is
byte-identical in size, and what persists is one PATH in `shared_preferences`
(~100 bytes) — pinned by `ui_settings_store_test.dart`'s key-set test, which
is where "this file never becomes somewhere image data lives" stays honest.

One qualification that cannot be engineered away, and is written into
`BackgroundPhotoService`'s header rather than glossed: Android's photo picker
hands back a COPY in the app's own cache directory, not a live handle on the
gallery file. That is the platform API. So exactly one copy exists at a time,
and it is deleted on uninstall by Android along with everything else the app
stored (the player's "uninstall ke baad chala jaye", satisfied by the OS
rather than by code that could get it wrong), deleted whenever the system
wants the cache space, and deleted here the moment a different photo is picked
or a gradient is chosen instead. The alternative — keeping a URI and re-reading
the gallery each launch — is not reliable under scoped storage: the picker's
grant is not persistable, so the background would vanish at an unpredictable
moment and read as a bug.

**A missing file is an ordinary state, resolved at the EDGE.**
`BackgroundPhotoPath.build` stats the path once, where the value enters the
app, and answers null if it is gone — so everything downstream is a plain
"photo or no photo" question with no I/O in it, and the gradient is on screen
from the very first frame rather than after a failed async load. This also
made the test deterministic: an `errorBuilder` firing on real disk I/O never
completes under `flutter_test`'s fake clock (the trap `sync_inspector_test.dart`
already records for Drift), so a test written against it hung rather than
failed. The `errorBuilder` stays for the one case the edge check cannot cover —
an eviction WHILE the app is on screen.

Two things the photo half needs that a gradient does not:

- **A downscale ceiling, applied by the picker before a byte reaches Dart**
  (1080x2400, quality 85). A 12MP photo is ~48MB decoded, on the 2GB-RAM phone
  this game targets; the loss is invisible on an image that is dimmed and sits
  behind opaque cards. `Image.file` caps decode again at the screen's own pixel
  width, for a device narrower than the stored copy.
- **A scrim, which is legibility rather than decoration.** A photo is
  arbitrary — a white sky or a black night — and behind it sit the top bar's
  score and the word chips, which are plain text with no card of their own. The
  scrim makes those readable against ANY picture rather than against the ones
  that happened to be tried, which matters more for a 45+ audience often
  running a large system font.

**A fresh filename per pick, never one fixed name.** Flutter's image cache keys
a `FileImage` on its PATH, not on contents or mtime, so overwriting one name in
place would leave the PREVIOUS photo on screen and tell a player who just
picked a new one, convincingly, that the picker is broken. The old copies are
swept by prefix rather than by one remembered path, so a file orphaned by a
crash between the copy and the preference write cannot sit in the cache
forever.

`image_picker` was checked for the trap `applovin_max` sprang twice
(`compileSdk = flutter.compileSdkVersion`, `minSdk 24` — it inherits correctly),
and its manifest declares NO `uses-permission`: the modern Android photo picker
needs none, which is the same "a permission scares this audience" reasoning
P17 used to rule out a contacts picker for friends.

### Eight themes, and a clock — `AppThemeVariant`

Player-requested, and the request came with its own hard constraint: *"per
theme esy ho k text b highlight theak ho ... kahin b gap na ho k user ko
display theak ho."* So the interesting part of this feature is not the eight
palettes; it is that "readable everywhere" is a CHECKED PROPERTY rather than
a claim, and that adding a ninth theme cannot quietly stop being one.

**The app was hard-locked to dark until this landed.** `app.dart` carried
`themeMode: ThemeMode.dark` from P02, so `AppTheme.light()` — a fully written,
fully tested 29-colour palette — had never once been on screen. Half of this
feature was already built and unreachable.

#### A theme moves its GROUND, its TEXT and its ACCENT. Nothing else.

`lib/domain/theme/app_theme_variant.dart` is pure Dart and names no colour:
`AppThemeVariant` carries an `id` (which doubles as the persisted preference
string, the same discipline `SoundTheme.id` keeps) and an `isDark` bool.
`Brightness` lives in `dart:ui`, so the translation happens exactly once, in
`AppTokens.forVariant`, and a variant and its brightness cannot disagree.

The palettes themselves are in `app_tokens.dart` — still the only file in
`lib/` allowed a colour literal — and every one of the six added ones reuses
the LIGHTNESS of the corresponding step in its family's shipped ladder. Only
hue and saturation move. That is what makes them safe to add rather than a
new accessibility search each: contrast is overwhelmingly a function of
lightness, so a palette built this way starts within a rounding error of a
ratio the live app already proved legible.

The found-word six and the region accents are SHARED per family, deliberately.
Those colours came out of a search maximising minimum pairwise CIE ΔE under
normal, protanopic and deuteranopic vision; giving each theme its own would
mean eight such searches having to keep passing forever, for a set of colours
a player never chooses.

#### The accent bar is measured, not chosen

Every added accent has to sit at least as far from its family's found-word six
as the SHIPPED marigold already does — ΔE 13.9 on dark, 8.5 on light, under all
three vision models. That number is not invented: it is the separation the live
app has always had between the selection capsule under the player's finger and
the words already found, so the bar reads as "at least as distinguishable as
the app people are playing today".

It rejected obvious choices. An orange accent on the forest ground and a red
one on the sand ground both collide with a found-word hue and are not in this
build; the aqua, rose, new-leaf, steel-blue, deep-teal and terracotta that
shipped are what cleared it.

#### The palette test grew from two palettes to eight, at the same thresholds

The file's own header already said "if this fails after a palette edit, pick
different hues; do not lower the threshold." That instruction is what made this
tractable, so it was obeyed: ΔE > 25 and contrast ≥ 3.0 are untouched, and the
`palettes` map is now derived from `AppThemeVariant.values` so a theme cannot
be added without being held to them. Four checks were ADDED, per theme, because
"text b highlight theak ho" is about more than the found-word six:

- `onSurface` vs `surface` ≥ **4.5** (WCAG AA body text)
- `onSurfaceMuted` / `onSurfaceFaint` vs `surface` ≥ **3.0**
- `primary` vs `surface` ≥ **3.0** — an accent that vanishes into its own
  ground is a selection capsule nobody can see
- `onPrimary` vs `primary` ≥ **4.5** — button text on the accent
- and the accent-vs-found-word bar above

Plus one structural check: no two variants may return the same palette. An
exhaustive `switch` already makes a variant with NO palette a compile error,
but two variants returning the same one would compile and ship a picker with a
chip that does nothing.

#### AUTO reads LOCAL time, and this is the one place that does

`DayKey`, `getDailySeed` and `TrustedClock` all count days in UTC because a
streak and a Daily puzzle have to mean the same thing for every player at once.
A palette is the opposite kind of question: what matters is the light in the
room the player is actually sitting in, which only their own wall clock knows.
There is also nothing to cheat — a player who sets their clock forward gets an
evening palette early and has taken nothing from anyone.

Six slots, `TimeOfDaySlot`: morning 05-08 (Morning Mint), day 08-12 (Daylight),
afternoon 12-16 (Desert Sand), evening 16-19 (Twilight), night 19-23
(Midnight), lateNight 23-05 (Deep Sea). Forest and Slate are manual-only —
eight palettes, six slots. The slot is named `lateNight` rather than `midnight`
because `AppThemeVariant.midnight` is the palette the NIGHT slot wears; the two
words genuinely mean different things here.

#### Two ways a boundary is crossed, and it takes both to cover them

`ResolvedThemeVariant` arms **one** `Timer` for the next boundary — not a poll.
A per-minute tick would rebuild the entire `MaterialApp` theme forever to
discover that nothing had changed, which is the same mistake P12 refused to
make when it kept the DDA idle clock out of `GameState`. And the app is not
always in the foreground when a boundary passes, where timers do not reliably
fire, so `AppLifecycleListener.onShow` re-resolves on the way back in. Neither
alone is enough.

**The timer is only ever a HINT.** Every resolution re-reads the clock, so a
timer that fires early — a clock change, a long doze, a 23- or 25-hour local
day — costs one redundant recomputation rather than a wrong palette.
`AutoTheme.timeUntilNextSlot` is floored at one minute so a clock that moves
backwards cannot produce a zero-delay timer that spins, and its test asserts
the property that actually matters: from every hour and minute sampled across
a day, the moment the timer wakes at is in a DIFFERENT slot.

The whole switch is proven against a clock the test moves itself
(`themeClockProvider`, injectable for exactly that reason) rather than by
waiting for 19:00. Reverting `_arm(clock())` was confirmed to fail three of
those cases, including the one that catches a timer which fires once and then
stops.

#### AUTO is the default, and that DISAGREES with `BackgroundStyle`

`background_style_test.dart` pins `defaultStyle` the other way, with the reason
written into it: an existing player's screen must not change under them on an
upgrade that only ADDED the ability to change it. This one defaults to AUTO
anyway, and the difference is the point — there the picker added a choice
nobody had asked to have moved; here **the moving IS the feature**. A theme
system shipped defaulted to one fixed palette would be invisible to every
player who never opens Settings. Any of the eight, including the exact palette
the app shipped with (`Midnight`, unchanged to the byte), is one tap away.

#### `theme` and `darkTheme` are the SAME object, and `themeMode` is gone

Material's light/dark pair exists to follow the OS setting, and that is exactly
the vote this app does not give it: the player picked this palette, or picked
AUTO, which follows the time of day rather than the system switch. Filling both
slots identically makes `themeMode` unable to change anything, whatever it is
set to. `app_theme_wiring_test.dart` pumps the real app root under both
`platformBrightness` values and asserts the palette does not move.

#### The picker shows swatches, not nine words

Each chip carries a miniature of the palette it names — that palette's own
`surfaceHigh`, ringed by its own `outline`, with a dot of its own `primary`,
read through `AppTokens.colorsFor(variant)` rather than from the ambient theme
(the whole point is showing a palette that is NOT the one on screen). Nine
identical chips differing only in a word would make a player tap through all of
them to find out what they do, and the names are the half of this screen a
native speaker has not reviewed yet. AUTO's swatch is whatever it resolves to
right now, which is the honest preview: picking it gives you that, for now.

The Style Gallery's dark/light toggle became a NEXT-THEME button for the same
reason its own test rewrite states: a two-state control could only ever reach
two of eight palettes, leaving six with no way to be eyeballed across all three
scripts, which is the entire job of that screen.

#### Free consequences worth knowing

`AppBackground`'s three gradients are already derived from `background`/
`surfaceHigh`/`primaryDim`/`regionAccent.first` through `Color.lerp`, so all
three re-tint per theme with zero extra work — pick Forest and Ember becomes a
forest ember. That is the same "derived, not declared" property the background
picker was built on, collecting its interest.

**Not verified here**: whether the eight actually look good. Contrast ratios,
ΔE margins and the wiring are all proven; "professional and stylish" is a
judgement only a device can make, the same standing limit this file already
records for the audio themes and the music bed.

### Player-supplied audio, and the sound-theme picker's retirement

The three synthesized `SoundTheme` sets (Soft Bells / Chimes / Minimal) and the
picker that chose between them are GONE. In their place is one set of real
recordings the player sourced themselves from Pixabay, plus a background track
they supplied — nine one-shot clips and a 32-second loop, flat in
`assets/audio/`, no folder level and no choice to make.

**The picker went because the argument for it did.** It existed so a curated
sound design could be offered in three flavours; with one definitive set there
is nothing to pick between, and a chip row that always shows the same single
selected chip is UI asking a question with one answer. `SoundTheme`,
`SoundThemeSetting`, `soundThemeSync`, `AudioService.setTheme`,
`UiSettingsStore.soundTheme` and their ARB strings and tests all came out with
it. What remains in Settings is what the player asked for: Sound on/off and
Music on/off, the two switches Ch03 argued for separately and which are
untouched.

`tool/generate_audio_assets.py` went too. It synthesized every shipped clip
from sine partials, and nothing it produced is in the app any more.

#### Levels were normalised, not just copied

The supplied clips arrived between -9.5 LUFS (the level-complete fanfare) and
-70 LUFS (the shuffle clip, so quiet its integrated measure was meaningless at
0.38s). Shipping those as-is would have made the celebration blast and the
error cue inaudible. Every clip is peak-normalised through the same chain and
then trimmed by ROLE rather than to a single target:

| clip | trim | why |
|---|---|---|
| `button_tap` | -10 dB | fires hundreds of times a session |
| `shuffle` | -8 dB | frequent, and a second look is not an event |
| `wrong`, `transition` | -7 dB | noticed, never punishing |
| `coin` | -6 dB | |
| `found` | -5 dB | |
| `chest_open`, `level_complete`, `daily_complete` | -3 dB | rare, and allowed to land |

A one-shot's RMS is not comparable across a 0.4s click and a 5.8s chest, so a
single loudness target across all of them would have been a worse answer than
this table.

#### The background loop is cut and cross-faded, and the seam is measured

The supplied track is 2:52. Embedding all of it would cost 4MB and still seam
audibly, since nothing about it was written to loop. What ships is a 32-second
segment (from 0:24, chosen off a nine-point energy scan for a stretch that
holds a steady level rather than the track's own build) with the three seconds
that FOLLOW it equal-power cross-faded onto its head — so the wrap lands where
the material already continued.

**The first attempt clicked, at 3.8x the track's own largest internal step.**
The cause was `-ss` on an mp3 not being sample-accurate: the two cut points did
not actually meet at the same sample. Decoding the whole track to wav ONCE and
cutting from that fixed it, and a 40ms guard fade at both extremes makes the
wrap silence-to-silence regardless of what the encoder does to the edges. Final
measurement, against the same bar the old generated loop used: **wrap step 5,
largest internal step 1353, ratio 0.004.**

#### Four sounds that did not exist before

- **`wrong`** — Ch03 specified SILENCE on a miss (the capsule's 180ms fade and
  nothing else) so a wrong guess could never feel like a scolding. **That call
  is deliberately reversed**, on the player's direct request. The half that
  stands is the haptic: "no buzz" is untouched, and
  `game_screen_test.dart`'s Ch03 guardian test was REWRITTEN rather than
  deleted, so it now pins exactly that split — a miss is heard, never felt.
- **`shuffle`** — the rotate button, which previously played the generic click.
  A board that physically turns over reading as an ordinary button press
  undersells it.
- **`transition`** — Continue, on the level-complete card. A movement sound,
  because something is being left behind.
- **`daily_complete`** — the Daily's own finish, distinct from a journey
  level's. It is the supplied 22-second clip capped at 4 seconds with a
  600ms tail fade, as asked. Once a day, so it can afford to be the longest
  thing in the set. The switch on `GameSession` is exhaustive, so the compiler
  guarantees both arms; only the journey arm is driven by a widget test,
  because no harness pumps `GameScreen` in daily mode and standing one up is
  more scaffolding than the assertion is worth — the test says so.

#### `audio_assets_test.dart` exists because the audio stopped being generated

A synthesizer cannot emit a missing file. Hand-placed recordings can, and
`AudioPlayersAudioService.preload` swallows a failed `setSource` by design
(juice never surfaces an error), so a misnamed clip would go silent forever
without a single log line. The test walks `AudioClip.values` and checks each
file exists and is non-trivial, that no two clips share a file, that nothing in
the folder is unclaimed by the enum, and that the whole set stays under the
933KB the three theme folders used to cost. It ships at **620KB** — smaller
than what it replaced, despite being real recordings, because the saving is
the picker going away rather than the audio getting worse.

### Four device-reported audio faults, and one root cause behind two of them

Reported after playing the shipped build: the background music was never
there; it stopped "as soon as the game starts"; the level-complete sound was
the wrong clip; and several buttons — the back arrow, "Continue with Google" —
made no sound at all.

#### OUR OWN SFX WERE EVICTING OUR OWN MUSIC, THROUGH ANDROID AUDIO FOCUS

`audioplayers` gives every player it creates `AUDIOFOCUS_GAIN`
(`AudioContextAndroid`'s own default), requested on each `resume`. Android
grants focus to the newest requester and sends `AUDIOFOCUS_LOSS` to the
previous holder — and that holder, inside one app, is our own bed.
`WrappedPlayer`'s handler treats a non-transient loss as final: it calls
`pause()` and clears its `playing` flag, and its `onGranted` only restarts a
player that flag says is playing. So the FIRST sound the app made killed the
music for the rest of the session, and nothing calls `setMusicPlaying` again
to bring it back.

That is one bug producing both reports. Launch, hear the bed, tap into a
level: the tap's own click takes focus and the music never returns — "it
stops when the game starts". Launch and tap immediately, which is what a
returning player does: the bed is gone before it registers — "music was off
by default". **`UiSettingsStore.musicEnabled` has defaulted to `true` the
whole time**, in both stores; nothing was ever off.

The fix is one call at the top of `preload`:
`AudioPlayer.global.setAudioContext` with `AndroidAudioFocus.none`, before the
first `AudioPlayer(...)` is constructed — the Android plugin copies the global
context into each new player at construction, so setting it once covers all 28
with no ordering trap. Nothing else about the context moves; `contentType`
and `usageType` keep their defaults, because only focus was implicated.

**`none` for the BED as well as the SFX**, though silencing only the SFX would
also have stopped the eviction. Three reasons:

1. With no player anywhere requesting focus, no player can be told to lose it.
   The bug becomes impossible rather than avoided — Ch10's "a property, not a
   promise", applied to a vendor default.
2. `pause` does not abandon focus; only `stop` does, and `setMusicPlaying`
   deliberately pauses so the loop resumes mid-bar. A bed holding `GAIN` would
   keep ANOTHER app's music silenced for as long as ours sat in the
   background — a worse bug than the one being fixed, and a much quieter one.
3. It is the right manners for this audience. Ch01's player is on a 2GB phone,
   often with their own music or a radio stream already going; a relaxed
   offline puzzle has no business interrupting it, and the Music switch in
   Settings already gives them the other choice.

`focusFreeContext` is a named `@visibleForTesting` getter rather than an
inline argument at its one call site, and `audio_service_test.dart` asserts
its focus mode. The regression it guards is someone restoring the plugin
default while tidying, which produces no error, no warning and no other
failing test — only silent music on a device, which is exactly how it reached
a player the first time.

`preload` also now honours a `_musicPlaying` intent recorded before there was
a player to carry it. `setMusicPlaying` returns early when `_music` is null,
keeping only the flag — and the NEXT call then returns early too, on
`playing == _musicPlaying`, so the bed would never start. `bootstrap.dart`
awaits the preload before `runApp`, so today `musicSync` always fires after
it; that is an ordering nothing enforces and a failure that is completely
silent.

#### The level-complete and Daily clips swapped places

The player supplied `4.mp3` a second time to say it belonged on level
complete rather than on the Daily, where it had first landed. The two files
were exchanged rather than re-derived: both had gone through the same -3 dB
role trim, so swapping preserves the processing exactly. Level complete is now
the ~3.9s clip and the Daily keeps the ~2.1s one — still distinct, so the
once-a-day moment never sounds like an ordinary one.

#### A GLOBAL TAP LISTENER IS THE RIGHT FIX AND FLUTTER WILL NOT ALLOW IT

P09 wired `playButtonTap` + `buttonTap` inline, three lines per control. By
the time the build reached a phone, **5 of roughly 65 interactive controls had
it**, and the player found the gaps immediately. A rule that has to be
remembered at 65 call sites is not a rule.

So the structural fix was tried first: one `Listener` at the app root that
plays the click whenever a pointer lands on something tappable, covering every
present and future control with nothing to remember. It was abandoned on
evidence, not on taste. Dumping the hit-test path of an ENABLED
`ElevatedButton` beside a DISABLED one gives **byte-identical lists of render
objects** — `InkResponse` builds its inner `GestureDetector` with
`excludeFromSemantics: true`, so no `RenderSemanticsGestureHandler` carrying
an `onTap` reaches the path, and `RenderSemanticsAnnotations` appears a dozen
times over even for plain text. A root listener could not tell a live button
from a greyed-out one and would have clicked at both — worse than the bug it
fixed. Reading it back out needs `@protected` framework API or private class
names, neither of which survives a Flutter upgrade. (A probe also has to fire
on pointer-UP with a slop check, or every scroll started on the journey map's
300 nodes clicks.)

What shipped instead is `ref.tapFeedback()` — `presentation/widgets/tap_feedback.dart`,
one call per control. It does not make forgetting impossible; it makes
forgetting visible, because a handler missing the line reads as different from
every handler around it. Every non-dev control now has it, including the ones
the player named.

Two choices inside that sweep worth keeping:

- **The AppBar arrow and the Android system back share one `goHome`**, so the
  click is in the shared function rather than on the button. That is the same
  argument `_leaveGame` already made for those two paths: they cannot drift
  apart if there is only one of them.
- **The Settings switches are self-consistent by construction.** Turning SOUND
  off silences its own click through `AudioService.setMuted`; turning HAPTICS
  off suppresses its own tick. Neither needed a special case.

Deliberately excluded: the grid (P06 owns its selection tick), the rotate
button and level-complete "Continue" (each has its own sound), and every
dev-only surface — the debug panel, the Sync Inspector, the Style Gallery.

`tap_feedback_test.dart` pumps the REAL app and taps the real arrows: a screen
in isolation would let one wired to nothing still pass. Reverting `goHome` on
the journey screen was confirmed to fail it, naming the route.

#### What could not be verified here

The audio-focus fix is confirmed from the plugin's own Kotlin source — the
`AUDIOFOCUS_GAIN` default, the loss handler's `pause()`, and the per-player
context copy are all read directly out of `audioplayers_android` 5.3.0 — but
this container has no audio device and no Android SDK, so **the bed actually
surviving a session was not heard**. Same standing limit every audio change in
this file records.

### The audio-focus fix alone was not enough — a self-healing watchdog closes the rest

Tested against the real build carrying the audio-focus fix above: music
started correctly at launch, then still stopped the instant a level was
opened from the journey map. The focus fix is correct and stays — no code
path in this app requests `AudioFocus` any more, confirmed again against the
plugin source — so the remaining stop is not this app asking Android for
focus; it is Android, or the device's own OEM power/audio manager, pausing
the background `MediaPlayer` directly, through no API this app calls. Several
popular Android skins are documented doing exactly this to a
non-foreground-service `MediaPlayer` on their own initiative — a doze-adjacent
heuristic, a "smart" battery saver — and none of it goes through
`AudioFocusChangeListener`, so there is no callback here to catch it with.

There is no public API to opt out of that behaviour. The only thing left to
do is notice it happened and undo it, so `preload` now also arms a
self-healing watchdog on the music player's own state stream:
`AudioPlayer.onPlayerStateChanged` is watched for the rest of the session,
and any transition to `paused` or `stopped` while [`_musicPlaying`] still says
the bed SHOULD be playing calls `resume()` immediately.

**The ordering that makes this safe already existed.** [`setMusicPlaying`]
flips `_musicPlaying` to `false` BEFORE calling `pause()` — a discipline
adopted for an unrelated reason (so a concurrent lifecycle change and toggle
flip agree on the target state) that turns out to be exactly what this needs
too. An intentional pause (the Music switch, the app backgrounding) is
already reflected in the flag by the time its state change reaches the
watchdog, so the listener sees nothing to correct there; only a pause NEITHER
of those two paths asked for gets fought and reversed.

`hasMusicWatchdog` is a `@visibleForTesting` getter rather than the
subscription staying entirely private — the same shape `focusFreeContext`
already took for the same reason: a regression here (someone removing the
listener while refactoring `preload`) produces no error and no other failing
test, only silent music on a device that happens to hit this OEM behaviour,
which is precisely how both bugs in this pair reached a player instead of a
test run.

**Not verified here, for the standing reason every audio change in this file
already states**: no audio device in this container. The watchdog's logic is
sound against the plugin's own documented state-stream API, but whether it
actually wins the race against a real OEM's pause — and how quickly — can
only be confirmed by playing the real build.

### The music bed's volume, raised to full on the player's direct request

`_musicVolume` shipped at 0.35 (post-P17's music-bed section: "well under the
SFX, the bed exists to be noticed only when it stops") and read as "very
quiet" ("bht slow") on a real device. The player asked for the DEFAULT level,
not a specific number — so `_musicVolume` is now `1.0`, `AudioPlayer`'s own
unattenuated default, rather than a second guessed constant this file could
get wrong the same way twice. `1.0` means "no reduction on top of whatever
the player's own phone media-volume slider is already set to," which is the
literal reading of "default."

Found by a player's own local `flutter build apk --flavor stg --release`
failing outright — this container has no Android SDK, so it cannot be
GRADLE-verified here, but the root cause is confirmed from the package
source itself: `applovin_max` 4.6.4's own `android/build.gradle`
hardcodes `compileSdkVersion 31`, completely independent of this app's own
`compileSdk` (36, `android/app/build.gradle.kts`). Modern androidx
transitives it pulls in — `androidx.fragment:1.7.1`,
`androidx.lifecycle:*:2.7.0`, `androidx.core-ktx:1.13.1`, and others —
require compileSdk 34+, so AGP's AAR-metadata check fails the build on
ANY current Flutter/AGP toolchain, not one machine. `4.6.4` is confirmed
still the latest published version (checked against the pub.dev package
API directly), so there is no newer release to upgrade to.

The fix is in `android/build.gradle.kts` (the ROOT one, not
`android/app/build.gradle.kts`): a `subprojects` block scoped to
`project.name == "applovin_max"` overrides that one module's
`LibraryExtension.compileSdk` to 36 inside `afterEvaluate` — late enough
that it runs AFTER the plugin's own build.gradle has already configured
the extension, so the override wins rather than being overwritten back.
Scoped by name rather than applied to every subproject, so a plugin that
already declares its compileSdk correctly is never second-guessed.

**Not verified here, and worth a second look if it still fails locally**:
this container's lack of an Android SDK means the fix could not be
confirmed against a real Gradle sync. The `LibraryExtension` DSL class
used is AGP's long-standing public API for `com.android.library` modules
and should resolve under AGP 9.1.0 (the version this repo's
`android/settings.gradle.kts` pins), but if a future AGP release removes
or relocates it, the fix needs updating alongside — same class of "this
needs re-verifying against a specific vendor toolchain" gap as
`MaxAdGateway`'s own already-documented untested-here status.

### `applovin_max`'s bundled Open Measurement SDK breaks R8, one layer further in

The compileSdk fix above got a real local `flutter build apk --flavor stg
--release` measurably further — past compilation, into
`:app:minifyStgReleaseWithR8` — where it hit a second, unrelated failure:
"Missing classes detected while running R8" naming three classes under
`com.amazon.privacypass` (`PrivacyPass`, `VerificationContext`,
`callback.AttestAPICallback`), each referenced from
`com.iab.omid.library.applovin.attestation.i.a(...)`. That namespace is the
IAB Open Measurement SDK `applovin_max` bundles for ad viewability
measurement; its attestation path optionally reaches for Amazon's Privacy
Pass library on an Amazon-Appstore build. This app is never built for the
Amazon Appstore, so `com.amazon.privacypass.*` is never on the classpath —
R8's whole-program analysis flags the reference as a class it cannot find
and fails the build rather than assuming the reference is dead code, unless
told explicitly that this is expected.

That is the standard, well-documented shape for this exact dependency
combination, and the fix is the standard one: a `-dontwarn` rule for the
missing package, in a proguard file R8 actually reads for this module. Two
things were true before this fix that are worth recording, because neither
was obvious from `android/app/build.gradle.kts` alone:

- **Minification was already running for release builds with no
  `proguardFiles` line in this file at all.** `grep`/`find` across
  `android/` for `minify`/`proguard` turned up nothing except
  `gradle.properties`'s own comment about a prior R8-related Gradle-daemon
  OOM crash on a small-RAM Windows machine — proof R8 had already been
  exercised successfully on this project before, just never against this
  particular missing-class combination. AGP still aggregates every
  dependency AAR's own bundled consumer-rules automatically regardless of
  whether the app module declares `proguardFiles` itself, which is
  sufficient to get a release build running R8 with zero lines of app-owned
  proguard config — this repo was in exactly that state.
- **`proguard-rules.pro` did not exist anywhere under `android/`.** It is
  now `android/app/proguard-rules.pro`, containing exactly one rule
  (`-dontwarn com.amazon.privacypass.**`) with a header explaining why, and
  `android/app/build.gradle.kts`'s `release` block gained
  `proguardFiles("proguard-rules.pro")` to make R8 actually read it. It is
  added ALONE — not alongside AGP's own default
  `getDefaultProguardFile("proguard-android-optimize.txt")` — deliberately:
  minification was already succeeding (elsewhere) without that default file
  in the mix, so pulling it in now would change R8's optimization
  aggressiveness project-wide to fix a problem that needs exactly one
  targeted rule, trading a known-good baseline for an unrelated, untested
  risk.

**Not verified here, for the same standing reason as the compileSdk fix**:
no Android SDK in this container means R8 cannot actually be run here to
confirm the build now completes. `-dontwarn com.amazon.privacypass.**` is
the documented fix for this exact IAB-Omid/Amazon-Privacy-Pass "missing
class" pattern (the same shape widely seen wherever `applovin_max`/other
MAX-mediated adapters bundle that OM SDK), and the wildcard covers all
three classes R8 named since they share one package — but if a *different*
missing-class family surfaces on the next build attempt, it is a new,
separate `-dontwarn` line in the same file, not evidence this one was
wrong.

## A splash screen, and the FTUE flow it changed (post-R8-fix)

Player-requested, with its own concrete shape: the app's name centred, the
brand icon at the bottom, the background music already playing underneath —
and, in the same request, a flow change: splash → language select → **Home**
(Play/Daily/Leaderboard), rather than splash → language select → straight
into a level.

### `SplashRoute` is the router's ONLY `initialLocation` now

Every launch — FTUE or returning — opens on `/` (`SplashScreen`). The router
no longer branches on `hasChosenLanguageProvider` at all: that decision moved
into the splash screen itself, which reads it ONCE, right before its own
one-shot navigation to `LanguageRoute` (first-time) or `HomeRoute`
(returning). This is a strictly STRONGER version of the discipline the
previous shape needed — `routerProvider` used to read that provider directly
to build `initialLocation`, and the whole "`read`, not `watch`" comment
existed to explain why that one read was safe. Now `routerProvider` depends
on nothing but the flavor, so it cannot be rebuilt out from under a running
session by ANY change to player state, because it never touches player state
at all. `router_start_test.dart` asserts this directly rather than merely by
convention: build the router, flip the language, invalidate the OTHER
provider, confirm the router instance never moved.

### The FTUE contract deliberately changed: Home, not straight into level 1

P12 shipped "Level 1 auto-loads. No Play tap required" as an explicit Ch02
decision, and it held until this prompt. The player asked, directly and
specifically, for splash → language-select → **Home**, where Play/Daily/
Leaderboard are all one tap away — the same destination a RETURNING player
already reached. `LanguageScreen`'s card `onTap` no longer branches on
`returning` at all: both paths land on `HomeRoute` now, which is why the
branch came out rather than being repointed. Nothing about `GameController`,
`ProgressionController` or the Zeigarnik swap changed — this is purely which
route a card's `onTap` resolves to. The cost is honest and worth stating
plainly: a first-time player now needs one more tap to reach their first
grid than the shipped P12 design intended. That is a deliberate trade this
prompt made on the player's explicit, repeated instruction, not an
accidental regression — `app_smoke_test.dart`, `language_screen_test.dart`
and `no_network_dialog_test.dart` all had assertions PINNING the old
straight-to-level-1 behaviour, and all three were rewritten rather than
patched around, so nothing in the suite still asserts a contract this build
no longer honours.

### The splash's own animation found a real `pumpAndSettle()` trap

First version: a raw `Timer(1600ms)` for the hand-off, alongside a SHORTER
(900ms) `TweenAnimationBuilder` for the icon/name entrance. It looked right
and broke almost every widget test in this repo that pumps the real app
root — `app_smoke_test.dart`, `style_gallery_test.dart`, `rtl_test.dart`,
`no_network_dialog_test.dart`, all of it, all at once, with "Found 0 widgets
with text 'English'" as the symptom, meaning `pumpAndSettle()` never got
past the splash.

The cause is a real, general `pumpAndSettle()` gotcha, not a splash-specific
bug: `pumpAndSettle()` stops pumping the instant nothing is scheduling a new
frame — it does not wait for every pending `Timer` to fire. Once the 900ms
entrance animation settled, the widget tree went fully static for the
remaining ~700ms until the separate `Timer` would have fired — and
`pumpAndSettle()`, seeing no scheduled frame, returned control right there,
well before the hand-off timer ever got a chance to run.

The fix folds both concerns into ONE `AnimationController`, running for the
FULL `_displayDuration` (1600ms) rather than a short entrance plus a silent
tail: `AnimationController(duration: _displayDuration)..forward()`, with
`addStatusListener` firing the navigation on `AnimationStatus.completed`.
The icon/name reveals are `Interval`s of that SAME controller's value
(`[0.0, 0.4]` and `[0.2, 0.55]`) — the identical "one driver, several
`Interval`s" shape `LevelCompleteCard`'s confetti and `ChestOpenCard` already
use — so the controller keeps ticking (and therefore keeps a frame
scheduled) for the entire window even once both reveals have visually
settled at their end values around 880ms. `pumpAndSettle()` now rides the
controller straight through to the hand-off, the same way it already rides
every other P09/P11 choreography animation in this app.

Reduce-motion skips the VISUAL entrance outright (both `Interval`-derived
opacities render at `1.0` from the first frame — never faded/scaled in) but
does NOT shorten `_displayDuration`: the hold is a branding beat, not a
movement, and a player who asked for less motion still needs the same moment
to register the screen — the identical "remove the movement, keep the
information" distinction `_PulseHighlight` already draws elsewhere in this
codebase. The controller's own duration is therefore never reduced; only
what the builder chooses to RENDER is.

`splash_screen_test.dart` pins all of this directly with `tester.pump(duration)`
rather than `pumpAndSettle()` — proving the exact hand-off timing for both
FTUE and returning players, that reduce-motion keeps the same timing while
skipping the transform, AND, as its own dedicated regression case, that a
plain `pumpAndSettle()` ride reaches the language picker on its own. That
last case is the one that would have caught this bug before it ever reached
every OTHER test file in the repo.

### The brand icon is the existing one, reused rather than redrawn

`assets/branding/app_icon.png` is a bundled copy of
`docs/store-listing/assets/icon_512.png` — the exact icon already generated
for the Play Store listing and the Android/iOS launcher icons (P17-adjacent
work). Copied rather than referenced, because `docs/` is never part of the
Flutter asset bundle and the splash needs a real `Image.asset` target. Using
the SAME file means a player sees the identical mark on the splash that they
just tapped to open the app, and it cost nothing new to generate.

### What could not be verified here

The standing limitation every visual/audio prompt in this file already
states: no display in this sandbox. Contrast, layout, the reveal timing and
the FTUE routing are all proven by the test suite (1230 tests, all four CI
checks, `flutter analyze` clean); whether the splash actually reads as
"stylish" is a judgement only a device can make. The background music
question the player asked about is not new wiring — `musicSync` already
starts the bed the instant `WordSearchMasterApp` builds, which is before the
splash's own first frame, so nothing here needed to change for the music to
already be playing when the wordmark appears; that a real device's audio
survives the whole session is the standing limitation the two most recent
audio sections of this file already record.
