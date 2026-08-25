import 'dart:math';

import 'package:characters/characters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/domain/grid/filler_strategy.dart';
import 'package:word_search_master/domain/text/language.dart';
import 'package:word_search_master/domain/text/script_normalizer.dart';

void main() {
  List<String> graphemesOf(String word, Language language) =>
      ScriptNormalizer.graphemes(word, language);

  group('target bias', () {
    test('roughly 60% of fillers come from the target words themselves', () {
      // This is the whole point of the class: uniform fillers make the answer
      // letters visibly different from the noise, so the eye finds words
      // without reading them (Ch06).
      final words = [graphemesOf('QQQZZZ', Language.english)];
      final filler = FillerStrategy(
        language: Language.english,
        words: words,
        random: Random(1),
      );

      final draws = [for (var i = 0; i < 20000; i++) filler.next()];
      final fromTarget = draws.where((g) => g == 'Q' || g == 'Z').length;

      // Q and Z are near-absent from the English frequency table, so almost
      // every Q/Z drawn must have come from the target pool.
      expect(fromTarget / draws.length, closeTo(0.6, 0.05));
    });

    test('a bias of 0 never draws from the target pool', () {
      final filler = FillerStrategy(
        language: Language.english,
        words: [graphemesOf('QQQQ', Language.english)],
        random: Random(1),
        targetBias: 0,
      );

      final draws = [for (var i = 0; i < 3000; i++) filler.next()];
      // 'Q' has weight 1 of ~1000 in the table, so a target-free run should
      // essentially never be dominated by it.
      expect(
        draws.where((g) => g == 'Q').length / draws.length,
        lessThan(0.05),
      );
    });

    test('with no words, every draw comes from the language table', () {
      final filler = FillerStrategy(
        language: Language.english,
        words: const [],
        random: Random(1),
      );

      final pool = FillerStrategy.poolFor(Language.english).toSet();
      for (var i = 0; i < 500; i++) {
        expect(pool, contains(filler.next()));
      }
    });
  });

  group('pools are valid letters', () {
    test('every filler is a single grapheme cluster in every language', () {
      for (final language in Language.values) {
        for (final grapheme in FillerStrategy.poolFor(language)) {
          expect(
            grapheme.characters.length,
            1,
            reason: '$language pool entry "$grapheme" is not one cell',
          );
        }
      }
    });

    test('every filler is already in normalized form', () {
      // Otherwise a filler could compare unequal to the identical letter in a
      // placed word, and overlaps would silently stop working.
      for (final language in Language.values) {
        for (final grapheme in FillerStrategy.poolFor(language)) {
          expect(
            ScriptNormalizer.normalize(grapheme, language),
            grapheme,
            reason: '$language pool entry "$grapheme"',
          );
        }
      }
    });

    test('the Hindi pool contains consonant+matra aksharas, not only bare consonants', () {
      // A pool of bare consonants would make every word containing a matra
      // stand out instantly against the noise.
      final pool = FillerStrategy.poolFor(Language.hindi);
      final withMatra = pool.where((g) => g.runes.length > 1);

      expect(withMatra, isNotEmpty);
      expect(withMatra.length, greaterThan(10));
    });

    test('frequency weighting shows up in the draws', () {
      // E should beat Z by a wide margin, or the grid stops looking like text.
      final filler = FillerStrategy(
        language: Language.english,
        words: const [],
        random: Random(2),
      );

      final draws = [for (var i = 0; i < 20000; i++) filler.next()];
      final e = draws.where((g) => g == 'E').length;
      final z = draws.where((g) => g == 'Z').length;

      expect(e, greaterThan(z * 20));
    });
  });

  test('draws are deterministic for a given seed', () {
    List<String> run() {
      final filler = FillerStrategy(
        language: Language.urdu,
        words: [graphemesOf('پانی', Language.urdu)],
        random: Random(7),
      );
      return [for (var i = 0; i < 200; i++) filler.next()];
    }

    expect(run(), run());
  });
}
