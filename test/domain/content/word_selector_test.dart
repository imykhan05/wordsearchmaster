import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/domain/content/word_selector.dart';
import 'package:word_search_master/domain/grid/grid_directions.dart';
import 'package:word_search_master/domain/models/level_definition.dart';
import 'package:word_search_master/domain/models/word_entry.dart';
import 'package:word_search_master/domain/text/language.dart';
import 'package:word_search_master/domain/text/script_normalizer.dart';

WordEntry _entry(
  String word,
  int graphemes,
  String category, {
  String? id,
  Language lang = Language.english,
}) => WordEntry(
  id: id ?? 'en_${category}_$word',
  lang: lang,
  word: word,
  display: word,
  roman: word,
  en: word,
  category: category,
  graphemes: graphemes,
  difficulty: 1,
  hint: 'hint',
);

LevelDefinition _level({
  int id = 1,
  Language language = Language.english,
  int seed = 1,
  int gridSize = 10,
  int wordCount = 3,
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
  final pool = [
    _entry('WATER', 5, 'nature'),
    _entry('FIRE', 4, 'nature'),
    _entry('WIND', 4, 'nature'),
    _entry('TREE', 4, 'nature'),
    _entry('BREAD', 5, 'food'),
    _entry('ENORMOUSWORD', 12, 'nature'),
  ];

  test('filters to the level categoryPool', () {
    final level = _level(
      categoryPool: const ['nature'],
      wordCount: 10,
      gridSize: 12,
    );
    final chosen = WordSelector.selectForLevel(level: level, pool: pool);
    expect(chosen.every((e) => e.category == 'nature'), isTrue);
    expect(chosen.any((e) => e.word == 'BREAD'), isFalse);
  });

  test('filters out words longer than gridSize', () {
    final level = _level(
      categoryPool: const ['nature'],
      wordCount: 10,
      gridSize: 6,
    );
    final chosen = WordSelector.selectForLevel(level: level, pool: pool);
    expect(chosen.any((e) => e.word == 'ENORMOUSWORD'), isFalse);
  });

  test('returns exactly wordCount when the eligible pool is large enough', () {
    final level = _level(
      categoryPool: const ['nature'],
      wordCount: 3,
      gridSize: 12,
    );
    final chosen = WordSelector.selectForLevel(level: level, pool: pool);
    expect(chosen, hasLength(3));
  });

  test(
    'returns fewer than wordCount, never throws, when the pool is too small',
    () {
      final level = _level(
        categoryPool: const ['food'],
        wordCount: 5,
        gridSize: 12,
      );
      final chosen = WordSelector.selectForLevel(level: level, pool: pool);
      expect(chosen, hasLength(1));
    },
  );

  test('an empty pool returns an empty list', () {
    expect(
      WordSelector.selectForLevel(level: _level(), pool: const []),
      isEmpty,
    );
  });

  test('never returns duplicates', () {
    final level = _level(
      categoryPool: const ['nature'],
      wordCount: 10,
      gridSize: 12,
    );
    final chosen = WordSelector.selectForLevel(level: level, pool: pool);
    expect(chosen.map((e) => e.id).toSet(), hasLength(chosen.length));
  });

  test('is deterministic for a fixed seed', () {
    final level = _level(
      categoryPool: const ['nature'],
      wordCount: 3,
      gridSize: 12,
      seed: 7,
    );
    final a = WordSelector.selectForLevel(
      level: level,
      pool: pool,
    ).map((e) => e.id).toList();
    final b = WordSelector.selectForLevel(
      level: level,
      pool: pool,
    ).map((e) => e.id).toList();
    expect(a, b);
  });

  test('different seeds can select a different subset', () {
    final chosenBySeed = <int, List<String>>{};
    for (var seed = 0; seed < 30; seed++) {
      final level = _level(
        categoryPool: const ['nature'],
        wordCount: 3,
        gridSize: 12,
        seed: seed,
      );
      chosenBySeed[seed] = WordSelector.selectForLevel(
        level: level,
        pool: pool,
      ).map((e) => e.id).toList()..sort();
    }
    expect(chosenBySeed.values.toSet().length, greaterThan(1));
  });

  test('prefers a grapheme-sharing candidate over a non-sharing one', () {
    // BE shares B with AB and nothing else here does — so whichever of the
    // four becomes the anchor, if a cohesive partner exists among the rest
    // it must be picked next, per WordSelector's whole reason for existing
    // (CLAUDE.md's Hindi-intersection fix).
    final cohesionPool = [
      _entry('AB', 2, 'x', id: 'e1'),
      _entry('CD', 2, 'x', id: 'e2'),
      _entry('BE', 2, 'x', id: 'e3'),
      _entry('FG', 2, 'x', id: 'e4'),
    ];

    for (var seed = 0; seed < 50; seed++) {
      final level = _level(
        categoryPool: const ['x'],
        wordCount: 2,
        gridSize: 4,
        seed: seed,
      );
      final chosen = WordSelector.selectForLevel(
        level: level,
        pool: cohesionPool,
      );
      expect(chosen, hasLength(2));

      final anchor = chosen.first;
      final anchorGraphemes = ScriptNormalizer.graphemes(
        anchor.word,
        Language.english,
      ).toSet();
      final cohesive = cohesionPool
          .where(
            (e) =>
                e.id != anchor.id &&
                ScriptNormalizer.graphemes(
                  e.word,
                  Language.english,
                ).any(anchorGraphemes.contains),
          )
          .toList();

      if (cohesive.isNotEmpty) {
        expect(cohesive, hasLength(1));
        expect(chosen[1].id, cohesive.first.id);
      }
    }
  });
}
