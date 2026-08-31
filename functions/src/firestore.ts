/**
 * The admin SDK handle and the small set of paths every function shares.
 *
 * `initializeApp()` is called exactly once, lazily, so importing a module for
 * a unit test does not require credentials — the pure halves of this codebase
 * (`scoring.ts`, `validation.ts`, `levels.ts`, `leaderboardKeys.ts`) import
 * nothing from here for precisely that reason.
 */

import { getApps, initializeApp } from 'firebase-admin/app';
import { FieldValue, getFirestore, type Firestore } from 'firebase-admin/firestore';

import { COLLECTIONS } from './config';

export { FieldValue };

let cached: Firestore | undefined;

export function db(): Firestore {
  if (cached === undefined) {
    if (getApps().length === 0) initializeApp();
    cached = getFirestore();
  }
  return cached;
}

export function userRef(uid: string) {
  return db().collection(COLLECTIONS.users).doc(uid);
}

export function scoreRef(uid: string, scoreId: string) {
  return userRef(uid).collection(COLLECTIONS.scores).doc(scoreId);
}

export function nonceRef(uid: string, nonce: string) {
  return userRef(uid).collection(COLLECTIONS.nonces).doc(encodeDocId(nonce));
}

export function coinGrantRef(uid: string, eventId: string) {
  return userRef(uid).collection(COLLECTIONS.coinGrants).doc(encodeDocId(eventId));
}

export function moderationRef(uid: string) {
  return db().collection(COLLECTIONS.moderation).doc(uid).collection(COLLECTIONS.flags);
}

export function leaderboardEntryRef(board: string, uid: string) {
  return db()
    .collection(COLLECTIONS.leaderboards)
    .doc(board)
    .collection(COLLECTIONS.entries)
    .doc(uid);
}

export function rewardCallbackRef(eventId: string) {
  return db().collection(COLLECTIONS.rewardCallbacks).doc(encodeDocId(eventId));
}

/** `level_{lang}_{level}` — one document per level per language, best-of. */
export function levelScoreId(language: string, level: number): string {
  return `level_${language}_${level}`;
}

/**
 * `daily_{lang}_{date}` — one document per language per date.
 *
 * Per LANGUAGE as well as per date, because a date has three different daily
 * puzzles (`DailyRepository` keys its rows by `(date, language)` for exactly
 * this reason). The one-entry-per-uid-per-date rule the board needs is
 * enforced a level up, in `updateLeaderboards`, which keeps the best of them.
 */
export function dailyScoreId(language: string, date: string): string {
  return `daily_${language}_${date}`;
}

/**
 * Makes an arbitrary string safe as a document id.
 *
 * Firestore forbids `/` in an id and reserves `__x__`; a nonce is derived from
 * client-supplied fields and an ad network's `event_id` is entirely
 * theirs, so neither can be trusted to be path-safe. Encoding rather than
 * rejecting keeps the replay guard working for every input instead of only
 * the well-behaved ones.
 */
export function encodeDocId(raw: string): string {
  return Buffer.from(raw, 'utf8').toString('base64url').slice(0, 1500);
}
