// Wired into CI (.github/workflows/ci.yaml). Run locally with:
//   dart run tool/validate_content.dart
//
// Runs every check in Chapter 07's content validation list against the
// generated assets/content/ pack: schema/consistency checks on the three
// words_{lang}.json packs and levels.json, then exercises GridGenerator
// directly so a content change that would leave a player stuck on an
// unplaceable level fails the build instead. See CLAUDE.md → Content
// pipeline (P10).
//
// A plain-Dart CLI, not a Flutter one: it must run via `dart run`, so it (and
// everything it imports) stays clear of `package:flutter` — the standalone
// Dart SDK has no `dart:ui`, which `package:flutter` ultimately needs. Every
// import below is `lib/domain/**`, which CI's own check_domain_purity.dart
// already guarantees is pure Dart.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:word_search_master/domain/content/blocklist_parser.dart';
import 'package:word_search_master/domain/content/word_selector.dart';
import 'package:word_search_master/domain/grid/grid_directions.dart';
import 'package:word_search_master/domain/grid/grid_generator.dart';
import 'package:word_search_master/domain/models/level_definition.dart';
import 'package:word_search_master/domain/models/word_entry.dart';
import 'package:word_search_master/domain/text/language.dart';
import 'package:word_search_master/domain/text/script_normalizer.dart';

/// The twelve Ch07 categories. The one place both word packs and level
/// definitions are checked against — see CLAUDE.md's `RowTags` rationale for
/// why a single definition matters more than it looks like it should.
const knownCategories = {
  'animals',
  'body',
  'colors',
  'family',
  'food',
  'home',
  'nature',
  'numbers',
  'professions',
  'school',
  'sports',
  'weather',
};

const minGraphemes = 2;
const maxGraphemes = 9;
const wordsPerLanguage = 320;
const minWordsPerCategory = 24;

/// One step of the Ch07 difficulty curve, mirrored here from
/// `test/domain/grid/word_fixtures.dart`'s `ch07Curve` — that fixture is
/// test-only, so the validator (a separate entrypoint, not a test) restates
/// the same table rather than depending on `test/`.
final class CurveStep {
  const CurveStep({
    required this.maxLevel,
    required this.gridSize,
    required this.wordCount,
  });

  final int maxLevel;
  final int gridSize;
  final int wordCount;
}

const curve = [
  CurveStep(maxLevel: 5, gridSize: 6, wordCount: 4),
  CurveStep(maxLevel: 20, gridSize: 8, wordCount: 6),
  CurveStep(maxLevel: 60, gridSize: 10, wordCount: 8),
  CurveStep(maxLevel: 150, gridSize: 10, wordCount: 10),
  CurveStep(maxLevel: 300, gridSize: 12, wordCount: 12),
];

CurveStep curveFor(int level) => curve.firstWhere(
  (step) => level <= step.maxLevel,
  orElse: () => curve.last,
);

/// The breather rule: every 7th level trims `wordCount` by 2 (never below 3)
/// and leaves `gridSize`/`directionTier` untouched.
int expectedWordCount(int id, CurveStep step) => id % 7 == 0
    ? (step.wordCount - 2).clamp(3, step.wordCount)
    : step.wordCount;

int expectedDifficulty(int graphemes) => switch (graphemes) {
  <= 3 => 1,
  <= 5 => 2,
  <= 7 => 3,
  8 => 4,
  _ => 5,
};

Future<void> main(List<String> args) async {
  final root = args.isNotEmpty ? args.first : '.';
  final problems = <String>[];

  final wordsByLanguage = <Language, List<WordEntry>>{};
  for (final language in Language.values) {
    final entries = loadWordPack(root, language, problems);
    wordsByLanguage[language] = entries;
    problems.addAll(validateWordEntries(language, entries));
  }

  final allLevels = <LevelDefinition>[];
  final levelsById = <int, Map<Language, LevelDefinition>>{};
  loadLevels(root, problems, allLevels, levelsById);
  problems.addAll(validateLevels(allLevels, levelsById));

  final blocklists = <Language, Set<String>>{};
  for (final language in Language.values) {
    blocklists[language] = loadBlocklist(root, language, problems);
  }

  if (problems.isEmpty) {
    problems.addAll(validateLevelWordAvailability(allLevels, wordsByLanguage));
  }

  if (problems.isNotEmpty) {
    fail(problems);
    return;
  }

  final totalWords = wordsByLanguage.values.fold(0, (n, l) => n + l.length);
  stdout.writeln(
    'validate_content: schema OK — $totalWords words, ${allLevels.length} '
    'levels, all Ch07 checks passed.',
  );

  final placementFailures = validateCanonicalPlacement(
    allLevels,
    wordsByLanguage,
    blocklists,
  );
  if (placementFailures.isNotEmpty) {
    fail([
      'canonical-seed placement pass: ${placementFailures.length}/'
          '${allLevels.length} level(s) failed to place completely:',
      ...placementFailures,
    ]);
    return;
  }
  stdout.writeln(
    'validate_content: canonical-seed placement OK — all ${allLevels.length} '
    '(level, language) combinations place completely.',
  );

  const fuzzIterations = 500;
  final fuzzFailures = validateFuzzPlacement(
    levelsById,
    wordsByLanguage,
    blocklists,
    iterations: fuzzIterations,
    metaSeed: 20260826,
  );
  if (fuzzFailures.isNotEmpty) {
    fail([
      '500x fuzz pass: ${fuzzFailures.length}/$fuzzIterations iteration(s) '
          'failed to place completely:',
      ...fuzzFailures,
    ]);
    return;
  }
  stdout.writeln(
    'validate_content: 500x fuzz OK — $fuzzIterations freshly-reseeded '
    'generations sampled across the curve all placed completely.',
  );

  stdout.writeln('validate_content: OK — all checks passed.');
}

