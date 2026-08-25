import 'dart:math';

import '../text/language.dart';
import '../text/script_normalizer.dart';
import 'cell.dart';
import 'grid_point.dart';
import 'grid_vector.dart';

/// The live state of a drag across the grid.
///
/// Immutable — [SelectionResolver] returns a new one per pointer move, so the
/// game controller can hold it in Riverpod state without mutation surprises.
final class SelectionState {
  const SelectionState({
    required this.anchor,
    required this.direction,
    required this.cells,
  });

  static const SelectionState empty = SelectionState(
    anchor: null,
    direction: null,
    cells: [],
  );

  /// The cell the finger first touched. Fixed for the whole drag.
  final Cell? anchor;

  /// One of the eight vectors, locked once the drag leaves the anchor cell.
  /// Null while the selection is still just the anchor — that is what lets a
  /// player who set off the wrong way come back and pick a new direction
  /// without lifting their finger.
  final GridVector? direction;

  /// The selected run, starting at [anchor].
  final List<Cell> cells;

  bool get isEmpty => cells.isEmpty;

  /// A legal, non-empty run inside the grid. The resolver clamps and projects,
  /// so any state it produces satisfies this; it is exposed because Ch06's
  /// contract names it.
  bool get isValid => cells.isNotEmpty;

  /// A single cell can never be a word — the shortest content word is two
  /// graphemes (Ch07) — so this is the "tap, not drag" case.
  bool get isTap => cells.length == 1;
}

/// The result of lifting the finger.
final class SelectionOutcome {
  const SelectionOutcome({required this.cells, required this.matchedWord});

  static const SelectionOutcome none = SelectionOutcome(
    cells: [],
    matchedWord: null,
  );

  /// The selected cells, ORIENTED TO THE MATCHED WORD: `cells[i]` holds
  /// grapheme `i` of [matchedWord]. When the player traced the word backwards
  /// these are reversed relative to the drag, so P09's strike-through and
  /// particle sequence always run along the word's reading direction.
  final List<Cell> cells;

  /// The word that was found, in its normalized form, or null.
  final String? matchedWord;

  bool get isValid => matchedWord != null;
}

/// Turns pointer movement into a selected run of cells, and decides on release
/// whether it spells one of the remaining words.
///
/// PURE DART. Implements the Ch06 contract:
///
///  1. the first touched cell locks the anchor;
///  2. the second cell locks the direction to one of the eight vectors;
///  3. after that the pointer is PROJECTED onto that line — wandering off it
///     must not break the selection, which is the whole secret of the sticky
///     feel;
///  4. dragging back toward the anchor removes cells;
///  5. on release the sequence is normalized and matched against the remaining
///     words, forwards and backwards.
final class SelectionResolver {
  const SelectionResolver({required this.size});

  final int size;

  /// A drag may be attempted in any of the eight directions, regardless of
  /// which directions the level actually placed words along. Restricting the
  /// drag to the level's tier would make the finger feel stuck for no visible
  /// reason; an unproductive direction simply matches nothing.
  static const List<GridVector> directions = GridVector.all;

  /// Begins a drag. Returns [SelectionState.empty] if the touch was outside
  /// the grid.
  SelectionState begin(GridPoint point) {
    final cell = point.cell;
    if (!cell.isInside(size)) return SelectionState.empty;

    return SelectionState(anchor: cell, direction: null, cells: [cell]);
  }

  /// Extends, shrinks or re-aims the selection as the finger moves.
  SelectionState extendTo(SelectionState state, GridPoint point) {
    final anchor = state.anchor;
    if (anchor == null) return begin(point);

    final dx = point.x - (anchor.col + 0.5);
    final dy = point.y - (anchor.row + 0.5);

    // Still inside the anchor cell: nothing to aim at yet.
    final direction = state.direction ?? _snapToEight(dx, dy);
    if (direction == null) {
      return SelectionState(anchor: anchor, direction: null, cells: [anchor]);
    }

    // Project the pointer onto the locked line. `steps` is how many cells
    // along that line the finger currently reaches — off-line movement only
    // changes the component that gets discarded.
    final lengthSquared =
        (direction.dx * direction.dx + direction.dy * direction.dy).toDouble();
    final projected = (dx * direction.dx + dy * direction.dy) / lengthSquared;

    final steps = projected.round().clamp(0, _maxSteps(anchor, direction));

    // Back at the anchor: release the direction so the next move can choose a
    // new one without lifting a finger.
    if (steps == 0) {
      return SelectionState(anchor: anchor, direction: null, cells: [anchor]);
    }

    return SelectionState(
      anchor: anchor,
      direction: direction,
      cells: [for (var i = 0; i <= steps; i++) anchor.stepBy(direction, i)],
    );
  }

  /// Decides what the finished drag spelled.
  ///
  /// [remainingWords] are the words still to be found; already-found words are
  /// excluded by the caller so re-tracing one does not re-score it.
  SelectionOutcome release({
    required SelectionState state,
    required List<List<String>> grid,
    required Iterable<String> remainingWords,
    required Language language,
  }) {
    // A tap is not an attempt at a word.
    if (state.cells.length < 2) return SelectionOutcome.none;

    final graphemes = [
      for (final cell in state.cells) grid[cell.row][cell.col],
    ];

    final forward = ScriptNormalizer.normalize(graphemes.join(), language);
    final backward = ScriptNormalizer.normalize(
      graphemes.reversed.join(),
      language,
    );

    for (final word in remainingWords) {
      final target = ScriptNormalizer.normalize(word, language);
      if (target.isEmpty) continue;

      if (target == forward) {
        return SelectionOutcome(
          cells: List.unmodifiable(state.cells),
          matchedWord: target,
        );
      }
      if (target == backward) {
        // Traced backwards: hand back the cells the other way round so the
        // caller animates along the word, not along the finger.
        return SelectionOutcome(
          cells: List.unmodifiable(state.cells.reversed.toList()),
          matchedWord: target,
        );
      }
    }

    return SelectionOutcome(
      cells: List.unmodifiable(state.cells),
      matchedWord: null,
    );
  }

  /// The nearest of the eight directions to the raw drag vector, or null if
  /// the pointer has not left the anchor cell.
  ///
  /// Compares direction only, not distance: each candidate is normalised so a
  /// diagonal is not favoured over an orthogonal simply for being longer.
  GridVector? _snapToEight(double dx, double dy) {
    final magnitude = sqrt(dx * dx + dy * dy);
    // Half a cell of slop, so a resting finger does not jitter into a
    // direction lock.
    if (magnitude < 0.5) return null;

    GridVector? best;
    var bestCosine = -2.0;

    for (final candidate in directions) {
      final candidateMagnitude = sqrt(
        candidate.dx * candidate.dx + candidate.dy * candidate.dy,
      );
      final cosine =
          (dx * candidate.dx + dy * candidate.dy) /
          (magnitude * candidateMagnitude);

      if (cosine > bestCosine) {
        bestCosine = cosine;
        best = candidate;
      }
    }

    return best;
  }

  /// How many steps fit from [anchor] along [direction] before leaving the
  /// grid. This is what keeps a diagonal drag toward a corner from producing
  /// out-of-bounds cells.
  int _maxSteps(Cell anchor, GridVector direction) {
    var limit = size;

    if (direction.dx > 0) {
      limit = min(limit, size - 1 - anchor.col);
    } else if (direction.dx < 0) {
      limit = min(limit, anchor.col);
    }

    if (direction.dy > 0) {
      limit = min(limit, size - 1 - anchor.row);
    } else if (direction.dy < 0) {
      limit = min(limit, anchor.row);
    }

    return max(limit, 0);
  }
}
