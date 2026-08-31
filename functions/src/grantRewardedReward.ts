/**
 * The AppLovin MAX server-side rewarded callback.
 *
 * ---------------------------------------------------------------------------
 * WHY THIS IS THE ONLY FUNCTION WITHOUT App Check
 *
 * Every callable in this project sets `enforceAppCheck: true`, because every
 * callable is called by the game. This one is not: it is called by AppLovin's
 * servers, which have no app instance and can never hold an App Check token.
 * So the attestation has to come from somewhere else, and that somewhere is a
 * SHARED SECRET the two sides agree on out of band — configured in the MAX
 * dashboard next to the callback URL, stored here as a Secret Manager secret,
 * never in this repository.
 *
 * That substitution is the entire reason the endpoint exists. The client could
 * perfectly well tell the server "I watched an ad, give me coins" — and then a
 * modified client would say it constantly. P14's rule is literal: THE CLIENT
 * MUST NEVER BE ABLE TO GRANT ITSELF A REWARD, so the only path that mints
 * coins is one the client cannot invoke, cannot sign, and cannot observe.
 *
 * ---------------------------------------------------------------------------
 * THREE DEFENCES, AND EACH COVERS THE OTHERS' GAP
 *
 *  1. HMAC-SHA256 over the canonical parameter string, compared with
 *     `timingSafeEqual`. Stops a forged call. A plain `===` on a hex digest
 *     leaks the correct prefix through response timing, which is exactly the
 *     comparison an attacker can afford to run a million times.
 *  2. A freshness window on the callback's own timestamp. A signature is valid
 *     forever; a captured URL replayed next month must not still pay out.
 *  3. Idempotency on `event_id`. AppLovin retries on a non-2xx, and a retry of
 *     a callback that already landed must not pay twice. This one is not
 *     hypothetical — retries are the DOCUMENTED behaviour, not an edge case.
 *
 * ---------------------------------------------------------------------------
 * THE SIGNATURE SCHEME IS A P18 HANDSHAKE, AND IT IS FLAGGED AS ONE
 *
 * The canonical string below (`user_id|event_id|amount|ts`) is this side of a
 * contract whose other side is typed into the MAX dashboard. Ad networks
 * differ on what they sign and in what order, and the dashboard is not
 * reachable from here — so P18, which wires the ad units, must confirm the
 * exact scheme and change [canonicalString] to match if it differs. Everything
 * around it (freshness, idempotency, the coin ceiling, the write path) is
 * independent of that choice.
 */

import { createHmac, timingSafeEqual } from 'node:crypto';

import { onRequest } from 'firebase-functions/v2/https';
import { defineSecret } from 'firebase-functions/params';
import { logger } from 'firebase-functions';

import { LIMITS, REGION } from './config';
import { FieldValue, coinGrantRef, db, rewardCallbackRef, userRef } from './firestore';

/**
 * Set with `firebase functions:secrets:set MAX_REWARD_SECRET`, per flavor
 * project. Never committed — `docs/firebase-setup.md` is the runbook.
 */
export const MAX_REWARD_SECRET = defineSecret('MAX_REWARD_SECRET');

export interface RewardCallback {
  readonly userId: string;
  readonly eventId: string;
  readonly amount: number;
  readonly timestampMillis: number;
  readonly signature: string;
}

/** The bytes that are signed. See the header: P18 confirms this against MAX. */
export function canonicalString(callback: Omit<RewardCallback, 'signature'>): string {
  return [
    callback.userId,
    callback.eventId,
    String(callback.amount),
    String(callback.timestampMillis),
  ].join('|');
}

export function sign(
  callback: Omit<RewardCallback, 'signature'>,
  secret: string,
): string {
  return createHmac('sha256', secret).update(canonicalString(callback)).digest('hex');
}

/** Constant-time compare of two hex digests. Length mismatch fails first. */
export function signatureMatches(expected: string, provided: string): boolean {
  const a = Buffer.from(expected, 'utf8');
  const b = Buffer.from(provided, 'utf8');
  if (a.length !== b.length) return false;
  return timingSafeEqual(a, b);
}

export type RewardRejection = 'malformed' | 'bad_signature' | 'stale' | 'unknown_user';

