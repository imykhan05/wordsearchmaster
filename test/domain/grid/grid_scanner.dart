import 'package:word_search_master/domain/grid/cell.dart';
import 'package:word_search_master/domain/grid/grid_vector.dart';

/// Finds a word in a finished grid by brute force, independently of whatever
/// the generator claims it did.
///
/// Deliberately naive and written from scratch: if the placer and the checker
/// shared code, a bug in the shared part would hide itself. This scans all
/// eight directions from every cell, exactly like a player's eye.
List<Cell>? findWord(List<List<String>> cells, List<String> graphemes) {
  if (graphemes.isEmpty) return null;
  final size = cells.length;

  for (var row = 0; row < size; row++) {
    for (var col = 0; col < size; col++) {
      for (final direction in GridVector.all) {
        final found = _matchFrom(
          cells,
          size,
          Cell(row, col),
          direction,
          graphemes,
        );
        if (found != null) return found;
      }
    }
  }
  return null;
}

List<Cell>? _matchFrom(
  List<List<String>> cells,
  int size,
  Cell start,
  GridVector direction,
  List<String> graphemes,
) {
  final path = <Cell>[];
  for (var i = 0; i < graphemes.length; i++) {
    final cell = start.stepBy(direction, i);
    if (!cell.isInside(size)) return null;
    if (cells[cell.row][cell.col] != graphemes[i]) return null;
    path.add(cell);
  }
  return path;
}
