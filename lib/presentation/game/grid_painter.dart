import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../../domain/grid/cell.dart';
import '../../domain/grid/selection_resolver.dart';
import 'grapheme_painter_cache.dart';
import 'grid_geometry.dart';

/// Repaint counters, for the dev-flavor performance overlay.
///
/// Plain mutable counters rather than a [ChangeNotifier]: notifying listeners
/// from inside `paint()` would schedule work during the paint phase, which is
/// exactly the sort of thing this overlay exists to catch.
final class GridPaintStats {
  int letters = 0;
  int foundWords = 0;
  int selection = 0;
  int particles = 0;

  void reset() {
    letters = 0;
    foundWords = 0;
    selection = 0;
    particles = 0;
  }
}

/// ============================================================================
/// THE GRID IS ONE PAINTER PER LOGICAL PASS — NEVER 144 WIDGETS.
///
/// 144 `Container`s would mean 144 render objects laid out and composited every
/// frame, which janks on the 2GB phones this game targets. Instead the grid is
/// three [CustomPainter]s stacked in three [CustomPaint]s:
///
///   pass 1  [GridLettersPainter]  cell backgrounds + letters   (static)
///   pass 2  [FoundWordsPainter]   the capsules through found words
///   pass 3  [SelectionPainter]    the live drag
///
/// They are separate painters rather than three blocks inside one `paint()`
/// for a concrete reason: only pass 3 may repaint per frame. Passes 1 and 2 sit
/// behind [RepaintBoundary]s, so while a finger is moving Flutter re-rasterises
/// one capsule — not 144 glyphs.
/// ============================================================================

/// PASS 1 — cell backgrounds and letters. Repaints only when the grid itself
/// changes, which is once per level.
final class GridLettersPainter extends CustomPainter {
  GridLettersPainter({
    required this.cells,
    required this.geometry,
    required this.textStyle,
    required this.cellColor,
    required this.cornerRadius,
    required this.cache,
    required this.textDirection,
    this.stats,
  });

  /// `cells[row][col]`, one grapheme cluster each.
  final List<List<String>> cells;
  final GridGeometry geometry;
  final TextStyle textStyle;
  final Color cellColor;
  final double cornerRadius;
  final GraphemePainterCache cache;
  final TextDirection textDirection;
  final GridPaintStats? stats;

  /// Fraction of the cell a glyph may occupy before it is scaled down.
  static const double _inset = 0.86;

  @override
  void paint(Canvas canvas, Size size) {
    stats?.letters++;

    final background = Paint()..color = cellColor;
    final radius = Radius.circular(cornerRadius);

    for (var row = 0; row < geometry.size; row++) {
      for (var col = 0; col < geometry.size; col++) {
        final cell = Cell(row, col);
        final rect = geometry.cellRect(cell);
        canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), background);

        // Cached and already laid out — paint() never calls layout() for a
        // grapheme it has seen before.
        final painter = cache.get(
          cells[row][col],
          style: textStyle,
          textDirection: textDirection,
        );

        _paintFitted(canvas, painter, rect);
      }
    }
  }

  /// Draws [painter] centred in [rect], shrinking it if it would overflow.
  ///
  /// This is the FittedBox equivalent, done on the canvas: a wide Devanagari
  /// akshara such as क्षि is far broader than a Latin letter at the same font
  /// size, and without this it would spill into its neighbours.
  void _paintFitted(Canvas canvas, TextPainter painter, Rect rect) {
    final maxWidth = rect.width * _inset;
    final maxHeight = rect.height * _inset;

    final scale = min(
      1.0,
      min(
        painter.width == 0 ? 1.0 : maxWidth / painter.width,
        painter.height == 0 ? 1.0 : maxHeight / painter.height,
      ),
    );

    if (scale >= 1.0) {
      painter.paint(
        canvas,
        rect.center - Offset(painter.width / 2, painter.height / 2),
      );
      return;
    }

    canvas.save();
    canvas.translate(rect.center.dx, rect.center.dy);
    canvas.scale(scale);
    painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(GridLettersPainter old) {
    // Field by field. `cells` is compared by identity on purpose: GridResult
    // hands out an unmodifiable grid that is rebuilt per level, so a new
    // identity is exactly what "the grid changed" means — and deep-comparing
    // 144 strings on every frame would cost more than the repaint it avoids.
    return !identical(old.cells, cells) ||
        old.geometry != geometry ||
        old.textStyle != textStyle ||
        old.cellColor != cellColor ||
        old.cornerRadius != cornerRadius ||
        old.textDirection != textDirection ||
        !identical(old.cache, cache);
  }
}

/// One found word's highlight.
@immutable
final class FoundWordHighlight {
  const FoundWordHighlight({
    required this.cells,
    required this.color,
    required this.borderWidth,
  });

  final List<Cell> cells;
  final Color color;

