/**
 * The shared body of `submitScore` and `submitDaily`.
 *
 * ---------------------------------------------------------------------------
 * ONE TRANSACTION, AND WHY THE NONCE CHECK LIVES INSIDE IT
 *
 * Everything a submission touches — the replay guard, the score document, the
 * account's totals, its progression high-water mark, its rate window and its
 * timing accumulator — is read and written in a SINGLE Firestore transaction.
 * Split it up and two copies of the same outbox row racing (which is the
 * normal case, not the exotic one: the queue retries, and a retry can overlap
 * a slow first attempt) would both find the nonce absent and both add the
 * score to the totals. The client cannot make that not happen; only the
 * transaction can.
 *
 * ---------------------------------------------------------------------------
 * A REPLAYED NONCE IS A SUCCESS, NOT AN ERROR
 *
 * The obvious reading of "nonce replay check" is to refuse the second
 * submission. That would be wrong here, and the reason is the outbox: a row
 * whose response was lost to a dropped connection is retried, and it is the
 * SAME row with the same nonce. Refusing it would strand a real, completed
 * level in the queue forever. So a repeat returns the stored result verbatim
 * and writes nothing — idempotent, which is what an at-least-once delivery
 * pipeline actually needs. It also happens to tell a replay attacker nothing,
 * which is the second reason not to answer with an error.
 */

import { HttpsError } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions';

import { FLAGS, LIMITS, type LanguageCode } from './config';
import {
  FieldValue,
  dailyScoreId,
  db,
  levelScoreId,
  moderationRef,
  nonceRef,
  scoreRef,
  userRef,
} from './firestore';
import { weeklyBoardId } from './leaderboardKeys';
import { DAILY_SHAPE, isKnownLevel, levelShape, type LevelShape } from './levels';
import { SPEC_VERSION } from './scoring';
import {
  EMPTY_TIMING,
  evaluateSubmission,
  nextRateWindow,
  type EvaluatedSubmission,
  type RateWindow,
  type Submission,
  type TimingContext,
} from './validation';

/**
 * What the client is told.
 *
 * DELIBERATELY THE SAME SHAPE FOR AN ACCEPTED AND A FLAGGED SUBMISSION. There
 * is no `suspicious` field, no flag list and no hint that anything was
 * checked: P14's rule is that a suspected cheater never learns they were
 * caught, and a response that differed even in its key set would leak exactly
 * that. The honest player has no use for the information either — their score
 * is their score.
 */
export interface SubmitResponse {
  readonly score: number;
  readonly stars: number;
  readonly bestScore: number;
  readonly bestStars: number;
  readonly specVersion: number;
  /**
   * True when this call did not create a new record: a replayed nonce, or a
   * daily whose day was already spent. An honest client uses it to retire the
   * outbox row; it says nothing about whether anything was flagged.
   */
  readonly alreadyRecorded: boolean;
}

interface StoredScore {
  score: number;
  stars: number;
  suspicious: boolean;
}

function readStoredScore(
  data: FirebaseFirestore.DocumentData | undefined,
): StoredScore | null {
  if (data === undefined) return null;
  return {
    score: typeof data['score'] === 'number' ? data['score'] : 0,
    stars: typeof data['stars'] === 'number' ? data['stars'] : 0,
    suspicious: data['suspicious'] === true,
  };
}

function readTiming(data: FirebaseFirestore.DocumentData | undefined): TimingContext {
  const raw: unknown = data?.['timing'];
  if (typeof raw !== 'object' || raw === null) return EMPTY_TIMING;
  const record = raw as Record<string, unknown>;
  const num = (key: string): number | null => {
    const value = record[key];
    return typeof value === 'number' ? value : null;
  };
  return {
    submissionCount: num('submissionCount') ?? 0,
    earliestCompletedAt: num('earliestCompletedAt'),
    latestCompletedAt: num('latestCompletedAt'),
    minRequiredMillis: num('minRequiredMillis') ?? 0,
  };
}

