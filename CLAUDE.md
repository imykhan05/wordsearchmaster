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
│   ├── sync_controller.dart
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

## Flavors — three separate worlds

| Flavor | Firebase project | Ads          | Analytics       |
|--------|-------------------|--------------|------------------|
| dev    | wsm-dev            | MAX test mode | DebugView        |
| stg    | wsm-stg            | MAX test mode | separate property|
| prod   | wsm-prod           | Real ad units | Production       |

`dev` and `stg` use an `applicationIdSuffix` so all three can be installed on
one device at once. `dev`/`stg` must never be able to serve a real ad unit —
that is the single most common cause of a permanent AdMob/MAX account ban.

## Text handling (critical)

- ALWAYS use `.characters` (grapheme clusters from `package:characters`),
  never `.split('')` or raw `.length`, on any user-facing word/letter.
- Normalize all Urdu via `ScriptNormalizer` before compare or grid placement
  (Yeh/Kaf/Heh variants, strip harakat and ZW*, never merge Alef Madda).
- Grid cells: Noto Naskh Arabic (Urdu), Noto Sans Devanagari (Hindi) — never
  Nastaliq in a grid cell. Nastaliq is for Urdu UI/headings/word-list only.
- Fonts are bundled assets (`assets/fonts/`), subset with `fonttools`. Never
  rely on the device having a Urdu-capable font installed.
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

Code + unit tests + `flutter analyze` clean + `dart run tool/check_domain_purity.dart`
clean + updated CLAUDE.md if architecture changed + acceptance criteria for
the prompt met + committed.
