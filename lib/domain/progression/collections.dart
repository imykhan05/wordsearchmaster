/// Collections (Ch02) — one badge per completed category, per language.
///
/// PURE DART. A badge is DERIVED from level progress, never stored as a flag:
/// the `achievements` row that records an unlock is a cache of this
/// computation and a hook for the sync outbox, not its source of truth. That
/// ordering matters, because a stored flag is one number to forge, while this
/// requires forging every `level_progress` row underneath it — the same
/// argument `ProgressRepository.watchHighestCompletedLevel` already makes.
///
/// ---------------------------------------------------------------------------
/// PER LANGUAGE, AND THAT IS THE POINT
///
/// Level 47 in Urdu and level 47 in Hindi are different puzzles drawn from
/// different word packs (P10), and `level_progress` already keys completion by
/// `(language, level)`. So "collected ANIMALS" has to mean "collected ANIMALS
/// in this language" — 12 categories x 3 languages is 36 badges, and a player
/// who switches script starts that script's shelf empty. Collapsing them onto
/// one shelf per category would hand a trilingual player two thirds of the
/// collection for free.
library;

import '../models/level_definition.dart';
import '../text/language.dart';

/// One collectible slot: a (category, language) pair and how far along it is.
final class CategoryBadge {
  const CategoryBadge({
    required this.category,
    required this.language,
    required this.levelsCompleted,
    required this.levelsTotal,
  });

  /// A `WordEntry.category` / `LevelDefinition.categoryPool` entry.
  final String category;
  final Language language;

  final int levelsCompleted;
  final int levelsTotal;

  /// Filled. Ch02's grid shows this as a solid slot; anything else is an
  /// outline.
  bool get isEarned => levelsTotal > 0 && levelsCompleted >= levelsTotal;

  /// 0.0–1.0, for the progress ring drawn inside an unearned slot.
  ///
  /// A category spans ~25 levels, so a purely binary filled/empty grid would
  /// sit entirely empty for a player's first several hours — technically what
  /// Ch02 asks for and a poor read of why it asks for it. The slot is still
  /// binary; the ring just tells the player the shelf is reachable.
  double get progress {
    if (levelsTotal <= 0) return 0;
    final ratio = levelsCompleted / levelsTotal;
    return ratio < 0
        ? 0
        : ratio > 1
        ? 1
        : ratio;
  }

  /// The `achievements.id` this badge is recorded under when earned.
  ///
  /// Namespaced so the achievements table can hold other Ch12 unlockables
  /// later without a collision, and readable in a support ticket without a
  /// lookup table.
  String get achievementId => achievementIdFor(category, language);

  static String achievementIdFor(String category, Language language) =>
      'collection:${language.code}:$category';

  @override
  bool operator ==(Object other) =>
      other is CategoryBadge &&
      other.category == category &&
      other.language == language &&
      other.levelsCompleted == levelsCompleted &&
      other.levelsTotal == levelsTotal;

  @override
  int get hashCode =>
      Object.hash(category, language, levelsCompleted, levelsTotal);

  @override
  String toString() =>
      'CategoryBadge($category/${language.code}: '
      '$levelsCompleted/$levelsTotal${isEarned ? ' EARNED' : ''})';
}

/// Derives badges from level definitions plus completed levels.
abstract final class Collections {
  /// Every badge for [language], ordered by category name so the grid is
  /// stable between builds.
  ///
  /// [levels] is that language's full [LevelDefinition] set;
  /// [completedLevels] the level numbers finished in it. A level counts toward
  /// EVERY category in its `categoryPool` — the pool is a single category
  /// today (P10), but the rule is written against the field rather than
  /// against that happening to be true.
  static List<CategoryBadge> forLanguage({
    required List<LevelDefinition> levels,
    required Set<int> completedLevels,
    required Language language,
  }) {
    final totals = <String, int>{};
    final done = <String, int>{};

    for (final level in levels) {
      if (level.language != language) continue;
      for (final category in level.categoryPool) {
        totals[category] = (totals[category] ?? 0) + 1;
        if (completedLevels.contains(level.id)) {
          done[category] = (done[category] ?? 0) + 1;
        }
      }
    }

    final categories = totals.keys.toList()..sort();
    return [
      for (final category in categories)
        CategoryBadge(
          category: category,
          language: language,
          levelsCompleted: done[category] ?? 0,
          levelsTotal: totals[category]!,
        ),
    ];
  }

  /// The badges that a completion at [justCompleted] pushed over the line.
  ///
  /// Computed as a DIFFERENCE between two full evaluations — the badges earned
  /// after the completion minus those already earned before it — so an unlock
  /// fires exactly once.
  ///
  /// [completedBefore] IS THE LEVEL SET AS IT WAS BEFORE THIS COMPLETION, and
  /// the caller must read it before writing the new progress row. That
  /// ordering is the whole correctness argument: an earlier version of this
  /// took the set AFTER the write and reconstructed "before" by subtracting
  /// [justCompleted], which is wrong for a REPLAY — subtracting a level the
  /// player had already finished makes the category look incomplete, so
  /// finishing an old level in a completed category re-fired its badge every
  /// time. There is no way to tell those two cases apart from the after-set
  /// alone, so the API asks for the one that carries the answer.
  static List<CategoryBadge> newlyEarnedBy({
    required List<LevelDefinition> levels,
    required Set<int> completedBefore,
    required Language language,
    required int justCompleted,
  }) {
    final before = {
      for (final badge in forLanguage(
        levels: levels,
        completedLevels: completedBefore,
        language: language,
      ))
        if (badge.isEarned) badge.category,
    };

    return [
      for (final badge in forLanguage(
        levels: levels,
        completedLevels: {...completedBefore, justCompleted},
        language: language,
      ))
        if (badge.isEarned && !before.contains(badge.category)) badge,
    ];
  }
}
