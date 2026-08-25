import 'cell.dart';
import 'grid_vector.dart';

/// Where one word ended up.
final class WordPlacement {
  const WordPlacement({
    required this.word,
    required this.graphemes,
    required this.direction,
    required this.cells,
  });

  /// The NORMALIZED word (`ScriptNormalizer.normalize`), which is what the
  /// grid actually holds. Callers holding a display form must normalize
  /// before looking a word up.
  final String word;

  /// One entry per cell — grapheme clusters, never code points.
  final List<String> graphemes;

  final GridVector direction;

  /// The cells this word occupies, in reading order from its first grapheme.
  final List<Cell> cells;

  Cell get start => cells.first;
}

/// The output of [GridGenerator.generate].
final class GridResult {
  GridResult({
    required this.size,
    required List<List<String>> cells,
    required List<WordPlacement> placementDetails,
    required this.intersectionRatio,
    required this.attempts,
    required List<String> unplacedWords,
  }) : cells = List.unmodifiable([
         for (final row in cells) List<String>.unmodifiable(row),
       ]),
       placementDetails = List.unmodifiable(placementDetails),
       unplacedWords = List.unmodifiable(unplacedWords);

  /// The grid's side length. May exceed the requested size: the generator
  /// grows the grid rather than failing when words will not fit.
  final int size;

  /// `cells[row][col]` — exactly one grapheme cluster per cell.
  final List<List<String>> cells;

  final List<WordPlacement> placementDetails;

  /// Fraction of placed letters that sit on a shared cell.
  ///
  /// `1 - (distinctCellsUsed / totalLetters)`. Ch06 targets 0.15–0.30: too low
  /// and the words sit in isolation and the puzzle is trivial, too high and
  /// the grid looks like mush.
  final double intersectionRatio;

  /// Total (position, direction) candidates evaluated, across every word and
  /// every grid-size retry. Useful for spotting a level whose word set is
  /// pathologically hard to place.
  final int attempts;

  /// Words that could not be placed even after growing the grid.
  ///
  /// The generator never throws, so this is how a caller detects failure.
  /// P10's content validator fails the build when this is non-empty.
  final List<String> unplacedWords;

  bool get isComplete => unplacedWords.isEmpty;

  /// Word → its cells, as specified in Ch06. Keyed by the NORMALIZED word.
  Map<String, List<Cell>> get placements => {
    for (final placement in placementDetails)
      placement.word: List<Cell>.unmodifiable(placement.cells),
  };

  String cellAt(Cell cell) => cells[cell.row][cell.col];
}