  /// Paired with [color] from `AppTokens.foundWordBorderWidths`, so two
  /// highlights differ by stroke as well as hue. Colour is never the only cue
  /// (Ch03 accessibility).
  final double borderWidth;
}

/// PASS 2 — the capsules through found words. Repaints when a word is found,
/// not per frame.
final class FoundWordsPainter extends CustomPainter {
  FoundWordsPainter({
    required this.highlights,
    required this.geometry,
    this.stats,
  });

  final List<FoundWordHighlight> highlights;
  final GridGeometry geometry;
  final GridPaintStats? stats;

  @override
  void paint(Canvas canvas, Size size) {
    stats?.foundWords++;

    for (final highlight in highlights) {
      if (highlight.cells.isEmpty) continue;
      paintCapsule(
        canvas: canvas,
        geometry: geometry,
        cells: highlight.cells,
        fill: highlight.color.withValues(alpha: 0.28),
        border: highlight.color,
        borderWidth: highlight.borderWidth,
      );
    }
  }

  @override
  bool shouldRepaint(FoundWordsPainter old) {
    if (old.geometry != geometry) return true;
    if (old.highlights.length != highlights.length) return true;

    for (var i = 0; i < highlights.length; i++) {
      final a = old.highlights[i];
      final b = highlights[i];
      if (a.color != b.color ||
          a.borderWidth != b.borderWidth ||
          !identical(a.cells, b.cells)) {
        return true;
      }
    }
    return false;
  }
}

/// PASS 3 — the live drag. THE ONLY LAYER THAT MAY REPAINT PER FRAME.
///
/// Driven by a [ValueListenable] handed to `CustomPaint.repaint`, so a moving
/// finger repaints this one capsule without rebuilding a single widget.
/// Rebuilding the tree 60 times a second would give back everything the
/// three-pass split just bought.
final class SelectionPainter extends CustomPainter {
  SelectionPainter({
    required this.selection,
    required this.geometry,
    required this.color,
    required this.borderWidth,
    required this.fadeAlpha,
    this.stats,
  }) : super(repaint: Listenable.merge([selection, fadeAlpha]));

  final ValueListenable<SelectionState> selection;
  final GridGeometry geometry;
  final Color color;
  final double borderWidth;

  /// 1.0 for a live drag; eased down to 0.0 over the wrong-selection 180ms
  /// fade-out (Ch03) once the drag is released without a match. The capsule
  /// stays in this SAME colour throughout — a miss is a fade, never a
  /// colour or shape change, which is the whole of "no punishment feedback."
  final ValueListenable<double> fadeAlpha;

  final GridPaintStats? stats;

  @override
  void paint(Canvas canvas, Size size) {
    stats?.selection++;

    final cells = selection.value.cells;
    final alpha = fadeAlpha.value;
    if (cells.isEmpty || alpha <= 0) return;

    paintCapsule(
      canvas: canvas,
      geometry: geometry,
      cells: cells,
      fill: color.withValues(alpha: 0.34 * alpha),
      border: color.withValues(alpha: alpha),
      borderWidth: borderWidth,
    );
  }

  @override
  bool shouldRepaint(SelectionPainter old) =>
      old.geometry != geometry ||
      old.color != color ||
      old.borderWidth != borderWidth ||
      !identical(old.selection, selection) ||
      !identical(old.fadeAlpha, fadeAlpha);
}

/// Draws a rounded capsule running THROUGH a run of cells.
///
/// One shape from the first cell's centre to the last, not a square per cell:
/// a per-cell highlight reads as a row of blocks, while a capsule reads as a
/// single word — which is what it is.
void paintCapsule({
  required Canvas canvas,
  required GridGeometry geometry,
  required List<Cell> cells,
  required Color fill,
  required Color border,
  required double borderWidth,
  double scale = 1.0,
}) {
  final start = geometry.cellCenter(cells.first);
  final end = geometry.cellCenter(cells.last);

  final delta = end - start;
  final thickness = geometry.cellSize * 0.84;
  final rect = Rect.fromCenter(
    center: Offset.zero,
    width: delta.distance + thickness,
    height: thickness,
  );
  final capsule = RRect.fromRectAndRadius(rect, Radius.circular(thickness / 2));

  canvas.save();
  canvas.translate(start.dx + delta.dx / 2, start.dy + delta.dy / 2);
  // Zero-length runs (a single cell) have no meaningful angle; atan2(0,0) is
  // 0, which draws a circle — correct.
  canvas.rotate(atan2(delta.dy, delta.dx));
  // Applied last so it scales the capsule about its own centre — the found-
  // word reveal's 60–120ms punch (Ch03) is the only caller that passes
  // anything but the default.
  if (scale != 1.0) canvas.scale(scale);

  canvas.drawRRect(capsule, Paint()..color = fill);
  canvas.drawRRect(
    capsule,
    Paint()
      ..color = border
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth,
  );

  canvas.restore();
}
