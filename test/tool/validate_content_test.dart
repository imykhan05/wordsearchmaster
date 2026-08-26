import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/domain/grid/grid_directions.dart';
import 'package:word_search_master/domain/models/level_definition.dart';
import 'package:word_search_master/domain/models/word_entry.dart';
import 'package:word_search_master/domain/text/language.dart';

import '../../tool/validate_content.dart';

WordEntry _word({
  required String id,
  Language lang = Language.english,
  required String word,
  required String category,
  required int graphemes,
  int? difficulty,
  String display = 'display',
  String roman = 'ROMAN',
  String en = 'EN',
  String hint = 'hint',
}) => WordEntry(
  id: id,
  lang: lang,
  word: word,
  display: display,
  roman: roman,
  en: en,
  category: category,
  graphemes: graphemes,
  difficulty: difficulty ?? expectedDifficulty(graphemes),
  hint: hint,
);

LevelDefinition _level({
  int id = 1,
  Language language = Language.english,
  int seed = 1,
  int? gridSize,
  int? wordCount,
  List<String> categoryPool = const ['nature'],
  DirectionTier? directionTier,
  String theme = 'Nature',
}) {
  final step = curveFor(id);
  return LevelDefinition(
    id: id,
    language: language,
    seed: seed,
    gridSize: gridSize ?? step.gridSize,
    wordCount: wordCount ?? expectedWordCount(id, step),
    categoryPool: categoryPool,
    directionTier: directionTier ?? DirectionTier.forLevel(id),
    theme: theme,
  );
}

/// A word 2–9 letters long, deterministic in [index] — long enough to cycle
/// through every grapheme-count band without needing real vocabulary.
String _syntheticWord(int index) {
  final length = minGraphemes + (index % (maxGraphemes - minGraphemes + 1));
  return List.generate(
    length,
    (k) => String.fromCharCode(65 + (index + k) % 26),
  ).join();
}

/// Exactly [wordsPerLanguage] schema-valid entries spread across
/// [knownCategories] the same way the real pack is (mostly 27, a few 26 —
/// see `assets/content/words_en.json`).
List<WordEntry> _validPack(Language language) {
  final categories = knownCategories.toList()..sort();
  final counts = [for (var i = 0; i < categories.length; i++) i < 8 ? 27 : 26];
  assert(counts.reduce((a, b) => a + b) == wordsPerLanguage);

  final entries = <WordEntry>[];
  for (var c = 0; c < categories.length; c++) {
    for (var i = 0; i < counts[c]; i++) {
      final word = _syntheticWord(i);
      entries.add(
        _word(
          id: '${language.code}_${categories[c]}_${i.toString().padLeft(3, '0')}',
          lang: language,
          word: word,
          category: categories[c],
          graphemes: word.length,
        ),
      );
    }
  }
  return entries;
}

