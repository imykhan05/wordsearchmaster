import 'cell.dart';

/// A continuous position over the grid, measured in CELL UNITS.
///
/// `(0.0, 0.0)` is the top-left corner of cell (0, 0) and `(0.5, 0.5)` is its
/// centre, so `Cell(y.floor(), x.floor())` is the cell under the point.
///
/// PURE DART, which is why this exists rather than `dart:ui`'s `Offset`
/// (CLAUDE.md → Architecture). The presentation layer converts pixels to cell
/// units — divide by cell size, subtract the grid origin — and hands the
/// result here, so the whole selection contract is testable with no device.
///
/// Sub-cell precision is kept on purpose: projecting a continuous pointer onto
/// the locked line is what makes the selection feel sticky rather than
/// snapping cell-to-cell.
final class GridPoint {
  const GridPoint(this.x, this.y);

  /// Along the column axis, growing rightward.
  final double x;

  /// Along the row axis, growing downward.
  final double y;

  /// The centre of [cell].
  factory GridPoint.centerOf(Cell cell) =>
      GridPoint(cell.col + 0.5, cell.row + 0.5);

  Cell get cell => Cell(y.floor(), x.floor());

  @override
  bool operator ==(Object other) =>
      other is GridPoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'GridPoint($x, $y)';
}
