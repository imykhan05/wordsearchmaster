import 'grid_vector.dart';

/// A coordinate in the grid. `row` grows downward, `col` grows rightward —
/// the same convention as [GridVector].
///
/// PURE DART. Value equality, so cells work as set members and map keys.
final class Cell {
  const Cell(this.row, this.col);

  final int row;
  final int col;

  /// One step from here along [direction].
  Cell step(GridVector direction) =>
      Cell(row + direction.dy, col + direction.dx);

  /// [count] steps from here along [direction].
  Cell stepBy(GridVector direction, int count) =>
      Cell(row + direction.dy * count, col + direction.dx * count);

  bool isInside(int size) => row >= 0 && row < size && col >= 0 && col < size;

  @override
  bool operator ==(Object other) =>
      other is Cell && other.row == row && other.col == col;

  @override
  int get hashCode => Object.hash(row, col);

  @override
  String toString() => 'Cell($row, $col)';
}