void fail(List<String> problems) {
  stderr.writeln('validate_content: FAILED — ${problems.length} problem(s):');
  const maxPrinted = 40;
  for (final problem in problems.take(maxPrinted)) {
    stderr.writeln('  $problem');
  }
  if (problems.length > maxPrinted) {
    stderr.writeln('  … and ${problems.length - maxPrinted} more');
  }
  exitCode = 1;
}

// ---------------------------------------------------------------------------
// Loading (dart:io — the only I/O in this file).
// ---------------------------------------------------------------------------

List<WordEntry> loadWordPack(
  String root,
  Language language,
  List<String> problems,
) {
  final path = '$root/assets/content/words_${language.code}.json';
  final file = File(path);
  final label = 'words_${language.code}.json';

  if (!file.existsSync()) {
    problems.add('$label: file not found at $path');
    return const [];
  }

  final Map<String, Object?> json;
  try {
    json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  } catch (e) {
    problems.add('$label: invalid JSON — $e');
    return const [];
  }

  final rawList = json['words'];
  if (rawList is! List) {
    problems.add('$label: missing or non-list "words" key');
    return const [];
  }

  final entries = <WordEntry>[];
  for (var i = 0; i < rawList.length; i++) {
    try {
      entries.add(
        WordEntry.fromJson((rawList[i] as Map).cast<String, Object?>()),
      );
    } catch (e) {
      problems.add('$label[$i]: failed to parse — $e');
    }
  }
  return entries;
}

void loadLevels(
  String root,
  List<String> problems,
  List<LevelDefinition> allLevels,
  Map<int, Map<Language, LevelDefinition>> levelsById,
) {
  final path = '$root/assets/content/levels.json';
  final file = File(path);
  const label = 'levels.json';

  if (!file.existsSync()) {
    problems.add('$label: file not found at $path');
    return;
  }

  final Map<String, Object?> json;
  try {
    json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  } catch (e) {
    problems.add('$label: invalid JSON — $e');
    return;
  }

  final rawList = json['levels'];
  if (rawList is! List) {
    problems.add('$label: missing or non-list "levels" key');
    return;
  }

  for (var i = 0; i < rawList.length; i++) {
    try {
      final level = LevelDefinition.fromJson(
        (rawList[i] as Map).cast<String, Object?>(),
      );
      allLevels.add(level);
      (levelsById[level.id] ??= {})[level.language] = level;
    } catch (e) {
      problems.add('$label[$i]: failed to parse — $e');
    }
  }
}

Set<String> loadBlocklist(
  String root,
  Language language,
  List<String> problems,
) {
  final path = '$root/assets/content/blocklist_${language.code}.txt';
  final file = File(path);
  if (!file.existsSync()) {
    problems.add('blocklist_${language.code}.txt: file not found at $path');
    return const {};
  }
  return BlocklistParser.parse(file.readAsStringSync());
}

// ---------------------------------------------------------------------------
// Schema / consistency checks — pure functions over already-parsed data, so
// they're unit-testable with hand-built fixtures and no file I/O at all.
// ---------------------------------------------------------------------------

