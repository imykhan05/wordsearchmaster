/**
 * `nameReports/{reportId}` → a blanked `displayName`, once enough distinct
 * players report the same one (SECURITY.md's AR-4 / T12).
 *
 * ---------------------------------------------------------------------------
 * WHY A REPORT COLLECTION AND NOT A CALLABLE
 *
 * Every other client-initiated write in this codebase (`submitScore`,
 * `submitAchievement`, `redeemInviteCode`) is a callable, because each of
 * those needs a computed RESPONSE. A report needs none — the reporter gets no
 * feedback beyond "thanks", by design (a report count or a "still under
 * review" reply would tell an abusive player exactly how close their name is
 * to being blanked, the identical reason `submitScore` never explains a flag).
 * So this is the one client-initiated write that goes straight to Firestore:
 * `firestore.rules` allows `create` on `nameReports/{reportId}` and nothing
 * else, and `onNameReportCreated` is the trigger that reacts to it.
 *
 * ---------------------------------------------------------------------------
 * DISTINCT REPORTERS, NEVER A RAW COUNT
 *
 * If one report could blank a name, the report button itself would be a
 * griefing tool — a single hostile player erasing anyone's name on demand.
 * `crossesReportThreshold` counts DISTINCT uids via `FieldValue.arrayUnion`,
 * which is idempotent: report the same name from the same account five times
 * and it still counts once. `LIMITS.nameReportThreshold` is deliberately
 * small (3) — the cost of a false positive here is a placeholder name, not a
 * lost level or a lost score, so this leans toward acting on a NNN-shaped
 * false-positive budget the way `SECURITY.md`'s standing assumption #3 states
 * for every other threshold in this codebase, not toward proof beyond doubt.
 *
 * ---------------------------------------------------------------------------
 * WHAT THIS DOES NOT DO (AR-4's remaining, accepted gap)
 *
 * There is still no profanity filter, and nothing stops a blanked player
 * immediately setting a new `displayName` — including the same one. Closing
 * that needs either a filter (SECURITY.md already argues a bad one is worse
 * than none: it rejects real Urdu/Hindi names far more often than it catches
 * abuse) or a moderator queue, neither of which this prompt attempts. What
 * this closes is the gap AR-4 named as "still owed": a report action exists,
 * and a moderation queue (`moderation/{uid}/flags/{autoId}`, the same
 * subcollection `submissions.ts` and `submitAchievement.ts` already write
 * evidence into) can act on a name without needing a human to be watching the
 * leaderboard at the right moment.
 *
 * ---------------------------------------------------------------------------
 * TRIGGER WIRING IS UNVERIFIED HERE — SAME GAP AS P14/P17's OTHER TRIGGERS
 *
 * `onNameReportCreated`'s registration cannot be exercised under this
 * sandbox's outbound-proxy-restricted emulator run, identically to
 * `updateLeaderboards` (P14) and `recomputeLeaderboardRanks` (P17) — see
 * `functions/README.md`. `applyNameReport`, the function body, is split out
 * for exactly that reason and is fully exercised against the real Firestore
 * emulator in `test/integration/moderation.test.ts`.
 */

import { logger } from 'firebase-functions';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';

import { COLLECTIONS, LIMITS, REGION } from './config';
import { FieldValue, db, moderationRef, userRef } from './firestore';

/**
 * Pure decision: does adding [reporterUid] to [existingReporters] cross
 * [threshold]? Split out from the transaction below so `nameReports.test.ts`
 * can walk every edge (a repeat reporter, one below threshold, exactly at
 * threshold) with no emulator — the same "extract the pure decision" shape
 * `advanceStats`/`advanceEngagementStreak` (`stats.ts`) already use.
 */
export function crossesReportThreshold(
  existingReporters: readonly string[],
  reporterUid: string,
  threshold: number = LIMITS.nameReportThreshold,
): boolean {
  if (existingReporters.includes(reporterUid)) return false;
  return existingReporters.length + 1 >= threshold;
}

function readReporters(data: FirebaseFirestore.DocumentData | undefined): string[] {
  const moderation: unknown = data?.['moderation'];
  if (typeof moderation !== 'object' || moderation === null) return [];
  const reporters = (moderation as Record<string, unknown>)['nameReporters'];
  if (!Array.isArray(reporters)) return [];
  return reporters.filter((value): value is string => typeof value === 'string');
}

export interface NameReportResult {
  readonly blanked: boolean;
}

/**
 * Records one report against [reportedUid] and blanks their `displayName`
 * the moment [LIMITS.nameReportThreshold] distinct players have reported it.
 *
 * A report against an account that has no `displayName` (already blanked, or
 * never set one) never re-blanks — there is nothing to move — but the report
 * itself is still recorded, so a moderator reviewing `moderation/` sees the
 * full history rather than a gap where the interesting reports were silently
 * dropped.
 */
export async function applyNameReport(
  reportedUid: string,
  reporterUid: string,
): Promise<NameReportResult> {
  const user = userRef(reportedUid);

  return db().runTransaction(async (tx) => {
    const snapshot = await tx.get(user);
    const data = snapshot.data();
    const existingReporters = readReporters(data);
    const currentName: unknown = data?.['displayName'];

    const willBlank =
      typeof currentName === 'string' &&
      crossesReportThreshold(existingReporters, reporterUid);

    tx.set(
      user,
      {
        moderation: { nameReporters: FieldValue.arrayUnion(reporterUid) },
        ...(willBlank ? { displayName: null } : {}),
      },
      { merge: true },
    );

    tx.set(moderationRef(reportedUid).doc(), {
      uid: reportedUid,
      kind: 'name_report',
      reporterUid,
      reportedDisplayName: typeof currentName === 'string' ? currentName : null,
      blanked: willBlank,
      flaggedAt: FieldValue.serverTimestamp(),
    });

    if (willBlank) {
      logger.warn('display name blanked after reports', { uid: reportedUid });
    }

    return { blanked: willBlank };
  });
}

export const onNameReportCreated = onDocumentCreated(
  { document: `${COLLECTIONS.nameReports}/{reportId}`, region: REGION },
  async (event) => {
    const data = event.data?.data();
    const reportedUid: unknown = data?.['reportedUid'];
    const reporterUid: unknown = data?.['reporterUid'];
    if (typeof reportedUid !== 'string' || typeof reporterUid !== 'string') {
      // `firestore.rules` already shapes every client write this trigger can
      // ever see; this only guards a doc seeded some other way (a test, a
      // future admin tool) from crashing the trigger.
      logger.warn('malformed nameReports document, ignoring', {
        id: event.params.reportId,
      });
      return;
    }
    await applyNameReport(reportedUid, reporterUid);
  },
);
