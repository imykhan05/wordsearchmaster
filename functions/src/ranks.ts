/**
 * Server-computed ranks (P17).
 *
 * ---------------------------------------------------------------------------
 * WHY THIS IS A PERIODIC BATCH JOB, NOT A PER-SUBMISSION COMPUTATION
 *
 * "The current user is pinned at the bottom with their true rank even when
 * outside the top 100" needs a number that answers "how many entries beat
 * this one" — and answering that live, on every `submitScore`, means reading
 * the WHOLE board on every single submission just to place one row. That is
 * the exact "download 100k docs to count" the prompt forbids, except paid for
 * on every level completion instead of every leaderboard view.
 *
 * A periodic job pays the O(n) board scan ONCE per run and amortises it across
 * every player who opens the leaderboard in between runs. `recomputeRanksForBoard`
 * is that scan: it is the only place in this codebase that reads a leaderboard
 * beyond `.limit(100)`, and it does so on a schedule, off the request path.
 *
 * A rank is therefore never real-time — it is as fresh as the last run
 * (`RUN_INTERVAL_MINUTES` in `index.ts`). That is the right trade for a number
 * whose whole job is orienting a player among thousands of others; nobody
 * needs to see their rank move the instant a rival finishes a level.
 *
 * ---------------------------------------------------------------------------
 * WHERE THE RESULT LANDS
 *
 * Two writes per entry, both idempotent (safe to run the same rank twice):
 *
 *  1. `leaderboards/{board}/entries/{uid}.rank` — so a future top-100 read
 *     could show a rank column without the client computing index+1 itself
 *     (it does not need to today; the client's own row order already implies
 *     rank inside the top 100). Kept because the entry doc is where the
 *     PUBLIC board data already lives, and rank is exactly that kind of data.
 *  2. `users/{uid}.stats.ranks.{board}` — the one the prompt asks for by
 *     name, and the one the client actually reads for the PINNED row: a
 *     player outside the top 100 never appears in the query above, so their
 *     rank has to come from somewhere that does not require being in it.
 */

import { logger } from 'firebase-functions';

import { COLLECTIONS, LANGUAGES } from './config';
import { db, leaderboardEntryRef, userRef } from './firestore';
import { GLOBAL_BOARD, currentDailyBoardId, weeklyBoardId } from './leaderboardKeys';

export interface RankedEntry {
  readonly uid: string;
  readonly rank: number;
}

/**
 * Assigns 1-based ranks by score, descending. Ties share nothing special —
 * the order among equal scores is whatever `scores` arrives in, which is
 * itself Firestore's own `orderBy(score, desc)` order, so this stays a pure
 * re-statement of that order rather than a second sort with its own tie rule
 * to keep in sync with the query's.
 */
export function computeRanks(
  scores: readonly { uid: string; score: number }[],
): RankedEntry[] {
  return scores.map((entry, index) => ({ uid: entry.uid, rank: index + 1 }));
}

const RANK_BATCH_SIZE = 400; // under Firestore's 500-write batch cap, with room.

/**
 * Recomputes and writes ranks for every entry in [board].
 *
 * Reads the WHOLE board — the one place that is allowed, see the header —
 * ordered by score descending, the identical order the client's own top-100
 * query uses, so a rank of 1 always means "the row the client's query also
 * shows first".
 *
 * Returns the entry count, for the caller to log.
 */
export async function recomputeRanksForBoard(board: string): Promise<number> {
  const snapshot = await db()
    .collection(COLLECTIONS.leaderboards)
    .doc(board)
    .collection(COLLECTIONS.entries)
    .orderBy('score', 'desc')
    .get();

  const ranked = computeRanks(
    snapshot.docs.map((doc) => ({
      uid: doc.id,
      score:
        typeof doc.data()['score'] === 'number' ? (doc.data()['score'] as number) : 0,
    })),
  );

  for (let start = 0; start < ranked.length; start += RANK_BATCH_SIZE) {
    const batch = db().batch();
    for (const entry of ranked.slice(start, start + RANK_BATCH_SIZE)) {
      batch.set(
        leaderboardEntryRef(board, entry.uid),
        { rank: entry.rank },
        { merge: true },
      );
      batch.set(
        userRef(entry.uid),
        { stats: { ranks: { [board]: entry.rank } } },
        { merge: true },
      );
    }
    await batch.commit();
  }

  logger.info('ranks recomputed', { board, entries: ranked.length });
  return ranked.length;
}

/**
 * Clears the rank of every uid that no longer appears in [board] but still
 * carries a stale rank from a PREVIOUS run — the daily and weekly board ids
 * change every day/week, so a player's old `stats.ranks.daily_2026-08-31`
 * would otherwise sit there forever, stale, once that board stops being
 * recomputed.
 *
 * Deliberately NOT attempted for `global`/`ur`/`hi`/`en`: those boards are
 * evergreen, so a uid missing from one of them (a player who has literally
 * never scored) never had a stale rank to begin with, and there is no bounded
 * way to enumerate "every user who is not on this board" without the exact
 * full-collection scan this file exists to avoid.
 */
export function isRotatingBoard(board: string): boolean {
  return board.startsWith('weekly_') || board.startsWith('daily_');
}

/** The boards this job maintains — the six live tabs (P17). */
export function liveBoardsFor(now: Date): readonly string[] {
  return [GLOBAL_BOARD, ...LANGUAGES, weeklyBoardId(now), currentDailyBoardId(now)];
}

// ---------------------------------------------------------------------------
// The scheduled wrapper. Split from the pure functions above for the same
// reason `deleteAccountFor`/`mirrorScoreToLeaderboards` are split from their
// wrappers: the integration suite can drive `recomputeRanksForBoard` against
// a real Firestore emulator directly, without the scheduler itself — which,
// like the Firestore trigger in P14, cannot be registered inside this
// sandbox's outbound-proxy-restricted emulator run. The BODY is exercised;
// the schedule wiring is not, and `functions/README.md` says so.
// ---------------------------------------------------------------------------

import { onSchedule } from 'firebase-functions/v2/scheduler';
import { REGION } from './config';

/** Every 15 minutes — frequent enough that a rank feels current, infrequent
 * enough that six board scans a run stays a trivial cost next to the
 * thousands of individual submissions it is amortising the cost of ranking
 * for. See the file header for the full argument against computing this live. */
export const recomputeLeaderboardRanks = onSchedule(
  { schedule: 'every 15 minutes', region: REGION },
  async () => {
    const boards = liveBoardsFor(new Date());
    for (const board of boards) {
      await recomputeRanksForBoard(board);
    }
  },
);
