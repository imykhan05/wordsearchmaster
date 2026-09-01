# Play Store listing copy — English

Draft, ready to paste into Play Console → Store presence → Main store listing.
Character counts are verified below each block — do not edit without
re-running the count (`wc -m` on the block, UTF-8 locale).

## App name (30 chars max)

```
Word Search Master
```
18 characters.

## Short description (80 chars max)

```
Relaxed word search in Urdu, Hindi and English - no timer, fully offline
```
72 characters.

## Full description (4000 chars max)

```
Word Search Master is a relaxed word puzzle built for Urdu, Hindi and
English readers - each language rendered in its own correct script, not a
transliteration.

NO TIMER, EVER
This is a relaxed game. There is no clock counting down, no rush, no
penalty for taking your time. Find words at your own pace. (A separate
timed "Blitz" mode is planned as an optional extra, never the default.)

WORKS WITH NO INTERNET
Every puzzle is fully playable offline - on a bus, on a plane, with no
data plan at all. The game only reaches out to the network quietly in the
background to back up your progress and sync leaderboards, and it never
blocks play while doing so.

THREE LANGUAGES, EACH DONE PROPERLY
- Urdu, right-to-left, in Naskh script
- Hindi, in Devanagari script
- English

Pick the language you're comfortable in from the very first screen - no
menus to dig through.

A JOURNEY OF 300 LEVELS
Levels grow gradually from small, easy 6x6 grids to full 12x12 challenges,
grouped into regions with their own look. Play through nature, animals,
food, family, sports, weather, and more.

DAILY CHALLENGE
A fresh, fixed puzzle every day, the same for every player - see how you
compare on the daily leaderboard.

COINS, CHESTS, STREAKS
Earn coins as you play, open chests for a bonus, and keep your daily streak
alive. Nothing here is pay-to-win - coins buy hints, nothing more.

LEADERBOARDS AND FRIENDS
Compare your score on global, per-language, weekly and daily leaderboards.
Invite friends with a simple share code - no contacts access, ever.

BUILT FOR EVERY PHONE
Word Search Master is built to run smoothly even on older, low-memory
Android phones - so the people you want to share it with can actually play
it, not just look at it.

No forced ads before your first win. No interstitial after a level you
didn't finish. Your privacy and your time are respected.
```
1863 characters (verified with `python3 -c "print(len(open('full.txt').read()))"`)
- well under the 4000 limit, with room for future keyword tuning once the
listing is live and ASO data comes in.

## Notes

- Language names on Word Search Master's own in-app picker are intentionally
  NOT translated (CLAUDE.md rule: a player who reads only Urdu has to find
  the Urdu card by its own script) - the same logic does not apply to store
  listing copy, which Play Console serves per-locale automatically once
  `descriptions_ur.md` / `descriptions_hi.md` are added as additional
  listing languages.
- Keywords deliberately repeated for ASO without stuffing: "word search",
  "word puzzle", "Urdu", "Hindi", "offline", "relaxed", "no timer", "family".
