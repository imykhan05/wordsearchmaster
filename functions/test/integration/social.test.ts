/**
 * The emulator-backed half of P17's acceptance criteria: server-computed
 * ranks (including the true rank outside a top-100 window), auto-granted
 * achievements, the one client-claimed achievement, and the friend graph.
 *
 * Same shape as `pipeline.test.ts`: real Firestore, inner functions driven
 * directly rather than through the callable transport (see that file's
 * header for the reasoning, which applies here unchanged).
 */

import { randomUUID } from 'node:crypto';

import { getApps, initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { ACHIEVEMENTS } from '../../src/stats';
import { recordAchievementClaim } from '../../src/submitAchievement';
import { recordSubmission } from '../../src/submissions';
import { getOrCreateInviteCode, redeemCode } from '../../src/friends';
import { computeRanks, recomputeRanksForBoard } from '../../src/ranks';
import { levelShape } from '../../src/levels';
import type { ScoreEvent } from '../../src/scoring';
import { parseLevelSubmission, type LevelSubmission } from '../../src/validation';

if (process.env['FIRESTORE_EMULATOR_HOST'] === undefined) {
  throw new Error(
    'These tests require the Firestore emulator. Run `npm run test:emulator`.',
  );
}
if (getApps().length === 0) {
  initializeApp({ projectId: process.env['GCLOUD_PROJECT'] ?? 'wsm-dev' });
}

const firestore = getFirestore();

function newUid(): string {
  return `test-${randomUUID()}`;
}

const found = (g: number): ScoreEvent => ({ t: 'w', g });

function levelPayload(
  level: number,
  options: {
    completedAt: number;
    language?: string;
    words?: number;
    graphemes?: number;
    hintsUsed?: number;
  },
): Record<string, unknown> {
  const words = options.words ?? levelShape(level).wordCount;
  const graphemes = options.graphemes ?? 3;
  return {
    language: options.language ?? 'en',
    level,
    stars: 3,
    hintsUsed: options.hintsUsed ?? 0,
    completedAt: options.completedAt,
    specVersion: 1,
    events: Array.from({ length: words }, () => found(graphemes)),
    nonce: `level:${options.language ?? 'en'}:${level}:${options.completedAt}`,
  };
}

function parseLevel(payload: Record<string, unknown>): LevelSubmission {
  return parseLevelSubmission(payload);
}

async function submitLevel(
  uid: string,
  level: number,
  options: Parameters<typeof levelPayload>[1],
) {
  return recordSubmission(uid, parseLevel(levelPayload(level, options)));
}

async function userDoc(uid: string) {
  return (await firestore.doc(`users/${uid}`).get()).data();
}

const createdUsers: string[] = [];
afterAll(async () => {
  await Promise.all(
    createdUsers.map((uid) => firestore.recursiveDelete(firestore.doc(`users/${uid}`))),
  );
});

beforeAll(() => {
  expect(process.env['FIRESTORE_EMULATOR_HOST']).toBeDefined();
});

// ===========================================================================
// CRITERION 1 — "user ka rank top-100 se bahar hone par bhi sahi dikhta hai"
// ===========================================================================

describe('server-computed rank, outside the top 100', () => {
  it('gives the true rank of a player far below the top 100 window', async () => {
    // 130 real accounts on ONE board, scored so the rank ordering is
    // unambiguous. This is the exact case a top-100 query can never answer.
    const board = `test-global-${randomUUID()}`;
    const uids: string[] = [];

    for (let i = 0; i < 130; i++) {
      const uid = newUid();
      uids.push(uid);
      createdUsers.push(uid);
      await firestore.doc(`users/${uid}`).set({ displayName: `Player ${i}` });
      await firestore.doc(`leaderboards/${board}/entries/${uid}`).set({
        uid,
        displayName: `Player ${i}`,
        photoUrl: null,
        score: 10_000 - i, // strictly descending: player 0 is #1, player 129 is #130.
        updatedAt: 1,
      });
    }

    await recomputeRanksForBoard(board);

    // Player 129 (score 9871) sits OUTSIDE any top-100 query — this is the
    // uid a client's `.limit(100)` read would never return, and the rank the
    // pinned row has nowhere else to come from.
    const outsideTopUid = uids[129]!;
    const stats = await userDoc(outsideTopUid);
    expect(
      (stats?.['stats'] as Record<string, unknown> | undefined)?.['ranks'],
    ).toEqual({
      [board]: 130,
    });

    // And the entry doc itself also carries it, for a board read that wants
    // to show rank inline with the row (see `ranks.ts`'s header).
    const entry = (
      await firestore.doc(`leaderboards/${board}/entries/${outsideTopUid}`).get()
    ).data();
    expect(entry?.['rank']).toBe(130);

    // A player who genuinely IS in the top 100 gets a rank inside it too —
    // the pinned-row logic on the client only needs THIS number to decide
    // whether to render a second, separate row at all.
    const topUid = uids[0]!;
    const topStats = await userDoc(topUid);
    expect(
      (topStats?.['stats'] as Record<string, unknown> | undefined)?.['ranks'],
    ).toEqual({
      [board]: 1,
    });
  });

  it('never scans more than the one board it was asked to recompute', async () => {
    // A recompute of board A must not touch a uid's rank on board B — proves
    // the job is scoped per board, not a blanket "recompute everything" scan.
    const boardA = `test-a-${randomUUID()}`;
    const boardB = `test-b-${randomUUID()}`;
    const uid = newUid();
    createdUsers.push(uid);
    await firestore.doc(`users/${uid}`).set({ displayName: 'Solo' });
    await firestore
      .doc(`leaderboards/${boardA}/entries/${uid}`)
      .set({ uid, score: 10, updatedAt: 1 });
    await firestore
      .doc(`leaderboards/${boardB}/entries/${uid}`)
      .set({ uid, score: 20, updatedAt: 1 });

    await recomputeRanksForBoard(boardA);

    const stats = (await userDoc(uid))?.['stats'] as
      | Record<string, unknown>
      | undefined;
    expect(stats?.['ranks']).toEqual({ [boardA]: 1 });
  });

  it('re-running the job is idempotent — the same ranking comes out twice', async () => {
    const board = `test-idem-${randomUUID()}`;
    const uid = newUid();
    createdUsers.push(uid);
    await firestore.doc(`users/${uid}`).set({ displayName: 'X' });
    await firestore
      .doc(`leaderboards/${board}/entries/${uid}`)
      .set({ uid, score: 5, updatedAt: 1 });

    await recomputeRanksForBoard(board);
    const first = ((await userDoc(uid))?.['stats'] as Record<string, unknown>)['ranks'];
    await recomputeRanksForBoard(board);
    const second = ((await userDoc(uid))?.['stats'] as Record<string, unknown>)[
      'ranks'
    ];
    expect(second).toEqual(first);
  });

  it('computeRanks matches what recomputeRanksForBoard actually wrote', async () => {
    // The pure function and the Firestore-writing wrapper must agree — this
    // is what makes the pure unit tests in ranks.test.ts trustworthy evidence
    // about the wrapper's behaviour.
    const board = `test-parity-${randomUUID()}`;
    const scores = [30, 10, 20];
    const uids = scores.map(() => newUid());
    uids.forEach((uid) => createdUsers.push(uid));

    for (let i = 0; i < uids.length; i++) {
      await firestore.doc(`users/${uids[i]}`).set({ displayName: `p${i}` });
      await firestore
        .doc(`leaderboards/${board}/entries/${uids[i]}`)
        .set({ uid: uids[i], score: scores[i], updatedAt: 1 });
    }
    await recomputeRanksForBoard(board);

    const expected = computeRanks(
      uids
        .map((uid, i) => ({ uid, score: scores[i]! }))
        .sort((a, b) => b.score - a.score),
    );
    for (const entry of expected) {
      const stats = (await userDoc(entry.uid))?.['stats'] as Record<string, unknown>;
      expect((stats['ranks'] as Record<string, number>)[board]).toBe(entry.rank);
    }
  });
});

// ===========================================================================
// Achievements — auto-granted
// ===========================================================================

describe('achievements auto-grant inside recordSubmission', () => {
  it('grants First Word on the first accepted submission with a word in it', async () => {
    const uid = newUid();
    createdUsers.push(uid);
    await submitLevel(uid, 1, { completedAt: Date.now() });

    const stats = (await userDoc(uid))?.['stats'] as Record<string, unknown>;
    expect(Object.keys(stats['achievements'] as object)).toContain(
      ACHIEVEMENTS.firstWord,
    );
  });

  it('grants Trilingual once all three languages have an accepted submission', async () => {
    const uid = newUid();
    createdUsers.push(uid);
    // Spaced minutes apart, not milliseconds: three submissions this close
    // together would themselves trip the timing floor (`validation.ts`) and
    // arrive SUSPICIOUS, which must never grant an achievement — proven
    // separately below. This test is about language coverage, so it gives
    // the timing check plenty of room instead.
    const now = Date.now();
    await submitLevel(uid, 1, { completedAt: now - 20 * 60_000, language: 'en' });
    await submitLevel(uid, 1, { completedAt: now - 10 * 60_000, language: 'ur' });
    await submitLevel(uid, 1, { completedAt: now, language: 'hi' });

    const stats = (await userDoc(uid))?.['stats'] as Record<string, unknown>;
    expect(Object.keys(stats['achievements'] as object)).toContain(
      ACHIEVEMENTS.trilingual,
    );
  });

  it('does NOT grant anything from a suspicious (flagged) submission', async () => {
    const uid = newUid();
    createdUsers.push(uid);
    // A level id far beyond anything reachable — the progression-gap flag.
    await submitLevel(uid, 250, {
      completedAt: Date.now(),
      words: 12,
      graphemes: 6,
    });

    const stats = (await userDoc(uid))?.['stats'] as
      | Record<string, unknown>
      | undefined;
    // Either stats never got written, or it holds no achievements — either
    // way, a flagged submission must not have unlocked First Word.
    expect(stats?.['achievements'] ?? {}).toEqual({});
  });

  it('an achievement, once unlocked, survives further play untouched', async () => {
    const uid = newUid();
    createdUsers.push(uid);
    await submitLevel(uid, 1, { completedAt: Date.now() });
    const firstUnlockedAt = (
      ((await userDoc(uid))?.['stats'] as Record<string, unknown>)[
        'achievements'
      ] as Record<string, { unlockedAt: unknown }>
    )[ACHIEVEMENTS.firstWord]!.unlockedAt;

    await submitLevel(uid, 2, { completedAt: Date.now() + 5000 });
    const stillThere = (
      ((await userDoc(uid))?.['stats'] as Record<string, unknown>)[
        'achievements'
      ] as Record<string, { unlockedAt: unknown }>
    )[ACHIEVEMENTS.firstWord]!.unlockedAt;

    expect(stillThere).toEqual(firstUnlockedAt);
  });
});

// ===========================================================================
// Achievements — the one client-claimed path (Collector)
// ===========================================================================

describe('submitAchievement — Collector', () => {
  /**
   * A player who has genuinely reached level 20 — seeded directly rather
   * than by submitting twenty levels, because the plausibility bound this
   * claim is checked against reads `progress.{lang}.highestLevel` straight
   * off the user document, not the submission history that produced it.
   * That keeps this suite about the CLAIM, and progression continuity is
   * already covered by `validation.test.ts` and the rest of this file.
   */
  async function seedProgress(uid: string, language: string, highestLevel: number) {
    await firestore
      .doc(`users/${uid}`)
      .set({ progress: { [language]: { highestLevel } } }, { merge: true });
  }

  it('grants a plausible claim', async () => {
    const uid = newUid();
    createdUsers.push(uid);
    await firestore.doc(`users/${uid}`).set({ displayName: 'Player' });
    await seedProgress(uid, 'en', 20);

    const result = await recordAchievementClaim(uid, 'animals', 'en');
    expect(result).toEqual({ recorded: true, alreadyRecorded: false });

    const stats = (await userDoc(uid))?.['stats'] as Record<string, unknown>;
    expect(Object.keys(stats['achievements'] as object)).toContain(
      'collection:en:animals',
    );
  });

  it('is idempotent — claiming the same category twice changes nothing the second time', async () => {
    const uid = newUid();
    createdUsers.push(uid);
    await firestore.doc(`users/${uid}`).set({ displayName: 'Player' });
    await seedProgress(uid, 'en', 20);

    await recordAchievementClaim(uid, 'animals', 'en');
    const second = await recordAchievementClaim(uid, 'animals', 'en');
    expect(second).toEqual({ recorded: true, alreadyRecorded: true });
  });

  it('never errors on an implausible claim — it is flagged, not refused', async () => {
    const uid = newUid();
    createdUsers.push(uid);
    // No play behind this account at all.
    await firestore.doc(`users/${uid}`).set({ displayName: 'New' });

    const result = await recordAchievementClaim(uid, 'animals', 'en');
    expect(result).toEqual({ recorded: true, alreadyRecorded: false });

    const stats = (await userDoc(uid))?.['stats'] as
      | Record<string, unknown>
      | undefined;
    expect(stats?.['achievements'] ?? {}).toEqual({});

    const flags = await firestore.collection(`moderation/${uid}/flags`).get();
    expect(flags.size).toBe(1);
    expect(flags.docs[0]?.data()['kind']).toBe('achievement_claim');
  });

  it('refuses a category that does not exist, without granting it', async () => {
    const uid = newUid();
    createdUsers.push(uid);
    await submitLevel(uid, 20, { completedAt: Date.now() });

    await recordAchievementClaim(uid, 'not-a-real-category', 'en');
    const stats = (await userDoc(uid))?.['stats'] as
      | Record<string, unknown>
      | undefined;
    expect(stats?.['achievements'] ?? {}).toEqual({});
  });
});

// ===========================================================================
// CRITERION 3 — "friends invite code se kaam karta hai"
// ===========================================================================

describe('friends — invite codes', () => {
  it('a redeemed code creates a MUTUAL friendship', async () => {
    const owner = newUid();
    const redeemer = newUid();
    createdUsers.push(owner, redeemer);
    await firestore.doc(`users/${owner}`).set({ displayName: 'Owner', photoUrl: null });
    await firestore
      .doc(`users/${redeemer}`)
      .set({ displayName: 'Redeemer', photoUrl: null });

    const { code } = await getOrCreateInviteCode(owner);
    expect(code).toHaveLength(8);

    const outcome = await redeemCode(redeemer, code);
    expect(outcome).toEqual({ status: 'friended', friendUid: owner });

    const ownerSide = (
      await firestore.doc(`users/${owner}/friends/${redeemer}`).get()
    ).data();
    const redeemerSide = (
      await firestore.doc(`users/${redeemer}/friends/${owner}`).get()
    ).data();

    expect(ownerSide?.['displayName']).toBe('Redeemer');
    expect(redeemerSide?.['displayName']).toBe('Owner');
  });

  it('the same code is returned on a second call, not a fresh one', async () => {
    const uid = newUid();
    createdUsers.push(uid);
    await firestore.doc(`users/${uid}`).set({ displayName: 'Stable' });

    const first = await getOrCreateInviteCode(uid);
    const second = await getOrCreateInviteCode(uid);
    expect(second.code).toBe(first.code);
  });

  it('lower case and surrounding whitespace redeem the same as the canonical code', async () => {
    const owner = newUid();
    const redeemer = newUid();
    createdUsers.push(owner, redeemer);
    await firestore.doc(`users/${owner}`).set({ displayName: 'Owner' });
    await firestore.doc(`users/${redeemer}`).set({ displayName: 'Redeemer' });
    const { code } = await getOrCreateInviteCode(owner);

    const outcome = await redeemCode(redeemer, `  ${code.toLowerCase()}  `);
    expect(outcome.status).toBe('friended');
  });

  it('an unknown code is reported, not thrown', async () => {
    const redeemer = newUid();
    createdUsers.push(redeemer);
    await firestore.doc(`users/${redeemer}`).set({ displayName: 'R' });

    const outcome = await redeemCode(redeemer, 'NOTREAL1');
    expect(outcome).toEqual({ status: 'notFound' });
  });

  it('a player cannot redeem their own code', async () => {
    const uid = newUid();
    createdUsers.push(uid);
    await firestore.doc(`users/${uid}`).set({ displayName: 'Solo' });
    const { code } = await getOrCreateInviteCode(uid);

    const outcome = await redeemCode(uid, code);
    expect(outcome).toEqual({ status: 'ownCode' });

    const selfFriend = await firestore.doc(`users/${uid}/friends/${uid}`).get();
    expect(selfFriend.exists).toBe(false);
  });

  it('redeeming twice is reported as already friends, and stays a single row', async () => {
    const owner = newUid();
    const redeemer = newUid();
    createdUsers.push(owner, redeemer);
    await firestore.doc(`users/${owner}`).set({ displayName: 'Owner' });
    await firestore.doc(`users/${redeemer}`).set({ displayName: 'Redeemer' });
    const { code } = await getOrCreateInviteCode(owner);

    await redeemCode(redeemer, code);
    const again = await redeemCode(redeemer, code);
    expect(again).toEqual({ status: 'alreadyFriends', friendUid: owner });

    const friends = await firestore.collection(`users/${redeemer}/friends`).get();
    expect(friends.size).toBe(1);
  });

  it("does not touch the OTHER player's friend list on a failed redemption", async () => {
    const owner = newUid();
    const redeemer = newUid();
    createdUsers.push(owner, redeemer);
    await firestore.doc(`users/${owner}`).set({ displayName: 'Owner' });
    await firestore.doc(`users/${redeemer}`).set({ displayName: 'Redeemer' });

    await redeemCode(redeemer, 'GARBAGE1');

    expect((await firestore.collection(`users/${owner}/friends`).get()).size).toBe(0);
    expect((await firestore.collection(`users/${redeemer}/friends`).get()).size).toBe(
      0,
    );
  });
});
