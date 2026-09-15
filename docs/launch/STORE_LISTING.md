# Store listing copy — production, SEO-tuned

Paste-ready for Play Console → Store presence → Main store listing. Every
block is character-counted against Play's limit. Re-count if you edit.

The reasoning behind the keyword choices is in
`docs/launch/PRODUCTION_LAUNCH.md` §6 — read that before rewriting anything,
because the title in particular is doing deliberate work.

---

## App name — 30 char limit

```
Word Search Master: Urdu Hindi
```

**30 characters.** Exactly at the limit.

`Word Search` is the head term nobody wins on its own. `Urdu Hindi` is the
tail you can plausibly rank first for, and it doubles as the thing that makes
someone tap: a reader who searches in those terms is looking for exactly this
and mostly finding apps that render their script badly or not at all.

If you would rather lead with brand, the alternative is:

```
Word Search Master - اردو हिंदी
```
**30 characters.** Riskier: script in a title can render oddly in some
surfaces, and it costs you the Latin `urdu`/`hindi` keyword match.

---

## Short description — 80 char limit

```
Relaxed offline word search in Urdu, Hindi and English. No timer, no rush.
```

**73 characters.**

This field is weighted heavily per character and is shown under the title in
search results. It front-loads `offline`, `word search`, all three languages,
and the single strongest differentiator against the category (`no timer`).

---

## Full description — 4000 char limit

The first two lines are the collapsed preview — almost all of the reading
that happens, happens there. Everything after is for the minority who expand,
and for indexing.

```
A word search that finally reads right in Urdu, Hindi and English - each one
in its own script, with no timer and no internet needed.

Most word games treat other languages as an afterthought. Urdu comes out
backwards or in the wrong font, Hindi letters break apart, and you spend more
time fighting the app than finding words. Word Search Master was built the
other way round: the script came first, and the game was built to fit it.

WHAT YOU GET

- 300 hand-checked levels in each language, from gentle 6x6 grids up to 12x12
- A new Daily Challenge every day, the same puzzle for everyone
- Completely playable offline - on a plane, on the train, on no signal at all
- No timer anywhere. Take an hour on one level if you like

BUILT FOR THE SCRIPT, NOT BOLTED ON

- Urdu runs right to left, the way it should, in proper Naskh
- Hindi renders each akshara as one letter instead of splitting it
- English is English
- Every word is checked before it ships, and the difficulty follows the
  length of the actual letters rather than a guess

RELAXED BY DESIGN

There is no countdown, no lives to run out, no pop-up telling you that you
are too slow. If you get stuck, the board can be rotated for a fresh look at
the same grid, and a hint is there when you want one. Nothing punishes you
for taking your time.

MADE TO KEEP

- A journey map of 300 levels, so you can always see where you are
- Streaks, coins and chests that reward coming back without nagging
- Collections to fill in across twelve categories
- Leaderboards and friend codes, if you like a bit of competition
- Eight colour themes, or let it follow the time of day

LIGHT ON YOUR PHONE

Built for a 2GB phone on Android 7 and up. It does not need a fast connection
because it does not need a connection at all - your progress is saved on the
device first and synced later, if and when there is a network.

Free to play. No account needed to start.
```

**1,684 characters.** Comfortably inside the limit, with room to add an
awards or press line later if you earn one.

### What is deliberately NOT in there

- No "#1", no star claims, no install counts. Play rejects unearned
  superlatives, and it is the single commonest rejection on a new listing.
- No keyword block at the bottom. It reads as spam to both the reviewer and
  the ranker.
- No mention of ads, because there are none yet. The moment AppLovin lands,
  this text and the data-safety form both change.

---

## Urdu and Hindi listings

Already drafted at `docs/store-listing/descriptions_ur.md` and
`descriptions_hi.md`. Add them in Play Console under **Manage translations**.

This is the highest-leverage SEO action on the whole page: Play indexes each
localised listing separately, so an Urdu listing makes you findable for
اردو-script queries that the English listing cannot match at all — and those
are exactly the queries where you have almost no competition.

⚠️ Get a native speaker to read both before publishing. The drafts are
machine-assisted and carry the same review caveat as the in-app Urdu/Hindi
strings.

---

## Graphics checklist

| Asset | Requirement | File |
|---|---|---|
| Icon | 512×512 PNG, no transparency | `docs/store-listing/assets/icon_512.png` |
| Feature graphic | 1024×500 PNG | `docs/store-listing/assets/feature_graphic_1024x500.png` |
| Phone screenshots | 2–8, min 320px, 16:9-ish | capture with `tool/capture_store_screenshots.ps1` |
| Promo video | YouTube URL (not a file upload) | upload `docs/store-listing/assets/promo_video.mp4` to YouTube first |

Screenshot order, best-selling first:

1. **The grid mid-word** — one word highlighted, a few already found. This is
   the picture that says what the app is in half a second.
2. **The journey map** — the trail, a few completed nodes with stars.
3. **The language picker** — three scripts side by side. This is the
   differentiator, made visual.
4. **The grid in Urdu** — proof, not a claim.
5. The daily challenge.
6. Settings, theme row visible.

---

## Release notes — 500 char limit

```
First release. 300 levels in Urdu, Hindi and English, a daily challenge, and
everything playable offline. No timer, no ads, no account needed to start.
```

**150 characters.**
