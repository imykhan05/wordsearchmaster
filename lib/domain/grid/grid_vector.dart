/// A unit step across the grid, in cells.
///
/// PURE DART on purpose. Flutter's `Offset` would do the same job, but it
/// comes from `dart:ui`, which only exists inside a Flutter runtime — and the
/// grid engine (P04/P05) has to stay runnable and testable as plain Dart, and
/// its scoring rules get ported to TypeScript for the Cloud Function in P14.
/// An integer cell step is also simply the honest type: grid movement is
/// discrete, never fractional.
///
/// Presentation code that wants a Flutter `Offset` gets one from
/// `LanguageX.gridPrimaryDirection` / `GridVector.toOffset()` in the app layer.
///
/// Coordinates follow screen convention: `dx` grows to the right, `dy` grows
/// DOWNWARD. So [south] is `(0, 1)`, not `(0, -1)`.
final class GridVector {
  const GridVector(this.dx, this.dy);

  final int dx;
  final int dy;

  // Orthogonal.
  static const GridVector east = GridVector(1, 0);
  static const GridVector west = GridVector(-1, 0);
  static const GridVector south = GridVector(0, 1);
  static const GridVector north = GridVector(0, -1);

  // Diagonal.
  static const GridVector southEast = GridVector(1, 1);
  static const GridVector southWest = GridVector(-1, 1);
  static const GridVector northEast = GridVector(1, -1);
  static const GridVector northWest = GridVector(-1, -1);

  /// All eight directions a word may run in, in a stable order.
  static const List<GridVector> all = [
    east,
    west,
    south,
    north,
    southEast,
    southWest,
    northEast,
    northWest,
  ];

  /// The same step in the opposite direction.
  GridVector get opposite => GridVector(-dx, -dy);

  bool get isDiagonal => dx != 0 && dy != 0;
  bool get isHorizontal => dy == 0;
  bool get isVertical => dx == 0;

  @override
  bool operator ==(Object other) =>
      other is GridVector && other.dx == dx && other.dy == dy;

  @override
  int get hashCode => Object.hash(dx, dy);

  @override
  String toString() => 'GridVector($dx, $dy)';
}
