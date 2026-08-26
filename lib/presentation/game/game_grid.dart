import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../app/theme/theme.dart';
import '../../domain/grid/cell.dart';
import '../../domain/grid/selection_resolver.dart';
import '../../domain/text/language.dart';
import '../../services/haptics/haptics_service.dart';
import 'found_word_reveal.dart';
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
///   RepaintBoundary  hint         one-shot appear, then static (P07)
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
    this.hintedCell,
    this.particleController,
    this.foundWordRevealController,
    this.hapticsService = const NoopHapticsService(),
    this.showPerfOverlay = false,
    this.cache,
    this.stats,
    super.key,
  });

  /// `cells[row][col]` — one grapheme cluster each, from `GridResult.cells`.
  final List<List<String>> cells;

  final Language language;

  /// One entry per found word, in the order found: the colour and border
  /// weight are taken from the token palette by that index.
  final List<List<Cell>> foundWordCells;

  /// The cell `GameController.useHint` last pointed at, or null. Drawn as a
  /// one-shot appear-and-hold ring rather than a continuous pulse — an
  /// indefinitely looping animation would keep repainting for as long as the
  /// hint sits on screen, which is exactly the per-frame cost P06 built this
  /// three-pass split to avoid paying outside the live selection.
  final Cell? hintedCell;

  /// Fires on pointer-up with the finished drag and the geometry it was drawn
  /// against, and returns whether it matched a word. P07's GameController
  /// matches the drag against the remaining words; the geometry comes along
  /// so the caller can position a particle burst without reaching back in
  /// through a [GlobalKey]. The bool return drives the miss fade below —
  /// see [GameGridState._startMissFade].
  final bool Function(SelectionState state, GridGeometry geometry)
  onSelectionReleased;

  final ParticleController? particleController;

  /// Drives the 0–120ms flash/scale-punch reveal (Ch03) on top of a just-
  /// found word. Optional for the same reason [particleController] is —
  /// tests that only care about the static grid don't need to provide one.
  final FoundWordRevealController? foundWordRevealController;

  /// Routes every in-grid haptic (selection ticks) through the master
  /// toggle. Defaults to the no-op binding so existing tests that build a
  /// bare [GameGrid] keep compiling and stay silent, same as before P09.
  final HapticsService hapticsService;

  /// Dev flavor only — the caller gates this.
  final bool showPerfOverlay;

  /// Injectable so tests can assert on the hit rate.
  final GraphemePainterCache? cache;
  final GridPaintStats? stats;

  @override
  State<GameGrid> createState() => GameGridState();
}

class GameGridState extends State<GameGrid>
    with SingleTickerProviderStateMixin {
  late GraphemePainterCache _cache = widget.cache ?? GraphemePainterCache();
  late final GridPaintStats _stats = widget.stats ?? GridPaintStats();

  /// The live drag. A notifier rather than `setState`, so a moving finger
  /// repaints one capsule and rebuilds nothing.
  final ValueNotifier<SelectionState> _selection =
      ValueNotifier<SelectionState>(SelectionState.empty);

  /// Multiplies the selection capsule's alpha. 1.0 for a live drag; ramped
  /// to 0.0 over [_missFadeDuration] after a released drag misses — see
  /// [_startMissFade]. `SelectionPainter` blends this in directly rather
  /// than this state hiding/showing the capsule itself, so the fade is a
  /// smooth per-frame repaint of pass 3 alone, not a widget rebuild.
  final ValueNotifier<double> _fadeAlpha = ValueNotifier<double>(1.0);

  Ticker? _fadeTicker;

  /// Ch03: "just a 180ms fade-out" — the wrong-selection spec in full: no
  /// sound, no buzz, no shake, no colour change, only this.
  static const Duration _missFadeDuration = Duration(milliseconds: 180);

  GridGeometry? _geometry;

  /// Exposed for tests and for P07's hint system, which needs to know where a
  /// cell sits on screen.
  GridGeometry? get geometry => _geometry;
  GraphemePainterCache get cache => _cache;
  GridPaintStats get stats => _stats;
  ValueListenable<SelectionState> get selection => _selection;

  /// Exposed for tests — the wrong-selection 180ms fade (Ch03) is otherwise
  /// only observable by eye.
  ValueListenable<double> get fadeAlpha => _fadeAlpha;

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
    _fadeAlpha.dispose();
    _fadeTicker?.dispose();
    super.dispose();
  }

  /// A drag was released and did not match — start (or restart) the 180ms
  /// fade. Under reduce-motion the capsule just vanishes on the spot: Ch03
  /// collapses every duration to zero, and there is nothing else to show for
  /// a miss once the fade itself is gone.
  bool _onGridReleased(SelectionState state, GridGeometry geometry) {
    final matched = widget.onSelectionReleased(state, geometry);
    if (matched) return true;

    if (MediaQuery.disableAnimationsOf(context)) {
      _selection.value = SelectionState.empty;
    } else {
      _fadeAlpha.value = 1.0;
      (_fadeTicker ??= createTicker(_onFadeTick)).start();
    }
    return false;
  }

  /// A new drag started — cancel any miss-fade still in flight so it doesn't
  /// leave the NEW drag's capsule starting at a stale, partly-faded alpha.
  void _onGridStarted() {
    _fadeTicker?.stop();
    _fadeAlpha.value = 1.0;
  }

  void _onFadeTick(Duration elapsed) {
    final t =
        (elapsed.inMicroseconds / 1000.0 / _missFadeDuration.inMilliseconds)
            .clamp(0.0, 1.0);
    _fadeAlpha.value = 1.0 - t;

    if (t >= 1.0) {
      _fadeTicker?.stop();
      _selection.value = SelectionState.empty;
      _fadeAlpha.value = 1.0;
    }
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
            if (widget.foundWordRevealController != null)
              FoundWordRevealLayer(
                controller: widget.foundWordRevealController!,
                geometry: geometry,
                flashColor: tokens.colors.foundWordFlash,
                stats: _stats,
              ),
            if (widget.hintedCell != null)
              // Positioned must be a direct Stack child — RepaintBoundary
              // goes INSIDE it, not around it, or Positioned's parent data
              // never applies and it silently expands to fill the Stack.
              Positioned.fromRect(
                rect: geometry.cellRect(widget.hintedCell!).inflate(4),
                child: RepaintBoundary(
                  // Keyed on the cell so a hint that MOVES to a new word (a
                  // second `useHint` call) restarts the appear animation at
                  // the new location instead of silently jumping there.
                  child: _HintHighlight(
                    key: ValueKey(widget.hintedCell),
                    color: tokens.colors.info,
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
                  fadeAlpha: _fadeAlpha,
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
              onReleased: (state) => _onGridReleased(state, geometry),
              onStarted: _onGridStarted,
              hapticsService: widget.hapticsService,
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

/// The hint ring: an outline that punches in over the hinted cell and then
/// holds still. See [GameGrid.hintedCell] for why this is one-shot rather
/// than a loop. Positioning is the caller's job (a `Positioned` ancestor) —
/// this just fills whatever box it is given.
class _HintHighlight extends StatelessWidget {
  const _HintHighlight({required this.color, super.key});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Motion.reduced(context, Motion.base),
      curve: Motion.punch,
      builder: (context, t, child) {
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: t,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: AppTokens.borderRadius8,
                border: Border.all(color: color, width: 2.5),
              ),
            ),
          ),
        );
      },
    );
  }
}
