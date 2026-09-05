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