List<String> validateWordEntries(Language language, List<WordEntry> entries) {
  final problems = <String>[];
  final seenIds = <String>{};
  final perCategory = <String, int>{};

  for (final entry in entries) {
    final where = '${entry.id} (${language.code})';

    if (entry.lang != language) {
      problems.add(
        '$where: lang field is ${entry.lang.code}, expected ${language.code}',
      );
    }
    if (!seenIds.add(entry.id)) {
      problems.add('$where: duplicate id');
    }

    if (entry.word.isEmpty) {
      problems.add('$where: empty word');
    } else {
      final renormalized = ScriptNormalizer.normalize(entry.word, language);
      if (renormalized != entry.word) {
        problems.add(
          '$where: word "${entry.word}" is not normalized '
          '(normalizes to "$renormalized")',
        );
      }
    }

    final liveCount = ScriptNormalizer.graphemeCount(entry.word, language);
    if (entry.graphemes != liveCount) {
      problems.add(
        '$where: stored graphemes=${entry.graphemes} but recompute=$liveCount',
      );
    }
    if (entry.graphemes < minGraphemes || entry.graphemes > maxGraphemes) {
      problems.add(
        '$where: graphemes=${entry.graphemes} outside $minGraphemes-$maxGraphemes',
      );
    }

    if (!knownCategories.contains(entry.category)) {
      problems.add('$where: unknown category "${entry.category}"');
    } else {
      perCategory[entry.category] = (perCategory[entry.category] ?? 0) + 1;
    }

    final wantDifficulty = expectedDifficulty(entry.graphemes);
    if (entry.difficulty != wantDifficulty) {
      problems.add(
        '$where: difficulty=${entry.difficulty}, expected $wantDifficulty '
        'for graphemes=${entry.graphemes}',
      );
    }
    if (entry.difficulty < 1 || entry.difficulty > 5) {
      problems.add('$where: difficulty=${entry.difficulty} outside 1-5');
    }

    if (entry.display.isEmpty) problems.add('$where: empty display');
    if (entry.roman.isEmpty) problems.add('$where: empty roman');
    if (entry.en.isEmpty) problems.add('$where: empty en');
    if (entry.hint.isEmpty) problems.add('$where: empty hint');
  }

  if (entries.length != wordsPerLanguage) {
    problems.add(
      'words_${language.code}.json: ${entries.length} entries, expected '
      'exactly $wordsPerLanguage',
    );
  }
  for (final category in knownCategories) {
    final count = perCategory[category] ?? 0;
    if (count < minWordsPerCategory) {
      problems.add(
        'words_${language.code}.json: category "$category" has $count '
        'entries, expected at least $minWordsPerCategory',
      );
    }
  }

  return problems;
}

List<String> validateLevels(
  List<LevelDefinition> allLevels,
  Map<int, Map<Language, LevelDefinition>> levelsById,
) {
  final problems = <String>[];
  final seenPairs = <String>{};
  final seedById = <int, int>{};

  for (final level in allLevels) {
    final where = 'level ${level.id} (${level.language.code})';

    if (!seenPairs.add('${level.id}_${level.language.code}')) {
      problems.add('$where: duplicate (id, language) entry');
    }
    if (level.id < 1 || level.id > 300) {
      problems.add('$where: id ${level.id} outside 1-300');
    }

    final step = curveFor(level.id);
    final wantWordCount = expectedWordCount(level.id, step);
    if (level.gridSize != step.gridSize) {
      problems.add(
        '$where: gridSize=${level.gridSize}, expected ${step.gridSize} per '
        'the Ch07 curve',
      );
    }
    if (level.wordCount != wantWordCount) {
      final breather = level.id % 7 == 0 ? ' (breather level)' : '';
      problems.add(
        '$where: wordCount=${level.wordCount}, expected $wantWordCount per '
        'the Ch07 curve$breather',
      );
    }
    if (level.wordCount < 3) {
      problems.add(
        '$where: wordCount=${level.wordCount} is below the minimum playable 3',
      );
    }
    if (level.gridSize < 1 || level.gridSize > GridGenerator.maxSize) {
      problems.add(
        '$where: gridSize=${level.gridSize} outside 1-${GridGenerator.maxSize}',
      );
    }

    final wantTier = DirectionTier.forLevel(level.id);
    if (level.directionTier != wantTier) {
      problems.add(
        '$where: directionTier=${level.directionTier.name}, expected '
        '${wantTier.name}',
      );
    }

    if (level.categoryPool.isEmpty) {
      problems.add('$where: empty categoryPool');
    }
    for (final category in level.categoryPool) {
      if (!knownCategories.contains(category)) {
        problems.add('$where: categoryPool has unknown category "$category"');
      }
    }
    if (level.theme.isEmpty) {
      problems.add('$where: empty theme');
    }

    if (level.seed < 0) {
      problems.add('$where: negative seed ${level.seed}');
    }
    final existingSeed = seedById[level.id];
    if (existingSeed == null) {
      seedById[level.id] = level.seed;
    } else if (existingSeed != level.seed) {
      problems.add(
        '$where: seed=${level.seed} differs from level ${level.id}\'s other '
        'language(s) (seed=$existingSeed) — one level id must reuse the same '
        'seed across every language',
      );
    }
  }

  for (var id = 1; id <= 300; id++) {
    final byLanguage = levelsById[id];
    for (final language in Language.values) {
      if (byLanguage == null || !byLanguage.containsKey(language)) {
        problems.add(
          'levels.json: missing level $id for language ${language.code}',
        );
      }
    }
  }

  return problems;
}

