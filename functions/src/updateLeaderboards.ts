/**
 * Mirrors a written score onto every board it feeds.
 *
 * ---------------------------------------------------------------------------
 * THE TRIGGER COPIES, IT NEVER ACCUMULATES — AND THAT IS THE DESIGN
 *
 * A Firestore trigger is AT-LEAST-ONCE. It can fire twice for one write, and
 * it will, eventually. So the obvious implementation — "add this score to the
 * player's total" — silently double-counts, and does so rarely enough that it
 * is discovered months later on a leaderboard nobody can explain.
 *
 * The totals are therefore accumulated in `recordSubmission`'s transaction,
 * which is exactly-once because the nonce guards it. This function only
 * READS those already-correct numbers and copies them onto the boards. Running
 * it twice writes the same bytes twice, which is not a bug.
 *
 * ---------------------------------------------------------------------------
 * WHAT AN ENTRY IS ALLOWED TO CONTAIN
 *
 * `{ uid, displayName, photoUrl, score, updatedAt }`. Nothing else — not the
 * level, not the language, not a timestamp of when they played, not an email.
 * A leaderboard is the one collection in this system that is READ BY OTHER
 * PLAYERS, so every field on it is a publication decision. `displayName` and
 * `photoUrl` are there because the player chose to display them; anything
 * beyond that would be publishing something they did not.
 */

import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions';

import { LANGUAGES, REGION, isLanguageCode } from './config';
import { FieldValue, db, leaderboardEntryRef, userRef } from './firestore';
import {
  GLOBAL_BOARD,
  dailyBoardId,
  languageBoardId,
  weeklyBoardId,
} from './leaderboardKeys';

interface PublicProfile {
  readonly displayName: string | null;
  readonly photoUrl: string | null;
}

function readProfile(data: FirebaseFirestore.DocumentData | undefined): PublicProfile {
  const displayName: unknown = data?.['displayName'];
  const photoUrl: unknown = data?.['photoUrl'];
  return {
    displayName:
      typeof displayName === 'string' && displayName.length > 0 ? displayName : null,
    photoUrl: typeof photoUrl === 'string' && photoUrl.length > 0 ? photoUrl : null,
  };
}

function readNumber(source: unknown, key: string): number {
  if (typeof source !== 'object' || source === null) return 0;
  const value = (source as Record<string, unknown>)[key];
  return typeof value === 'number' && Number.isFinite(value) ? value : 0;
}

/** The five fields an entry may hold, and no others. */
function entryFor(uid: string, profile: PublicProfile, score: number) {
  return {
    uid,
    displayName: profile.displayName,
    photoUrl: profile.photoUrl,
    score,
    updatedAt: FieldValue.serverTimestamp(),
  };
}

export const updateLeaderboards = onDocumentWritten(
  { document: 'users/{uid}/scores/{scoreId}', region: REGION },
  async (event) => {
    const after = event.data?.after;
    if (after === undefined || !after.exists) return; // A delete: `deleteAccount` owns entry removal.

    const score = after.data();
    if (score === undefined) return;

    const uid = event.params['uid'];
    if (typeof uid !== 'string' || uid.length === 0) return;

    await mirrorScoreToLeaderboards(uid, score);
    logger.debug('leaderboards updated', { uid, scoreId: event.params['scoreId'] });
  },
);

/**
 * The mirror itself, separated from the trigger wrapper.
 *
 * Split for the same reason `deleteAccountFor` is: the integration suite can
 * then drive it against a real Firestore emulator without also standing up the
 * functions runtime and waiting for an eventing round trip. It also makes the
 * at-least-once argument in this file's header checkable — the test calls it
 * twice and asserts the boards do not move.
 */
export async function mirrorScoreToLeaderboards(
  uid: string,
  score: FirebaseFirestore.DocumentData,
): Promise<void> {
  // EXCLUDED FROM PUBLIC LEADERBOARDS. The document still exists, the
  // moderation record still exists, and the player is still told nothing.
  if (score['suspicious'] === true) return;

  const userSnap = await userRef(uid).get();
  const userData = userSnap.data();
  const profile = readProfile(userData);
  const totals: unknown = userData?.['totals'];
  const weekly: unknown = userData?.['weekly'];

  const lang: unknown = score['lang'];
  const completedAt: unknown = score['completedAt'];

  const writes: Promise<unknown>[] = [];

  // Cumulative boards: the sum of the player's best score on every puzzle,
  // globally and per script.
  writes.push(
    leaderboardEntryRef(GLOBAL_BOARD, uid).set(
      entryFor(uid, profile, readNumber(totals, 'global')),
    ),
  );
  if (isLanguageCode(lang)) {
    writes.push(
      leaderboardEntryRef(languageBoardId(lang), uid).set(
        entryFor(uid, profile, readNumber(totals, lang)),
      ),
    );
  }

  // Weekly: points EARNED in that ISO week, keyed off the completion the
  // player claims rather than off now — a queued row that drains on Monday
  // belongs to the week it was played in, not to the week it synced in.
  if (typeof completedAt === 'number' && Number.isFinite(completedAt)) {
    const board = weeklyBoardId(new Date(completedAt));
    writes.push(
      leaderboardEntryRef(board, uid).set(
        entryFor(uid, profile, readNumber(weekly, board)),
      ),
    );
  }

  if (score['kind'] === 'daily' && typeof score['date'] === 'string') {
    writes.push(writeDailyEntry(dailyBoardId(score['date']), uid, profile, score));
  }

  await Promise.all(writes);
}

/**
 * The daily board takes the BEST of the player's dailies for that date.
 *
 * A date has three daily puzzles — one per language — and one board
 * (`dailyBoardId`'s own header explains why that is defensible). "One entry
 * per uid per date" therefore has to decide which of up to three results the
 * entry holds, and taking the best is both the kindest reading and the only
 * one that is order-independent: whichever language syncs last, the entry
 * ends up the same. A plain `set` would instead publish whichever result
 * happened to arrive last, which is not a rule anyone could explain to a
 * player.
 *
 * A transaction rather than a read-then-write, because this trigger can run
 * concurrently with itself for two languages of the same date.
 */
async function writeDailyEntry(
  board: string,
  uid: string,
  profile: PublicProfile,
  score: FirebaseFirestore.DocumentData,
): Promise<void> {
  const value = typeof score['score'] === 'number' ? score['score'] : 0;
  const ref = leaderboardEntryRef(board, uid);

  await db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const existing = snap.exists ? readNumber(snap.data(), 'score') : null;
    if (existing !== null && existing >= value) {
      // Still refresh the display fields: a player who renamed themselves
      // should not stay on the board under the old name.
      tx.set(ref, entryFor(uid, profile, existing));
      return;
    }
    tx.set(ref, entryFor(uid, profile, value));
  });
}

/** Board ids this function maintains, in the order the README documents them. */
export const MAINTAINED_BOARDS = [
  GLOBAL_BOARD,
  ...LANGUAGES,
  'weekly_{isoWeek}',
  'daily_{date}',
] as const;
