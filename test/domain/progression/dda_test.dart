import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/domain/progression/dda.dart';

/// `dda.dart`'s pure contract: the two-threshold decision function, the
/// abandon-streak rule, and the word-count downshift. `game_screen.dart`'s
/// idle timer and `dda_repository.dart`'s persistence are covered separately
/// (widget/repository tests) — this file only walks the pure functions,
/// exactly like `streak_test.dart` walks `StreakRules` with no clock, no I/O.
void main() {
  group('DdaEngine.stateFor', () {
    test('below both thresholds is none', () {
      expect(
        DdaEngine.stateFor(idleFor: const Duration(seconds: 0)),
        DdaState.none,
      );
      expect(
        DdaEngine.stateFor(idleFor: const Duration(seconds: 24)),
        DdaState.none,
      );
    });

    test('at exactly stuckSeconds it pulses', () {
      expect(
        DdaEngine.stateFor(idleFor: const Duration(seconds: 25)),
        DdaState.pulse,
      );
    });

    test('between the two thresholds stays pulse', () {
      expect(
        DdaEngine.stateFor(idleFor: const Duration(seconds: 59)),
        DdaState.pulse,
      );
    });

    test('at exactly hintOfferSeconds it offers a hint', () {
      expect(
        DdaEngine.stateFor(idleFor: const Duration(seconds: 60)),
        DdaState.hintOffer,
      );
    });

    test('idle forever stays at hintOffer, never a third state', () {
      expect(
        DdaEngine.stateFor(idleFor: const Duration(hours: 3)),
        DdaState.hintOffer,
      );
    });

    test('a custom config is honoured, not the defaults', () {
      const config = DdaConfig(stuckSeconds: 5, hintOfferSeconds: 10);

      expect(
        DdaEngine.stateFor(idleFor: const Duration(seconds: 4), config: config),
        DdaState.none,
      );
      expect(
        DdaEngine.stateFor(idleFor: const Duration(seconds: 5), config: config),
        DdaState.pulse,
      );
      expect(
        DdaEngine.stateFor(
          idleFor: const Duration(seconds: 10),
          config: config,
        ),
        DdaState.hintOffer,
      );
    });
  });

  group('DdaConfig', () {
    test('has value equality', () {
      const a = DdaConfig(stuckSeconds: 25, hintOfferSeconds: 60);
      const b = DdaConfig(stuckSeconds: 25, hintOfferSeconds: 60);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(const DdaConfig(stuckSeconds: 30, hintOfferSeconds: 60)));
    });

    test('defaults are 25s / 60s, matching the shipped RemoteConfig keys', () {
      expect(DdaConfig.defaults.stuckSeconds, 25);
      expect(DdaConfig.defaults.hintOfferSeconds, 60);
    });
  });

  group('DdaAbandonRules', () {
    test('zero or one abandon does not trigger a downshift', () {
      expect(DdaAbandonRules.shouldDownshift(0), isFalse);
      expect(DdaAbandonRules.shouldDownshift(1), isFalse);
    });

    test('two consecutive abandons trigger it, per Ch02', () {
      expect(DdaAbandonRules.shouldDownshift(2), isTrue);
    });

    test('more than two still triggers it', () {
      expect(DdaAbandonRules.shouldDownshift(5), isTrue);
    });
  });

  group('DdaDownshift.dropOneWord', () {
    test('drops exactly the last word when above the floor', () {
      final result = DdaDownshift.dropOneWord(['a', 'b', 'c', 'd']);

      expect(result, ['a', 'b', 'c']);
    });

    test('leaves a list already AT the floor untouched', () {
      final result = DdaDownshift.dropOneWord(['a', 'b', 'c']);

      expect(result, ['a', 'b', 'c']);
    });

    test('leaves a list already BELOW the floor untouched', () {
      final result = DdaDownshift.dropOneWord(['a', 'b']);

      expect(result, ['a', 'b']);
    });

    test('the floor is 3, matching the Ch07 breather-level minimum', () {
      expect(DdaDownshift.minWords, 3);
    });

    test('is generic — works on the actual WordEntry-shaped lists too', () {
      final result = DdaDownshift.dropOneWord([1, 2, 3, 4, 5]);

      expect(result, [1, 2, 3, 4]);
    });
  });
}
