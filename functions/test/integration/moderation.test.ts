/**
 * The emulator-backed half of `nameReports.ts` (AR-4 / T12, post-P17).
 *
 * Same shape as `pipeline.test.ts`/`social.test.ts`: real Firestore,
 * `applyNameReport` driven directly rather than through the trigger
 * transport — the trigger WIRING cannot be registered in this sandbox (see
 * that file's header and `functions/README.md`), so this proves the body a
 * real `onDocumentCreated` invocation would call.
 */

import { randomUUID } from 'node:crypto';

import { getApps, initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { applyNameReport } from '../../src/nameReports';

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

const createdUsers: string[] = [];
afterAll(async () => {
  await Promise.all(
    createdUsers.map((uid) => firestore.recursiveDelete(firestore.doc(`users/${uid}`))),
  );
});

beforeAll(() => {
  expect(process.env['FIRESTORE_EMULATOR_HOST']).toBeDefined();
});

describe('applyNameReport', () => {
  it('does not blank the name on the first two distinct reports', async () => {
    const reported = newUid();
    createdUsers.push(reported);
    await firestore.doc(`users/${reported}`).set({ displayName: 'Offensive Name' });

    await applyNameReport(reported, newUid());
    await applyNameReport(reported, newUid());

    const data = (await firestore.doc(`users/${reported}`).get()).data();
    expect(data?.['displayName']).toBe('Offensive Name');
    expect(
      (data?.['moderation'] as Record<string, unknown> | undefined)?.['nameReporters'],
    ).toHaveLength(2);
  });

  it('blanks the name on the third DISTINCT report', async () => {
    const reported = newUid();
    createdUsers.push(reported);
    await firestore.doc(`users/${reported}`).set({ displayName: 'Offensive Name' });

    await applyNameReport(reported, newUid());
    await applyNameReport(reported, newUid());
    const third = await applyNameReport(reported, newUid());

    expect(third.blanked).toBe(true);
    const data = (await firestore.doc(`users/${reported}`).get()).data();
    expect(data?.['displayName']).toBeNull();
  });

  it('the SAME reporter reporting three times never blanks anything', async () => {
    const reported = newUid();
    createdUsers.push(reported);
    await firestore.doc(`users/${reported}`).set({ displayName: 'Offensive Name' });
    const reporter = newUid();

    await applyNameReport(reported, reporter);
    await applyNameReport(reported, reporter);
    const third = await applyNameReport(reported, reporter);

    expect(third.blanked).toBe(false);
    const data = (await firestore.doc(`users/${reported}`).get()).data();
    expect(data?.['displayName']).toBe('Offensive Name');
    expect(
      (data?.['moderation'] as Record<string, unknown> | undefined)?.['nameReporters'],
    ).toHaveLength(1);
  });

  it('writes a moderation record for every report, including ones that do not blank', async () => {
    const reported = newUid();
    createdUsers.push(reported);
    await firestore.doc(`users/${reported}`).set({ displayName: 'Offensive Name' });

    await applyNameReport(reported, newUid());

    const flags = await firestore
      .collection('moderation')
      .doc(reported)
      .collection('flags')
      .get();
    expect(flags.size).toBe(1);
    expect(flags.docs[0]?.data()['kind']).toBe('name_report');
    expect(flags.docs[0]?.data()['blanked']).toBe(false);
  });

  it('a report against an already-blank name records evidence but blanks nothing', async () => {
    const reported = newUid();
    createdUsers.push(reported);
    await firestore.doc(`users/${reported}`).set({ displayName: null });

    const result = await applyNameReport(reported, newUid());

    expect(result.blanked).toBe(false);
    const data = (await firestore.doc(`users/${reported}`).get()).data();
    expect(data?.['displayName']).toBeNull();
  });
});
