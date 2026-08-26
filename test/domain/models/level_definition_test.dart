import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/domain/grid/grid_directions.dart';
import 'package:word_search_master/domain/models/level_definition.dart';
import 'package:word_search_master/domain/text/language.dart';

LevelDefinition _level({
  int id = 1,
  Language language = Language.english,
  int seed = 42,
  int gridSize = 6,
  int wordCount = 4,
  List<String> categoryPool = const ['nature'],
  DirectionTier directionTier = DirectionTier.starter,
  String theme = 'Nature',
}) => LevelDefinition(
  id: id,
  language: language,
  seed: seed,
  gridSize: gridSize,
  wordCount: wordCount,
  categoryPool: categoryPool,
  directionTier: directionTier,
  theme: theme,
);

void main() {
  group('LevelDefinition.fromJson', () {
    test('parses every field', () {
      final level = LevelDefinition.fromJson(const {
        'id': 7,
        'lang': 'ur',
        'seed': 12345,
        'gridSize': 8,
        'wordCount': 4,
        'categoryPool': ['food'],
        'directionTier': 'basic',
        'theme': 'Food',
      });

      expect(level.id, 7);
      expect(level.language, Language.urdu);
      expect(level.seed, 12345);
      expect(level.gridSize, 8);
      expect(level.wordCount, 4);
      expect(level.categoryPool, ['food']);
      expect(level.directionTier, DirectionTier.basic);
      expect(level.theme, 'Food');
    });

    test('throws on an unknown directionTier', () {
      expect(
        () => LevelDefinition.fromJson(const {
          'id': 1,
          'lang': 'en',
          'seed': 1,
          'gridSize': 6,
          'wordCount': 4,
          'categoryPool': ['nature'],
          'directionTier': 'impossible',
          'theme': 'Nature',
        }),
        throwsA(anything),
      );
    });

    test('throws on a missing required field', () {
      expect(
        () => LevelDefinition.fromJson(const {'id': 1}),
        throwsA(anything),
      );
    });
  });

  group('equality', () {
    test('two levels with identical fields are equal', () {
      expect(_level(), _level());
      expect(_level().hashCode, _level().hashCode);
    });

    test('differing categoryPool order or content breaks equality', () {
      expect(_level(), isNot(_level(categoryPool: const ['food'])));
      expect(
        _level(categoryPool: const ['a', 'b']),
        isNot(_level(categoryPool: const ['b', 'a'])),
      );
    });

    test('differing on any single scalar field breaks equality', () {
      expect(_level(), isNot(_level(id: 2)));
      expect(_level(), isNot(_level(seed: 99)));
      expect(_level(), isNot(_level(directionTier: DirectionTier.all)));
      expect(_level(), isNot(_level(theme: 'Food')));
    });
  });

  test('toString is human-readable', () {
    expect(_level().toString(), contains('id: 1'));
    expect(_level().toString(), contains('Nature'));
  });
}
