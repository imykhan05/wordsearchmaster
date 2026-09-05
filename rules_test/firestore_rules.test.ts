/**
 * Security-rules suite for `firestore.rules` (Ch08 / P15).
 *
 * ---------------------------------------------------------------------------
 * EVERY RULE GETS AN ALLOW TEST *AND* A DENY TEST, AND THE ALLOW HALF IS THE
 * ONE THAT ACTUALLY EARNS ITS KEEP
 *
 * A rules file that denies everything passes every deny test ever written, and
 * ships an app where nothing works. The deny tests say the door is locked; the
 * allow tests say it is a door. `describe` blocks below are paired for that
 * reason, and the pairing is the acceptance criterion, not a stylistic choice.
 *
 * ---------------------------------------------------------------------------
 * THREE THINGS THAT MAKE A RULES TEST PASS FOR THE WRONG REASON
 *
 *  1. `updateDoc` ON A DOCUMENT THAT DOES NOT EXIST fails with `not-found`,
 *     never `permission-denied` — so `assertFails` goes green against a rules
 *     file that would have allowed the write. Every update and delete case
 *     here therefore SEEDS its document first, through
 *     `withSecurityRulesDisabled`, which is also the only honest way to create
 *     the server-authored fields (`totals`, `progress`) a client must not be
 *     able to touch.
 *  2. `getDoc` ON A MISSING DOCUMENT SUCCEEDS when the rule allows it, and
 *     returns an empty snapshot. A read test that only checks "no error" is
 *     really checking the rule; a read test that checks the DATA needs the
 *     document to be there. Both shapes appear below, deliberately.
 *  3. `get` AND `list` ARE DIFFERENT OPERATIONS. `list` is evaluated against a
 *     QUERY, before any document is fetched, so a rule that reads as
 *     "owner only" silently governs "can anyone enumerate this collection".
 *     `/users` is tested for both.
 *
 * Run with `npm run test:rules`, which wraps this in
 * `firebase emulators:exec --only firestore`. The project id is
 * `demo-wsm-rules`: the `demo-` prefix tells the Firebase tooling this project
 * is emulator-only, so nothing here can reach — or need credentials for — a
 * real Firebase project.
 */

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  type RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  addDoc,
  collection,
  deleteDoc,
  deleteField,
  doc,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
  type Firestore,
} from 'firebase/firestore';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), '..');

const ALICE = 'alice';
const MALLORY = 'mallory';

let testEnv: RulesTestEnvironment;

/** The signed-in owner of every `alice` document below. */
function asAlice(): Firestore {
  return testEnv.authenticatedContext(ALICE).firestore() as unknown as Firestore;
}

/** A different signed-in player. Guest-first means this is the common case. */
function asMallory(): Firestore {
  return testEnv.authenticatedContext(MALLORY).firestore() as unknown as Firestore;
}

/** No auth at all — the state before bootstrap step 4 completes. */
function asStranger(): Firestore {
  return testEnv.unauthenticatedContext().firestore() as unknown as Firestore;
}

/**
 * The Admin SDK's view: rules do not apply.
 *
 * Used for two different jobs, and the difference matters. As a FIXTURE it
 * writes the server-authored state a client must not be able to reach. As an
 * ASSERTION it is the allow half of a rule whose client answer is always
 * "no" — `deleteAccount` really can delete a user document, and a moderator
 * really can read `moderation/`; those paths exist, and a test suite that only
 * proved the client cannot reach them would not have shown that anyone can.
 */
async function asServer(work: (db: Firestore) => Promise<unknown>): Promise<void> {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await work(context.firestore() as unknown as Firestore);
  });
}

/** A realistic `users/{uid}`: two client fields, the rest server-authored. */
async function seedUser(uid = ALICE): Promise<void> {
  await asServer((db) =>
    setDoc(doc(db, 'users', uid), {
      displayName: 'Ayesha',
      photoUrl: 'https://example.test/a.png',
      updatedAt: 1_756_600_000_000,
      totals: { global: 1560, en: 1560 },
      progress: { en: { highestLevel: 12 } },
      suspiciousCount: 0,
    }),
  );
}

beforeAll(async () => {
  if (process.env['FIRESTORE_EMULATOR_HOST'] === undefined) {
    throw new Error(
      'The Firestore emulator is not running. Use `npm run test:rules`.',
    );
  }
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-wsm-rules',
    firestore: {
      // The REAL file that gets deployed. Loading a copy, or a subset, would
      // make every assertion below a statement about a file nobody ships.
      rules: readFileSync(join(repoRoot, 'firestore.rules'), 'utf8'),
    },
  });
});