function readRateWindow(
  data: FirebaseFirestore.DocumentData | undefined,
): RateWindow | null {
  const raw: unknown = data?.['rate'];
  if (typeof raw !== 'object' || raw === null) return null;
  const record = raw as Record<string, unknown>;
  if (
    typeof record['windowStartMillis'] !== 'number' ||
    typeof record['count'] !== 'number'
  ) {
    return null;
  }
  return {
    windowStartMillis: record['windowStartMillis'],
    count: record['count'],
  };
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

function scoreIdFor(submission: Submission): string {
  return submission.kind === 'level'
    ? levelScoreId(submission.language, submission.level)
    : dailyScoreId(submission.language, submission.date);
}

function shapeFor(submission: Submission): LevelShape | null {
  if (submission.kind === 'daily') return DAILY_SHAPE;
  return isKnownLevel(submission.level) ? levelShape(submission.level) : null;
}

/**
 * Runs one submission end to end and returns what the client is told.
 *
 * Throws only `resource-exhausted` (the rate limit). Every cheat signal
 * resolves to a flagged write and a normal-looking success — see the file
 * header and `validation.ts`.
 */
export async function recordSubmission(
  uid: string,
  submission: Submission,
): Promise<SubmitResponse> {
  const scoreId = scoreIdFor(submission);
  const serverNowMillis = Date.now();

  return db().runTransaction(async (tx) => {
    const nonce = nonceRef(uid, submission.nonce);
    const user = userRef(uid);
    const score = scoreRef(uid, scoreId);

    // One round trip for all three, in the order requested. Indexed rather
    // than destructured because `noUncheckedIndexedAccess` (rightly) widens
    // array access to `| undefined`, and `getAll` guarantees one snapshot per
    // ref.
    const snapshots = await tx.getAll(nonce, user, score);
    const nonceSnap = snapshots[0]!;
    const userSnap = snapshots[1]!;
    const scoreSnap = snapshots[2]!;

    // ---- 1. Nonce replay -------------------------------------------------
    if (nonceSnap.exists) {
      const stored = readStoredScore(scoreSnap.data());
      return {
        score:
          (nonceSnap.data()?.['score'] as number | undefined) ?? stored?.score ?? 0,
        stars:
          (nonceSnap.data()?.['stars'] as number | undefined) ?? stored?.stars ?? 0,
        bestScore: stored?.score ?? 0,
        bestStars: stored?.stars ?? 0,
        specVersion: SPEC_VERSION,
        alreadyRecorded: true,
      } satisfies SubmitResponse;
    }

    const userData = userSnap.data();

    // ---- 2. Rate limit ---------------------------------------------------
    //
    // The ONE check that answers with an error. It is not a cheat signal — an
    // honest client wedged in a retry loop hits it too, and telling that
    // client to back off is the correct, useful answer. It is also the only
    // check whose whole job is protecting the backend rather than the
    // leaderboard.
    const rate = nextRateWindow(readRateWindow(userData), serverNowMillis);
    if (!rate.allowed) {
      throw new HttpsError('resource-exhausted', 'Too many submissions. Retry later.');
    }

    // ---- 3. Daily: one entry per uid per (language, date) -----------------
    //
    // Enforced HERE, on the server, rather than by trusting the client's own
    // `daily_results` row — which is the right check for the client (it makes
    // the Daily playable with the radio off) but is a local row on a device
    // the player controls. A second, differently-nonced attempt is answered
    // with the FIRST result: "one attempt per day" with a best-of write would
    // let a player grind the daily leaderboard, which is the whole reason
    // `DailyRepository` records the first attempt and not the best.
    const existing = readStoredScore(scoreSnap.data());
    if (submission.kind === 'daily' && existing !== null) {
      return {
        score: existing.score,
        stars: existing.stars,
        bestScore: existing.score,
        bestStars: existing.stars,
        specVersion: SPEC_VERSION,
        alreadyRecorded: true,
      } satisfies SubmitResponse;
    }

    // ---- 4. Replay the events and collect every signal --------------------
    const evaluated = evaluateSubmission(submission, shapeFor(submission), {
      serverNowMillis,
      highestLevel: readHighestLevel(userData, submission.language),
      timing: readTiming(userData),
    });

    // ---- 5. Write ---------------------------------------------------------
    const previousClean = existing !== null && !existing.suspicious ? existing : null;

    const userUpdate: Record<string, unknown> = {
      rate: rate.window,
      timing: evaluated.timing,
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (userData === undefined) userUpdate['createdAt'] = FieldValue.serverTimestamp();

    if (evaluated.suspicious) {
      writeSuspicious(tx, uid, scoreId, submission, evaluated, previousClean !== null);
      userUpdate['suspiciousCount'] = FieldValue.increment(1);
    } else {
      const bestScore = Math.max(evaluated.score, previousClean?.score ?? 0);
      const bestStars = Math.max(evaluated.stars, previousClean?.stars ?? 0);
      // Totals move by the IMPROVEMENT, never by the raw score, so replaying a
      // level for fun cannot pump a leaderboard. It also makes the trigger
      // that mirrors these numbers a pure copy rather than an increment, and
      // therefore safe to run twice — which matters, because a Firestore
      // trigger is at-least-once.
      const delta = Math.max(0, evaluated.score - (previousClean?.score ?? 0));

      tx.set(
        score,
        {
          kind: submission.kind,
          lang: submission.language,
          ...(submission.kind === 'level'
            ? { level: submission.level }
            : { date: submission.date }),
          score: bestScore,
          stars: bestStars,
          hintsUsed: evaluated.hintsUsed,
          wordsFound: evaluated.wordsFound,
          maxCombo: evaluated.maxCombo,
          lastScore: evaluated.score,
          specVersion: submission.specVersion,
          completedAt: submission.completedAt,
          submittedAt: FieldValue.serverTimestamp(),
          suspicious: false,
          flags: [],
          nonce: submission.nonce,
        },
        { merge: true },
      );

      if (delta > 0) {
        userUpdate['totals'] = {
          global: FieldValue.increment(delta),
          [submission.language]: FieldValue.increment(delta),
        };
        userUpdate['weekly'] = {
          [weeklyBoardId(new Date(submission.completedAt))]:
            FieldValue.increment(delta),
        };
      }
      if (submission.kind === 'level') {
        userUpdate['progress'] = {
          [submission.language]: {
            highestLevel: Math.max(
              submission.level,
              readHighestLevel(userData, submission.language),
            ),
          },
        };
      }
    }

    tx.set(user, userUpdate, { merge: true });
    tx.set(nonce, {
      scoreId,
      score: evaluated.score,
      stars: evaluated.stars,
      createdAt: FieldValue.serverTimestamp(),
      // Lets a retention job expire replay guards without walking every score.
      expiresAt: new Date(serverNowMillis + 90 * 86400000),
    });

    const bestScore = evaluated.suspicious
      ? (previousClean?.score ?? evaluated.score)
      : Math.max(evaluated.score, previousClean?.score ?? 0);
    const bestStars = evaluated.suspicious
      ? (previousClean?.stars ?? evaluated.stars)
      : Math.max(evaluated.stars, previousClean?.stars ?? 0);

    return {
      score: evaluated.score,
      stars: evaluated.stars,
      bestScore,
      bestStars,
      specVersion: SPEC_VERSION,
      alreadyRecorded: false,
    } satisfies SubmitResponse;
  });
}

/**
 * The suspicious path: record it, keep it off every board, tell nobody.
 *
 * The score document is only CREATED by a flagged submission — if a clean
 * result is already stored for this level, the flagged one must not overwrite
 * it. Otherwise a single tampered submission could quietly destroy the honest
 * best score a player earned, which would punish exactly the wrong person on
 * a false positive. Either way the full payload lands in `moderation/`, which
 * is the record that actually matters: it holds what was submitted, what the
 * server computed instead, and which checks tripped.
 */
function writeSuspicious(
  tx: FirebaseFirestore.Transaction,
  uid: string,
  scoreId: string,
  submission: Submission,
  evaluated: EvaluatedSubmission,
  hasCleanScore: boolean,
): void {
  if (!hasCleanScore) {
    tx.set(
      scoreRef(uid, scoreId),
      {
        kind: submission.kind,
        lang: submission.language,
        ...(submission.kind === 'level'
          ? { level: submission.level }
          : { date: submission.date }),
        score: evaluated.score,
        stars: evaluated.stars,
        hintsUsed: evaluated.hintsUsed,
        wordsFound: evaluated.wordsFound,
        maxCombo: evaluated.maxCombo,
        specVersion: submission.specVersion,
        completedAt: submission.completedAt,
        submittedAt: FieldValue.serverTimestamp(),
        suspicious: true,
        flags: evaluated.flags,
        nonce: submission.nonce,
      },
      { merge: true },
    );
  } else {
    tx.set(
      scoreRef(uid, scoreId),
      {
        flaggedSubmissions: FieldValue.increment(1),
        lastFlaggedAt: FieldValue.serverTimestamp(),
        lastFlags: evaluated.flags,
      },
      { merge: true },
    );
  }

  tx.set(moderationRef(uid).doc(), {
    uid,
    scoreId,
    kind: submission.kind,
    lang: submission.language,
    ...(submission.kind === 'level'
      ? { level: submission.level }
      : { date: submission.date }),
    flags: evaluated.flags,
    serverScore: evaluated.score,
    serverStars: evaluated.stars,
    clientStars: submission.clientStars,
    clientHintsUsed: submission.clientHintsUsed,
    specVersion: submission.specVersion,
    completedAt: submission.completedAt,
    // The events themselves, so a moderator can replay the submission by hand
    // rather than trusting this function's summary of it.
    events: submission.events,
    nonce: submission.nonce,
    flaggedAt: FieldValue.serverTimestamp(),
  });

  logger.warn('submission flagged', {
    uid,
    scoreId,
    flags: evaluated.flags,
    serverScore: evaluated.score,
  });
}

/** Re-exported so `index.ts` reads as a list of contracts, not of imports. */
export { FLAGS, LIMITS };
