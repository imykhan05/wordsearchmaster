import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/domain/grid/grid_directions.dart';
import 'package:word_search_master/domain/models/level_definition.dart';
import 'package:word_search_master/domain/progression/collections.dart';
import 'package:word_search_master/domain/text/language.dart';

void main() {
  LevelDefinition level(
    int id,
    String category, {
    Language language = Language.english,
  }) => LevelDefinition(
    id: id,
    language: language,
    seed: id,
    gridSize: 6,
    wordCount: 4,
    categoryPool: [category],
    directionTier: DirectionTier.starter,
    theme: category,
  );

  /// Six levels: 1-3 animals, 4-6 food, in one language.
  List<LevelDefinition> pack({Language language = Language.english}) => [
    for (var id = 1; id <= 3; id++) level(id, 'animals', language: language),
    for (var id = 4; id <= 6; id++) level(id, 'food', language: language),
  ];

  group('forLanguage', () {
    test('counts each category and reports totals', () {
      final badges = Collections.forLanguage(
        levels: pack(),
        completedLevels: const {1, 2},
        language: Language.english,
      );

      expect(badges, hasLength(2));
      expect(badges.map((b) => b.category).toList(), ['animals', 'food']);

      final animals = badges.first;
      expect(animals.levelsTotal, 3);
      expect(animals.levelsCompleted, 2);
      expect(animals.isEarned, isFalse);
      expect(animals.progress, closeTo(2 / 3, 0.001));
    });

    test('a badge is earned only when EVERY level of its category is done', () {
      final almost = Collections.forLanguage(
        levels: pack(),
        completedLevels: const {1, 2},
        language: Language.english,
      ).first;
      expect(almost.isEarned, isFalse);

      final earned = Collections.forLanguage(
        levels: pack(),
        completedLevels: const {1, 2, 3},
        language: Language.english,
      ).first;
      expect(earned.isEarned, isTrue);
      expect(earned.progress, 1.0);
    });

    test('sorted by category, so the grid is stable between builds', () {
      final badges = Collections.forLanguage(
        levels: [level(1, 'weather'), level(2, 'animals'), level(3, 'food')],
        completedLevels: const {},
        language: Language.english,
      );

      expect(badges.map((b) => b.category).toList(), [
        'animals',
        'food',
        'weather',
      ]);
    });

    test('levels of ANOTHER language do not count', () {
      final levels = [...pack(), ...pack(language: Language.urdu)];

      final english = Collections.forLanguage(
        levels: levels,
        // The same level ids are complete, but only the English badge should
        // see them — `level_progress` is keyed by (language, level).
        completedLevels: const {1, 2, 3},
        language: Language.english,
      );
      final urdu = Collections.forLanguage(
        levels: levels,
        completedLevels: const {},
        language: Language.urdu,
      );

      expect(english.first.isEarned, isTrue);
      expect(urdu.first.isEarned, isFalse);
      expect(
        urdu.first.levelsTotal,
        3,
        reason: 'Urdu has its own three animals levels to finish',
      );
    });

    test('a level counts toward every category in its pool', () {
      final levels = [
        LevelDefinition(
          id: 1,
          language: Language.english,
          seed: 1,
          gridSize: 6,
          wordCount: 4,
          categoryPool: const ['animals', 'food'],
          directionTier: DirectionTier.starter,
          theme: 'Mixed',
        ),
      ];

      final badges = Collections.forLanguage(
        levels: levels,
        completedLevels: const {1},
        language: Language.english,
      );

      expect(badges, hasLength(2));
      expect(badges.every((b) => b.isEarned), isTrue);
    });

    test('an empty pack yields no badges rather than throwing', () {
      expect(
        Collections.forLanguage(
          levels: const [],
          completedLevels: const {},
          language: Language.english,
        ),
        isEmpty,
      );
    });
  });

  group('achievementId', () {
    test('is namespaced by language and category', () {
      expect(
        CategoryBadge.achievementIdFor('animals', Language.urdu),
        'collection:ur:animals',
      );
    });

    test('differs per language for the same category', () {
      final ids = {
        for (final language in Language.values)
          CategoryBadge.achievementIdFor('animals', language),
      };
      expect(ids, hasLength(3));
    });
  });

  group('newlyEarnedBy', () {
    test('reports only the badge the completion pushed over the line', () {
      final newly = Collections.newlyEarnedBy(
        levels: pack(),
        completedBefore: const {1, 2},
        language: Language.english,
        justCompleted: 3,
      );

      expect(newly, hasLength(1));
      expect(newly.single.category, 'animals');
    });

    test('a mid-category completion earns nothing', () {
      expect(
        Collections.newlyEarnedBy(
          levels: pack(),
          completedBefore: const {1},
          language: Language.english,
          justCompleted: 2,
        ),
        isEmpty,
      );
    });

    test(
      'REPLAYING a level in an already-complete category re-fires nothing',
      () {
        // The badge is earned either way, so a naive "is it earned now?" check
        // would celebrate again on every replay.
        final newly = Collections.newlyEarnedBy(
          levels: pack(),
          completedBefore: const {1, 2, 3},
          language: Language.english,
          justCompleted: 1,
        );

        expect(newly, isEmpty);
      },
    );

    test('finishing the last level of two categories at once earns both', () {
      final levels = [
        LevelDefinition(
          id: 1,
          language: Language.english,
          seed: 1,
          gridSize: 6,
          wordCount: 4,
          categoryPool: const ['animals', 'food'],
          directionTier: DirectionTier.starter,
          theme: 'Mixed',
        ),
      ];

      final newly = Collections.newlyEarnedBy(
        levels: levels,
        completedBefore: const {},
        language: Language.english,
        justCompleted: 1,
      );

      expect(newly.map((b) => b.category).toSet(), {'animals', 'food'});
    });
  });

  test('CategoryBadge has value equality', () {
    const a = CategoryBadge(
      category: 'animals',
      language: Language.english,
      levelsCompleted: 2,
      levelsTotal: 3,
    );
    const b = CategoryBadge(
      category: 'animals',
      language: Language.english,
      levelsCompleted: 2,
      levelsTotal: 3,
    );

    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });
}