afterAll(async () => {
  await testEnv?.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

// ===========================================================================
// /users/{uid} — reading
// ===========================================================================

describe('users/{uid} · get', () => {
  it('ALLOW: the owner reads their own document', async () => {
    await seedUser();
    const snapshot = await assertSucceeds(getDoc(doc(asAlice(), 'users', ALICE)));
    // Asserting the DATA, not just the absence of an error: a rule that
    // allowed the read of a document that was never there would pass a
    // no-error check.
    expect(snapshot.data()?.['displayName']).toBe('Ayesha');
  });

  it('DENY: an unauthenticated caller reads it', async () => {
    await seedUser();
    await assertFails(getDoc(doc(asStranger(), 'users', ALICE)));
  });

  it('DENY: a different signed-in player reads it', async () => {
    // Guest-first auth (Ch02) means everyone is signed in, so "signed in" is
    // never the question — "signed in as whom" is.
    await seedUser();
    await assertFails(getDoc(doc(asMallory(), 'users', ALICE)));
  });
});

describe('users · list', () => {
  it('DENY: the owner enumerates the user collection', async () => {
    await seedUser();
    await assertFails(getDocs(collection(asAlice(), 'users')));
  });

  it('DENY: a query narrowed to their own uid is still a list', async () => {
    // The tempting workaround, and the reason `allow list: if false` is
    // spelled out rather than left implicit: a filtered query is still an
    // enumeration, and the engine evaluates it before fetching anything.
    await seedUser();
    await assertFails(
      getDocs(query(collection(asAlice(), 'users'), where('displayName', '==', 'Ayesha'))),
    );
  });

  it('ALLOW: the same owner still reads that document by name', async () => {
    // The allow half of the same rule: refusing `list` must not have cost the
    // client the `get` it actually needs.
    await seedUser();
    await assertSucceeds(getDoc(doc(asAlice(), 'users', ALICE)));
  });
});

// ===========================================================================
// /users/{uid} — creating
// ===========================================================================

describe('users/{uid} · create', () => {
  it('ALLOW: the owner creates their document with only profile fields', async () => {
    await assertSucceeds(
      setDoc(doc(asAlice(), 'users', ALICE), {
        displayName: 'Ayesha',
        photoUrl: 'https://example.test/a.png',
        updatedAt: 1_756_600_000_000,
      }),
    );
  });

  it('ALLOW: a create carrying only a display name', async () => {
    await assertSucceeds(
      setDoc(doc(asAlice(), 'users', ALICE), { displayName: 'Ayesha' }),
    );
  });

  it('DENY: a create that smuggles in an extra field', async () => {
    // The whole point of `hasOnly` on create. Without it a client mints its
    // own opening balance on the way in, and every later rule that guards
    // `coins` guards a number that was already wrong.
    await assertFails(
      setDoc(doc(asAlice(), 'users', ALICE), { displayName: 'Ayesha', coins: 999_999 }),
    );
  });

  it('DENY: a create that smuggles in a server-authored total', async () => {
    await assertFails(
      setDoc(doc(asAlice(), 'users', ALICE), {
        displayName: 'Ayesha',
        totals: { global: 999_999 },
      }),
    );
  });

  it("DENY: creating someone else's document", async () => {
    await assertFails(
      setDoc(doc(asMallory(), 'users', ALICE), { displayName: 'Not Ayesha' }),
    );
  });

  it('DENY: an unauthenticated create', async () => {
    await assertFails(
      setDoc(doc(asStranger(), 'users', ALICE), { displayName: 'Ayesha' }),
    );
  });
});

// ===========================================================================
// /users/{uid} — updating
// ===========================================================================

describe('users/{uid} · update', () => {
  beforeEach(() => seedUser());

  it('ALLOW: the owner updates displayName', async () => {
    await assertSucceeds(
      updateDoc(doc(asAlice(), 'users', ALICE), { displayName: 'Ayesha K.' }),
    );
  });

  it('ALLOW: the owner updates photoUrl and updatedAt together', async () => {
    await assertSucceeds(
      updateDoc(doc(asAlice(), 'users', ALICE), {
        photoUrl: 'https://example.test/b.png',
        updatedAt: 1_756_600_000_001,
      }),
    );
  });

  it('ALLOW: clearing the display name to null', async () => {
    // `updateDoc(ref, {displayName: null})` WRITES a null; it does not remove
    // the key. So `is string` alone would refuse a clear, and the refusal
    // would reach the player as a silent permission error on a screen that
    // must never show one.
    await assertSucceeds(
      updateDoc(doc(asAlice(), 'users', ALICE), { displayName: null }),
    );
  });

  it('ALLOW: removing the display name field outright', async () => {
    // The other shape of the same intent, which takes the different branch:
    // `deleteField()` removes the key, so `'displayName' in
    // request.resource.data` is false.
    await assertSucceeds(
      updateDoc(doc(asAlice(), 'users', ALICE), { displayName: deleteField() }),
    );
  });

  it('DENY: updating a field outside the allowed diff set', async () => {
    await assertFails(
      updateDoc(doc(asAlice(), 'users', ALICE), { totals: { global: 999_999 } }),
    );
  });

  it('DENY: updating an allowed field AND a forbidden one in the same write', async () => {
    // `hasOnly` has to reject the whole write, not just the offending key.
    await assertFails(
      updateDoc(doc(asAlice(), 'users', ALICE), {
        displayName: 'Ayesha K.',
        suspiciousCount: 7,
      }),
    );
  });

  it('ALLOW (documented, not a hole): restating a server field at its current value', async () => {
    // `affectedKeys()` is a VALUE diff, not a list of the keys the client
    // mentioned, so a write that includes `suspiciousCount` at the value it
    // already holds is not "affecting" it and passes. That is correct — it
    // changes nothing — but it is not what the rule looks like it says, and
    // there is no v2 primitive for "which fields did the client mention"
    // (`writeFields` was v1 and is gone). Pinned here so a future reader meets
    // this behaviour as a documented property rather than as a suspected bug,
    // and so a change that made it MATTER would fail a test.
    await assertSucceeds(
      updateDoc(doc(asAlice(), 'users', ALICE), {
        displayName: 'Ayesha K.',
        suspiciousCount: 0, // the seeded value, unchanged
      }),
    );
    // The guarantee that does hold: the value cannot be MOVED.
    await assertFails(
      updateDoc(doc(asAlice(), 'users', ALICE), { suspiciousCount: 1 }),
    );
  });

  it('DENY: adding a brand-new field the rules never named', async () => {
    await assertFails(updateDoc(doc(asAlice(), 'users', ALICE), { coins: 999_999 }));
  });

  it("DENY: a full set() that would drop the server's fields", async () => {
    // `affectedKeys()` covers REMOVALS, which is why a client cannot launder
    // an edit into a rewrite.
    await assertFails(
      setDoc(doc(asAlice(), 'users', ALICE), { displayName: 'Ayesha' }),
    );
  });

  it("DENY: another player edits Ayesha's profile", async () => {
    await assertFails(
      updateDoc(doc(asMallory(), 'users', ALICE), { displayName: 'pwned' }),
    );
  });
});

describe('users/{uid} · displayName length', () => {
  beforeEach(() => seedUser());

  const exactly24 = 'a'.repeat(24);
  const twentyFive = 'a'.repeat(25);

  it('ALLOW: exactly 24 characters, on update', async () => {
    await assertSucceeds(
      updateDoc(doc(asAlice(), 'users', ALICE), { displayName: exactly24 }),
    );
  });

  it('DENY: 25 characters, on update', async () => {
    await assertFails(
      updateDoc(doc(asAlice(), 'users', ALICE), { displayName: twentyFive }),
    );
  });

  it('DENY: 25 characters, on CREATE as well', async () => {
    // Checking length on only one of create/update is the classic hole: a
    // client that cannot update a long name simply creates the document with
    // one, and the leaderboard renders it either way.
    await testEnv.clearFirestore();
    await assertFails(
      setDoc(doc(asAlice(), 'users', ALICE), { displayName: twentyFive }),
    );
  });

  it('ALLOW: exactly 24 characters, on create', async () => {
    await testEnv.clearFirestore();
    await assertSucceeds(
      setDoc(doc(asAlice(), 'users', ALICE), { displayName: exactly24 }),
    );
  });

  it('DENY: a displayName that is not a string at all', async () => {
    await assertFails(
      updateDoc(doc(asAlice(), 'users', ALICE), { displayName: 12_345 }),
    );
  });

  it('DENY: an absurdly long photoUrl', async () => {
    await assertFails(
      updateDoc(doc(asAlice(), 'users', ALICE), {
        photoUrl: `https://example.test/${'x'.repeat(600)}`,
      }),
    );
  });
});

// ===========================================================================
// /users/{uid} — fcmToken and language (post-P17 re-engagement notifications)
// ===========================================================================

describe('users/{uid} · fcmToken and language', () => {
  beforeEach(() => seedUser());

  it('ALLOW: the owner registers an fcmToken', async () => {
    await assertSucceeds(
      updateDoc(doc(asAlice(), 'users', ALICE), { fcmToken: 'a-real-looking-token' }),
    );
  });

  it('ALLOW: the owner sets their language preference', async () => {
    await assertSucceeds(updateDoc(doc(asAlice(), 'users', ALICE), { language: 'ur' }));
  });

  it('ALLOW: both together, the shape the registration write actually sends', async () => {
    await assertSucceeds(
      updateDoc(doc(asAlice(), 'users', ALICE), {
        fcmToken: 'a-real-looking-token',
        language: 'hi',
      }),
    );
  });

  it('ALLOW: clearing fcmToken to null', async () => {
    await assertSucceeds(updateDoc(doc(asAlice(), 'users', ALICE), { fcmToken: null }));
  });

  it('DENY: a language outside the three real ones', async () => {
    await assertFails(updateDoc(doc(asAlice(), 'users', ALICE), { language: 'fr' }));
  });

  it('DENY: an absurdly long fcmToken', async () => {
    await assertFails(
      updateDoc(doc(asAlice(), 'users', ALICE), { fcmToken: 'x'.repeat(5000) }),
    );
  });

  it('DENY: another player registers a token on Ayesha\'s document', async () => {
    await assertFails(
      updateDoc(doc(asMallory(), 'users', ALICE), { fcmToken: 'stolen' }),
    );
  });

  it('DENY: setting fcmToken alongside a server-authored field', async () => {
    await assertFails(
      updateDoc(doc(asAlice(), 'users', ALICE), {
        fcmToken: 'a-real-looking-token',
        suspiciousCount: 7,
      }),
    );
  });

  it('ALLOW: registering a token on CREATE, before any level has ever synced', async () => {
    // A player can consent to notifications before their first submission
    // creates `users/{uid}` any other way — the registration write must not
    // depend on a score having landed first.
    await testEnv.clearFirestore();
    await assertSucceeds(
      setDoc(doc(asAlice(), 'users', ALICE), {
        fcmToken: 'a-real-looking-token',
        language: 'en',
      }),
    );
  });
});

// ===========================================================================
// /users/{uid} — deleting
// ===========================================================================

describe('users/{uid} · delete', () => {
  beforeEach(() => seedUser());

  it('DENY: the owner deletes their own document', async () => {
    // Deletion is `deleteAccount`'s job (P14). A client-side delete would
    // leave the leaderboard entries, the moderation trail and the auth record
    // behind while looking, to the player, like the deletion Play policy
    // promises.
    await assertFails(deleteDoc(doc(asAlice(), 'users', ALICE)));
  });

  it('DENY: another player deletes it', async () => {
    await assertFails(deleteDoc(doc(asMallory(), 'users', ALICE)));
  });

  it('ALLOW: the server path that deleteAccount uses still works', async () => {
    // The allow half. Without this the suite would prove the door is locked
    // without ever showing there is a way through it.
    await asServer(async (db) => {
      await deleteDoc(doc(db, 'users', ALICE));
      expect((await getDoc(doc(db, 'users', ALICE))).exists()).toBe(false);
    });
  });
});

// ===========================================================================
// /users/{uid}/scores — the outputs of submitScore
// ===========================================================================

describe('users/{uid}/scores', () => {
  beforeEach(async () => {
    await seedUser();
    await asServer((db) =>
      setDoc(doc(db, 'users', ALICE, 'scores', 'level_en_1'), {
        kind: 'level',
        lang: 'en',
        level: 1,
        score: 156,
        stars: 3,
        suspicious: false,
      }),
    );
  });

  it('ALLOW: the owner reads their own score document', async () => {
    const snapshot = await assertSucceeds(
      getDoc(doc(asAlice(), 'users', ALICE, 'scores', 'level_en_1')),
    );
    expect(snapshot.data()?.['score']).toBe(156);
  });

  it('ALLOW: the owner lists their own scores', async () => {
    const snapshot = await assertSucceeds(
      getDocs(collection(asAlice(), 'users', ALICE, 'scores')),
    );
    expect(snapshot.size).toBe(1);
  });

  it('DENY: the owner writes a score', async () => {
    // A client that could write here would not need to cheat `submitScore`'s
    // pipeline — it could skip it entirely.
    await assertFails(
      setDoc(doc(asAlice(), 'users', ALICE, 'scores', 'level_en_1'), {
        score: 999_999,
      }),
    );
  });

  it('DENY: the owner edits one field of an existing score', async () => {
    await assertFails(
      updateDoc(doc(asAlice(), 'users', ALICE, 'scores', 'level_en_1'), {
        score: 999_999,
      }),
    );
  });

  it('DENY: the owner deletes a score', async () => {
    // Deleting is a write too, and a flagged score a player could delete is
    // not evidence of anything.
    await assertFails(deleteDoc(doc(asAlice(), 'users', ALICE, 'scores', 'level_en_1')));
  });

  it('DENY: the owner creates a score for a level they never played', async () => {
    await assertFails(
      setDoc(doc(asAlice(), 'users', ALICE, 'scores', 'level_en_300'), {
        score: 999_999,
      }),
    );
  });

  it("DENY: another player reads Ayesha's scores", async () => {
    await assertFails(getDoc(doc(asMallory(), 'users', ALICE, 'scores', 'level_en_1')));
  });

  it('DENY: an unauthenticated read', async () => {
    await assertFails(getDoc(doc(asStranger(), 'users', ALICE, 'scores', 'level_en_1')));
  });
});

describe('users/{uid}/nonces and coinGrants', () => {
  beforeEach(async () => {
    await seedUser();
    await asServer(async (db) => {
      await setDoc(doc(db, 'users', ALICE, 'nonces', 'n1'), { scoreId: 'level_en_1' });
      await setDoc(doc(db, 'users', ALICE, 'coinGrants', 'evt1'), { coins: 40 });
    });
  });

  it('ALLOW: the owner reads their replay guards and coin grants', async () => {
    await assertSucceeds(getDoc(doc(asAlice(), 'users', ALICE, 'nonces', 'n1')));
    await assertSucceeds(getDoc(doc(asAlice(), 'users', ALICE, 'coinGrants', 'evt1')));
  });

  it('DENY: the owner writes a nonce, which would burn a replay guard', async () => {
    await assertFails(
      setDoc(doc(asAlice(), 'users', ALICE, 'nonces', 'n2'), { scoreId: 'x' }),
    );
  });

  it('DENY: the owner mints their own coin grant', async () => {
    // The rules half of "the client must never be able to grant itself a
    // reward" — `grantRewardedReward` is the only writer.
    await assertFails(
      setDoc(doc(asAlice(), 'users', ALICE, 'coinGrants', 'evt2'), { coins: 999_999 }),
    );
  });

  it("DENY: another player reads Ayesha's coin grants", async () => {
    await assertFails(getDoc(doc(asMallory(), 'users', ALICE, 'coinGrants', 'evt1')));
  });
});

// ===========================================================================
// /leaderboards — the only publicly readable collection
// ===========================================================================

describe('leaderboards', () => {
  beforeEach(async () => {
    await asServer(async (db) => {
      await setDoc(doc(db, 'leaderboards', 'global'), { updatedAt: 1 });
      await setDoc(doc(db, 'leaderboards', 'global', 'entries', ALICE), {
        uid: ALICE,
        displayName: 'Ayesha',
        photoUrl: null,
        score: 1560,
        updatedAt: 1,
      });
      await setDoc(doc(db, 'leaderboards', 'global', 'entries', MALLORY), {
        uid: MALLORY,
        displayName: 'Mallory',
        photoUrl: null,
        score: 20,
        updatedAt: 1,
      });
    });
  });

  it('ALLOW: a signed-in player reads an entry', async () => {
    const snapshot = await assertSucceeds(
      getDoc(doc(asAlice(), 'leaderboards', 'global', 'entries', ALICE)),
    );
    expect(snapshot.data()?.['score']).toBe(1560);
  });

  it("ALLOW: a signed-in player reads SOMEONE ELSE'S entry", async () => {
    // A leaderboard nobody else can read is not a leaderboard.
    await assertSucceeds(
      getDoc(doc(asMallory(), 'leaderboards', 'global', 'entries', ALICE)),
    );
  });

  it('ALLOW: a signed-in player lists a board', async () => {
    const snapshot = await assertSucceeds(
      getDocs(collection(asAlice(), 'leaderboards', 'global', 'entries')),
    );
    expect(snapshot.size).toBe(2);
  });

  it('ALLOW: an anonymous guest reads a board', async () => {
    // `authenticatedContext` with no provider is exactly the anonymous sign-in
    // bootstrap step 4 performs, and Ch02 promises a guest can play — which
    // includes seeing what they are playing for.
    await assertSucceeds(
      getDocs(collection(testEnv.authenticatedContext('guest-uid').firestore() as unknown as Firestore, 'leaderboards', 'global', 'entries')),
    );
  });

  it('DENY: an unauthenticated caller reads a board', async () => {
    await assertFails(
      getDoc(doc(asStranger(), 'leaderboards', 'global', 'entries', ALICE)),
    );
  });

  it('DENY: a player writes their own entry', async () => {
    await assertFails(
      setDoc(doc(asAlice(), 'leaderboards', 'global', 'entries', ALICE), {
        uid: ALICE,
        displayName: 'Ayesha',
        photoUrl: null,
        score: 999_999,
        updatedAt: 2,
      }),
    );
  });

  it('DENY: a player edits the score on their own entry', async () => {
    await assertFails(
      updateDoc(doc(asAlice(), 'leaderboards', 'global', 'entries', ALICE), {
        score: 999_999,
      }),
    );
  });

  it("DENY: a player deletes a rival's entry", async () => {
    await assertFails(
      deleteDoc(doc(asAlice(), 'leaderboards', 'global', 'entries', MALLORY)),
    );
  });

  it('DENY: a player writes the board document itself', async () => {
    await assertFails(setDoc(doc(asAlice(), 'leaderboards', 'global'), { hacked: true }));
  });

  it('DENY: a player invents a new board', async () => {
    await assertFails(
      setDoc(doc(asAlice(), 'leaderboards', 'weekly_2026-W36', 'entries', ALICE), {
        uid: ALICE,
        score: 999_999,
      }),
    );
  });

  it('ALLOW: the server path that updateLeaderboards uses still works', async () => {
    await asServer(async (db) => {
      await setDoc(doc(db, 'leaderboards', 'daily_2026-08-31', 'entries', ALICE), {
        uid: ALICE,
        displayName: 'Ayesha',
        photoUrl: null,
        score: 400,
        updatedAt: 3,
      });
    });
    await assertSucceeds(
      getDoc(doc(asAlice(), 'leaderboards', 'daily_2026-08-31', 'entries', ALICE)),
    );
  });
});

// ===========================================================================
// /moderation and /rewardCallbacks — invisible to every client
// ===========================================================================

describe('moderation and rewardCallbacks', () => {
  beforeEach(async () => {
    await asServer(async (db) => {
      await setDoc(doc(db, 'moderation', ALICE, 'flags', 'f1'), {
        uid: ALICE,
        flags: ['progression_gap'],
      });
      await setDoc(doc(db, 'rewardCallbacks', 'evt1'), { uid: ALICE, coins: 40 });
    });
  });

  it('DENY: the FLAGGED player reads their own moderation record', async () => {
    // The one rule where the owner is exactly the person who must not read it:
    // someone who can see `moderation/` learns which check caught them, and a
    // cheater who knows that iterates until it does not.
    await assertFails(getDoc(doc(asAlice(), 'moderation', ALICE, 'flags', 'f1')));
  });

  it('DENY: the flagged player deletes the evidence', async () => {
    await assertFails(deleteDoc(doc(asAlice(), 'moderation', ALICE, 'flags', 'f1')));
  });

  it('DENY: any client reads the ad-network callback log', async () => {
    await assertFails(getDoc(doc(asAlice(), 'rewardCallbacks', 'evt1')));
  });

  it('DENY: a client forges a reward callback record', async () => {
    await assertFails(
      setDoc(doc(asAlice(), 'rewardCallbacks', 'evt2'), { uid: ALICE, coins: 999_999 }),
    );
  });

  it('ALLOW: a moderator reading through the Admin SDK still can', async () => {
    await asServer(async (db) => {
      const snapshot = await getDoc(doc(db, 'moderation', ALICE, 'flags', 'f1'));
      expect(snapshot.data()?.['flags']).toEqual(['progression_gap']);
    });
  });
});

// ===========================================================================
// Undeclared paths
// ===========================================================================

describe('paths the rules never named', () => {
  it('DENY: a write to a top-level collection nobody declared', async () => {
    await assertFails(setDoc(doc(asAlice(), 'hackers', 'x'), { anything: true }));
  });

  it('DENY: a read of a top-level collection nobody declared', async () => {
    await assertFails(getDoc(doc(asAlice(), 'hackers', 'x')));
  });

  it('DENY: a write to an undeclared SUBcollection of their own document', async () => {
    // The likelier mistake than a stray top-level collection: a path that
    // sits under a document the player does own, and therefore looks like it
    // might inherit its permissions. It does not — rules do not cascade.
    await seedUser();
    await assertFails(
      setDoc(doc(asAlice(), 'users', ALICE, 'secrets', 'x'), { coins: 999_999 }),
    );
  });

  it('DENY: a deeply nested undeclared path', async () => {
    await assertFails(
      setDoc(doc(asAlice(), 'users', ALICE, 'a', 'b', 'c', 'd'), { x: 1 }),
    );
  });

  it('ALLOW: the same client writing the one path it IS allowed', async () => {
    // The contrast that makes the four denies above mean something: this
    // client is not simply blocked from everything.
    await assertSucceeds(
      setDoc(doc(asAlice(), 'users', ALICE), { displayName: 'Ayesha' }),
    );
  });
});

// ===========================================================================
// users/{uid}/friends — accepted friendships only (P17)
// ===========================================================================

describe('users/{uid}/friends', () => {
  beforeEach(async () => {
    await seedUser();
    await asServer((db) =>
      setDoc(doc(db, 'users', ALICE, 'friends', MALLORY), {
        uid: MALLORY,
        displayName: 'Mallory',
        photoUrl: null,
        since: 1,
      }),
    );
  });

  it('ALLOW: the owner reads their own friend list', async () => {
    const snapshot = await assertSucceeds(
      getDocs(collection(asAlice(), 'users', ALICE, 'friends')),
    );
    expect(snapshot.size).toBe(1);
  });

  it('ALLOW: the owner reads one friend by uid', async () => {
    const snapshot = await assertSucceeds(
      getDoc(doc(asAlice(), 'users', ALICE, 'friends', MALLORY)),
    );
    expect(snapshot.data()?.['displayName']).toBe('Mallory');
  });

  it("DENY: another player reads Ayesha's friend list", async () => {
    // A friend list is as personal as a contact book — not even a mutual
    // friend gets to read the OTHER side's collection through this path.
    await assertFails(getDocs(collection(asMallory(), 'users', ALICE, 'friends')));
  });

  it('DENY: an unauthenticated read', async () => {
    await assertFails(getDoc(doc(asStranger(), 'users', ALICE, 'friends', MALLORY)));
  });

  it('DENY: the owner adds a friend directly, bypassing redeemInviteCode', async () => {
    // A client that could write its own side could invent a one-directional
    // "friendship" the other account never agreed to — the whole reason
    // redemption writes both sides in one server transaction.
    await assertFails(
      setDoc(doc(asAlice(), 'users', ALICE, 'friends', 'stranger-uid'), {
        uid: 'stranger-uid',
        displayName: 'Nobody',
        photoUrl: null,
        since: 2,
      }),
    );
  });

  it('DENY: the owner removes a friend directly', async () => {
    await assertFails(deleteDoc(doc(asAlice(), 'users', ALICE, 'friends', MALLORY)));
  });

  it('ALLOW: the server path redeemInviteCode uses still works', async () => {
    await asServer(async (db) => {
      await setDoc(doc(db, 'users', ALICE, 'friends', 'new-friend'), {
        uid: 'new-friend',
        displayName: 'New',
        photoUrl: null,
        since: 3,
      });
      const snapshot = await getDoc(doc(db, 'users', ALICE, 'friends', 'new-friend'));
      expect(snapshot.exists()).toBe(true);
    });
  });
});

// ===========================================================================
// inviteCodes/{code} — the code -> owner map, invisible to every client (P17)
// ===========================================================================

describe('inviteCodes', () => {
  beforeEach(async () => {
    await asServer((db) => setDoc(doc(db, 'inviteCodes', 'ABCD1234'), { uid: ALICE }));
  });

  it("DENY: the code's OWNER reads it", async () => {
    // Reading it back would let a client enumerate the collection instead of
    // ever being handed a code the intended way — through the callable.
    await assertFails(getDoc(doc(asAlice(), 'inviteCodes', 'ABCD1234')));
  });

  it('DENY: a stranger reads it', async () => {
    await assertFails(getDoc(doc(asMallory(), 'inviteCodes', 'ABCD1234')));
  });

  it('DENY: a client mints their own code, bypassing rate limits and collision checks', async () => {
    await assertFails(
      setDoc(doc(asAlice(), 'inviteCodes', 'FORGED01'), { uid: ALICE }),
    );
  });

  it('DENY: a client overwrites an existing code to steal it', async () => {
    await assertFails(
      setDoc(doc(asMallory(), 'inviteCodes', 'ABCD1234'), { uid: MALLORY }),
    );
  });

  it('ALLOW: the server path createInviteCode/redeemInviteCode use still works', async () => {
    await asServer(async (db) => {
      const snapshot = await getDoc(doc(db, 'inviteCodes', 'ABCD1234'));
      expect(snapshot.data()?.['uid']).toBe(ALICE);
    });
  });
});

// ===========================================================================
// nameReports/{reportId} — client CREATE only, invisible to every reader
// (AR-4 / T12, post-P17)
// ===========================================================================

describe('nameReports · create', () => {
  it('ALLOW: a signed-in player reports a name they saw on a leaderboard', async () => {
    await assertSucceeds(
      addDoc(collection(asAlice(), 'nameReports'), {
        reportedUid: MALLORY,
        reporterUid: ALICE,
        createdAt: serverTimestamp(),
      }),
    );
  });

  it('DENY: an unauthenticated caller reports a name', async () => {
    await assertFails(
      addDoc(collection(asStranger(), 'nameReports'), {
        reportedUid: MALLORY,
        reporterUid: 'nobody',
        createdAt: serverTimestamp(),
      }),
    );
  });

  it("DENY: spoofing reporterUid as someone else's uid", async () => {
    // Without this, one account could manufacture several "distinct"
    // reports against the same name by lying about who is reporting —
    // exactly the check that makes `crossesReportThreshold` mean anything.
    await assertFails(
      addDoc(collection(asAlice(), 'nameReports'), {
        reportedUid: MALLORY,
        reporterUid: 'someone-else',
        createdAt: serverTimestamp(),
      }),
    );
  });

  it('DENY: reporting yourself', async () => {
    await assertFails(
      addDoc(collection(asAlice(), 'nameReports'), {
        reportedUid: ALICE,
        reporterUid: ALICE,
        createdAt: serverTimestamp(),
      }),
    );
  });

  it('DENY: a client-supplied timestamp instead of the server one', async () => {
    // `createdAt == request.time` only holds for `serverTimestamp()`; a
    // literal number is the client asserting its own clock, which is exactly
    // what this codebase never trusts (`validation.ts`'s timing checks make
    // the identical call for a submission's `completedAt`).
    await assertFails(
      addDoc(collection(asAlice(), 'nameReports'), {
        reportedUid: MALLORY,
        reporterUid: ALICE,
        createdAt: 1_756_600_000_000,
      }),
    );
  });

  it('DENY: a report missing reportedUid', async () => {
    await assertFails(
      addDoc(collection(asAlice(), 'nameReports'), {
        reporterUid: ALICE,
        createdAt: serverTimestamp(),
      }),
    );
  });

  it('DENY: a report carrying an extra field', async () => {
    await assertFails(
      addDoc(collection(asAlice(), 'nameReports'), {
        reportedUid: MALLORY,
        reporterUid: ALICE,
        createdAt: serverTimestamp(),
        reason: 'offensive',
      }),
    );
  });
});

describe('nameReports · reading and writing back', () => {
  beforeEach(async () => {
    await asServer((db) =>
      setDoc(doc(db, 'nameReports', 'r1'), {
        reportedUid: MALLORY,
        reporterUid: ALICE,
        createdAt: 1_756_600_000_000,
      }),
    );
  });

  it('DENY: the reporter reads their own report back', async () => {
    // No feedback beyond "thanks" is the point — see `nameReports.ts`'s
    // header. A reporter who could read reports back would learn how close a
    // name is to being blanked.
    await assertFails(getDoc(doc(asAlice(), 'nameReports', 'r1')));
  });

  it('DENY: any client lists the report collection', async () => {
    await assertFails(getDocs(collection(asAlice(), 'nameReports')));
  });

  it('DENY: the reporter edits their own report', async () => {
    await assertFails(
      updateDoc(doc(asAlice(), 'nameReports', 'r1'), { reportedUid: ALICE }),
    );
  });

  it('DENY: the reporter deletes their own report', async () => {
    await assertFails(deleteDoc(doc(asAlice(), 'nameReports', 'r1')));
  });

  it('ALLOW: the server path onNameReportCreated uses still works', async () => {
    // The allow half: `applyNameReport` (Admin SDK) really can read the
    // report it was triggered by.
    await asServer(async (db) => {
      const snapshot = await getDoc(doc(db, 'nameReports', 'r1'));
      expect(snapshot.data()?.['reportedUid']).toBe(MALLORY);
    });
  });
});
