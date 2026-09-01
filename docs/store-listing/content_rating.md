# Play Console — Content Rating (IARC) questionnaire answers

Fill this at Play Console → App content → Content ratings. Category:
**Games → Puzzle**. Answers below reflect what the app actually does — a
word-search puzzle with a leaderboard and optional social features, no
combat, no gambling mechanics, no user-generated content beyond a
freeform display name.

| Question | Answer |
|---|---|
| Violence | None |
| Blood | None |
| Sexuality / nudity | None |
| Profanity / crude humor | None |
| Controlled substances (alcohol, tobacco, drugs) | None referenced |
| Gambling — simulated | No. Chests use a fixed weighted-random coin reward, never wagered currency, never real-money purchase of chances, and never withdrawable — CLAUDE.md's own P11 section documents the weighting as a tuning choice, not a gambling mechanic |
| Gambling — real money | No |
| User-generated content shared with others | Limited: a player-chosen display name (capped 24 chars, no moderation filter beyond length — flagged as SECURITY.md's AR-4) is visible on public leaderboards. No chat, no free-text messaging, no images. |
| Shares personal info with other users | Only the display name + photo (if signed in with Google) on public leaderboards, and a friend's own entries once a friend code is redeemed |
| Digital purchases | No real-money purchases exist yet in this build |
| Unrestricted internet access | The app makes network calls (sync, leaderboards, ads once P18 ships), but every screen is fully usable offline and no in-app browser or unrestricted web view is embedded |
| Location sharing | No |
| Personal info shared with third parties | Yes, in the limited sense the Data Safety form already states (Firebase as infrastructure processor; AppLovin once ads ship) |

## Expected outcome

With these answers, the IARC engine should return an **Everyone / 3+** (or
equivalent per region) rating. If the questionnaire's exact wording differs
from this table by the time it's filled in, answer by the *actual current
app behaviour*, not by this table verbatim — re-verify against
`lib/domain/progression/coin_economy.dart` (chest weighting) and
`lib/presentation/meta/friends_tab.dart` (no contact access, no chat) if
anything is ambiguous.

## Target audience

Set to **13 and older** at the target-audience step (matches
CLAUDE.md → SECURITY.md → AR-4's framing and the Data Safety sheet's "not
committed to the Families Policy" answer) — not because younger players
can't enjoy a word-search game, but because the unmoderated public display
name is exactly the kind of surface the Families Policy scrutinizes, and
this build hasn't done that moderation work yet.
