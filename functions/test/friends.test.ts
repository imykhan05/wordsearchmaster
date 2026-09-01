import { describe, expect, it } from 'vitest';

import { generateCode, normalizeCode } from '../src/friends';
import { LIMITS } from '../src/config';

describe('generateCode', () => {
  it('is the configured length', () => {
    expect(generateCode(() => 0.5)).toHaveLength(LIMITS.inviteCodeLength);
  });

  it('never contains an ambiguous character', () => {
    // 0/O, 1/I/L are exactly the pairs a player misreads off a phone screen.
    const random = mulberry32(1234);
    for (let i = 0; i < 200; i++) {
      const code = generateCode(random);
      expect(code).not.toMatch(/[01ILO]/);
    }
  });

  it('is always upper-case, so redemption cannot fail on case alone', () => {
    const code = generateCode(() => 0.9);
    expect(code).toBe(code.toUpperCase());
  });

  it('spreads across the alphabet rather than collapsing to one symbol', () => {
    const random = mulberry32(99);
    const codes = new Set<string>();
    for (let i = 0; i < 500; i++) codes.add(generateCode(random));
    // 500 draws from a 32^8 keyspace should not collide even once.
    expect(codes.size).toBe(500);
  });
});

describe('normalizeCode', () => {
  it('upper-cases and trims what a player pastes', () => {
    expect(normalizeCode('  abcd1234  ')).toBe('ABCD1234');
  });

  it('is idempotent, so redeeming an already-normalized code is unaffected', () => {
    expect(normalizeCode(normalizeCode('AbCd'))).toBe(normalizeCode('AbCd'));
  });
});

/** A tiny seeded PRNG so the alphabet/spread tests are deterministic. */
function mulberry32(seed: number): () => number {
  let a = seed;
  return () => {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
