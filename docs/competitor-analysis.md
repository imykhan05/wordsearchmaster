# Competitor teardown — three top word games, measured

Analysis of screen recordings of three competitors, done by extracting video
frames and measuring the audio spectrally rather than by recollection. This
file is the durable record of what was found and what is worth acting on; the
backlog at the bottom is meant to be worked through and ticked off.

The three apps:

| App | Publisher | Genre | Why it is here |
| --- | --- | --- | --- |
| Word Search Explorer | PlaySimple | word search | already cited in CLAUDE.md's ad-policy mining |
| Word Search Journey | Bluetile | word search | already cited in CLAUDE.md's ad-policy mining |
| Wordscapes | PeopleFun | word *forming* (not search) | the category's biggest title; the presentation benchmark |

Wordscapes is a different core mechanic — swipe letters from a wheel to fill a
crossword — so its *gameplay* is not a model for this app. Its presentation,
meta-game and monetisation are.

## Method, so this is reproducible

- Frames every 2s into contact sheets to map each video's flow, then 5fps
  bursts over the interesting 15-second windows (found-word resolution, level
  complete) to read animation timing. At 5fps each frame is 200ms, which is
  the resolution of every duration quoted below.
- Colours sampled from full-resolution frames with ImageMagick, not eyeballed.
- **Audio: measured, never heard.** The bed and the effects overlap, so each
  effect's spectrum is isolated by subtracting the pre-onset spectrum from the
  post-onset spectrum, leaving only the partials the effect added. Tempo is an
  autocorrelation of the energy envelope over a menu stretch with few effects.

## The convergence table — the most reliable finding here

Anything all three do independently is a genre convention, not one studio's
taste. This table is the strongest evidence in the document.

