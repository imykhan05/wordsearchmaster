/**
 * Account deletion, as Play policy requires it.
 *
 * ---------------------------------------------------------------------------
 * FIRESTORE FIRST, AUTH LAST — THE ORDER IS THE WHOLE DESIGN
 *
 * Deleting the auth record first would be a one-way door: the moment it is
 * gone the player cannot authenticate, so if any Firestore deletion then
 * failed they could never retry, and their data would sit there forever with
 * nobody able to ask for it again. Doing it last means a partial failure is
 * RESUMABLE — the player still has an account, still has a session, and can
 * call this again. The step that removes the ability to retry has to be the
 * step that runs when there is nothing left to retry.
 *
 * ---------------------------------------------------------------------------
 * WHAT GETS DELETED, AND THE ONE UNCOMFORTABLE CALL
 *
 *  * `users/{uid}` and every subcollection (scores, nonces, coinGrants).
 *  * Every `leaderboards/*&#47;entries/{uid}`, found by collection-group query.
 *  * `moderation/{uid}` and its flags.
 *  * The Firebase Auth record.
 *
 * The moderation records are the uncomfortable one. They are anti-abuse
 * evidence, and deleting them means a cheater can launder their history by
 * deleting and re-creating an account. They are also, unambiguously, data
 * about a person who has asked for their data to be deleted — and Play policy
 * does not carve out an exception for records the developer finds useful. So
 * they go. The deterrent that remains is the one that was always doing the
 * real work: deleting the account also deletes every level, every coin and
 * every streak the cheater had.
 *
 * LOCAL DATA IS NOT TOUCHED, because this function cannot reach it — the same
 * property `FirebaseAuthService.signOut` has. A player who deletes their cloud
 * account and keeps playing offline keeps their Drift database, which is the
 * correct outcome: they asked to delete their ACCOUNT, not to be wiped.
 */

import { getAuth } from 'firebase-admin/auth';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions';

import { COLLECTIONS, REGION } from './config';
import { db, userRef } from './firestore';

export interface DeleteAccountResult {
  readonly deleted: true;
  readonly uid: string;
  readonly leaderboardEntriesRemoved: number;
  readonly moderationRecordsRemoved: number;
  readonly deletedAt: string;
}

export const deleteAccount = onCall<unknown, Promise<DeleteAccountResult>>(
  { region: REGION, enforceAppCheck: true },
  async (request) => {
    const uid = request.auth?.uid;
    if (uid === undefined) {
      throw new HttpsError('unauthenticated', 'Sign in before deleting an account.');
    }
    return deleteAccountFor(uid);
  },
);

/**
 * The deletion itself, separated from the callable wrapper.
 *
 * Split so `test/integration/functions.test.ts` can drive it against a real
 * Firestore emulator without standing up the callable transport, an auth
 * token and an App Check token first. What the wrapper adds — "is there a
 * uid" — is one line, and it is the part that needs no emulator to check.
 */
export async function deleteAccountFor(uid: string): Promise<DeleteAccountResult> {
  const firestore = db();

  // 1. Leaderboard entries. A collection-group query rather than walking the
  //    board list, because the board list is open-ended (`weekly_*` and
  //    `daily_*` grow forever) and a player who is missed here stays visible
  //    on a public board after asking to be deleted — the one failure mode of
  //    this function that other people can see.
  const entries = await firestore
    .collectionGroup(COLLECTIONS.entries)
    .where('uid', '==', uid)
    .get();
  const entryWriter = firestore.bulkWriter();
  // `void`: each delete's own promise is deliberately not awaited — `close()`
  // below flushes the whole batch and is what actually reports failure.
  for (const entry of entries.docs) void entryWriter.delete(entry.ref);
  await entryWriter.close();

  // 2. Moderation records.
  const moderation = firestore.collection(COLLECTIONS.moderation).doc(uid);
  const flags = await moderation.collection(COLLECTIONS.flags).get();
  await firestore.recursiveDelete(moderation);

  // 3. The user document and everything under it.
  await firestore.recursiveDelete(userRef(uid));

  // 4. The auth record, last.
  try {
    await getAuth().deleteUser(uid);
  } catch (error) {
    // An already-absent auth record is a SUCCESS: it means a previous call got
    // this far and the retry is finishing the job. Anything else is real, and
    // must not be swallowed — the player would be told their account was
    // deleted while they can still sign in to it.
    if ((error as { code?: string }).code !== 'auth/user-not-found') {
      logger.error('auth deletion failed', { uid, error });
      throw new HttpsError('internal', 'Account deletion did not complete.');
    }
  }

  logger.info('account deleted', {
    uid,
    leaderboardEntries: entries.size,
    moderationRecords: flags.size,
  });

  return {
    deleted: true,
    uid,
    leaderboardEntriesRemoved: entries.size,
    moderationRecordsRemoved: flags.size,
    deletedAt: new Date().toISOString(),
  };
}
