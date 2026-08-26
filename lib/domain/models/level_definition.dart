import '../grid/grid_directions.dart';
import '../text/language.dart';

/// One row of `assets/content/levels.json` (Ch07/P10) — the STRUCTURE of a
/// level (how big, how many words, how hard the directions are), never the
/// actual word list. [WordEntry]s are drawn from a `words_{lang}.json` pack
/// at runtime via `WordSelector`, seeded by [seed], so the same
/// [LevelDefinition] always resolves to the same playable level without the
/// content pack needing to store word lists redundantly per level.
///
/// Plain final class, not `@freezed` — see the doc on `WordEntry` for why.
final class LevelDefinition {
  const LevelDefinition({
    required this.id,
    required this.language,
    required this.seed,
    required this.gridSize,
    required this.wordCount,
    required this.categoryPool,
    required this.directionTier,
    required this.theme,
  });

  /// 1–300. The SAME id repeats once per [Language] in the content file —
  /// level 47 in Urdu and level 47 in Hindi are different
  /// [LevelDefinition]s, matching how `level_progress` already keys
  /// completion by (language, level) (CLAUDE.md → Local persistence).
  final int id;

  final Language language;

  /// Feeds BOTH `GridGenerator.generate(seed:)` and `WordSelector` — the two
  /// independently create their own `Random(seed)`, so reusing one seed for
  /// both is safe (no shared stream) and is what makes a [LevelDefinition]
  /// alone enough to reproduce an identical playable level anywhere,
  /// forever, with nothing else stored.
  final int seed;

  final int gridSize;
  final int wordCount;

  /// Category names (`WordEntry.category`) eligible for this level. Usually
  /// one category — see `theme`, which is derived from it.
  final List<String> categoryPool;

  final DirectionTier directionTier;

  /// Display title for the level, e.g. "Animals". Not localized (CLAUDE.md
  /// → language names on the picker aren't either): content is per-language
  /// data already, and the category names here are themselves informal
  /// English labels an eventual l10n pass can map, not user-facing strings
  /// today.
  final String theme;

  factory LevelDefinition.fromJson(Map<String, Object?> json) =>
      LevelDefinition(
        id: json['id']! as int,
        language: Language.fromCode(json['lang']! as String),
        seed: json['seed']! as int,
        gridSize: json['gridSize']! as int,
        wordCount: json['wordCount']! as int,
        categoryPool: (json['categoryPool']! as List).cast<String>(),
        directionTier: DirectionTier.values.byName(
          json['directionTier']! as String,
        ),
        theme: json['theme']! as String,
      );

  @override
  bool operator ==(Object other) =>
      other is LevelDefinition &&
      other.id == id &&
      other.language == language &&
      other.seed == seed &&
      other.gridSize == gridSize &&
      other.wordCount == wordCount &&
      _listEquals(other.categoryPool, categoryPool) &&
      other.directionTier == directionTier &&
      other.theme == theme;

  @override
  int get hashCode => Object.hash(
    id,
    language,
    seed,
    gridSize,
    wordCount,
    Object.hashAll(categoryPool),
    directionTier,
    theme,
  );

  @override
  String toString() =>
      'LevelDefinition(id: $id, lang: ${language.code}, theme: $theme)';
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
