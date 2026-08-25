import '../text/language.dart';
import 'grid_vector.dart';

/// How hard the direction set is, per the difficulty curve in Ch06/Ch07.
///
/// Stored per level in `levels.json` (P10) as `directionTier`, so the curve
/// is content that can be retuned without a code change.
enum DirectionTier {
  /// Levels 1–5. Reading direction and straight down. The player should win
  /// their first few levels — that is the whole job of these levels.
  starter,

  /// Levels 6–20. Adds upward, so vertical scanning goes both ways.
  basic,

  /// Levels 21–60. Diagonals unlock. "Asli game shuru".
  diagonal,

  /// Levels 61–150. Adds words written against the reading direction.
  reverse,

  /// Levels 151–300. All eight.
  all;

  /// The tier a given level number sits in, following the Ch07 curve table.
  ///
  /// Clamps rather than throwing: an out-of-range level id from bad content
  /// should degrade to the hardest tier, not crash a player's session.
  static DirectionTier forLevel(int level) {
    if (level <= 5) return DirectionTier.starter;
    if (level <= 20) return DirectionTier.basic;
    if (level <= 60) return DirectionTier.diagonal;
    if (level <= 150) return DirectionTier.reverse;
    return DirectionTier.all;
  }
}

/// The direction vectors a word may be placed along, per language and tier.
///
/// Language-aware by construction: "forward" means west in Urdu and east in
/// Hindi/English, and the diagonals mirror to match. A tier therefore feels
/// equally hard in every language, which a fixed vector list would not.
abstract final class GridDirections {
  /// The allowed directions for [language] at [tier].
  ///
  /// The returned list is unmodifiable and its order is stable, so a seeded
  /// generator produces identical grids across runs (P04's determinism
  /// requirement depends on this).
  static List<GridVector> forLanguage(Language language, DirectionTier tier) {
    final forward = language.primaryDirection;
    final backward = language.reverseDirection;

    // Diagonals that travel in the reading direction: down-forward and
    // up-forward. In Urdu these lean the opposite way to English, which is
    // exactly what a native reader expects.
    final forwardDown = GridVector(forward.dx, 1);
    final forwardUp = GridVector(forward.dx, -1);
    final backwardDown = GridVector(backward.dx, 1);
    final backwardUp = GridVector(backward.dx, -1);

    return switch (tier) {
      DirectionTier.starter => List.unmodifiable([forward, GridVector.south]),
      DirectionTier.basic => List.unmodifiable([
        forward,
        GridVector.south,
        GridVector.north,
      ]),
      DirectionTier.diagonal => List.unmodifiable([
        forward,
        GridVector.south,
        GridVector.north,
        forwardDown,
        forwardUp,
      ]),
      DirectionTier.reverse => List.unmodifiable([
        forward,
        GridVector.south,
        GridVector.north,
        forwardDown,
        forwardUp,
        backward,
      ]),
      DirectionTier.all => List.unmodifiable([
        forward,
        GridVector.south,
        GridVector.north,
        forwardDown,
        forwardUp,
        backward,
        backwardDown,
        backwardUp,
      ]),
    };
  }

  /// Convenience for callers that have a level number rather than a tier.
  static List<GridVector> forLevel(Language language, int level) =>
      forLanguage(language, DirectionTier.forLevel(level));
}
