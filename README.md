# Patch — Exit dialog + version bump + level-progress-lost fix

Sab files inhi paths par apne project ke root mein copy/replace kar dein.

## 1. `pubspec.yaml` → REPLACE
Sirf version line change hui: `1.0.1+7` → `1.0.1+8` (Play Store ka
versionCode bump, bundle upload ke liye).

## 2. Exit-confirmation dialog (pehla patch)
- `lib/presentation/widgets/exit_confirmation_dialog.dart` — NEW
- `lib/presentation/screens/home_screen.dart` — REPLACE
- `lib/l10n/*` (teeno .arb + generated .dart) — naye exit-dialog strings

## 3. Level progress ghayab hone wala issue — REPLACE

**Masla jo aap ne bataya:** 1 level clear kiya, phir jaldi jaldi 2-3 aur
clear kiye, wapis jane par sirf level 1 hi unlocked raha — 2 aur 3 dobara
locked/disabled ho gaye.

**Wajah:** Level clear hote hi coins/stars/progress ka database mein save
**background mein (async)** shuru hota hai — screen turant continue kar
deti hai, save peechhe chalta rehta hai. Journey map (level select screen)
hamesha seedha database se taza data parhta hai — koi cache nahi. Agar aap
level clear karne ke foran baad bohat tezi se back/exit kar dein, to us
level ka save abhi database tak pahoncha hi nahi hota, aur navigation usay
adhoora chhor deti hai. Isi liye sirf pehla level (jisay thora time mila)
theek se save hua, baaqi jo "jaldi jaldi" clear kiye unka save beech mein
reh gaya — is liye wo agli dafa locked dikhte hain.

**Fix:** Ab game screen se bahar jaane ke har raste (back button, back
gesture, pause-menu ka "Home" button) us level ke save ka poora hona
**intezar karte hain** navigate karne se pehle. Agar save already ho chuka
ho to koi delay mehsoos nahi hoga (aksar milliseconds mein poora ho jata
hai); sirf us rare case mein thora sa rukta hai jahan save abhi chal raha
ho — aur is se woh level dobara locked nahi hoga.

Changed files:
- `lib/application/progression_controller.dart` — save ka "pending" track
  karne wala mechanism add kiya.
- `lib/presentation/screens/game_screen.dart` — back button, back gesture,
  aur pause-menu ka Home button — teeno ab is save ka intezar karte hain.
  (Ek chhoti si extra improvement bhi: agar save kabhi fail ho to ab
  silently ghayab hone ke bajaye report hota hai, taake future mein
  Crashlytics wire hone par aisi cheezein pakri ja sakein.)
- `lib/presentation/widgets/exit_confirmation_dialog.dart` — App-exit
  dialog bhi (belt-and-braces) isi save ka intezar karta hai "Yes" dabane
  par, app band hone se pehle.

## 4. ASAL WAJAH — "Continue" ke baad level locked hona (naya, confirmed fix)

Aap ne bataya: seedha back button dabane se level clear show hota hai,
lekin "Continue" dabane se nahi. Yehi confirm karta hai asal wajah kya hai:

**Continue button sirf Journey levels par ek interstitial AD dikhata hai**
(back button is se guzarta hi nahi). Ye ad ek alag Android Activity kholti
hai — aur kam RAM wale phone par, ya jahan "Don't keep activities"
developer option on ho, Android us waqt app ka background process/engine
band kar sakta hai. Agar us level ka database save (jo peeche background
mein chal raha hota hai) abhi poora nahi hua hota, to wahi save beech mein
kat jata hai — aur wo level dobara locked reh jata hai.

**Fix:** `lib/presentation/screens/game_screen.dart` mein `Continue` button
ka handler (`_continueFromLevelComplete`) ab ad dikhaane se **pehle** us
level ke save ka poora hona intezar karta hai. Ab jab tak ad khulay,
data pehle hi surakshit tarah se database mein commit ho chuka hoga.

Is file mein pichla fix (#3) bhi shamil hai — same file, dono changes ek
sath.

## 5. Doosri jagah bhi wahi masla — "Watch Ad for double reward" button

Level-complete card par EK aur button hota hai: "double reward ke liye ad
dekho" (rewarded ad). Ye bhi ad Activity kholta hai — bilkul "Continue"
wale button jaisa risk, lekin maine pichli dafa sirf "Continue" wala
button fix kiya tha, ye wala reh gaya tha.

Ab `_watchRewardedAd()` bhi ad dikhane se pehle level ke save ka intezar
karta hai — same fix, doosri jagah.

**IMPORTANT — apna test dobara karne se pehle:** Agar aap ne abhi jo test
kiya wo PURANI APK (bina in fixes ke) par kiya tha, to bug ka aana normal
tha — fixes install hi nahi hui thi. Fixes kaam kar rahi hain ya nahi ye
sirf tab pata chalega jab:
1. Neeche di gayi saari files apne project mein copy/replace karein
   (khaaskar `game_screen.dart` — is mein AB TEEN jagah fix hai: back
   button, pause-menu, aur DONO ad buttons).
2. `flutter clean && flutter pub get`
3. Nayi APK/bundle banayein aur SIRF wahi test karein.

Agar nayi build ke baad bhi yehi masla dobara aaye, to please exactly
bataiye:
- Level clear hone ke baad "Continue" dabaya ya "Watch Ad (double reward)"
  dabaya, ya dono?
- Us waqt internet chalu tha ya band?
- Kya phone purana/kam RAM wala hai?

Ye details agla clue denge agar masla phir bhi na jaye.

