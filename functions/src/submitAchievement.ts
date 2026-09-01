/**
 * `submitAchievement` — the one client-claimed achievement (P17).
 *
 * Collector ("a full category") is the only achievement of the eight that the
 * server cannot derive on its own — `stats.ts`'s header explains why: it
 * needs to know which WORDS were in a level, and the word packs are not
 * ported into this bundle (SECURITY.md's AR-9). So the client, which HAS that
 * knowledge locally (`Collections.forLanguage` over its own `level_progress`
 * rows, from P11), submits a CLAIM rather than having the server derive it.
 *
 * ---------------------------------------------------------------------------
 * "BOUNDED PLAUSIBILITY", NOT VERIFICATION — AND THAT IS STATED, NOT HIDDEN
 *
 * The server checks what it CAN check without the content it does not have:
 * the category is one of the twelve real ones, the language is one of the
 * three real ones, and the account has reached a level of meaningful
 * progress in that language (`MIN_PLAUSIBLE_LEVEL`). It cannot check that the
 * claimed category was actually completed. A forged claim therefore costs a
 * cosmetic badge, not a leaderboard position or a coin — the same
 * proportionality judgement AR-9 already makes for the score itself ("closing
 * it... should be weighed against simply capping", i.e. a cheap partial
 * mitigation beats an expensive complete one when the stakes are this low).
 *
 * A claim outside those bounds is not an error — same posture as every other
 * check in this pipeline — it is logged to `moderation/` and the callable
 * still returns success, so a forged claim tells the forger nothing.
 */

import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions';

import { isLanguageCode, REGION, type LanguageCode } from './config';
import { FieldValue, db, moderationRef, userRef } from './firestore';
import { type AchievementId } from './stats';

/** The twelve real categories (P10). Mirrors the content pack's own set. */
const CATEGORIES = new Set([
  'nature',
  'animals',
  'food',
  'colors',
  'family',
  'body',
  'home',
  'school',
  'sports',
  'weather',
  'professions',
  'numbers',
]);

/**
 * The shallowest progress a plausible full-category claim could come with.
 *
 * Deliberately LOW rather than tuned tight: categories are not laid out
 * contiguously across the 300-level curve (P10 spreads them through the whole
 * curve, not in blocks), so "reached level N" is a weak proxy for "finished
 * one specific category" no matter what N is. A low bound catches the
 * `highestLevel: 0` forgery — a claim with literally no play behind it —
 * without pretending to catch a modestly dishonest one; see the file header.
 */
const MIN_PLAUSIBLE_LEVEL = 5;

export interface SubmitAchievementRequest {
  readonly category: string;
  readonly language: string;
}

export interface SubmitAchievementResponse {
  readonly recorded: boolean;
  readonly alreadyRecorded: boolean;
}

export function achievementIdFor(
  category: string,
  language: LanguageCode,
): AchievementId {
  // MUST match `CategoryBadge.achievementIdFor` on the client byte-for-byte
  // (`lib/domain/progression/collections.dart`, P11) — that is the id the
  // local `achievements` table already records a category badge under, and
  // this callable's whole job is mirroring that same claim into
  // `users/{uid}.stats.achievements` under the identical key. `collection:`
  // predates this file by six prompts; the server adopts it rather than the
  // other way around.
  return `collection:${language}:${category}` as AchievementId;
}

function readHighestLevel(
  data: FirebaseFirestore.DocumentData | undefined,
  language: LanguageCode,
): number {
  const progress: unknown = data?.['progress'];
  if (typeof progress !== 'object' || progress === null) return 0;
  const perLanguage = (progress as Record<string, unknown>)[language];
  if (typeof perLanguage !== 'object' || perLanguage === null) return 0;
  const highest = (perLanguage as Record<string, unknown>)['highestLevel'];
  return typeof highest === 'number' ? highest : 0;
}

function hasAchievement(
  data: FirebaseFirestore.DocumentData | undefined,
  id: AchievementId,
): boolean {
  const stats: unknown = data?.['stats'];
  const achievements: unknown =
    typeof stats === 'object' && stats !== null
      ? (stats as Record<string, unknown>)['achievements']
      : undefined;
  return (
    typeof achievements === 'object' && achievements !== null && id in achievements
  );
}

/**
 * The claim itself, separated from the callable wrapper — the same split
 * `deleteAccountFor`/`mirrorScoreToLeaderboards`/`creditReward` use, so the
 * integration suite can drive it against a real Firestore emulator without
 * also standing up the callable transport.
 */
export async function recordAchievementClaim(
  uid: string,
  category: string,
  language: LanguageCode,
): Promise<SubmitAchievementResponse> {
  const id = achievementIdFor(category, language);
  const user = userRef(uid);

  return db().runTransaction(async (tx) => {
    const snapshot = await tx.get(user);
    const data = snapshot.data();

    if (hasAchievement(data, id)) {
      return {
        recorded: true,
        alreadyRecorded: true,
      } satisfies SubmitAchievementResponse;
    }

    const plausible =
      CATEGORIES.has(category) &&
      readHighestLevel(data, language) >= MIN_PLAUSIBLE_LEVEL;

    if (!plausible) {
      // Never an error — see the file header. Logged, not granted.
      tx.set(moderationRef(uid).doc(), {
        uid,
        kind: 'achievement_claim',
        achievementId: id,
        category,
        language,
        highestLevel: readHighestLevel(data, language),
        flaggedAt: FieldValue.serverTimestamp(),
      });
      logger.warn('implausible achievement claim', { uid, id });
      return {
        recorded: true,
        alreadyRecorded: false,
      } satisfies SubmitAchievementResponse;
    }

    tx.set(
      user,
      {
        stats: { achievements: { [id]: { unlockedAt: FieldValue.serverTimestamp() } } },
      },
      { merge: true },
    );
    return {
      recorded: true,
      alreadyRecorded: false,
    } satisfies SubmitAchievementResponse;
  });
}

export const submitAchievement = onCall<
  SubmitAchievementRequest,
  Promise<SubmitAchievementResponse>
>({ region: REGION, enforceAppCheck: true }, async (request) => {
  const uid = request.auth?.uid;
  if (uid === undefined) {
    throw new HttpsError('unauthenticated', 'Sign in before claiming an achievement.');
  }

  const { category, language } = request.data ?? ({} as SubmitAchievementRequest);
  if (typeof category !== 'string' || typeof language !== 'string') {
    throw new HttpsError(
      'invalid-argument',
      'category and language are required strings.',
    );
  }
  if (!isLanguageCode(language)) {
    throw new HttpsError('invalid-argument', 'unknown language.');
  }

  return recordAchievementClaim(uid, category, language);
});