export function parseCallback(query: Record<string, unknown>): RewardCallback | null {
  const str = (key: string): string | null => {
    const value = query[key];
    return typeof value === 'string' && value.length > 0 && value.length <= 256
      ? value
      : null;
  };

  const userId = str('user_id');
  const eventId = str('event_id');
  const signature = str('signature');
  const rawAmount = str('amount');
  const rawTimestamp = str('ts');
  if (
    userId === null ||
    eventId === null ||
    signature === null ||
    rawAmount === null ||
    rawTimestamp === null
  ) {
    return null;
  }

  const amount = Number(rawAmount);
  const timestampMillis = Number(rawTimestamp);
  if (
    !Number.isInteger(amount) ||
    amount <= 0 ||
    !Number.isInteger(timestampMillis) ||
    timestampMillis <= 0
  ) {
    return null;
  }

  return { userId, eventId, amount, timestampMillis, signature };
}

export function isFresh(timestampMillis: number, nowMillis: number): boolean {
  return Math.abs(nowMillis - timestampMillis) <= LIMITS.rewardCallbackMaxAgeMillis;
}

export const grantRewardedReward = onRequest(
  { region: REGION, secrets: [MAX_REWARD_SECRET], cors: false },
  async (request, response) => {
    const callback = parseCallback(request.query);
    if (callback === null) {
      // An ad network is not a player, so an honest error IS the right answer
      // here — the "never tell a cheater" rule protects the game client, and
      // the only caller that reaches this line is a misconfigured callback URL
      // whose owner needs to know it is misconfigured.
      response.status(400).send('malformed');
      return;
    }

    const expected = sign(callback, MAX_REWARD_SECRET.value());
    if (!signatureMatches(expected, callback.signature)) {
      logger.warn('rewarded callback signature rejected', {
        eventId: callback.eventId,
      });
      response.status(403).send('bad_signature');
      return;
    }

    const now = Date.now();
    if (!isFresh(callback.timestampMillis, now)) {
      logger.warn('rewarded callback stale', { eventId: callback.eventId });
      response.status(403).send('stale');
      return;
    }

    const outcome = await creditReward(callback);
    if (outcome === 'unknown_user') {
      logger.warn('rewarded callback for unknown user', { eventId: callback.eventId });
      response.status(404).send('unknown_user');
      return;
    }

    logger.info('rewarded callback processed', {
      eventId: callback.eventId,
      outcome,
    });
    response.status(200).send('OK');
  },
);

export type RewardOutcome = 'granted' | 'duplicate' | 'unknown_user';

/**
 * The credit itself, separated from the HTTP wrapper so the integration suite
 * can drive it against a real Firestore emulator.
 *
 * The signature and freshness checks deliberately stay OUTSIDE it: they are
 * pure, they are unit-tested without any emulator at all, and keeping them in
 * the wrapper means this function can never be reached by an unverified
 * callback even by accident.
 */
export async function creditReward(callback: RewardCallback): Promise<RewardOutcome> {
  const coins = Math.min(callback.amount, LIMITS.maxRewardCoins);
  const user = userRef(callback.userId);

  return db().runTransaction(async (tx) => {
    const snapshots = await tx.getAll(rewardCallbackRef(callback.eventId), user);
    const callbackSnap = snapshots[0]!;
    const userSnap = snapshots[1]!;
    // Idempotency: a retried callback is answered 200 so AppLovin stops
    // retrying, but pays nothing.
    if (callbackSnap.exists) return 'duplicate' as const;
    if (!userSnap.exists) return 'unknown_user' as const;

    tx.set(rewardCallbackRef(callback.eventId), {
      uid: callback.userId,
      coins,
      requestedAmount: callback.amount,
      timestampMillis: callback.timestampMillis,
      receivedAt: FieldValue.serverTimestamp(),
    });
    // The grant the client syncs down. Coins are never minted by the client
    // (CLAUDE.md: `coins_ledger` is append-only and locally signed), so a
    // server-granted reward has to arrive as its own record for the device to
    // append — it cannot be a balance the server sets.
    tx.set(coinGrantRef(callback.userId, callback.eventId), {
      eventId: callback.eventId,
      coins,
      source: 'rewarded_ad',
      grantedAt: FieldValue.serverTimestamp(),
    });
    tx.set(
      user,
      {
        coinsGranted: FieldValue.increment(coins),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return 'granted' as const;
  });
}
