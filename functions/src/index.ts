/**
 * Word Search Master — Cloud Functions (Ch08 / P14, extended by P17's
 * leaderboards, achievements and friends).
 *
 * Every callable here sets `enforceAppCheck: true` and lives in
 * `asia-south1`, matching `AppConfig.functionsRegion`. The one HTTPS endpoint
 * (`grantRewardedReward`) cannot use App Check and explains why in its own
 * header. `recomputeLeaderboardRanks` is neither — it is a SCHEDULED function
 * with no caller at all, see `ranks.ts`.
 *
 * The contracts and error codes are documented in `functions/README.md`.
 */

import { setGlobalOptions } from 'firebase-functions/v2';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import { REGION } from './config';
import {
  MalformedSubmission,
  parseDailySubmission,
  parseLevelSubmission,
} from './validation';
import { recordSubmission, type SubmitResponse } from './submissions';

setGlobalOptions({
  region: REGION,
  // A 2GB-RAM-phone audience on 2G links (Ch01) means concurrency matters more
  // than per-instance speed; the default 1 vCPU / 256MiB is ample for a replay
  // of at most 500 integers.
  maxInstances: 20,
});

export { updateLeaderboards } from './updateLeaderboards';
export { deleteAccount } from './deleteAccount';
export { grantRewardedReward } from './grantRewardedReward';
export { recomputeLeaderboardRanks } from './ranks';
export { submitAchievement } from './submitAchievement';
export { createInviteCode, redeemInviteCode } from './friends';
export { onNameReportCreated } from './nameReports';
export { sendStreakReminders } from './streakReminders';

/**
 * `submitScore` — a finished journey level.
 *
 * Payload: the `levelComplete` outbox row from `ProgressRepository`
 * (`{language, level, stars, hintsUsed, completedAt, specVersion, events,
 * nonce}`). THE CLIENT'S SCORE IS NOT IN IT and is never read: the server
 * replays `events` through its own port of the scoring spec and writes the
 * number it computes.
 */
export const submitScore = onCall<unknown, Promise<SubmitResponse>>(
  { enforceAppCheck: true },
  async (request) => {
    const uid = requireUid(request.auth?.uid);
    const submission = parse(() => parseLevelSubmission(request.data));
    return recordSubmission(uid, submission);
  },
);

/**
 * `submitDaily` — a finished Daily Challenge.
 *
 * Same validation shape as `submitScore`, plus the one-per-day rule enforced
 * server-side (`recordSubmission` step 3).
 */
export const submitDaily = onCall<unknown, Promise<SubmitResponse>>(
  { enforceAppCheck: true },
  async (request) => {
    const uid = requireUid(request.auth?.uid);
    const submission = parse(() => parseDailySubmission(request.data));
    return recordSubmission(uid, submission);
  },
);

function requireUid(uid: string | undefined): string {
  if (uid === undefined || uid.length === 0) {
    // Guest-first (Ch02/P13) means every real player HAS a uid — an anonymous
    // one, signed in silently at bootstrap step 4. So an unauthenticated call
    // is not a player who has not signed up; it is a caller that skipped the
    // app.
    throw new HttpsError('unauthenticated', 'Sign in before submitting a score.');
  }
  return uid;
}

function parse<T>(parser: () => T): T {
  try {
    return parser();
  } catch (error) {
    if (error instanceof MalformedSubmission) {
      throw new HttpsError('invalid-argument', error.message);
    }
    throw error;
  }
}
