/**
 * The emulator-backed half of P14's acceptance criteria.
 *
 * Run with `npm run test:emulator`, which wraps this in
 * `firebase emulators:exec --only firestore,auth`. Everything here talks to a
 * REAL Firestore and a REAL Auth emulator — transactions, `FieldValue`
 * increments, `recursiveDelete`, collection-group queries and the append-only
 * semantics of the writes are all genuinely exercised, none of it mocked.
 *
 * ---------------------------------------------------------------------------
 * WHY THE INNER FUNCTIONS AND NOT THE CALLABLE TRANSPORT
 *
 * The suite drives `recordSubmission` / `mirrorScoreToLeaderboards` /
 * `deleteAccountFor` / `creditReward` directly rather than posting a callable
 * envelope at the functions emulator. What the wrappers add is an auth check,
 * a parse and an App Check flag — the first two are covered by
 * `validation.test.ts` with no emulator at all, and the third is a deploy-time
 * property that an emulator does not enforce, so routing through the transport
 * would add minutes of startup for no additional coverage of the thing under
 * test: the data the pipeline writes.
 */

import { randomUUID } from 'node:crypto';

import { getApps, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { FLAGS, LIMITS } from '../../src/config';
import { deleteAccountFor } from '../../src/deleteAccount';
import { creditReward } from '../../src/grantRewardedReward';
import { levelShape } from '../../src/levels';
import { recordSubmission } from '../../src/submissions';
import { mirrorScoreToLeaderboards } from '../../src/updateLeaderboards';
import type { ScoreEvent } from '../../src/scoring';
import {
  parseDailySubmission,
  parseLevelSubmission,
  type LevelSubmission,
} from '../../src/validation';

if (process.env['FIRESTORE_EMULATOR_HOST'] === undefined) {
  throw new Error(
    'These tests require the Firestore emulator. Run `npm run test:emulator`.',
  );
}
if (getApps().length === 0) {
  initializeApp({ projectId: process.env['GCLOUD_PROJECT'] ?? 'wsm-dev' });
}

const firestore = getFirestore();
const auth = getAuth();

/** A fresh uid per test, so nothing here depends on run order or cleanup. */
function newUid(): string {
  return `test-${randomUUID()}`;
}

const found = (g: number): ScoreEvent => ({ t: 'w', g });

/**
 * The exact payload `ProgressRepository.recordLevelComplete` enqueues, built
 * from the outside so the test cannot accidentally construct something the
 * client could not send.
 */
function levelPayload(
  level: number,
  options: {
    completedAt: number;
    language?: string;
    words?: number;
    graphemes?: number;
    stars?: number;
    hintsUsed?: number;
    nonce?: string;
    extra?: Record<string, unknown>;
  },
): Record<string, unknown> {
  const words = options.words ?? levelShape(level).wordCount;
  const graphemes = options.graphemes ?? 3;
  return {
    language: options.language ?? 'en',
    level,
    stars: options.stars ?? 3,
    hintsUsed: options.hintsUsed ?? 0,
    completedAt: options.completedAt,
    specVersion: 1,
    events: Array.from({ length: words }, () => found(graphemes)),
    nonce: options.nonce ?? `level:en:${level}:${options.completedAt}`,
    ...options.extra,
  };
}

function parseLevel(payload: Record<string, unknown>): LevelSubmission {
  return parseLevelSubmission(payload);
}

async function scoreDoc(uid: string, scoreId: string) {
  return (await firestore.doc(`users/${uid}/scores/${scoreId}`).get()).data();
}

async function moderationFlags(uid: string) {
  const snap = await firestore.collection(`moderation/${uid}/flags`).get();
  return snap.docs.map((doc) => doc.data());
}

async function boardEntry(board: string, uid: string) {
  return (await firestore.doc(`leaderboards/${board}/entries/${uid}`).get()).data();
}

/** Plays a clean run of levels 1..n at a human pace, ending `now`. */
async function playHonestly(uid: string, levels: number, now: number): Promise<void> {
  for (let level = 1; level <= levels; level++) {
    const completedAt = now - (levels - level + 1) * 5 * 60_000;
    await recordSubmission(uid, parseLevel(levelPayload(level, { completedAt })));
  }
}

const createdUids: string[] = [];
afterAll(async () => {
  await Promise.all(
    createdUids.map((uid) => auth.deleteUser(uid).catch(() => undefined)),
  );
});

// ===========================================================================
// CRITERION 1 — "client se fake score submit karne ki koshish reject/flag hoti hai"
// ===========================================================================

describe('a forged submission is flagged, never answered with an error', () => {
  it('ignores an inflated score field entirely and writes the replayed number', async () => {
    const uid = newUid();
    const now = Date.now();
    await playHonestly(uid, 1, now);

    // The classic attack: the same events, with a score bolted on.
    const response = await recordSubmission(
      uid,
      parseLevel(
        levelPayload(2, {
          completedAt: now,
          extra: { score: 9_999_999, bestScore: 9_999_999 },
        }),
      ),
    );

    // 4 words x 3 graphemes on the 1..5 band: 30 + 36 + 42 + 48 = 156.
    expect(response.score).toBe(156);
    const stored = await scoreDoc(uid, 'level_en_2');
    expect(stored?.['score']).toBe(156);
    expect(stored?.['suspicious']).toBe(false);
  });

  it('flags a jump to a level the player never reached, and still returns success', async () => {
    const uid = newUid();
    const now = Date.now();
    await playHonestly(uid, 1, now);

    // No throw. The caller cannot tell this apart from an accepted submission.
    const response = await recordSubmission(
      uid,
      parseLevel(levelPayload(250, { completedAt: now, words: 12, graphemes: 6 })),
    );
    expect(response.alreadyRecorded).toBe(false);
    expect(Object.keys(response)).not.toContain('suspicious');
    expect(Object.keys(response)).not.toContain('flags');

    const stored = await scoreDoc(uid, 'level_en_250');
    expect(stored?.['suspicious']).toBe(true);
    expect(stored?.['flags']).toContain(FLAGS.progressionGap);

    const flags = await moderationFlags(uid);
    expect(flags).toHaveLength(1);
    expect(flags[0]?.['flags']).toContain(FLAGS.progressionGap);
    // The moderator gets the raw events, not this function's summary of them.
    expect(flags[0]?.['events']).toHaveLength(12);
    expect(flags[0]?.['serverScore']).toBe(componentScore(12, 6));
  });

  it('keeps a flagged score off every leaderboard', async () => {
    const uid = newUid();
    const now = Date.now();
    await playHonestly(uid, 1, now);
    await recordSubmission(
      uid,
      parseLevel(levelPayload(250, { completedAt: now, words: 12, graphemes: 6 })),
    );

    const stored = await scoreDoc(uid, 'level_en_250');
    await mirrorScoreToLeaderboards(uid, stored!);

    expect(await boardEntry('global', uid)).toBeUndefined();
    expect(await boardEntry('en', uid)).toBeUndefined();
  });

  it('does not let a flagged submission overwrite an honest best score', async () => {
    const uid = newUid();
    const now = Date.now();
    await playHonestly(uid, 1, now);
    const honest = await scoreDoc(uid, 'level_en_1');

    // A tampered replay of a level the player has legitimately finished.
    await recordSubmission(
      uid,
      parseLevel(
        levelPayload(1, {
          completedAt: now + 5_000,
          words: 12,
          nonce: 'forged',
        }),
      ),
    );

    const after = await scoreDoc(uid, 'level_en_1');
    expect(after?.['score']).toBe(honest?.['score']);
    expect(after?.['suspicious']).toBe(false);
    // But the attempt is on the record.
    expect(after?.['flaggedSubmissions']).toBe(1);
    expect(await moderationFlags(uid)).toHaveLength(1);
  });

  it('flags a claimed star count that the events do not support', async () => {
    const uid = newUid();
    const now = Date.now();
    await playHonestly(uid, 1, now);

    await recordSubmission(
      uid,
      parseLevel(
        levelPayload(2, {
          completedAt: now,
          stars: 3,
          hintsUsed: 0,
          // Three hints were actually used, so the honest answer is 1 star.
          extra: {
            events: [
              found(3),
              found(3),
              found(3),
              found(3),
              { t: 'h' },
              { t: 'h' },
              { t: 'h' },
            ],
          },
        }),
      ),
    );

    const stored = await scoreDoc(uid, 'level_en_2');
    expect(stored?.['suspicious']).toBe(true);
    expect(stored?.['flags']).toContain(FLAGS.clientStarsMismatch);
    expect(stored?.['stars']).toBe(1);
  });

  it('flags a burst of levels that could not have been played in the time claimed', async () => {
    const uid = newUid();
    const now = Date.now();
    let flagged = 0;
    for (let level = 1; level <= 12; level++) {
      await recordSubmission(
        uid,
        parseLevel(levelPayload(level, { completedAt: now + level })),
      );
      const stored = await scoreDoc(uid, `level_en_${level}`);
      if (stored?.['suspicious'] === true) flagged++;
    }
    expect(flagged).toBeGreaterThan(0);

    const codes = (await moderationFlags(uid)).flatMap(
      (flag) => flag['flags'] as string[],
    );
    expect(codes).toContain(FLAGS.timingFloor);
  });
});

/** The score `words` words of `graphemes` graphemes earn with no mistakes. */
function componentScore(words: number, graphemes: number): number {
  const table = [10, 12, 14, 16, 18, 20];
  let total = 0;
  for (let i = 1; i <= words; i++) total += graphemes * table[Math.min(i, 6) - 1]!;
  return total;
}

// ===========================================================================
// The honest paths
// ===========================================================================

describe('an honest submission', () => {
  it('records the server score, the stars and the progression high-water mark', async () => {
    const uid = newUid();
    const now = Date.now();
    await playHonestly(uid, 3, now);

    const stored = await scoreDoc(uid, 'level_en_3');
    expect(stored?.['score']).toBe(156);
    expect(stored?.['stars']).toBe(3);
    expect(stored?.['suspicious']).toBe(false);

    const user = (await firestore.doc(`users/${uid}`).get()).data();
    expect(user?.['progress']).toEqual({ en: { highestLevel: 3 } });
    expect(user?.['totals']).toEqual({ global: 468, en: 468 });
    expect(await moderationFlags(uid)).toHaveLength(0);
  });

  it('is idempotent when the outbox retries the same row', async () => {
    const uid = newUid();
    const now = Date.now();
    await playHonestly(uid, 1, now);

    const payload = levelPayload(2, { completedAt: now });
    const first = await recordSubmission(uid, parseLevel(payload));
    const second = await recordSubmission(uid, parseLevel(payload));

    // A replay is a SUCCESS, not an error: the row is the same row.
    expect(second.alreadyRecorded).toBe(true);
    expect(second.score).toBe(first.score);

    const user = (await firestore.doc(`users/${uid}`).get()).data();
    // 156 for level 1 plus 156 for level 2 — counted once, not twice.
    expect(user?.['totals']).toEqual({ global: 312, en: 312 });
  });

  it('keeps the better of two attempts at the same level, and moves totals by the difference', async () => {
    const uid = newUid();
    const now = Date.now();
    await recordSubmission(
      uid,
      parseLevel(levelPayload(1, { completedAt: now - 600_000, graphemes: 2 })),
    );
    const worse = (await firestore.doc(`users/${uid}`).get()).data();
    expect(worse?.['totals']).toEqual({ global: 104, en: 104 });

    await recordSubmission(
      uid,
      parseLevel(levelPayload(1, { completedAt: now, graphemes: 3 })),
    );
    const better = (await firestore.doc(`users/${uid}`).get()).data();
    // 156, not 104 + 156: replaying a level cannot pump a leaderboard.
    expect(better?.['totals']).toEqual({ global: 156, en: 156 });
    expect((await scoreDoc(uid, 'level_en_1'))?.['score']).toBe(156);
  });

  it('refuses to submit past the rate limit, and says so plainly', async () => {
    const uid = newUid();
    await firestore.doc(`users/${uid}`).set({
      rate: { windowStartMillis: Date.now(), count: LIMITS.rateMaxSubmissions },
    });

    await expect(
      recordSubmission(uid, parseLevel(levelPayload(1, { completedAt: Date.now() }))),
    ).rejects.toThrow(/Too many submissions/);
  });
});

// ===========================================================================
// Dailies
// ===========================================================================

describe('the Daily Challenge', () => {
  const dailyPayload = (date: string, completedAt: number, nonce: string) => ({
    date,
    language: 'en',
    stars: 3,
    completedAt,
    specVersion: 1,
    events: Array.from({ length: 8 }, () => found(4)),
    nonce,
  });

  it('records one entry per uid per date, server-side', async () => {
    const uid = newUid();
    const now = Date.now();

    const first = await recordSubmission(
      uid,
      parseDailySubmission(dailyPayload('2026-08-31', now - 600_000, 'daily-1')),
    );
    // A SECOND, differently-nonced attempt at the same day: a grind attempt,
    // or an honest replay after the local row failed its integrity check.
    // Either way the first attempt is the attempt.
    const second = await recordSubmission(
      uid,
      parseDailySubmission(dailyPayload('2026-08-31', now, 'daily-2')),
    );

    expect(second.alreadyRecorded).toBe(true);
    expect(second.score).toBe(first.score);

    const snap = await firestore.collection(`users/${uid}/scores`).get();
    expect(snap.docs.map((doc) => doc.id)).toEqual(['daily_en_2026-08-31']);
  });

  it('publishes the best of a date across languages, whichever syncs last', async () => {
    const uid = newUid();
    const now = Date.now();
    await firestore.doc(`users/${uid}`).set({ displayName: 'Ayesha', photoUrl: null });

    await recordSubmission(
      uid,
      parseDailySubmission({
        ...dailyPayload('2026-08-31', now - 900_000, 'ur-daily'),
        language: 'ur',
      }),
    );
    await recordSubmission(
      uid,
      parseDailySubmission({
        ...dailyPayload('2026-08-31', now, 'en-daily'),
        language: 'en',
        events: Array.from({ length: 8 }, () => found(2)),
      }),
    );

    await mirrorScoreToLeaderboards(uid, (await scoreDoc(uid, 'daily_ur_2026-08-31'))!);
    await mirrorScoreToLeaderboards(uid, (await scoreDoc(uid, 'daily_en_2026-08-31'))!);

    const entry = await boardEntry('daily_2026-08-31', uid);
    // The Urdu run (4-grapheme words) beats the English one (2-grapheme), and
    // arriving second must not demote it.
    expect(entry?.['score']).toBe(componentScore(8, 4));
    expect(entry?.['displayName']).toBe('Ayesha');
  });
});

// ===========================================================================
// Leaderboards
// ===========================================================================

describe('leaderboard entries', () => {
  it('carry exactly the five permitted fields', async () => {
    const uid = newUid();
    const now = Date.now();
    await firestore
      .doc(`users/${uid}`)
      .set({ displayName: 'Rahul', photoUrl: 'p.png' });
    await playHonestly(uid, 2, now);
    await mirrorScoreToLeaderboards(uid, (await scoreDoc(uid, 'level_en_2'))!);

    const entry = await boardEntry('global', uid);
    expect(Object.keys(entry ?? {}).sort()).toEqual([
      'displayName',
      'photoUrl',
      'score',
      'uid',
      'updatedAt',
    ]);
    expect(entry?.['score']).toBe(312);
  });

  it('is unchanged by a second delivery of the same write', async () => {
    // A Firestore trigger is at-least-once. Because the totals are accumulated
    // in `recordSubmission`'s transaction and only COPIED here, running the
    // mirror twice writes the same number twice.
    const uid = newUid();
    const now = Date.now();
    await playHonestly(uid, 2, now);
    const score = (await scoreDoc(uid, 'level_en_2'))!;

    await mirrorScoreToLeaderboards(uid, score);
    const once = await boardEntry('global', uid);
    await mirrorScoreToLeaderboards(uid, score);
    const twice = await boardEntry('global', uid);

    expect(twice?.['score']).toBe(once?.['score']);
  });

  it('writes the weekly board keyed by when the level was PLAYED, not synced', async () => {
    const uid = newUid();
    const completedAt = Date.UTC(2026, 7, 31, 9, 0, 0); // Monday of 2026-W36.
    await recordSubmission(uid, parseLevel(levelPayload(1, { completedAt })));
    await mirrorScoreToLeaderboards(uid, (await scoreDoc(uid, 'level_en_1'))!);

    expect((await boardEntry('weekly_2026-W36', uid))?.['score']).toBe(156);
  });

  it('writes a per-language board alongside the global one', async () => {
    const uid = newUid();
    const now = Date.now();
    await recordSubmission(
      uid,
      parseLevel(levelPayload(1, { completedAt: now, language: 'hi' })),
    );
    await mirrorScoreToLeaderboards(uid, (await scoreDoc(uid, 'level_hi_1'))!);

    expect((await boardEntry('hi', uid))?.['score']).toBe(156);
    expect((await boardEntry('global', uid))?.['score']).toBe(156);
    expect(await boardEntry('en', uid)).toBeUndefined();
  });
});

// ===========================================================================
// CRITERION 3 — "deleteAccount sab kuch saaf kar deta hai"
// ===========================================================================

describe('deleteAccount', () => {
  it('removes the user doc, every subcollection, every board entry, the moderation trail and the auth record', async () => {
    const uid = newUid();
    createdUids.push(uid);
    await auth.createUser({ uid, displayName: 'To Be Deleted' });

    const now = Date.now();
    await firestore.doc(`users/${uid}`).set({ displayName: 'To Be Deleted' });
    await playHonestly(uid, 3, now);
    await recordSubmission(
      uid,
      parseDailySubmission({
        date: '2026-08-31',
        language: 'en',
        stars: 3,
        completedAt: now - 3_600_000,
        specVersion: 1,
        events: Array.from({ length: 8 }, () => found(4)),
        nonce: 'daily-delete',
      }),
    );
    // A flagged submission too, so the moderation trail is non-empty.
    await recordSubmission(
      uid,
      parseLevel(levelPayload(250, { completedAt: now, words: 12, graphemes: 6 })),
    );
    // And a server-granted reward, so `coinGrants` is non-empty.
    await creditReward({
      userId: uid,
      eventId: `evt-${uid}`,
      amount: 40,
      timestampMillis: now,
      signature: 'checked-before-this-point',
    });

    for (const scoreId of [
      'level_en_1',
      'level_en_2',
      'level_en_3',
      'daily_en_2026-08-31',
    ]) {
      await mirrorScoreToLeaderboards(uid, (await scoreDoc(uid, scoreId))!);
    }

    // Everything exists.
    expect((await firestore.doc(`users/${uid}`).get()).exists).toBe(true);
    expect((await firestore.collection(`users/${uid}/scores`).get()).size).toBe(5);
    expect((await firestore.collection(`users/${uid}/nonces`).get()).size).toBe(5);
    expect((await firestore.collection(`users/${uid}/coinGrants`).get()).size).toBe(1);
    expect((await moderationFlags(uid)).length).toBe(1);
    const entriesBefore = await firestore
      .collectionGroup('entries')
      .where('uid', '==', uid)
      .get();
    expect(entriesBefore.size).toBeGreaterThan(0);

    const result = await deleteAccountFor(uid);

    expect(result.deleted).toBe(true);
    expect(result.uid).toBe(uid);
    expect(result.leaderboardEntriesRemoved).toBe(entriesBefore.size);
    expect(result.moderationRecordsRemoved).toBe(1);

    // And nothing does.
    expect((await firestore.doc(`users/${uid}`).get()).exists).toBe(false);
    expect((await firestore.collection(`users/${uid}/scores`).get()).size).toBe(0);
    expect((await firestore.collection(`users/${uid}/nonces`).get()).size).toBe(0);
    expect((await firestore.collection(`users/${uid}/coinGrants`).get()).size).toBe(0);
    expect((await moderationFlags(uid)).length).toBe(0);
    expect(
      (await firestore.collectionGroup('entries').where('uid', '==', uid).get()).size,
    ).toBe(0);
    await expect(auth.getUser(uid)).rejects.toThrow();
  });

  it('is safe to run twice — a retry finishes the job rather than failing', async () => {
    const uid = newUid();
    await auth.createUser({ uid });
    await recordSubmission(
      uid,
      parseLevel(levelPayload(1, { completedAt: Date.now() })),
    );

    await deleteAccountFor(uid);
    // The auth record is already gone; a second call must still resolve.
    const second = await deleteAccountFor(uid);
    expect(second.deleted).toBe(true);
  });
});

// ===========================================================================
// Rewarded ads
// ===========================================================================

describe('server-side rewarded grants', () => {
  it('credits coins once and pays nothing on a retried callback', async () => {
    const uid = newUid();
    await firestore.doc(`users/${uid}`).set({ displayName: 'Player' });
    const callback = {
      userId: uid,
      eventId: `evt-${uid}`,
      amount: 40,
      timestampMillis: Date.now(),
      signature: 'verified-in-the-wrapper',
    };

    expect(await creditReward(callback)).toBe('granted');
    // AppLovin retries on a non-2xx, so this is the normal case, not an edge one.
    expect(await creditReward(callback)).toBe('duplicate');

    const user = (await firestore.doc(`users/${uid}`).get()).data();
    expect(user?.['coinsGranted']).toBe(40);
    const grants = await firestore.collection(`users/${uid}/coinGrants`).get();
    expect(grants.size).toBe(1);
    expect(grants.docs[0]?.data()['coins']).toBe(40);
  });

  it('clamps a callback that asks for more coins than any ad unit should pay', async () => {
    const uid = newUid();
    await firestore.doc(`users/${uid}`).set({ displayName: 'Player' });
    await creditReward({
      userId: uid,
      eventId: `evt-big-${uid}`,
      amount: 1_000_000,
      timestampMillis: Date.now(),
      signature: 'verified',
    });

    const user = (await firestore.doc(`users/${uid}`).get()).data();
    expect(user?.['coinsGranted']).toBe(LIMITS.maxRewardCoins);
  });

  it('refuses to mint coins for an account that does not exist', async () => {
    expect(
      await creditReward({
        userId: newUid(),
        eventId: `evt-${randomUUID()}`,
        amount: 40,
        timestampMillis: Date.now(),
        signature: 'verified',
      }),
    ).toBe('unknown_user');
  });
});

beforeAll(() => {
  // Fail loudly rather than silently writing into a real project.
  expect(process.env['FIRESTORE_EMULATOR_HOST']).toBeDefined();
});
