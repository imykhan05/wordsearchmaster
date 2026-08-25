import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../app/theme/theme.dart';
import '../../domain/grid/cell.dart';
import '../../domain/grid/selection_resolver.dart';
import '../../domain/text/language.dart';
import 'gesture_layer.dart';
import 'grapheme_painter_cache.dart';
import 'grid_geometry.dart';
import 'grid_painter.dart';
import 'particles.dart';
import 'perf_overlay.dart';

/// The playable grid: three paint passes, a particle layer and a gesture layer,
/// stacked.
///
/// LAYER ORDER AND WHY EACH BOUNDARY IS THERE
///
///   RepaintBoundary  letters      static for the whole level
///   RepaintBoundary  found words  repaints when a word is found
///   RepaintBoundary  selection    the only layer that repaints per frame
///   RepaintBoundary  particles    170ms bursts, isolated from everything
///                    gestures     a bare Listener, no painting
///
/// Without the boundaries, a repaint of the live selection would mark the whole
/// stack dirty and re-rasterise 144 glyphs sixty times a second — which is the
/// exact failure this structure exists to prevent.
class GameGrid extends StatefulWidget {
  const GameGrid({
    required this.cells,
    required this.language,
    required this.foundWordCells,
    required this.onSelectionReleased,
    this.particleController,
    this.showPerfOverlay = false,
    this.cache,
    this.stats,
    this.enableHaptics = true,
    super.key,
  });

  /// `cells[row][col]` — one grapheme cluster each, from `GridResult.cells`.
  final List<List<String>> cells;

  final Language language;

  /// One entry per found word, in the order found: the colour and border
  /// weight are taken from the token palette by that index.
  final List<List<Cell>> foundWordCells;

  /// Fires on pointer-up with the finished drag and the geometry it was drawn
  /// against. P07's GameController matches the drag against the remaining
  /// words; the geometry comes along so the caller can position a particle
  /// burst without reaching back in through a [GlobalKey].
  final void Function(SelectionState state, GridGeometry geometry)
  onSelectionReleased;

  final ParticleController? particleController;

  /// Dev flavor only — the caller gates this.
  final bool showPerfOverlay;

  /// Injectable so tests can assert on the hit rate.
  final GraphemePainterCache? cache;
  final GridPaintStats? stats;

  final bool enableHaptics;

  @override
  State<GameGrid> createState() => GameGridState();
}

class GameGridState extends State<GameGrid> {
  late GraphemePainterCache _cache = widget.cache ?? GraphemePainterCache();
  late final GridPaintStats _stats = widget.stats ?? GridPaintStats();

  /// The live drag. A notifier rather than `setState`, so a moving finger
  /// repaints one capsule and rebuilds nothing.
  final ValueNotifier<SelectionState> _selection =
      ValueNotifier<SelectionState>(SelectionState.empty);

  GridGeometry? _geometry;

  /// Exposed for tests and for P07's hint system, which needs to know where a
  /// cell sits on screen.
  GridGeometry? get geometry => _geometry;
  GraphemePainterCache get cache => _cache;
  GridPaintStats get stats => _stats;
  ValueListenable<SelectionState> get selection => _selection;

  @override
  void didUpdateWidget(GameGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new language means new fonts, so the cached painters are all stale.
    if (oldWidget.language != widget.language) {
      _cache = widget.cache ?? GraphemePainterCache();
    }
  }

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final size = widget.cells.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final geometry = GridGeometry.fit(
          size: size,
          available: constraints.biggest,
          gap: AppTokens.space4 / 2,
        );
        _geometry = geometry;

        final textStyle = AppTypography.gridTextStyle(
          widget.language,
          cellSize: geometry.cellSize,
          color: tokens.colors.onSurface,
        );

        final highlights = [
          for (var i = 0; i < widget.foundWordCells.length; i++)
            FoundWordHighlight(
              cells: widget.foundWordCells[i],
              color:
                  tokens.colors.foundWord[i % tokens.colors.foundWord.length],
              borderWidth:
                  AppTokens.foundWordBorderWidths[i %
                      AppTokens.foundWordBorderWidths.length],
            ),
        ];

        return Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: CustomPaint(
                painter: GridLettersPainter(
                  cells: widget.cells,
                  geometry: geometry,
                  textStyle: textStyle,
                  cellColor: tokens.colors.surfaceElevated,
                  cornerRadius: AppTokens.radius4,
                  cache: _cache,
                  // Cells hold a single isolated grapheme, so the painter's own
                  // direction never mirrors anything; the RTL-ness of the grid
                  // lives in where the generator PUT the letters (Ch04).
                  textDirection: TextDirection.ltr,
                  stats: _stats,
                ),
              ),
            ),
            RepaintBoundary(
              child: CustomPaint(
                painter: FoundWordsPainter(
                  highlights: highlights,
                  geometry: geometry,
                  stats: _stats,
                ),
              ),
            ),
            RepaintBoundary(
              child: CustomPaint(
                painter: SelectionPainter(
                  selection: _selection,
                  geometry: geometry,
                  color: tokens.colors.primary,
                  borderWidth: 2.5,
                  stats: _stats,
                ),
              ),
            ),
            if (widget.particleController != null)
              ParticleLayer(
                controller: widget.particleController!,
                stats: _stats,
              ),
            GestureLayer(
              geometry: geometry,
              selection: _selection,
              onReleased: (state) =>
                  widget.onSelectionReleased(state, geometry),
              enableHaptics: widget.enableHaptics,
            ),
            if (widget.showPerfOverlay)
              Positioned(
                left: AppTokens.space8,
                top: AppTokens.space8,
                child: PerfOverlay(stats: _stats),
              ),
          ],
        );
      },
    );
  }
}
