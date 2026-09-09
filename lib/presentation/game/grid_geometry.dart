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
///
/// ---------------------------------------------------------------------------
/// THE VIEW ROTATION LIVES HERE, AND THAT IS THE WHOLE POINT
///
/// The rotate button turns the board 180° so a word running the "wrong" way
/// becomes easy to read. It is a VIEW transform and nothing else: the grid
/// data, the placements, the seed and every score the server will later replay
/// are untouched, so a rotated board is the same puzzle (Ch06 determinism, and
/// P14's server-side recompute, both stay true by construction).
///
/// Putting it in this class rather than in a `Transform` around the widget is
/// what keeps the P06 guarantee that touch and paint cannot disagree: every
/// painter asks this object where a cell is, and the gesture layer asks this
/// same object which cell a finger is on. One rotation, applied once, read by
/// both.
@immutable
final class GridGeometry {
  const GridGeometry({
    required this.size,
    required this.cellSize,
    required this.gap,
    required this.origin,
    this.rotated = false,
    this.paintSpin = 0,
  });

  /// Cells per side.
  final int size;

  /// Side length of one cell, in logical pixels.
  final double cellSize;

  /// Space between adjacent cells.
  final double gap;

  /// Top-left of the grid within the painting box.
  final Offset origin;

  /// Whether the board is currently viewed rotated by 180°.
  ///
  /// A bool rather than an angle on purpose. 180° is a REFLECTION through the
  /// grid's centre (`2c - p`), so the settled mapping needs no trigonometry at
  /// all and is its own inverse — one function serves both "where do I draw
  /// this cell" and "which cell is this finger on", and there is no forward /
  /// inverse pair to get backwards. That matters more here than generality:
  /// this is the path that decides which cell a touch lands on.
  final bool rotated;

  /// Transient extra rotation, in radians, for the rotate animation only.
  ///
  /// DELIBERATELY NOT APPLIED BY [toGridPoint]. During the ~360ms spin the
  /// letters are mid-flight and mean nothing as touch targets, so hit-testing
  /// keeps answering against the settled layout ([rotated]) throughout — which
  /// also keeps every `cos`/`sin` in this file on the painting side, where a
  /// rounding error is invisible, and out of the side where it would decide a
  /// cell index.
  final double paintSpin;

  /// How far the board shrinks at the midpoint of a spin.
  static const double _spinDip = 0.08;

  /// The spin animation is driven by ONE number in `[-1, 0]` — how much of the
  /// half-turn is still owed — and these two derive everything drawn from it,
  /// side by side so a painter cannot pair an angle with the wrong scale.
  static double spinRadians(double spin) => spin * pi;

  /// The board dips slightly at the midpoint and returns: a rigid body that
  /// swings without breathing reads as a screenshot being flipped, not as
  /// letters being tossed.
  static double spinScale(double spin) => 1 - _spinDip * sin(spin.abs() * pi);

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
    bool rotated = false,
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
      rotated: rotated,
    );
  }

  /// The same layout with [paintSpin] set — built inside `paint()`, once a
  /// frame, so the spin never has to travel through a widget rebuild.
  GridGeometry withPaintSpin(double radians) => GridGeometry(
    size: size,
    cellSize: cellSize,
    gap: gap,
    origin: origin,
    rotated: rotated,
    paintSpin: radians,
  );

  /// Centre of the painted grid, in the painting box's own coordinates. The
  /// board turns about this point, so both transforms below are anchored here.
  Offset get center => Offset(origin.dx + extent / 2, origin.dy + extent / 2);

  /// The settled 180°: a reflection through [center], which is its own
  /// inverse — the same call maps a cell to where it is drawn AND maps a
  /// touch back to the cell under it.
  Offset _flip(Offset point) =>
      Offset(2 * center.dx - point.dx, 2 * center.dy - point.dy);

  /// The in-flight part of the animation. Rotates a POSITION about [center]
  /// and nothing else — the glyph drawn at that position is never turned with
  /// it, which is what keeps every letter upright while the board swings.
  Offset _spun(Offset point) {
    if (paintSpin == 0) return point;
    final delta = point - center;
    final cosA = cos(paintSpin);
    final sinA = sin(paintSpin);
    return center +
        Offset(
          delta.dx * cosA - delta.dy * sinA,
          delta.dx * sinA + delta.dy * cosA,
        );
  }

  /// Where a point that would sit at [raw] on an upright, still board is
  /// actually drawn.
  Offset _painted(Offset raw) => _spun(rotated ? _flip(raw) : raw);

  Offset _rawCenter(Cell cell) => Offset(
    origin.dx + cell.col * stride + cellSize / 2,
    origin.dy + cell.row * stride + cellSize / 2,
  );

  Rect cellRect(Cell cell) => Rect.fromCenter(
    center: _painted(_rawCenter(cell)),
    width: cellSize,
    height: cellSize,
  );

  Offset cellCenter(Cell cell) => _painted(_rawCenter(cell));

  /// Converts a pointer position in THIS widget's local coordinates into the
  /// cell-unit space [GridPoint] uses.
  ///
  /// Keeps the fractional part: the selection resolver projects a continuous
  /// pointer onto the locked line, and rounding to whole cells here would
  /// throw away exactly the precision that makes the drag feel sticky.
  GridPoint toGridPoint(Offset local) {
    // [rotated] only — see [paintSpin]'s doc for why the animation is not
    // consulted here.
    final point = rotated ? _flip(local) : local;
    return GridPoint(
      (point.dx - origin.dx) / stride,
      (point.dy - origin.dy) / stride,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GridGeometry &&
      other.size == size &&
      other.cellSize == cellSize &&
      other.gap == gap &&
      other.origin == origin &&
      other.rotated == rotated &&
      other.paintSpin == paintSpin;

  @override
  int get hashCode =>
      Object.hash(size, cellSize, gap, origin, rotated, paintSpin);
}
