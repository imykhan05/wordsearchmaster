# Going live on Google Play — the complete runbook

Word Search Master · prepared 2026-09-16 · build `1.0.1+10`

This is everything between where the app is today and a public listing, in
order, with the things only you can do marked as such. Nothing here is
aspirational: every claim about the code was checked against this repository
on the date above, and where something is unfinished it says so rather than
being left for you to discover in review.

---

## 0. Read this first — the app you tested is not the app you are shipping

You have been testing **`com.educativz.wordsearchmaster.stg`**. The production
app is **`com.educativz.wordsearchmaster`** — no suffix.

Android treats those as two completely different apps, so:

- This is **not** a "promote testing to production" click. Production is a
  **separate Play Console entry**, and if you have never uploaded the
  unsuffixed package before, you are creating a new app and filling in its
  listing, content rating and data safety forms from scratch.
- The production build talks to a **different Firebase project**
  (`wsm-prod-a750e`, versus stg's `wsm-stg-b1d5f`). Anything that lives
  server-side — Firestore rules, indexes, Cloud Functions — has to be
  deployed to the production project, or it simply is not there.
- **The production build has never run on a phone.** Everything you have
  played was stg. Section 2 is about fixing that before, not after, you ship.

Both builds are ready in this repo:

| Flavour | Package | Artifact |
|---|---|---|
| stg | `com.educativz.wordsearchmaster.stg` | `build/app/outputs/bundle/stgRelease/app-stg-release.aab` |
| **prod** | `com.educativz.wordsearchmaster` | `build/app/outputs/bundle/prodRelease/app-prod-release.aab` |

Both are signed with your upload key (`android/key.properties` →
`upload-keystore.jks`), both are versionCode **10**, versionName **1.0.1**.

---

## 1. What is genuinely finished, and what is not

Being straight about this now is cheaper than a policy strike or a one-star
review later.

### Finished and tested

- The game: 300 levels per language, grid generation, scoring, stars, hints.
- Offline-first storage (Drift), integrity-tagged rows, the outbox sync queue.
- Server-authoritative scoring, leaderboards, achievements, friends, account
  deletion (Cloud Functions + Firestore rules, with an emulator-backed suite).
- 1257 automated tests green; `flutter analyze`, formatting and all four
  project CI checks clean.

### Known gaps you are shipping with

These are deliberate and documented in `CLAUDE.md`; none of them breaks the
app, but you should know them before you press publish.

1. **Urdu and Hindi content has never had a native-speaker review.** The word
   packs and their romanisations are machine-drafted, the UI strings in
   `app_ur.arb` / `app_hi.arb` still carry an `x-review-status` marker, and
   the accidental-word blocklists are thin (`blocklist_ur.txt` 21 lines,
   `blocklist_hi.txt` 17, against English's 46). The realistic risk is a
   grid that happens to spell something unfortunate in Urdu or Hindi, and
   the people most likely to find it are exactly your target audience. If
   you can get one native reader for each language for an hour before you go
   wide, do it — or launch English-first (see §7, staged rollout).
2. **No ads.** `FlavorAdConfig.forFlavor` returns null for every flavour, so
   `NoopAdGateway` is bound. The app is complete and ad-free; there is simply
   no revenue yet. Nothing crashes. Declare "no ads" in the Play forms
   (§5.4) — and if you add AppLovin later, that declaration must change with
   it.
3. **Server-side wiring you cannot verify from the client.** Firestore
   triggers and scheduled functions could never be registered in the build
   sandbox. Before launch, confirm in the Firebase console for
   `wsm-prod-a750e` that the functions actually deployed (§2.2).

---

## 2. Pre-flight — do these before you touch Play Console

### 2.1 Put the production build on a real phone

```powershell
cd D:\wordsearchmaster
flutter install --flavor prod
```

It installs alongside your stg copy (different package), so you can compare.
Walk the whole app once and specifically check the things that differ from
stg because they are wired to a different backend:

- [ ] Splash → language picker → Home
- [ ] Play a level, clear it, tap Continue, clear another, press back — the
      map shows both as cleared
- [ ] Daily Challenge opens and is playable
- [ ] Leaderboard screen loads (empty is fine — it is a fresh project)
- [ ] Profile → sign in with Google works, or fails gracefully offline
- [ ] Settings: sound, music, theme, background all apply
- [ ] Turn airplane mode ON and play a level — it must be completely normal

### 2.2 Deploy the production backend

From the repo root, with the Firebase CLI logged in:

```powershell
firebase deploy --only firestore:rules,firestore:indexes --project prod
firebase deploy --only functions --project prod
```

Then in the Firebase console for `wsm-prod-a750e`, confirm:

- [ ] Firestore rules show today's date, not "test mode"
- [ ] The composite index from `firestore.indexes.json` is **Enabled**, not
      "Building" (account deletion needs it)
- [ ] Functions list shows `submitScore`, `submitDaily`, `deleteAccount`,
      `updateLeaderboards`, `recomputeLeaderboardRanks`, `grantRewardedReward`
- [ ] App Check is in **monitor** mode, not enforced (turn enforcement on two
      weeks after launch, once you can see real tokens arriving)

### 2.3 Host the two pages Play will ask for

Both already exist in this repo:

- `docs/privacy-policy.html`
- `docs/account-deletion.html`

They need public URLs. GitHub Pages off the `docs/` folder is the free route:
repo → Settings → Pages → Source `main` / `/docs`. You will get
`https://<user>.github.io/<repo>/privacy-policy.html`. Open both and confirm
they load before you paste them into Play Console — a 404 there is a
guaranteed review rejection.

### 2.4 Rebuild if you changed anything

```powershell
flutter build appbundle --flavor prod -t lib/main_prod.dart --release
```

Every upload needs a versionCode higher than the last one you uploaded, so
bump `version:` in `pubspec.yaml` (`1.0.1+10` → `1.0.1+11`) before rebuilding
if you have already uploaded 10.

---

## 3. Create the production app in Play Console

Play Console → **Create app**.

| Field | Value |
|---|---|
| App name | `Word Search Master` |
| Default language | English (United States) — see §6 for why, and add Urdu/Hindi after |
| App or game | **Game** |
| Free or paid | **Free** |

Then work down the **Dashboard** checklist. It will not let you publish until
every item is green.

---

## 4. Store listing — the copy to paste

Full text, character-counted and SEO-reasoned, is in
**`docs/launch/STORE_LISTING.md`**. Short version:

- **App name (30):** `Word Search Master: Urdu Hindi`
- **Short description (80):** `Relaxed offline word search in Urdu, Hindi and English. No timer, no rush.`
- **Full description (4000):** see the file — it is written so the first two
  lines work as the collapsed preview, which is all most people read.

### Graphics

| Asset | Size | Status |
|---|---|---|
| App icon | 512×512 | ✅ `docs/store-listing/assets/icon_512.png` |
| Feature graphic | 1024×500 | ✅ `docs/store-listing/assets/feature_graphic_1024x500.png` |
| Phone screenshots | ≥2, 1080×1920 works | ⚠️ **you must capture these** |
| Promo video | YouTube URL | ✅ `docs/store-listing/assets/promo_video.mp4` → upload to YouTube, paste the link |

**Screenshots have to come off a real device.** Play requires them to show
the actual app, and a rendered mock-up is both a policy risk and a lie about
what a player gets. There is a script:

```powershell
flutter install --flavor prod
# put the phone on the screen you want, then:
.\tool\capture_store_screenshots.ps1 -Name 01_game
.\tool\capture_store_screenshots.ps1 -Name 02_journey
.\tool\capture_store_screenshots.ps1 -Name 03_languages
.\tool\capture_store_screenshots.ps1 -Name 04_urdu
.\tool\capture_store_screenshots.ps1 -Name 05_daily
.\tool\capture_store_screenshots.ps1 -Name 06_themes
# then frame them all with captions:
.\tool\capture_store_screenshots.ps1 -FrameAll
```

Upload the framed PNGs from `docs/store-listing/assets/screenshots/`, not the
ones in `raw/`.

Order matters more than count: **the first two are what people actually
look at.** Lead with the grid mid-word, then the journey map.

---

## 5. The forms — exact answers

### 5.1 App content → Privacy policy

Paste your hosted `privacy-policy.html` URL.

### 5.2 App access

**All functionality is available without special access.** True: the app is
guest-first and never requires a login.

### 5.3 Content rating

Answer the questionnaire from `docs/store-listing/content_rating.md`. The
substance: a word puzzle with no violence, no sexual content, no gambling, no
user-to-user free text. Expect **PEGI 3 / ESRB Everyone**.

One question people get wrong: **"Do users interact?"** — yes, technically,
because there is a leaderboard showing other players' display names and a
friend-code system. Say yes. It does not change the rating, and saying no
when a leaderboard exists is a misdeclaration.

### 5.4 Data safety

Answers are in `docs/store-listing/data_safety_form.md`. The shape of it:

- Data **is** collected (account ID, gameplay progress, crash logs, approximate
  usage) and transmitted to Firebase.
- Data **is** encrypted in transit.
- Users **can** request deletion — point it at your hosted
  `account-deletion.html`, and the in-app path is real
  (`functions/src/deleteAccount.ts`).
- **No ads** today. Revisit this the day AppLovin is wired in.

### 5.5 Ads

Declare **no ads**. (`FlavorAdConfig` returns null on every flavour.)

### 5.6 Target audience

13+ is the honest pick. It is a family-safe puzzle, but "Designed for
Families" brings a heavier compliance regime (and a stricter ads SDK
allowlist) that buys you nothing right now.

### 5.7 Government apps / News / COVID

No to all three.

---

## 6. SEO / ASO — how people will actually find this

Play ranking is driven mostly by **title**, **short description**, **install
velocity** and **retention**, with the long description contributing far less
than people assume. So the leverage is in the first two, and in localisation.

### The keyword bet

Your differentiator is not "word search" — that term is owned by apps with
100M+ installs and you will not outrank them. It is **word search in Urdu and
Hindi**, which almost nobody serves properly (correct scripts, right-to-left
Urdu, real Nastaliq/Naskh rendering). That is a small search volume you can
plausibly rank #1 for, and it converts far better than a generic term you
rank #200 for.

So the title leads with the category and ends with the differentiator:

```
Word Search Master: Urdu Hindi
```

30 characters exactly. `word search` is the head term; `urdu` and `hindi` are
the terms you can actually win.

### Localised listings are the biggest single win available

Play indexes each localised listing separately. Adding Urdu and Hindi store
listings means you appear for **اردو ورڈ سرچ** and **हिंदी वर्ड सर्च** queries
that the English listing cannot match at all. The copy already exists:

- `docs/store-listing/descriptions_ur.md`
- `docs/store-listing/descriptions_hi.md`

Add them under Store presence → Main store listing → Manage translations.
This is maybe an hour of work for the largest ranking gain on this page.

⚠️ Have a native speaker read them before publishing — same caution as §1.1.

### The rest of the checklist

- **Short description carries the most weight per character.** Ours front-loads
  `offline word search`, `Urdu`, `Hindi`, `English`, `no timer`.
- **Do not keyword-stuff the long description.** Play down-ranks it and
  reviewers reject it. Natural sentences that happen to contain the terms.
- **Never claim a rating or an award you do not have** ("#1 word game",
  "4.8 stars") — instant rejection, and it is the commonest one.
- **Install velocity in the first 72 hours matters.** Line up whatever
  audience you have to install on day one rather than trickling.
- **Retention outranks installs long-term.** The daily challenge and the
  streak reminder exist for exactly this; make sure notification permission
  is actually being granted (it is requested at streak 2).
- **Reply to every review for the first month.** Play surfaces responsiveness,
  and early one-stars are usually fixable misunderstandings.

---

## 7. Release — staged, not all at once

Production → **Create new release**.

1. Upload `app-prod-release.aab`.
2. Release name: `1.0.1 (10)`.
3. Release notes — keep it human:
   ```
   First release. 300 levels in Urdu, Hindi and English, a daily challenge,
   and everything playable offline.
   ```
4. Countries: start with **Pakistan and India**, plus anywhere you have
   people. Going worldwide on day one only adds reviews in languages you
   cannot act on.
5. **Rollout percentage: start at 20%.** A staged rollout is the one lever
   that lets you halt a bad build. Go 20% → 50% → 100% over about a week,
   watching §8 between steps.

Then **Send for review**. First review on a new app is typically a few days,
occasionally longer.

---

## 8. After it is live

Check daily for the first week:

- **Play Console → Quality → Android vitals.** Crash-free rate below 99% needs
  investigating; below 97% and Play will start suppressing you.
- **Firebase Crashlytics** (`wsm-prod-a750e`) for the actual stack traces.
- **Reviews**, especially one and two stars.

Two weeks in, when App Check is showing real tokens for the production app,
turn **App Check enforcement on** in the Firebase console. Doing it before
you have seen tokens arrive is how you take your own backend down.

---

## 9. Command reference

```powershell
# Production bundle (what you upload)
flutter build appbundle --flavor prod -t lib/main_prod.dart --release

# Production APK (for side-loading onto your own phone)
flutter build apk --flavor prod -t lib/main_prod.dart --release
flutter install --flavor prod

# Staging, unchanged
flutter build appbundle --flavor stg -t lib/main_stg.dart --release

# Full verification before any release build
flutter analyze
flutter test
dart run tool/check_domain_purity.dart
dart run tool/check_no_raw_colors.dart
dart run tool/check_localized_strings.dart
dart run tool/validate_content.dart

# Store graphics (feature graphic + promo video frames)
python3 tool/generate_store_graphics.py
```

---

## 10. The honest summary

Ready to upload today: the production bundle, the icon, the feature graphic,
the promo video, all the listing copy in three languages, and the privacy and
deletion pages.

Needs you, and cannot be done from here: capturing device screenshots,
hosting the two pages, deploying the production Firebase backend, testing the
prod build on a phone, and the Play Console account actions themselves.

Worth doing before you go wide rather than after: a native-speaker pass over
the Urdu and Hindi content. Everything else on this page can be fixed in an
update; that one is the sort of thing that shows up in reviews first.
