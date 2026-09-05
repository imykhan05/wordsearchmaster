/**
 * The emulator-backed half of `streakReminders.ts`: the query, the skip
 * rules and the write-back, against a real Firestore. The actual FCM
 * transport is faked — see that file's header for why there is no way to
 * exercise a real send in this sandbox (no FCM emulator, no service account).
 */

import { randomUUID } from 'node:crypto';

import { getApps, initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import {
  sendDueStreakReminders,
  type StreakReminderSender,
} from '../../src/streakReminders';

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

class FakeSender implements StreakReminderSender {
  readonly sent: { token: string; title: string; body: string }[] = [];
  private readonly failFor: Set<string>;

  constructor(failFor: readonly string[] = []) {
    this.failFor = new Set(failFor);
  }

  send(token: string, message: { title: string; body: string }): Promise<void> {
    if (this.failFor.has(token)) {
      return Promise.reject(new Error('simulated unregistered token'));
    }
    this.sent.push({ token, title: message.title, body: message.body });
    return Promise.resolve();
  }
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

describe('sendDueStreakReminders', () => {
  it('sends to an account whose streak lapses today, in its own language', async () => {
    const uid = newUid();
    createdUsers.push(uid);
    await firestore.doc(`users/${uid}`).set({
      fcmToken: `token-${uid}`,
      language: 'ur',
      stats: { engagementStreak: { current: 5, lastDay: '2026-09-04' } },
    });

    const sender = new FakeSender();
    const sent = await sendDueStreakReminders('2026-09-05', sender);

    expect(sent).toBe(1);
    expect(sender.sent).toHaveLength(1);
    expect(sender.sent[0]?.token).toBe(`token-${uid}`);
    // Urdu copy, not the English default — proves the language lookup runs.
    expect(sender.sent[0]?.title).toContain('لڑی');

    const data = (await firestore.doc(`users/${uid}`).get()).data();
    expect(
      (data?.['notifications'] as Record<string, unknown> | undefined)?.[
        'lastPushSentDay'
      ],
    ).toBe('2026-09-05');
  });

  it('never sends a second push the same day, even run twice', async () => {
    const uid = newUid();
    createdUsers.push(uid);
    await firestore.doc(`users/${uid}`).set({
      fcmToken: `token-${uid}`,
      language: 'en',
      stats: { engagementStreak: { current: 2, lastDay: '2026-09-04' } },
    });

    const sender = new FakeSender();
    await sendDueStreakReminders('2026-09-05', sender);
    const secondRunSent = await sendDueStreakReminders('2026-09-05', sender);

    expect(secondRunSent).toBe(0);
    expect(sender.sent).toHaveLength(1);
  });

  it('skips an account with no streak to lose', async () => {
    const uid = newUid();
    createdUsers.push(uid);
    await firestore.doc(`users/${uid}`).set({
      fcmToken: `token-${uid}`,
      language: 'en',
      stats: { engagementStreak: { current: 0, lastDay: null } },
    });

    const sender = new FakeSender();
    const sent = await sendDueStreakReminders('2026-09-05', sender);

    expect(sent).toBe(0);
    expect(sender.sent).toHaveLength(0);
  });

  it('skips an account with no fcmToken registered', async () => {
    const uid = newUid();
    createdUsers.push(uid);
    await firestore.doc(`users/${uid}`).set({
      language: 'en',
      stats: { engagementStreak: { current: 4, lastDay: '2026-09-04' } },
    });

    const sender = new FakeSender();
    const sent = await sendDueStreakReminders('2026-09-05', sender);

    expect(sent).toBe(0);
  });

  it('a send failure (stale token) does not write lastPushSentDay, and does not stop the run', async () => {
    const failing = newUid();
    const healthy = newUid();
    createdUsers.push(failing, healthy);
    await firestore.doc(`users/${failing}`).set({
      fcmToken: `token-${failing}`,
      language: 'en',
      stats: { engagementStreak: { current: 1, lastDay: '2026-09-04' } },
    });
    await firestore.doc(`users/${healthy}`).set({
      fcmToken: `token-${healthy}`,
      language: 'en',
      stats: { engagementStreak: { current: 1, lastDay: '2026-09-04' } },
    });

    const sender = new FakeSender([`token-${failing}`]);
    const sent = await sendDueStreakReminders('2026-09-05', sender);

    expect(sent).toBe(1);
    const failingData = (await firestore.doc(`users/${failing}`).get()).data();
    expect(failingData?.['notifications']).toBeUndefined();
    const healthyData = (await firestore.doc(`users/${healthy}`).get()).data();
    expect(
      (healthyData?.['notifications'] as Record<string, unknown> | undefined)?.[
        'lastPushSentDay'
      ],
    ).toBe('2026-09-05');
  });
});
