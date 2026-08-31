import { describe, expect, it } from 'vitest';

import { LIMITS } from '../src/config';
import {
  canonicalString,
  isFresh,
  parseCallback,
  sign,
  signatureMatches,
} from '../src/grantRewardedReward';

const SECRET = 'shared-with-the-max-dashboard';
const NOW = Date.UTC(2026, 7, 31, 12, 0, 0);

const callback = {
  userId: 'uid-123',
  eventId: 'evt-abc',
  amount: 40,
  timestampMillis: NOW,
};

function query(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    user_id: callback.userId,
    event_id: callback.eventId,
    amount: String(callback.amount),
    ts: String(callback.timestampMillis),
    signature: sign(callback, SECRET),
    ...overrides,
  };
}

describe('the callback signature', () => {
  it('covers every field that decides what gets paid, and to whom', () => {
    // If a field is not in the canonical string, it can be edited in flight.
    // The uid decides WHO is paid and the amount decides HOW MUCH, so both
    // have to be inside the signature rather than beside it.
    const signed = canonicalString(callback);
    expect(signed).toContain(callback.userId);
    expect(signed).toContain(callback.eventId);
    expect(signed).toContain(String(callback.amount));
    expect(signed).toContain(String(callback.timestampMillis));
  });

  it('accepts a correctly signed callback', () => {
    expect(signatureMatches(sign(callback, SECRET), sign(callback, SECRET))).toBe(true);
  });

  it.each([
    ['a redirected payout', { userId: 'someone-else' }],
    ['an inflated amount', { amount: 5000 }],
    ['a replayed event under a new id', { eventId: 'evt-different' }],
    ['a moved timestamp', { timestampMillis: NOW + 1 }],
  ])('rejects %s', (_label, tampered) => {
    const forged = { ...callback, ...tampered };
    expect(signatureMatches(sign(callback, SECRET), sign(forged, SECRET))).toBe(false);
  });

  it('rejects a signature made with a different secret', () => {
    expect(
      signatureMatches(sign(callback, SECRET), sign(callback, 'leaked-guess')),
    ).toBe(false);
  });

  it('rejects a signature of the wrong length without throwing', () => {
    // `timingSafeEqual` throws on a length mismatch, which would turn a forged
    // callback into a 500 instead of a 403 — and a 500 makes AppLovin retry.
    expect(() => signatureMatches(sign(callback, SECRET), 'short')).not.toThrow();
    expect(signatureMatches(sign(callback, SECRET), 'short')).toBe(false);
  });
});

describe('the freshness window', () => {
  it('accepts a callback that arrived just now', () => {
    expect(isFresh(NOW, NOW + 1000)).toBe(true);
  });

  it('rejects a captured URL replayed later', () => {
    expect(isFresh(NOW, NOW + LIMITS.rewardCallbackMaxAgeMillis + 1)).toBe(false);
  });

  it('rejects a callback stamped in the future by more than the window', () => {
    expect(isFresh(NOW + LIMITS.rewardCallbackMaxAgeMillis + 1, NOW)).toBe(false);
  });
});

describe('parsing', () => {
  it('reads a well-formed callback', () => {
    expect(parseCallback(query())).toEqual({
      ...callback,
      signature: expect.any(String),
    });
  });

  it.each([
    ['a missing user', { user_id: undefined }],
    ['a missing event id', { event_id: undefined }],
    ['a missing signature', { signature: undefined }],
    ['a non-numeric amount', { amount: 'lots' }],
    ['a zero amount', { amount: '0' }],
    ['a negative amount', { amount: '-40' }],
    ['a fractional amount', { amount: '1.5' }],
    ['a non-numeric timestamp', { ts: 'now' }],
    ['an absurdly long user id', { user_id: 'x'.repeat(500) }],
  ])('refuses %s', (_label, overrides) => {
    expect(parseCallback(query(overrides))).toBeNull();
  });
});
