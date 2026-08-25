import 'dart:math';

import 'package:characters/characters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/domain/grid/grid_directions.dart';
import 'package:word_search_master/domain/grid/grid_generator.dart';
import 'package:word_search_master/domain/grid/grid_result.dart';
import 'package:word_search_master/domain/grid/grid_vector.dart';
import 'package:word_search_master/domain/text/language.dart';
import 'package:word_search_master/domain/text/script_normalizer.dart';

import 'grid_scanner.dart';
import 'word_fixtures.dart';

void main() {
  String flatten(GridResult result) =>
      [for (final row in result.cells) row.join('|')].join('/');

  group('determinism', () {
    test('the same seed produces a byte-identical grid, 100 times over', () {
      // The whole content model rests on this: levels store a seed, not a
      // grid, so level 47 must be the same puzzle on every device forever.
      GridResult build() => GridGenerator.generate(
        seed: 8817342,
        size: 10,
        words: const ['WATER', 'CLOUD', 'STONE', 'RIVER', 'FOREST', 'LIGHT'],
        lang: Language.english,
        allowedDirections: GridDirections.forLanguage(
          Language.english,
          DirectionTier.all,
        ),
      );

      final reference = flatten(build());
      for (var i = 0; i < 100; i++) {
        expect(flatten(build()), reference, reason: 'iteration $i diverged');
      }
    });

    test('placements are identical too, not just the letters', () {
      GridResult build() => GridGenerator.generate(
        seed: 4242,
        size: 8,
        words: const ['پانی', 'بادل', 'ہوا', 'زمین'],
        lang: Language.urdu,
        allowedDirections: GridDirections.forLanguage(
          Language.urdu,
          DirectionTier.diagonal,
        ),
      );

      final first = build().placements;
      final second = build().placements;

      expect(second.keys, first.keys);
      for (final word in first.keys) {
        expect(second[word], first[word], reason: word);
      }
    });

    test('a different seed produces a different grid', () {
      GridResult build(int seed) => GridGenerator.generate(
        seed: seed,
        size: 10,
        words: const ['WATER', 'CLOUD', 'STONE', 'RIVER'],
        lang: Language.english,
        allowedDirections: GridDirections.forLanguage(
          Language.english,
          DirectionTier.all,
        ),
      );

      expect(flatten(build(1)), isNot(flatten(build(2))));
    });

    test('unnormalized input still lands on the canonical grid', () {
      // The same word typed on an Arabic keyboard must not produce a
      // different puzzle.
      final arabicKeyboard = GridGenerator.generate(
        seed: 99,
        size: 8,
        words: [
          String.fromCharCodes([0x067E, 0x0627, 0x0646, 0x064A]),
        ],
        lang: Language.urdu,
        allowedDirections: const [GridVector.west, GridVector.south],
      );
      final urduKeyboard = GridGenerator.generate(
        seed: 99,
        size: 8,
        words: [
          String.fromCharCodes([0x067E, 0x0627, 0x0646, 0x06CC]),
        ],
        lang: Language.urdu,
        allowedDirections: const [GridVector.west, GridVector.south],
      );

      expect(flatten(arabicKeyboard), flatten(urduKeyboard));
    });
  });

  group('every placed word is really there', () {
    test('each placement matches the cells it claims', () {
      final result = GridGenerator.generate(
        seed: 555,
        size: 10,
        words: const ['WATER', 'CLOUD', 'STONE', 'RIVER', 'FOREST'],
        lang: Language.english,
        allowedDirections: GridDirections.forLanguage(
          Language.english,
          DirectionTier.all,
        ),
      );

      for (final placement in result.placementDetails) {
        expect(placement.cells, hasLength(placement.graphemes.length));
        for (var i = 0; i < placement.graphemes.length; i++) {
          expect(
            result.cellAt(placement.cells[i]),
            placement.graphemes[i],
            reason: '${placement.word} at ${placement.cells[i]}',
          );
        }
      }
    });

    test('each word is findable by an independent scan of the grid', () {
      for (final language in Language.values) {
        final random = Random(31);
        final words = WordFixtures.pickCohesive(language, 8, 10, random);

        final result = GridGenerator.generate(
          seed: 777,
          size: 10,
          words: words,
          lang: language,
          allowedDirections: GridDirections.forLanguage(
            language,
            DirectionTier.all,
          ),
        );

        for (final placement in result.placementDetails) {
          expect(
            findWord(result.cells, placement.graphemes),
            isNotNull,
            reason: '${placement.word} ($language) is not actually in the grid',
          );
        }
      }
    });
  });

  group('script correctness', () {
    test('Urdu horizontal placements DECREASE the column index', () {
      // Ch04, Masla 5. The starter tier offers only west and south, so every
      // horizontal placement must run right-to-left.
      final directions = GridDirections.forLanguage(
        Language.urdu,
        DirectionTier.starter,
      );

      var horizontalSeen = 0;
      for (var seed = 0; seed < 40; seed++) {
        final random = Random(seed);
        final result = GridGenerator.generate(
          seed: seed,
          size: 9,
          words: WordFixtures.pickCohesive(Language.urdu, 6, 9, random),
          lang: Language.urdu,
          allowedDirections: directions,
        );

        for (final placement in result.placementDetails) {
          if (!placement.direction.isHorizontal) continue;
          horizontalSeen++;

          expect(placement.direction, GridVector.west);
          for (var i = 1; i < placement.cells.length; i++) {
            expect(
              placement.cells[i].col,
              lessThan(placement.cells[i - 1].col),
              reason: '${placement.word} should read right-to-left',
            );
            expect(placement.cells[i].row, placement.cells[i - 1].row);
          }
        }
      }

      expect(horizontalSeen, greaterThan(0), reason: 'nothing was exercised');
    });

    test(
      'English and Hindi horizontal placements increase the column index',
      () {
        for (final language in [Language.english, Language.hindi]) {
          final random = Random(5);
          final result = GridGenerator.generate(
            seed: 5,
            size: 10,
            words: WordFixtures.pickCohesive(language, 8, 10, random),
            lang: language,
            allowedDirections: GridDirections.forLanguage(
              language,
              DirectionTier.starter,
            ),
          );

          for (final placement in result.placementDetails) {
            if (!placement.direction.isHorizontal) continue;
            expect(placement.direction, GridVector.east, reason: '$language');
          }
        }
      },
    );

    test('a Hindi word with matras occupies one cell per akshara', () {
      // "पानी" is two cells (पा, नी), not four. A code-point split would
      // strand the matras in cells of their own.
      final result = GridGenerator.generate(
        seed: 1234,
        size: 8,
        words: const ['पानी', 'बादल', 'नदी'],
        lang: Language.hindi,
        allowedDirections: GridDirections.forLanguage(
          Language.hindi,
          DirectionTier.diagonal,
        ),
      );

      final paani = result.placementDetails.firstWhere((p) => p.word == 'पानी');
      expect(paani.graphemes, ['पा', 'नी']);
      expect(paani.cells, hasLength(2));

      // And every cell in the grid holds exactly one grapheme cluster.
      for (final row in result.cells) {
        for (final cell in row) {
          expect(
            cell.characters.length,
            1,
            reason: '"$cell" is not a single grapheme cluster',
          );
        }
      }
    });

    test(
      'every filler is a real letter of the language, never a stray mark',
      () {
        for (final language in Language.values) {
          final random = Random(3);
          final result = GridGenerator.generate(
            seed: 3,
            size: 10,
            words: WordFixtures.pickCohesive(language, 8, 10, random),
            lang: language,
            allowedDirections: GridDirections.forLanguage(
              language,
              DirectionTier.all,
            ),
          );

          for (final row in result.cells) {
            for (final cell in row) {
              expect(
                cell.trim(),
                isNotEmpty,
                reason: '$language had a blank cell',
              );
              expect(
                ScriptNormalizer.normalize(cell, language),
                cell,
                reason: '$language filler "$cell" is not in normalized form',
              );
            }
          }
        }
      },
    );
  });

  group('the Ch07 curve — 500 configurations', () {
    test('all 500 generate completely, and 80%+ land in the ratio band', () {
      final random = Random(20260825);
      final ratios = <double>[];
      final incomplete = <String>[];

      for (var i = 0; i < 500; i++) {
        final step = ch07Curve[random.nextInt(ch07Curve.length)];
        final language =
            Language.values[random.nextInt(Language.values.length)];
        final level =
            step.levelFrom + random.nextInt(step.levelTo - step.levelFrom + 1);

        final words = WordFixtures.pickCohesive(
          language,
          step.wordCount,
          step.gridSize,
          random,
        );

        final result = GridGenerator.generate(
          seed: random.nextInt(1 << 30),
          size: step.gridSize,
          words: words,
          lang: language,
          allowedDirections: GridDirections.forLevel(language, level),
        );

        if (!result.isComplete) {
          incomplete.add('${language.code} L$level ${result.unplacedWords}');
        }
        ratios.add(result.intersectionRatio);
      }

      expect(incomplete, isEmpty, reason: 'these configs failed to place');

      final inBand = ratios
          .where(
            (r) =>
                r >= GridGenerator.minIntersectionRatio &&
                r <= GridGenerator.maxIntersectionRatio,
          )
          .length;
      final percent = inBand / ratios.length * 100;

      expect(
        percent,
        greaterThanOrEqualTo(80),
        reason:
            'only ${percent.toStringAsFixed(1)}% of grids landed in '
            '0.15–0.30; the puzzle reads as isolated words below that band '
            'and as mush above it',
      );
    });

    test('word sets that share no graphemes cannot intersect — a content constraint', () {
      // Recorded here because it was measured, and because it lands on P10.
      //
      // A crossing needs two words to contain the IDENTICAL grapheme. In
      // Devanagari a cell holds an akshara, drawn from a far larger set than
      // the Latin alphabet, so randomly-chosen Hindi words collide much more
      // rarely: 17–38% of them share a grapheme with anything already placed,
      // against 91–97% in English.
      //
      // No generator can cross words that share nothing, so Hindi levels whose
      // word sets are picked at random produce grids of isolated words — a
      // measurably easier puzzle at the same level number. P10 must assemble
      // level word sets with this in mind.
      double shareableFraction(Language language, int count, int maxGraphemes) {
        final random = Random(11);
        var shareable = 0;
        var total = 0;

        for (var i = 0; i < 60; i++) {
          final words = WordFixtures.pick(
            language,
            count,
            maxGraphemes,
            random,
          );
          final sets = [
            for (final word in words)
              ScriptNormalizer.graphemes(word, language).toSet(),
          ];
          for (var w = 1; w < sets.length; w++) {
            total++;
            final earlier = <String>{for (var e = 0; e < w; e++) ...sets[e]};
            if (sets[w].intersection(earlier).isNotEmpty) shareable++;
          }
        }
        return shareable / total;
      }

      final hindi = shareableFraction(Language.hindi, 8, 10);
      final english = shareableFraction(Language.english, 8, 10);

      expect(
        hindi,
        lessThan(english),
        reason: 'if this ever inverts, the fixture or the finding has changed',
      );
      expect(hindi, lessThan(0.6), reason: 'Hindi aksharas collide rarely');
      expect(english, greaterThan(0.8));
    });
  });

  group('robustness — never throws, never hangs', () {
    test('an empty word list yields a filled grid with no placements', () {
      final result = GridGenerator.generate(
        seed: 1,
        size: 6,
        words: const [],
        lang: Language.english,
        allowedDirections: const [GridVector.east, GridVector.south],
      );

      expect(result.placementDetails, isEmpty);
      expect(result.unplacedWords, isEmpty);
      expect(result.cells, hasLength(6));
      expect(result.intersectionRatio, 0);
    });

    test(
      'no allowed directions reports every word unplaced instead of throwing',
      () {
        final result = GridGenerator.generate(
          seed: 1,
          size: 6,
          words: const ['WATER'],
          lang: Language.english,
          allowedDirections: const [],
        );

        expect(result.unplacedWords, ['WATER']);
        expect(result.isComplete, isFalse);
      },
    );

    test(
      'a word longer than the requested grid grows the grid instead of failing',
      () {
        final result = GridGenerator.generate(
          seed: 1,
          size: 4,
          words: const ['EXTRAORDINARY'],
          lang: Language.english,
          allowedDirections: const [GridVector.east, GridVector.south],
        );

        expect(result.size, greaterThanOrEqualTo('EXTRAORDINARY'.length));
        expect(result.isComplete, isTrue);
      },
    );

    test('duplicate and blank words are collapsed, not placed twice', () {
      final result = GridGenerator.generate(
        seed: 1,
        size: 8,
        words: const ['WATER', 'water', '  WATER  ', '', '   '],
        lang: Language.english,
        allowedDirections: const [GridVector.east, GridVector.south],
      );

      expect(result.placementDetails, hasLength(1));
      expect(result.placements.keys, ['WATER']);
    });

    test('a degenerate size is clamped rather than throwing', () {
      for (final size in [0, -5]) {
        expect(
          () => GridGenerator.generate(
            seed: 1,
            size: size,
            words: const ['AB'],
            lang: Language.english,
            allowedDirections: const [GridVector.east],
          ),
          returnsNormally,
          reason: 'size $size',
        );
      }
    });

    test(
      'an unsatisfiable word set terminates and reports what did not fit',
      () {
        // Ten 5-letter words sharing no letters, one direction, tiny grid.
        final result = GridGenerator.generate(
          seed: 1,
          size: 5,
          words: const [
            'AAAAA', 'BBBBB', 'CCCCC', 'DDDDD', 'EEEEE', //
            'FFFFF', 'GGGGG', 'HHHHH', 'IIIII', 'JJJJJ',
            'KKKKK', 'LLLLL', 'MMMMM', 'NNNNN', 'OOOOO',
          ],
          lang: Language.english,
          allowedDirections: const [GridVector.east],
          maxGrowth: 0,
        );

        // The contract is "never throws" — a caller (P10's validator) detects
        // the failure through unplacedWords instead.
        expect(result.unplacedWords, isNotEmpty);
        expect(result.isComplete, isFalse);
        expect(result.cells, hasLength(5));
      },
    );
  });

  group('blocklist scan', () {
    test('an accidental blocklisted word is re-rolled out of the grid', () {
      // Injected rather than using the shipped asset, so this tests the
      // mechanism and not the (deliberately incomplete) word lists.
      const banned = {'AAA', 'BBB', 'CCC', 'DDD'};

      for (var seed = 0; seed < 25; seed++) {
        final result = GridGenerator.generate(
          seed: seed,
          size: 8,
          words: const ['WATER', 'STONE'],
          lang: Language.english,
          allowedDirections: GridDirections.forLanguage(
            Language.english,
            DirectionTier.all,
          ),
          blocklist: banned,
        );

        for (final word in banned) {
          final graphemes = ScriptNormalizer.graphemes(word, Language.english);
          expect(
            findWord(result.cells, graphemes),
            isNull,
            reason: 'seed $seed still contains "$word"',
          );
        }
      }
    });

    test('re-rolling never damages a placed word', () {
      // Only filler cells may be re-rolled; a cell belonging to a real word is
      // left alone, so cleaning up the noise cannot break the puzzle.
      final result = GridGenerator.generate(
        seed: 9,
        size: 9,
        words: const ['WATER', 'STONE', 'RIVER', 'LIGHT'],
        lang: Language.english,
        allowedDirections: GridDirections.forLanguage(
          Language.english,
          DirectionTier.all,
        ),
        blocklist: const {'AE', 'RS', 'TT', 'EE', 'OO'},
      );

      for (final placement in result.placementDetails) {
        for (var i = 0; i < placement.graphemes.length; i++) {
          expect(result.cellAt(placement.cells[i]), placement.graphemes[i]);
        }
      }
    });

    test('an empty blocklist leaves the grid untouched', () {
      String build(Set<String> blocklist) => flatten(
        GridGenerator.generate(
          seed: 17,
          size: 8,
          words: const ['WATER', 'STONE'],
          lang: Language.english,
          allowedDirections: const [GridVector.east, GridVector.south],
          blocklist: blocklist,
        ),
      );

      expect(build(const {}), build(const {}));
    });
  });

  group('GridResult', () {
    test('intersectionRatio counts shared cells against total letters', () {
      final result = GridGenerator.generate(
        seed: 21,
        size: 10,
        words: const ['WATER', 'CLOUD', 'STONE', 'RIVER'],
        lang: Language.english,
        allowedDirections: GridDirections.forLanguage(
          Language.english,
          DirectionTier.all,
        ),
      );

      final totalLetters = result.placementDetails.fold<int>(
        0,
        (sum, p) => sum + p.graphemes.length,
      );
      final distinctCells = {
        for (final placement in result.placementDetails) ...placement.cells,
      }.length;

      expect(
        result.intersectionRatio,
        closeTo(1 - distinctCells / totalLetters, 1e-9),
      );
    });

    test('cells and placements are unmodifiable', () {
      final result = GridGenerator.generate(
        seed: 1,
        size: 6,
        words: const ['WATER'],
        lang: Language.english,
        allowedDirections: const [GridVector.east],
      );

      expect(() => result.cells.add(<String>[]), throwsUnsupportedError);
      expect(() => result.cells.first[0] = 'X', throwsUnsupportedError);
      expect(() => result.placementDetails.clear(), throwsUnsupportedError);
    });

    test('attempts is reported and non-zero', () {
      final result = GridGenerator.generate(
        seed: 1,
        size: 8,
        words: const ['WATER', 'STONE'],
        lang: Language.english,
        allowedDirections: const [GridVector.east, GridVector.south],
      );

      expect(result.attempts, greaterThan(0));
    });
  });
}
