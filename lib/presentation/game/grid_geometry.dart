import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../../domain/grid/cell.dart';
import '../../domain/grid/grid_point.dart';

/// Maps between pixels and cells.
///
/// The single source of truth for grid layout, shared by the painters and the
/// gesture layer. Because both read the same geometry, a touch always lands on
/// the cell the player can see — no `GlobalKey`, no hit-testing widget per
/// cell, and nothing to fall out of sync.
@immutable
final class GridGeometry {
  const GridGeometry({
    required this.size,
    required this.cellSize,
    required this.gap,
    required this.origin,
  });

  /// Cells per side.
  final int size;

  /// Side length of one cell, in logical pixels.
  final double cellSize;

  /// Space between adjacent cells.
  final double gap;

  /// Top-left of the grid within the painting box.
  final Offset origin;

  /// Distance from one cell's leading edge to the next.
  double get stride => cellSize + gap;

  /// Total painted extent, gaps included.
  double get extent => size * cellSize + (size - 1) * gap;

  /// Lays out the largest grid that fits [available], centred.
  ///
  /// Ch03 requires a 44dp minimum touch target, so on a very narrow screen the
  /// cell is allowed to keep that size and the caller scrolls or shrinks the
  /// grid instead of silently shipping targets nobody can hit.
  factory GridGeometry.fit({
    required int size,
    required Size available,
    double gap = 2,
    double minCellSize = 0,
  }) {
    final side = min(available.width, available.height);
    final usable = side - (size - 1) * gap;
    final cellSize = max(usable / size, minCellSize);

    final extent = size * cellSize + (size - 1) * gap;
    return GridGeometry(
      size: size,
      cellSize: cellSize,
      gap: gap,
      origin: Offset(
        (available.width - extent) / 2,
        (available.height - extent) / 2,
      ),
    );
  }

  Rect cellRect(Cell cell) => Rect.fromLTWH(
    origin.dx + cell.col * stride,
    origin.dy + cell.row * stride,
    cellSize,
    cellSize,
  );

  Offset cellCenter(Cell cell) => Offset(
    origin.dx + cell.col * stride + cellSize / 2,
    origin.dy + cell.row * stride + cellSize / 2,
  );

  /// Converts a pointer position in THIS widget's local coordinates into the
  /// cell-unit space [GridPoint] uses.
  ///
  /// Keeps the fractional part: the selection resolver projects a continuous
  /// pointer onto the locked line, and rounding to whole cells here would
  /// throw away exactly the precision that makes the drag feel sticky.
  GridPoint toGridPoint(Offset local) => GridPoint(
    (local.dx - origin.dx) / stride,
    (local.dy - origin.dy) / stride,
  );

  @override
  bool operator ==(Object other) =>
      other is GridGeometry &&
      other.size == size &&
      other.cellSize == cellSize &&
      other.gap == gap &&
      other.origin == origin;

  @override
  int get hashCode => Object.hash(size, cellSize, gap, origin);
}
