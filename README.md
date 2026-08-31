# wordsearchmaster
Word Search Master ek relaxed, offline-first word puzzle hai jo Urdu, Hindi aur English — teenon apni sahi script mein theek se render karta hai, aur jise 45-saal ki khatoon apne 2GB RAM wale phone par bina internet ke khel sakti hai.

## Repository layout

| Path | What it is |
| --- | --- |
| `lib/` | The Flutter app. `lib/domain/` is pure Dart with no `package:flutter` import, enforced in CI. |
| `functions/` | Cloud Functions (TypeScript, `asia-south1`) — server-authoritative scoring, leaderboards, account deletion. See `functions/README.md`. |
| `rules_test/` | The Firestore security-rules suite. Runs against the emulator. |
| `firestore.rules` | The deployed ruleset. Production rules from day one; never test mode. |
| `assets/content/` | Word packs and level definitions, validated by `tool/validate_content.dart`. |
| `CLAUDE.md` | The engineering rules and the rationale behind every prompt's decisions. |
| `SECURITY.md` | The Ch08 threat model, what is implemented, and what is an accepted risk. |

## Checks

```bash
flutter analyze && dart format --set-exit-if-changed lib test tool && flutter test
dart run tool/check_domain_purity.dart
dart run tool/check_no_raw_colors.dart
dart run tool/check_localized_strings.dart
dart run tool/validate_content.dart

npm ci && npm run test:rules            # Firestore security rules (emulator)
npm --prefix functions ci
npm --prefix functions run test:all     # unit + emulator-backed function tests
```

All of the above run in CI (`.github/workflows/ci.yaml`) as three jobs: the
Flutter suite, the Cloud Functions suite, and the security rules.
