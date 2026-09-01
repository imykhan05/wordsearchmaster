/**
 * The friend graph: invite codes and their redemption (P17).
 *
 * ---------------------------------------------------------------------------
 * BUILT BEFORE ANY FRIEND NOTIFICATION EXISTS, ON PURPOSE (Ch audit #11)
 *
 * There is no "so-and-so wants to be your friend" push, badge, or inbox
 * anywhere in this file. That is not an oversight to fix later — it is the
 * ordering the audit item names explicitly: the graph has to exist, be
 * populated, and be something P20 can query BEFORE a notification about it is
 * safe to send, because a notification with nothing behind it is a promise
 * this build cannot keep. P20 is the prompt that gets to turn this on.
 *
 * ---------------------------------------------------------------------------
 * WHY A CODE REDEMPTION IS AN IMMEDIATE, MUTUAL FRIENDSHIP — NOT A REQUEST
 *
 * A request/accept flow needs a way to tell the other player a request is
 * waiting, and the audit item above says that channel does not exist yet. A
 * pending request nobody is ever told about is a request that sits forever,
 * which is worse than no request flow at all. So redemption is immediate and
 * symmetric: possessing the code is the consent, because the code only
 * travels through a channel the OWNER chose (the native share sheet — never a
 * contact-book scrape, see `docs/friends.md`... — no, see the client's
 * `FriendsService` header), so redeeming it already required the owner to
 * have handed it to this specific person on purpose.
 *
 * ---------------------------------------------------------------------------
 * WHY A CODE IS ONE STABLE STRING PER PLAYER, NOT SINGLE-USE
 *
 * A single-use code would need regenerating after every invite, which turns
 * "share your code" into "generate, share, immediately invalidate, repeat" —
 * annoying for a player who wants to invite several people from one group
 * chat message. A stable code costs nothing extra to defend: redemption is
 * rate-limited per REDEEMER, not per code, so a leaked code cannot be
 * hammered any faster than any other player's redemption attempts.
 */

import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions';
import { randomBytes } from 'node:crypto';

import { LIMITS, REGION } from './config';
import { FieldValue, db, userRef } from './firestore';
import { nextRateWindow, type RateWindow } from './validation';

// Crockford-style: no 0/O, 1/I/L, or vowel run that spells something a
// support channel would rather not read out loud. Every character is
// unambiguous when a player reads it off one screen and types it into
// another, which a share code has to survive.
const CODE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

export function generateCode(random: () => number = Math.random): string {
  let code = '';
  for (let i = 0; i < LIMITS.inviteCodeLength; i++) {
    code += CODE_ALPHABET[Math.floor(random() * CODE_ALPHABET.length)];
  }
  return code;
}

/** A cryptographically random `[0, 1)` source, for real code generation. */
function secureRandom(): number {
  // 4 bytes gives more than enough resolution for a 32-symbol alphabet pick.
  return randomBytes(4).readUInt32BE(0) / 0x1_0000_0000;
}

/** Upper-cases and strips whitespace — what a player pastes rarely matches exactly. */
export function normalizeCode(raw: string): string {
  return raw.trim().toUpperCase();
}

function inviteCodeRef(code: string) {
  return db().collection('inviteCodes').doc(code);
}

export interface InviteCodeResult {
  readonly code: string;
}

/**
 * Returns the caller's existing code, or mints and reserves a new one.
 *
 * The reservation is a TRANSACTION per attempt: read the candidate code's
 * document, and only claim it if empty. `inviteCodeMaxAttempts` retries absorb
 * the vanishingly rare collision (2^-40 keyspace) without the caller ever
 * seeing it.
 */
export async function getOrCreateInviteCode(uid: string): Promise<InviteCodeResult> {
  const existing = await userRef(uid).get();
  const stored: unknown = existing.data()?.['inviteCode'];
  if (typeof stored === 'string' && stored.length > 0) {
    return { code: stored };
  }

  for (let attempt = 0; attempt < LIMITS.inviteCodeMaxAttempts; attempt++) {
    const candidate = generateCode(secureRandom);
    const claimed = await db().runTransaction(async (tx) => {
      const codeSnap = await tx.get(inviteCodeRef(candidate));
      if (codeSnap.exists) return false;
      tx.set(inviteCodeRef(candidate), {
        uid,
        createdAt: FieldValue.serverTimestamp(),
      });
      tx.set(userRef(uid), { inviteCode: candidate }, { merge: true });
      return true;
    });
    if (claimed) return { code: candidate };
  }

  // Practically unreachable at this keyspace, but a background job must never
  // throw an exception nobody can act on — see `LIMITS.inviteCodeMaxAttempts`'s
  // own doc for the odds.
  throw new HttpsError(
    'resource-exhausted',
    'Could not allocate an invite code. Try again.',
  );
}

