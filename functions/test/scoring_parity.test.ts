/**
 * P14 acceptance criterion 2: "Dart aur TS scoring 200 random inputs par
 * identical".
 *
 * The fixture is produced by `tool/generate_scoring_fixtures.dart` from the
 * real `lib/domain/scoring/scoring.dart`, and `test/tool/scoring_fixtures_test.dart`
 * fails if the committed file no longer matches what that spec produces. So a
 * green run of BOTH tests is the parity claim: the numbers below came out of
 * Dart, and this file proves TypeScript reproduces every one of them.
 */

import { readFileSync } from 'node:fs';
import { join } from 'node:path';

import { describe, expect, it } from 'vitest';

import {
  SPEC_VERSION,
  computeScore,
  computeStars,
  hintsIn,
  maxComboIn,
  type ScoreEvent,
} from '../src/scoring';

interface ParityCase {
  id: number;
  events: ScoreEvent[];
  expected: {
    score: number;
    hintsUsed: number;
    stars: number;
    maxCombo: number;
  };
}

interface ParityFixture {
  specVersion: number;
  randomCaseCount: number;
  edgeCaseCount: number;
  cases: ParityCase[];
}

const fixture = JSON.parse(
  readFileSync(join(__dirname, 'fixtures', 'scoring_parity.json'), 'utf8'),
) as ParityFixture;

describe('Dart <-> TypeScript scoring parity', () => {
  it('is generated from the same spec version this port implements', () => {
    expect(fixture.specVersion).toBe(SPEC_VERSION);
  });

  it('covers at least the 200 random inputs the criterion names', () => {
    expect(fixture.randomCaseCount).toBeGreaterThanOrEqual(200);
    expect(fixture.cases).toHaveLength(fixture.randomCaseCount + fixture.edgeCaseCount);
  });

  it('reproduces every expected value', () => {
    // Asserted as one aggregated diff rather than 210 separate expectations:
    // a port that is wrong is usually wrong for a whole CLASS of inputs, and
    // seeing every disagreeing case at once names the class immediately.
    const disagreements = fixture.cases.filter((testCase) => {
      const hints = hintsIn(testCase.events);
      return (
        computeScore(testCase.events) !== testCase.expected.score ||
        hints !== testCase.expected.hintsUsed ||
        computeStars(hints) !== testCase.expected.stars ||
        maxComboIn(testCase.events) !== testCase.expected.maxCombo
      );
    });

    expect(
      disagreements.map((testCase) => ({
        id: testCase.id,
        dart: testCase.expected,
        typescript: {
          score: computeScore(testCase.events),
          hintsUsed: hintsIn(testCase.events),
          stars: computeStars(hintsIn(testCase.events)),
          maxCombo: maxComboIn(testCase.events),
        },
      })),
    ).toEqual([]);
  });
});