void main() {
  group('curveFor / expectedWordCount / expectedDifficulty', () {
    test('matches the Ch07 curve boundaries', () {
      expect(curveFor(1).gridSize, 6);
      expect(curveFor(5).gridSize, 6);
      expect(curveFor(6).gridSize, 8);
      expect(curveFor(20).gridSize, 8);
      expect(curveFor(21).gridSize, 10);
      expect(curveFor(60).gridSize, 10);
      expect(curveFor(61).wordCount, 10);
      expect(curveFor(150).wordCount, 10);
      expect(curveFor(151).gridSize, 12);
      expect(curveFor(300).gridSize, 12);
    });

    test('every 7th level trims wordCount by 2, floored at 3', () {
      final step20 = curveFor(20);
      expect(expectedWordCount(14, step20), step20.wordCount - 2);
      expect(expectedWordCount(13, step20), step20.wordCount);

      final step5 = curveFor(5);
      expect(expectedWordCount(35, step5), greaterThanOrEqualTo(3));
    });

    test('difficulty follows the graphemes bands', () {
      expect(expectedDifficulty(2), 1);
      expect(expectedDifficulty(3), 1);
      expect(expectedDifficulty(4), 2);
      expect(expectedDifficulty(5), 2);
      expect(expectedDifficulty(6), 3);
      expect(expectedDifficulty(7), 3);
      expect(expectedDifficulty(8), 4);
      expect(expectedDifficulty(9), 5);
    });
  });

  group('validateWordEntries', () {
    test('a well-formed 320-entry pack produces zero problems', () {
      expect(
        validateWordEntries(Language.english, _validPack(Language.english)),
        isEmpty,
      );
    });

    test('flags a duplicate id', () {
      final pack = _validPack(Language.english);
      final problems = validateWordEntries(Language.english, [
        ...pack,
        pack.first,
      ]);
      expect(problems.any((p) => p.contains('duplicate id')), isTrue);
    });

    test('flags a lang field that does not match the file', () {
      final pack = _validPack(Language.english);
      pack[0] = _word(
        id: pack[0].id,
        lang: Language.hindi,
        word: pack[0].word,
        category: pack[0].category,
        graphemes: pack[0].graphemes,
      );
      final problems = validateWordEntries(Language.english, pack);
      expect(problems.any((p) => p.contains('lang field is hi')), isTrue);
    });

    test('flags graphemes outside 2-9', () {
      final pack = _validPack(Language.english);
      pack[0] = _word(
        id: pack[0].id,
        word: 'A',
        category: pack[0].category,
        graphemes: 1,
      );
      final problems = validateWordEntries(Language.english, pack);
      expect(
        problems.any((p) => p.contains('outside $minGraphemes-$maxGraphemes')),
        isTrue,
      );
    });

    test('flags a stored graphemes count that disagrees with recompute', () {
      final pack = _validPack(Language.english);
      pack[0] = _word(
        id: pack[0].id,
        word: pack[0].word,
        category: pack[0].category,
        graphemes: pack[0].graphemes + 1,
        difficulty: pack[0].difficulty,
      );
      final problems = validateWordEntries(Language.english, pack);
      expect(problems.any((p) => p.contains('recompute=')), isTrue);
    });

    test('flags an unknown category', () {
      final pack = _validPack(Language.english);
      pack[0] = _word(
        id: pack[0].id,
        word: pack[0].word,
        category: 'not_a_real_category',
        graphemes: pack[0].graphemes,
      );
      final problems = validateWordEntries(Language.english, pack);
      expect(problems.any((p) => p.contains('unknown category')), isTrue);
    });

    test('flags a difficulty that disagrees with the graphemes band', () {
      final pack = _validPack(Language.english);
      // pack[0] is 'animals' index 0 → synthetic word length 2 → difficulty 1.
      pack[0] = _word(
        id: pack[0].id,
        word: pack[0].word,
        category: pack[0].category,
        graphemes: pack[0].graphemes,
        difficulty: 5,
      );
      final problems = validateWordEntries(Language.english, pack);
      expect(problems.any((p) => p.contains('difficulty=5')), isTrue);
    });

    test('flags a word that is not already normalized', () {
      final pack = _validPack(Language.english);
      pack[0] = _word(
        id: pack[0].id,
        word: 'lowercase',
        category: pack[0].category,
        graphemes: 'lowercase'.length,
      );
      final problems = validateWordEntries(Language.english, pack);
      expect(problems.any((p) => p.contains('is not normalized')), isTrue);
    });

    test('flags a category that falls under the 24-word minimum', () {
      final pack = _validPack(Language.english)
        ..removeWhere(
          (e) =>
              e.category == 'animals' && int.parse(e.id.split('_').last) >= 20,
        );
      final problems = validateWordEntries(Language.english, pack);
      expect(problems.any((p) => p.contains('category "animals"')), isTrue);
    });

    test('flags a pack that is not exactly 320 entries', () {
      final pack = _validPack(Language.english)..removeLast();
      final problems = validateWordEntries(Language.english, pack);
      expect(problems.any((p) => p.contains('319 entries')), isTrue);
    });
  });

  group('validateLevels', () {
    test(
      'a sparse-but-internally-consistent fixture only reports coverage gaps',
      () {
        final levels = [
          for (final language in Language.values)
            for (final id in [1, 6, 7, 21, 300])
              _level(id: id, language: language),
        ];
        final byId = <int, Map<Language, LevelDefinition>>{};
        for (final level in levels) {
          (byId[level.id] ??= {})[level.language] = level;
        }

        final problems = validateLevels(levels, byId);
        for (final problem in problems) {
          expect(problem, contains('missing level'));
        }
      },
    );

    test('flags a gridSize that does not match the curve', () {
      final level = _level(id: 1, gridSize: 999);
      final problems = validateLevels(
        [level],
        {
          1: {Language.english: level},
        },
      );
      expect(problems.any((p) => p.contains('gridSize=999')), isTrue);
    });

    test('flags a breather level that did not reduce wordCount', () {
      final step = curveFor(7);
      final level = _level(id: 7, wordCount: step.wordCount);
      final problems = validateLevels(
        [level],
        {
          7: {Language.english: level},
        },
      );
      expect(problems.any((p) => p.contains('breather level')), isTrue);
    });

    test(
      'flags a directionTier that does not match DirectionTier.forLevel',
      () {
        final level = _level(id: 1, directionTier: DirectionTier.all);
        final problems = validateLevels(
          [level],
          {
            1: {Language.english: level},
          },
        );
        expect(problems.any((p) => p.contains('directionTier=all')), isTrue);
      },
    );

    test('flags an unknown category in categoryPool', () {
      final level = _level(id: 1, categoryPool: const ['not_real']);
      final problems = validateLevels(
        [level],
        {
          1: {Language.english: level},
        },
      );
      expect(
        problems.any((p) => p.contains('unknown category "not_real"')),
        isTrue,
      );
    });

    test(
      'flags a seed that differs across languages for the same level id',
      () {
        final en = _level(id: 1, language: Language.english, seed: 111);
        final ur = _level(id: 1, language: Language.urdu, seed: 222);
        final byId = {
          1: {Language.english: en, Language.urdu: ur},
        };
        final problems = validateLevels([en, ur], byId);
        expect(problems.any((p) => p.contains("differs from level 1")), isTrue);
      },
    );

    test('flags an id outside 1-300', () {
      final level = _level(
        id: 301,
        gridSize: curveFor(300).gridSize,
        wordCount: curveFor(300).wordCount,
        directionTier: DirectionTier.forLevel(301),
      );
      final problems = validateLevels(
        [level],
        {
          301: {Language.english: level},
        },
      );
      expect(problems.any((p) => p.contains('outside 1-300')), isTrue);
    });
  });

  group('validateLevelWordAvailability', () {
    test('flags a level whose eligible pool is smaller than wordCount', () {
      final level = _level(
        id: 1,
        categoryPool: const ['nature'],
        wordCount: 4,
        gridSize: 6,
      );
      final pool = {
        Language.english: [
          _word(id: 'a', word: 'CAT', category: 'nature', graphemes: 3),
          _word(id: 'b', word: 'DOG', category: 'nature', graphemes: 3),
        ],
      };
      final problems = validateLevelWordAvailability([level], pool);
      expect(problems.any((p) => p.contains('only 2 eligible')), isTrue);
    });

    test('does not flag a level with enough eligible words', () {
      final level = _level(
        id: 1,
        categoryPool: const ['nature'],
        wordCount: 2,
        gridSize: 6,
      );
      final pool = {
        Language.english: [
          _word(id: 'a', word: 'CAT', category: 'nature', graphemes: 3),
          _word(id: 'b', word: 'DOG', category: 'nature', graphemes: 3),
        ],
      };
      expect(validateLevelWordAvailability([level], pool), isEmpty);
    });
  });

  group('the real shipped content (integration — proves the P10 acceptance criteria)', () {
    late Map<Language, List<WordEntry>> wordsByLanguage;
    late List<LevelDefinition> allLevels;
    late Map<int, Map<Language, LevelDefinition>> levelsById;
    late Map<Language, Set<String>> blocklists;

    setUpAll(() {
      final problems = <String>[];
      wordsByLanguage = {
        for (final language in Language.values)
          language: loadWordPack('.', language, problems),
      };
      allLevels = [];
      levelsById = {};
      loadLevels('.', problems, allLevels, levelsById);
      blocklists = {
        for (final language in Language.values)
          language: loadBlocklist('.', language, problems),
      };
      expect(problems, isEmpty, reason: 'content failed to load: $problems');
    });

    test(
      'schema: every word and level entry is valid — 320/language, 900 levels',
      () {
        final problems = <String>[
          for (final language in Language.values)
            ...validateWordEntries(language, wordsByLanguage[language]!),
          ...validateLevels(allLevels, levelsById),
          ...validateLevelWordAvailability(allLevels, wordsByLanguage),
        ];
        expect(problems, isEmpty, reason: problems.take(20).join('\n'));
        expect(allLevels, hasLength(900));
        for (final language in Language.values) {
          expect(wordsByLanguage[language], hasLength(wordsPerLanguage));
        }
      },
    );

    test('all 900 (level, language) combinations place completely on their canonical seed', () {
      final failures = validateCanonicalPlacement(
        allLevels,
        wordsByLanguage,
        blocklists,
      );
      expect(failures, isEmpty, reason: failures.take(10).join('\n'));
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('500 freshly-reseeded generations sampled across the curve all place completely', () {
      final failures = validateFuzzPlacement(
        levelsById,
        wordsByLanguage,
        blocklists,
        iterations: 500,
        metaSeed: 20260826,
      );
      expect(failures, isEmpty, reason: failures.take(10).join('\n'));
    }, timeout: const Timeout(Duration(minutes: 5)));
  });
}