/// Confirms `WordSelector` will actually have enough to work with — the
/// filtered-eligible-pool size (`category ∈ categoryPool` AND
/// `graphemes <= gridSize`) must reach `wordCount` for every level, or a
/// player would be handed a level `WordSelector` cannot fill.
List<String> validateLevelWordAvailability(
  List<LevelDefinition> allLevels,
  Map<Language, List<WordEntry>> wordsByLanguage,
) {
  final problems = <String>[];
  for (final level in allLevels) {
    final pool = wordsByLanguage[level.language] ?? const [];
    final eligible = pool
        .where(
          (entry) =>
              level.categoryPool.contains(entry.category) &&
              entry.graphemes <= level.gridSize,
        )
        .length;
    if (eligible < level.wordCount) {
      problems.add(
        'level ${level.id} (${level.language.code}): only $eligible eligible '
        'word(s) in the pool for wordCount=${level.wordCount} '
        '(categoryPool=${level.categoryPool}, gridSize=${level.gridSize})',
      );
    }
  }
  return problems;
}

// ---------------------------------------------------------------------------
// Generator-exercising checks. These call the real GridGenerator/WordSelector
// so a content change that would strand a player on an unplaceable level
// fails HERE, not in production.
// ---------------------------------------------------------------------------

/// Every real (level, language) combination, generated on its own canonical
/// seed exactly as the app would generate it.
List<String> validateCanonicalPlacement(
  List<LevelDefinition> allLevels,
  Map<Language, List<WordEntry>> wordsByLanguage,
  Map<Language, Set<String>> blocklists,
) {
  final failures = <String>[];
  for (final level in allLevels) {
    final failure = _tryPlace(
      level: level,
      generatorSeed: level.seed,
      pool: wordsByLanguage[level.language] ?? const [],
      blocklist: blocklists[level.language] ?? const {},
    );
    if (failure != null) failures.add(failure);
  }
  return failures;
}

/// [iterations] freshly-reseeded generations, sampled across the real curve
/// (a random real level's shape, a random language) but with a BRAND NEW seed
/// each time rather than that level's canonical one — this is what exercises
/// the generator's general robustness (Ch07's "generate this level 500
/// times"), on top of [validateCanonicalPlacement]'s exact-content guarantee.
/// [metaSeed] makes the sample itself reproducible from one run to the next.
List<String> validateFuzzPlacement(
  Map<int, Map<Language, LevelDefinition>> levelsById,
  Map<Language, List<WordEntry>> wordsByLanguage,
  Map<Language, Set<String>> blocklists, {
  required int iterations,
  required int metaSeed,
}) {
  final failures = <String>[];
  final meta = Random(metaSeed);
  final languages = Language.values;

  for (var i = 0; i < iterations; i++) {
    final id = meta.nextInt(300) + 1;
    final language = languages[meta.nextInt(languages.length)];
    final base = levelsById[id]?[language];
    if (base == null) continue; // Already reported by validateLevels.

    final freshSeed = meta.nextInt(0x7FFFFFFF);
    final fuzzLevel = LevelDefinition(
      id: base.id,
      language: base.language,
      seed: freshSeed,
      gridSize: base.gridSize,
      wordCount: base.wordCount,
      categoryPool: base.categoryPool,
      directionTier: base.directionTier,
      theme: base.theme,
    );

    final failure = _tryPlace(
      level: fuzzLevel,
      generatorSeed: freshSeed,
      pool: wordsByLanguage[language] ?? const [],
      blocklist: blocklists[language] ?? const {},
      label: 'fuzz #$i',
    );
    if (failure != null) failures.add(failure);
  }

  return failures;
}

String? _tryPlace({
  required LevelDefinition level,
  required int generatorSeed,
  required List<WordEntry> pool,
  required Set<String> blocklist,
  String? label,
}) {
  final where =
      '${label != null ? '$label — ' : ''}level ${level.id} '
      '(${level.language.code}, seed $generatorSeed)';

  final chosen = WordSelector.selectForLevel(level: level, pool: pool);
  if (chosen.length < level.wordCount) {
    return '$where: WordSelector only found ${chosen.length}/'
        '${level.wordCount} eligible words';
  }

  final result = GridGenerator.generate(
    seed: generatorSeed,
    size: level.gridSize,
    words: [for (final entry in chosen) entry.word],
    lang: level.language,
    allowedDirections: GridDirections.forLanguage(
      level.language,
      level.directionTier,
    ),
    blocklist: blocklist,
  );

  if (!result.isComplete) {
    return '$where: ${result.unplacedWords.length} word(s) unplaced — '
        '${result.unplacedWords.join(', ')}';
  }
  return null;
}