| Pattern | Explorer | Journey | Wordscapes |
| --- | :-: | :-: | :-: |
| Photographic background; puzzle floats above it | ✓ | ✓ | ✓ |
| **No per-cell boxes** — letters on a plain ground | ✓ | ✓ | n/a |
| Puzzle surface does not fill the screen | ✓ | ✓ | ✓ |
| Element **wipes/fills in sequence**, never all at once | ✓ ~400ms | ✓ ~400–600ms | ✓ staggered tiles |
| **Found letters fly from the puzzle to their destination** | ✓ | ✓ | ✓ (wheel → tile) |
| Praise banner on success | "PERFECT" | "Way to Go!" | — |
| Level theme named in the header | BIRTHDAY | NATURE / FOOD | — |
| **Puzzle dissolves to reveal the photograph** | ✓ | ✓ | ✓ (scrim lifts) |
| Sparkle burst after the reveal | ✓ | ✓ | ✓ |
| Progress bar **animating up** toward a gift icon | 1/4 | 0/3 → 1/3 | RISE 0/4 → 2/4 |
| Primary CTA arrives last | ✓ | ✓ | ✓ |
| **Daily mode locked behind a level gate** | L24 | L12 | L100 |
| Locked features shown, not hidden | ✓ | ✓ | ✓ (art + unlock level) |
| **Music and Sound as separate toggles** | ✓ | ✓ | ✓ |
| Bonus words (words found that aren't on the list) | — | ✓ | ✓ |
| FTUE names the specific word to swipe | — | ✓ | ✓ |
| Continuous non-percussive music bed | ✓ 80% | ✓ 81% | ✓ 81% |
| Pitched bell SFX, octave+fifth partials, in the bed's key | ✓ | ✓ | ✓ |

Two rows are quiet validation of calls this codebase already made
independently: the Music/Sound split (CLAUDE.md's post-P17 music section) and
the pitched combo ladder (`ComboPitchLadder`, P09).

## Wordscapes solves the problem the other two don't

The obvious objection to a photographic background is legibility. Wordscapes
answers it directly: **the photo is heavily dimmed during play and brightens to
full saturation the instant the level completes.** The scrim is the tension and
lifting it is the reward. Explorer and Journey both keep the photo bright and
put the puzzle on an opaque white card instead — which works, but spends the
photo immediately instead of holding it back as a payoff.

For this app the dimmed-during-play approach is also the cheaper one: a dark
scrim over a background is exactly the ground the existing dark theme already
assumes, so token contrast ratios do not have to be re-derived.

## The audio recipe, measured

All three: **a continuous, non-percussive music bed** (active ~80% of the
timeline in each; autocorrelation shows a smooth pad with no beat), with
**pitched bell effects tuned to the bed's own key**.

Representative isolated partials:

- Explorer: `261 / 522 / 1044 / 2094 Hz` — a pure C octave stack.
  `196 / 396 / 592 / 802 Hz` — G with a fifth and an octave. Bed in F/B♭.
- Journey: `328 / 659 / 1322 Hz` — E4/E5/E6. `525 / 1047 / 1569 / 2094 Hz` —
  C5/C6/G6/C7. Bed in C.
- Wordscapes: `264 / 525 / 1036 / 2094 Hz` — C4/C5/C6/C7. Consecutive
  successes at 25.62/25.88/26.12/26.38s **rise in pitch** (C5 → D5 → F5 → D♯7),
  which is `ComboPitchLadder`'s behaviour observed in the wild.
- Celebration moments in all three add a **5–7 kHz shimmer layer**.

So the recipe is concrete: *fundamental + octave + fifth, on a scale degree of
the music bed, plus a high-frequency sparkle layer for celebrations.*
`ComboPitchLadder` already picks the right notes; `tool/generate_audio_assets.py`
produces the wrong timbre. That is a generator change with no Dart involved.

## Per-app notes worth keeping

### Word Search Explorer (PlaySimple)

- Grid card is white, radius ~24, letters near-black `#030204`, **no cell
  chrome**, ~10% of screen width per letter, occupying only the middle ~45% of
  the screen height.
- Found capsules: `#87BDFC` blue, `#E797F7` pink, mint green — light pastel
  fills with dark letters kept on top. Different strategy from this app's
  saturated hues at 0.28 alpha on dark; theirs read as more confidently filled.
- Level complete, in order: card dissolves → capsules scatter → photo blurs →
  ribbon → badge scales from a dot → **a glowing orb flies in and on impact the
  counter rolls AND the badge illustration changes** (bare field → grown tree)
  → progress bar → CTA. ~3.5s total, strictly sequential.
- Meta: passport/stamp book per country, categories gated by level, "Tap on the
  stamps to learn interesting facts!". Owl mascot greets by time of day
  ("Evening, Guest_…"). Login incentivised with **"150 FREE!"** on both the
  launch gate and in Settings.
- Bottom nav, 5 tabs, raised centre Home.

### Word Search Journey (Bluetile)

- **FTUE teaches three mechanics in sequence**, each naming its target word:
  swipe to start → *"Words can appear diagonally: BAY"* → *"Words can appear
  backwards: SNOW"*. Cream tooltip with a pointer tail, animated glove cursor.
- **Bonus words**: a star button opens a panel — *"Words not on the list fill
  the bonus bar"* — with an `0/20` bar paying coins.
- **Daily gift is pick-one-of-three wrapped boxes.** The reward is almost
  certainly predetermined; the choice is the whole mechanic.
- Hint has a visible flight: an orange dotted particle trail streams from the
  hint button to the target letter, and the corresponding word in the list
  turns orange at the same time — the hint shows what it bought.
- Level map is a **photo album**: themed chapters (SEA, FOREST, DESERT, FLORA,
  CORAL REEF, ARCTIC, TUNDRA, TAIGA, NORTHERN LIGHTS…), each a card with its
  own header colour and 5 slots; done slots hold a photo, locked ones a
  padlock.
- Bottom nav shows **four padlocked slots** around Home — locked features stay
  permanently visible as evidence there is more game.

### Wordscapes (PeopleFun)

- **Settings exposes four toggles: Music, Sound, Notifications, and VFX**, plus
  a dedicated ACCESSIBILITY section and MANAGE MY DATA. The VFX toggle is
  effectively a player-facing performance/motion switch — directly relevant to
  a 2GB-RAM target, and something this app currently only infers from the OS
  reduce-motion setting.
- **A built-in dictionary.** Tapping a solved word shows numbered definitions,
  "Powered by Wiktionary".
- Locked features each get **a modal with artwork and the unlock level**:
  WILDLIFE at 37, TEAMS at 51, DAILY PUZZLE at 100, PROFILE after starting a
  collection. Content keeps arriving for 100+ levels.
- Language change is instant and total — the language modal itself re-renders
  in the newly chosen language and the CTA becomes "NIVEAU 2".
- Anti-frustration nudge: *"If you get stuck, try tapping the shuffle or hint
  button"* with arrows pointing at both. Note this is a **tool tutorial**, not
  a difficulty change — it does not violate this codebase's rule against
  revealing a DDA downshift, but the neutral phrasing this app already uses
  ("Want a hint?") remains the better model.

### Market pricing, observed

Both Explorer and Wordscapes price in **PKR** — the primary audience for this
app. Observed ladders: Rs 190 / 290 / 470 / 550 / 850 / 890 / 1,250 / 1,400 /
1,450 / 1,900 / 2,800 / 2,850 / 2,950 / 3,250 / 5,700 / 7,000 / 11,300 /
14,100 / 22,500, with "REMOVE ADS" at Rs 1,700 and countdown offers ("Time
left 1d18h") at Rs 590. Two different publishers both top out around
Rs 14,100. This is tested price data for this market, should an IAP tier ever
be built.

## Backlog

Effort is relative. "Risk" means risk to the existing architecture and its
tests, not risk of the idea being wrong.

### Tier 1 — all three converge, cheap, no architectural risk

1. **Praise ribbon** on word found and on level complete. Pure presentation.
   Needs new ARB entries in all three languages — these are player-facing, so
   they cannot be English-only the way the Sync Inspector is.
2. **Show the level theme** in the game header. `levels.json` already carries a
   validated `theme` per level and nothing displays it.
3. **Directional wipe-in for the found-word capsule**, along the word's own
   direction vector. Extends `FoundWordRevealLayer`, which already owns the
   0–120ms handoff window. Doing it along the vector rather than always
   left-to-right is what makes it correct for Urdu, and doubles as a silent
   teaching aid for RTL word direction.
4. **Remove the per-cell background rects** in `GridLettersPainter`
   (`grid_painter.dart:85`) or reduce them to near-invisible, and increase
   letter weight. All three competitors put letters on a plain ground.
5. **Reward the login prompt with coins.** `_SaveProgressBanner` currently
   offers nothing; the ledger already supports a reason-tagged grant, the same
   mechanism `merge:<uid>` uses.
6. **Found letters fly to the word chip.** All three do a fly-to-destination on
   success.
7. **Regenerate the found-word SFX as octave+fifth bells** in the music bed's
   key, plus a shimmer layer for level complete. `tool/generate_audio_assets.py`
   only; no Dart change.

### Tier 2 — meaningful, moderate effort

8. **Dim-during-play / brighten-on-complete background treatment**, themed per
   journey region. `JourneyRegion` already carries an accent index to build on.
   Painted gradients rather than photographs — see "not copying" below.
9. **Persistent bottom navigation**, with locked future slots visible. Also
   structurally prevents the class of navigation bug recorded in CLAUDE.md's
   post-P17 section.
10. **Progress bar that animates from its old value to its new one** on the
    level-complete card, with the chest as the visible goal at the end.
11. **Pick-one-of-three chest** instead of a single chest. Presentation change
    over the same reward roll in `CoinEconomy`.
12. **Hint flight + word-chip link**, so a spent hint visibly connects to the
    word it revealed.
13. **A "VFX" toggle in Settings**, defaulting on, that disables particles and
    confetti independently of the OS reduce-motion setting. Genuinely useful on
    the 2GB target and a one-line gate at each existing `Motion.reduced()`
    branch.

### Tier 3 — discuss before building

14. **Word meaning on tap.** Wordscapes ships a Wiktionary dictionary; this app
    already has `hint`, `roman`, `en` and `category` for all 960 words, written
    and validator-checked. Tapping a found word to see its meaning and
    transliteration is *nearly free content-wise* and is worth more here than
    in an English-only game, because a player may be learning one of the three
    languages. **Strongest differentiator on this list.**
15. **Progressive feature gating.** All three gate the Daily (L12/L24/L100).
    But here the Daily and Leaderboard *are* the retention systems, so any gate
    should be low — around level 5 — and should show the locked feature with
    artwork rather than hiding it.
16. **Album-style journey map** — region nodes that fill in with earned art.
17. **Bonus words.** Two of three ship it, including the market leader. Blocked
    on Urdu and Hindi dictionaries, which is real content work for a native
    speaker, not a code task — the same constraint that already blocks
    `blocklist_ur.txt`/`blocklist_hi.txt`.
18. **IAP store / remove-ads.** Largest scope. Price data above.

### Deliberately not copying

- **Full-bleed photographic backgrounds at 300 levels.** Memory and APK cost on
  a 2GB Android 7 target. Take the dim/brighten *treatment* and apply it to
  painted gradients instead.
- **Notification permission at first launch.** Explorer and Journey both ask
  during the loading screen, before the player has anything worth protecting.
  This app's streak-of-2 gate is better practice and better for opt-in rate.
- **Escalating ad pressure.** Nothing observed here changes CLAUDE.md's
  existing "Never do" rules, which were mined from these same apps' reviews.

## What none of them can do

All three are single-script games. This app renders Urdu, Hindi and English
each in its own script, with a right-to-left primary direction for Urdu, and
ships a per-word hint, transliteration and English gloss in a validated content
pack. Every item above should be judged on whether it strengthens that or
merely imitates a game that never had to solve it.
