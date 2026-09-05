import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/domain/progression/ad_policy.dart';

/// `ad_policy.dart`'s pure contract: a fixed, non-escalating gap between
/// interstitials, gated on the player ever having completed a level at all.
/// The other two CLAUDE.md ad rules — never after a failed/abandoned level,
/// never before the first completion — are enforced by the CALLER never
/// consulting this policy on those paths (see the library header), so this
/// file only walks what [AdFrequencyPolicy.canShowInterstitial] itself
/// decides, exactly like `dda_test.dart` walks `DdaEngine` with no clock, no
/// I/O, no widget.
void main() {
  group('AdFrequencyPolicy.canShowInterstitial', () {
    const policy = AdFrequencyPolicy(minLevelsBetweenInterstitials: 4);

    test('never before the player has completed a single level', () {
      expect(
        policy.canShowInterstitial(
          totalLevelsCompleted: 0,
          levelsSinceLastInterstitial: 999,
        ),
        isFalse,
      );
    });

    test(
      'a corrupt negative completion count is also refused, not crashed',
      () {
        expect(
          policy.canShowInterstitial(
            totalLevelsCompleted: -1,
            levelsSinceLastInterstitial: 999,
          ),
          isFalse,
        );
      },
    );

    test('refused below the gap', () {
      expect(
        policy.canShowInterstitial(
          totalLevelsCompleted: 10,
          levelsSinceLastInterstitial: 3,
        ),
        isFalse,
      );
    });

    test('allowed at exactly the gap', () {
      expect(
        policy.canShowInterstitial(
          totalLevelsCompleted: 10,
          levelsSinceLastInterstitial: 4,
        ),
        isTrue,
      );
    });

    test('allowed past the gap too — a missed check does not lock it out', () {
      expect(
        policy.canShowInterstitial(
          totalLevelsCompleted: 10,
          levelsSinceLastInterstitial: 40,
        ),
        isTrue,
      );
    });

    test('the FIRST-ever eligible ad waits the identical gap as every later '
        'one — nothing here treats level 1 specially', () {
      expect(
        policy.canShowInterstitial(
          totalLevelsCompleted: 1,
          levelsSinceLastInterstitial: 4,
        ),
        isTrue,
      );
      expect(
        policy.canShowInterstitial(
          totalLevelsCompleted: 1,
          levelsSinceLastInterstitial: 1,
        ),
        isFalse,
      );
    });

    test(
      'the gap does not shrink as totalLevelsCompleted grows — never escalate',
      () {
        // Same `levelsSinceLastInterstitial`, wildly different progress: the
        // answer must be identical, because CLAUDE.md forbids frequency
        // depending on how far the player has come.
        for (final progress in [5, 50, 300]) {
          expect(
            policy.canShowInterstitial(
              totalLevelsCompleted: progress,
              levelsSinceLastInterstitial: 3,
            ),
            isFalse,
            reason: 'at $progress levels completed',
          );
          expect(
            policy.canShowInterstitial(
              totalLevelsCompleted: progress,
              levelsSinceLastInterstitial: 4,
            ),
            isTrue,
            reason: 'at $progress levels completed',
          );
        }
      },
    );

    test(
      'a custom (Remote Config) gap is honoured, not the shipped default',
      () {
        const wide = AdFrequencyPolicy(minLevelsBetweenInterstitials: 10);

        expect(
          wide.canShowInterstitial(
            totalLevelsCompleted: 5,
            levelsSinceLastInterstitial: 4,
          ),
          isFalse,
          reason: 'the default policy would allow this; the wide one must not',
        );
      },
    );

    test('a zero gap (min: 1 in RemoteConfigKeys rules this out in practice, '
        'but the pure function itself just compares) allows every level', () {
      const everyLevel = AdFrequencyPolicy(minLevelsBetweenInterstitials: 0);

      expect(
        everyLevel.canShowInterstitial(
          totalLevelsCompleted: 1,
          levelsSinceLastInterstitial: 0,
        ),
        isTrue,
      );
    });
  });

  group('AdFrequencyPolicy value semantics', () {
    test('equal gaps are equal', () {
      expect(
        const AdFrequencyPolicy(minLevelsBetweenInterstitials: 4),
        const AdFrequencyPolicy(minLevelsBetweenInterstitials: 4),
      );
    });

    test('different gaps are not equal', () {
      expect(
        const AdFrequencyPolicy(minLevelsBetweenInterstitials: 4),
        isNot(const AdFrequencyPolicy(minLevelsBetweenInterstitials: 5)),
      );
    });

    test('defaults is a 4-level gap — Ch01-consistent, not a knife edge', () {
      expect(AdFrequencyPolicy.defaults.minLevelsBetweenInterstitials, 4);
    });
  });
}
