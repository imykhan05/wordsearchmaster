# Store listing + testing — what's drafted, what's real, what's left

This folder plus `docs/index.html`, `docs/privacy-policy.html`,
`docs/account-deletion.html` and `docs/app-ads.txt` are everything from the
pre-launch checklist that can be produced without a Flutter toolchain,
Firebase console access, or a Google Play Console account — none of which
this build sandbox has. Every item below says plainly whether it's ready to
use, ready to fill in, or something only you can do and why.

## Ready to use now

- **App icon** — `docs/store-listing/assets/icon_512.png` (512×512, opaque,
  no transparency — Play Store's exact requirement). Already installed as
  the real Android launcher icon in all five `mipmap-*` densities, replacing
  Flutter's default icon, so testers stop seeing the generic Flutter logo.
- **Feature graphic** — `docs/store-listing/assets/feature_graphic_1024x500.png`.
- Both are a simple word-grid motif in the app's own marigold accent
  (`AppTokens` → `colors.primary`, `#E8A33D`) on the dark theme's background
  — **a placeholder, not a final professional design**. Good enough to stop
  testers seeing a blank/default icon; worth a real designer pass before the
  production listing goes live.
- **Short + full descriptions** — `descriptions_en.md`, character-counted
  and under Play's limits.
- **Privacy Policy** — `docs/privacy-policy.html`, matches what the code
  actually collects today (Firebase Auth/Firestore/Crashlytics/Analytics),
  with the AppLovin MAX row already written in and clearly marked "planned,
  not yet shipped" until P18 lands.
- **Account deletion page** — `docs/account-deletion.html`, describes the
  real in-app path (backed by `functions/src/deleteAccount.ts`, already
  built and tested in P14) plus an email fallback.
- **Data Safety form answers** — `data_safety_form.md`, mapped to actual
  service files, not guessed.
- **Content Rating answers** — `content_rating.md`.

## Needs one fill-in before it's usable

- ~~Every `docs/*.html` file has a `[SUPPORT_EMAIL]` placeholder~~ — filled
  in with `mohammaddeveloper38400@gmail.com` at the user's request. Worth
  revisiting later: a dedicated support alias is generally better than a
  personal inbox for something public and permanent, but that's a swap for
  whenever it's convenient, not a blocker.
- `descriptions_ur.md` / `descriptions_hi.md` are machine-drafted and
  flagged `@@x-review-status` — same status as the word packs and ARB
  files. Get a native speaker to read them before they go on the live
  listing, same rule CLAUDE.md already applies everywhere else in this repo.

## Hosting the two pages — GitHub Pages, free, from this repo

1. GitHub → this repo → **Settings → Pages**.
2. Under "Build and deployment", set **Source: Deploy from a branch**,
   branch **main** (or whichever this PR merges into), folder **`/docs`**.
3. Save. GitHub serves the contents of `docs/` at
   `https://<your-username>.github.io/wordsearchmaster/` within a minute or
   two — `index.html`, `privacy-policy.html` and `account-deletion.html` all
   become live URLs at that path.
4. Paste `https://<your-username>.github.io/wordsearchmaster/privacy-policy.html`
   into Play Console's Privacy Policy field, and the account-deletion URL
   into the equivalent field.

### `app-ads.txt` needs a different host — read this before wiring ads

`docs/app-ads.txt` is a **placeholder**, not ready to deploy — no real
AppLovin MAX publisher ID exists until P18. But when it is ready, it cannot
live at the same GitHub Pages URL as the two pages above. The ads.txt
standard requires the file at the **root of the domain** your Play listing
names as "Website" — for a *project* Pages site
(`<username>.github.io/wordsearchmaster/`), the file would sit at
`<username>.github.io/wordsearchmaster/app-ads.txt`, but crawlers check
`<username>.github.io/app-ads.txt` (the root of the `github.io` host) —
which is a different, *user-level* Pages site (`<username>.github.io` as
its own repo), not this one. Two ways to get this right later:

- Create a separate `<username>/<username>.github.io` repo and put
  `app-ads.txt` at its root — the cheap, free option.
- Or point a real custom domain at this site (Pages supports a `CNAME`
  file) and put `app-ads.txt` at that domain's root.

Either way, this is P18 work — the file here is just staged so it isn't
forgotten.

## What genuinely needs you, and why this session can't do it

This build environment has no Flutter SDK installed, no Firebase
credentials (by design — `docs/firebase-setup.md` explains why they can
never live in this repo), and no Google Play Console access. So the
following steps are real human/local-machine steps, not something to
delegate back to a coding session:

1. **Generate Firebase credentials** — run the `flutterfire configure`
   commands in `docs/firebase-setup.md` §1–2 from your own machine, logged
   into your own Google/Firebase account. This is interactive by design;
   nothing can script around the login.
2. **Build the testing AAB** — once `lib/app/config/firebase_options_stg.dart`
   exists from step 1, on your own machine with Flutter installed:
   ```sh
   flutter build appbundle --flavor stg -t lib/main_stg.dart --release
   ```
   Output lands at `build/app/outputs/bundle/stgRelease/app-stg-release.aab`.
3. **Create the closed testing track** — Play Console → your app (create it
   first if it doesn't exist yet, package `com.educativz.wordsearchmaster.stg`
   — the real `applicationId` + `.stg` suffix from
   `android/app/build.gradle.kts`, and now also what
   `docs/firebase-setup.md` uses after a correction made in this pass — it
   previously listed a `com.wordsearchmaster.app.*` placeholder that never
   matched the actual Gradle config) → **Testing → Closed testing** →
   create a track → upload the AAB from step 2 → add your testers' emails
   or a Google Group → publish the release → share the opt-in link Play
   Console gives you.
4. **Recruit testers, watch Crashlytics, get the native-speaker word review
   done** — the actual outreach and human feedback loop.

Once you have that opt-in link, come back and I can help with anything
code-side that testing turns up (crash fixes, RTL rendering issues, content
corrections) — I just can't click through the Play Console or hold your
Firebase login myself.
