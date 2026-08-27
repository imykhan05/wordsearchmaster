/// The Daily Challenge's puzzle shape (Ch12).
///
/// PURE DART, and every input is either the date or the language — which is
/// the whole point. `ContentRepository.getDailySeed` already derives
/// `sha256(utcDate + langCode)` on-device (P10); this turns that seed into a
/// full [LevelDefinition], so the daily puzzle is COMPUTED, never fetched.
/// That is what makes Ch12's promise literal: the Daily is playable in
/// airplane mode because there was never a network call in the path.
///
/// ---------------------------------------------------------------------------
/// WHY A FIXED SHAPE INSTEAD OF A LEVEL FROM THE CURVE
///
/// The daily is a LEADERBOARD puzzle: every player's score has to be
/// comparable, so every player has to get the same board. Borrowing a level
/// from the Ch07 curve would tie the daily's size to where the borrowed level
/// sits, and a player at level 3 and one at level 280 would be compared across
/// a 6x6 and a 12x12. So the size, the word count and the direction tier are
/// CONSTANTS here, and only the CATEGORY and the seed move with the date —
/// enough variety that two consecutive days feel different, none of it enough
/// to make two players' days different from each other.
///
/// The shape is deliberately mid-curve (a 10x10 with 8 words, diagonals but no
/// reversals): hard enough to be worth a leaderboard, reachable for a player
/// on their first day who has never seen a 12x12.
library;

import '../grid/grid_directions.dart';
import '../models/level_definition.dart';
import '../text/language.dart';
import 'day_key.dart';

abstract final class DailyPuzzle {
  /// Matches the Ch07 curve's levels 21–60 band.
  static const int gridSize = 10;
  static const int wordCount = 8;
  static const DirectionTier directionTier = DirectionTier.diagonal;

  /// The `LevelDefinition.id` a daily carries.
  ///
  /// Zero, which is never a real journey level (they are 1–300), so a daily
  /// definition can never be mistaken for one — including by
  /// `ProgressRepository`, which would otherwise happily record a daily as
  /// level progress and unlock a journey node the player never played.
  static const int levelId = 0;

  /// The puzzle for [day] in [language].
  ///
  /// [seed] is `ContentRepository.getDailySeed(day, language)`; it is passed
  /// in rather than computed here so this file stays free of `package:crypto`
  /// and of any notion of where content comes from.
  ///
  /// [categories] is the language's category list; the day's category is
  /// picked from it by the seed, so it is the same everywhere without any
  /// coordination. An empty list falls back to an empty pool, which
  /// `WordSelector` answers with an empty word list rather than a crash — the
  /// same degrade-don't-throw contract the rest of the content path keeps.
  static LevelDefinition definitionFor({
    required DayKey day,
    required Language language,
    required int seed,
    required List<String> categories,
  }) {
    final category = categories.isEmpty
        ? null
        : categories[seed.abs() % categories.length];

    return LevelDefinition(
      id: levelId,
      language: language,
      seed: seed,
      gridSize: gridSize,
      wordCount: wordCount,
      categoryPool: category == null ? const [] : [category],
      directionTier: directionTier,
      // The date, not the category: a daily is identified by its day
      // everywhere else in the app (`daily_results` is keyed by it), and a
      // theme that read "Animals" would collide with a journey region header.
      theme: day.toString(),
    );
  }
}
