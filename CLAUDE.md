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
updated CLAUDE.md if architecture changed + acceptance criteria for the
prompt met + committed.

Note on `lib/domain/`: it must stay runnable as plain Dart, so it uses
`GridVector` rather than `dart:ui`'s `Offset`, and knows nothing about
`Locale`, `TextDirection` or font families. The Flutter-typed views of a
`Language` live in the `LanguageX` extension in `lib/app/language/`.