export type RedeemOutcome =
  | { readonly status: 'friended'; readonly friendUid: string }
  | { readonly status: 'alreadyFriends'; readonly friendUid: string }
  | { readonly status: 'notFound' }
  | { readonly status: 'ownCode' }
  | { readonly status: 'friendLimitReached' };

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

/**
 * Redeems [code] on behalf of [uid], creating a MUTUAL friendship.
 *
 * One transaction: looks up the code's owner, refuses a self-redemption and a
 * full friend list on either side, then writes BOTH sides of
 * `users/*\/friends/*` so neither account can ever hold a one-directional
 * "friendship" the other side does not see.
 */
export async function redeemCode(uid: string, rawCode: string): Promise<RedeemOutcome> {
  const code = normalizeCode(rawCode);

  return db().runTransaction(async (tx) => {
    const codeSnap = await tx.get(inviteCodeRef(code));
    if (!codeSnap.exists) return { status: 'notFound' };

    const friendUid: unknown = codeSnap.data()?.['uid'];
    if (typeof friendUid !== 'string' || friendUid.length === 0)
      return { status: 'notFound' };
    if (friendUid === uid) return { status: 'ownCode' };

    const existingFriendship = await tx.get(
      userRef(uid).collection('friends').doc(friendUid),
    );
    if (existingFriendship.exists) return { status: 'alreadyFriends', friendUid };

    const [selfSnap, friendSnap, selfFriendCount, friendFriendCount] =
      await Promise.all([
        tx.get(userRef(uid)),
        tx.get(userRef(friendUid)),
        tx.get(userRef(uid).collection('friends').count()),
        tx.get(userRef(friendUid).collection('friends').count()),
      ]);

    if (
      selfFriendCount.data().count >= LIMITS.maxFriends ||
      friendFriendCount.data().count >= LIMITS.maxFriends
    ) {
      return { status: 'friendLimitReached' };
    }

    const now = FieldValue.serverTimestamp();
    const selfProfile = readProfile(selfSnap.data());
    const friendProfile = readProfile(friendSnap.data());

    tx.set(userRef(uid).collection('friends').doc(friendUid), {
      uid: friendUid,
      displayName: friendProfile.displayName,
      photoUrl: friendProfile.photoUrl,
      since: now,
    });
    tx.set(userRef(friendUid).collection('friends').doc(uid), {
      uid,
      displayName: selfProfile.displayName,
      photoUrl: selfProfile.photoUrl,
      since: now,
    });

    logger.info('friendship created', { uid, friendUid });
    return { status: 'friended', friendUid };
  });
}

function readRateWindow(
  data: FirebaseFirestore.DocumentData | undefined,
): RateWindow | null {
  const raw: unknown = data?.['friendRedeemRate'];
  if (typeof raw !== 'object' || raw === null) return null;
  const record = raw as Record<string, unknown>;
  if (
    typeof record['windowStartMillis'] !== 'number' ||
    typeof record['count'] !== 'number'
  ) {
    return null;
  }
  return { windowStartMillis: record['windowStartMillis'], count: record['count'] };
}

/**
 * `redeemCode` plus its OWN, tighter rate limit — separate from the
 * submission rate window in `submissions.ts`, so redeeming friend codes can
 * never eat into the budget an offline backlog drain needs, and vice versa.
 */
export async function redeemCodeRateLimited(
  uid: string,
  rawCode: string,
): Promise<RedeemOutcome> {
  const now = Date.now();
  const user = userRef(uid);
  const userSnap = await user.get();
  const rate = nextRateWindow(readRateWindow(userSnap.data()), now);
  await user.set({ friendRedeemRate: rate.window }, { merge: true });

  if (!rate.allowed) {
    throw new HttpsError('resource-exhausted', 'Too many attempts. Try again later.');
  }

  return redeemCode(uid, rawCode);
}

export const createInviteCode = onCall<unknown, Promise<InviteCodeResult>>(
  { region: REGION, enforceAppCheck: true },
  async (request) => {
    const uid = request.auth?.uid;
    if (uid === undefined) {
      throw new HttpsError(
        'unauthenticated',
        'Sign in before creating an invite code.',
      );
    }
    return getOrCreateInviteCode(uid);
  },
);

export interface RedeemInviteCodeRequest {
  readonly code: string;
}

export const redeemInviteCode = onCall<RedeemInviteCodeRequest, Promise<RedeemOutcome>>(
  { region: REGION, enforceAppCheck: true },
  async (request) => {
    const uid = request.auth?.uid;
    if (uid === undefined) {
      throw new HttpsError('unauthenticated', 'Sign in before redeeming a code.');
    }
    const code = request.data?.code;
    if (typeof code !== 'string' || code.length === 0 || code.length > 32) {
      throw new HttpsError('invalid-argument', 'code must be a short string.');
    }
    return redeemCodeRateLimited(uid, code);
  },
);
