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
    this.pulseController,
    this.rotationController,
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

  /// Drives the FTUE/DDA "look here" pulse (Ch02/P12) — a silent, free,
  /// NON-CONSUMING nudge, deliberately separate from [hintedCell]: it must
  /// never append a `HintUsed` event or cost a star, so it cannot be the same
  /// slot `GameController.useHint` writes. Null when neither the FTUE glow
  /// nor the DDA stuck-pulse is active for this build (most levels, most of
  /// the time).
  final PulseController? pulseController;

  /// Drives the rotate button's 180° view flip. Null in tests and anywhere
  /// the board is shown without the control (the Style Gallery).
  final GridRotationController? rotationController;

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

// Two tickers, not one: the wrong-selection fade and the rotate spin are
// independent and can overlap (a released miss, then a tap on rotate), and
// `SingleTickerProviderStateMixin` throws outright on the second `createTicker`.
class GameGridState extends State<GameGrid> with TickerProviderStateMixin {
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

  /// Whether the board is currently being viewed upside down. Settled state:
  /// it flips once per tap and is then read by [GridGeometry] for BOTH paint
  /// and touch.
  ///
  /// A [ValueNotifier] read through a builder rather than `setState`, matching
  /// the idiom the rest of this class already uses — and scoping the rebuild
  /// to the grid subtree instead of the screen.
  final ValueNotifier<bool> _rotated = ValueNotifier<bool>(false);

  /// How much of the half-turn is still owed, `-1` → `0`. Handed straight to
  /// the two painters through `CustomPaint.repaint`, so the spin costs no
  /// widget rebuilds at all — the same bargain the live selection makes.
  final ValueNotifier<double> _spin = ValueNotifier<double>(0);

  Ticker? _spinTicker;

  /// Long enough to read as the board being turned over, short enough that a
  /// player tapping twice to compare both views is not waiting on it.
  static const Duration _spinDuration = Motion.slow;

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

  /// Exposed for tests: the settled view flip, and the spin still in flight.
  ValueListenable<bool> get rotated => _rotated;
  ValueListenable<double> get spin => _spin;

  @override
  void initState() {
    super.initState();
    widget.rotationController?.requests.addListener(_onRotationRequested);
  }

  @override
  void didUpdateWidget(GameGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new language means new fonts, so the cached painters are all stale.
    if (oldWidget.language != widget.language) {
      _cache = widget.cache ?? GraphemePainterCache();
    }
    if (!identical(oldWidget.rotationController, widget.rotationController)) {
      oldWidget.rotationController?.requests.removeListener(
        _onRotationRequested,
      );
      widget.rotationController?.requests.addListener(_onRotationRequested);
    }
    // A NEW BOARD ALWAYS ARRIVES UPRIGHT. P07's Zeigarnik swap advances the
    // level in place, without remounting this widget, so nothing else would
    // ever clear the flip and the player would land on the next level already
    // upside down. `cells` is compared by identity for the same reason
    // `GridLettersPainter.shouldRepaint` does: `GridResult` hands out a fresh
    // grid per level, so a new identity IS "this is a different board".
    if (!identical(oldWidget.cells, widget.cells)) {
      _stopSpin();
      _rotated.value = false;
      _spin.value = 0;
    }
  }

  @override
  void dispose() {
    widget.rotationController?.requests.removeListener(_onRotationRequested);
    _selection.dispose();
    _fadeAlpha.dispose();
    _rotated.dispose();
    _spin.dispose();
    _fadeTicker?.dispose();
    _spinTicker?.dispose();
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

  /// The rotate button was tapped: flip the settled view, then play the board
  /// swinging into it.
  ///
  /// The flip lands FIRST and the animation runs backwards from it — [_spin]
  /// starts at `-1` (a half-turn still owed, which is exactly where the board
  /// was a moment ago) and eases to `0`. Written this way round because the
  /// settled state is the one everything else reads: the instant this returns,
  /// [GridGeometry] already answers for the new orientation, so a touch that
  /// arrives mid-spin is resolved against where the letters are LANDING rather
  /// than against a layout that is about to stop existing.
  void _onRotationRequested() {
    // A live capsule would be left pointing through cells that just moved, and
    // a miss-fade would finish somewhere the player never dragged.
    _fadeTicker?.stop();
    _fadeAlpha.value = 1.0;
    _selection.value = SelectionState.empty;

    _rotated.value = !_rotated.value;

    _stopSpin();
    if (MediaQuery.disableAnimationsOf(context)) {
      // Reduce-motion drops the SWING, never the rotation: the board really
      // has turned over, and a player who asked for that still needs to see
      // it. Same call this file's `_PulseHighlight` already makes for the same
      // reason — remove the movement, keep the information.
      _spin.value = 0;
      return;
    }
    _spin.value = -1;
    (_spinTicker ??= createTicker(_onSpinTick)).start();
  }

  void _onSpinTick(Duration elapsed) {
    final t = (elapsed.inMicroseconds / 1000.0 / _spinDuration.inMilliseconds)
        .clamp(0.0, 1.0);
    // Eased on the way in AND out: a half-turn that starts at full speed reads
    // as a glitch rather than as the board being turned by a hand.
    _spin.value = Motion.fade.transform(t) - 1;

    if (t >= 1.0) {
      _stopSpin();
      _spin.value = 0;
    }
  }

  /// `Ticker.start()` throws on an already-active ticker, and a second tap
  /// mid-spin is exactly what a player comparing the two views does. Stopping
  /// first also rewinds `elapsed`, which is what makes each spin measure its
  /// own `t` from zero.
  void _stopSpin() {
    if (_spinTicker?.isActive ?? false) _spinTicker!.stop();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final size = widget.cells.length;

    return LayoutBuilder(
      builder: (context, constraints) => ValueListenableBuilder<bool>(
        valueListenable: _rotated,
        builder: (context, rotated, child) {
          return _buildBoard(context, constraints, size, tokens, rotated);
        },
      ),
    );
  }

  Widget _buildBoard(
    BuildContext context,
    BoxConstraints constraints,
    int size,
    AppTokens tokens,
    bool rotated,
  ) {
    final geometry = GridGeometry.fit(
      size: size,
      available: constraints.biggest,
      gap: AppTokens.space4 / 2,
      rotated: rotated,
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
          color: tokens.colors.foundWord[i % tokens.colors.foundWord.length],
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
              // Zero-alpha, not removed: letters sit on the ONE card
              // `_GameContent` draws behind the whole grid, never on a
              // per-cell box — `cornerRadius` below stays wired so a
              // future per-cell treatment has somewhere to plug back in.
              cellColor: tokens.colors.surfaceElevated.withValues(alpha: 0),
              cornerRadius: AppTokens.radius4,
              cache: _cache,
              // Cells hold a single isolated grapheme, so the painter's own
              // direction never mirrors anything; the RTL-ness of the grid
              // lives in where the generator PUT the letters (Ch04).
              textDirection: TextDirection.ltr,
              spin: _spin,
              stats: _stats,
            ),
          ),
        ),
        RepaintBoundary(
          child: CustomPaint(
            painter: FoundWordsPainter(
              highlights: highlights,
              geometry: geometry,
              spin: _spin,
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
        if (widget.pulseController != null)
          ValueListenableBuilder<PulseSignal?>(
            valueListenable: widget.pulseController!.signal,
            builder: (context, signal, child) {
              if (signal == null) return const SizedBox.shrink();
              // Positioned must stay a direct Stack child — the
              // RepaintBoundary goes INSIDE it, matching the hint ring
              // below and the P07 gotcha CLAUDE.md documents.
              // ValueListenableBuilder itself creates no RenderObject, so
              // it does not break that chain.
              return Positioned.fromRect(
                rect: geometry.cellRect(signal.cell).inflate(4),
                child: RepaintBoundary(
                  key: ValueKey(signal.nonce),
                  child: _PulseHighlight(color: tokens.colors.primary),
                ),
              );
            },
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
          ParticleLayer(controller: widget.particleController!, stats: _stats),
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

/// One "look here" nudge: which [cell] to glow, plus a [nonce] that changes
/// on every call to [PulseController.pulse] even when the cell is the same —
/// see that class's doc for why identity, not just equality, has to change.
final class PulseSignal {
  const PulseSignal({required this.cell, required this.nonce});

  final Cell cell;
  final int nonce;
}

/// Drives [GameGrid.pulseController] — the FTUE glow (Ch02: "softly glow the
/// first letter of one target word", repeated every 6s) and the DDA stuck-
/// pulse (Ch02: 25s idle → "pulse the first grapheme of a random remaining
/// word") share this one mechanism, since both are "make one cell glow for a
/// moment" and differ only in WHICH cell and WHEN — decisions that belong to
/// the idle timer in `game_screen.dart`, not to the grid.
///
/// Deliberately NOT `GameState`: see `domain/progression/dda.dart`'s library
/// header for why this stays outside Riverpod state and outside the ordered
/// `events` log entirely — it is silent, free, and must never read back as a
/// hint.
final class PulseController {
  final ValueNotifier<PulseSignal?> _signal = ValueNotifier(null);

  ValueListenable<PulseSignal?> get signal => _signal;

  int _nonce = 0;

  /// Glows [cell]. A fresh [PulseSignal.nonce] every call, even for the SAME
  /// cell twice in a row — `ValueNotifier` only notifies on inequality, and
  /// without a changing nonce the FTUE glow's 6s repeat on the same first
  /// word would silently stop re-triggering after its first play.
  void pulse(Cell cell) {
    _signal.value = PulseSignal(cell: cell, nonce: _nonce++);
  }

  void clear() => _signal.value = null;

  void dispose() => _signal.dispose();
}

/// Asks the board to turn over. Held by `game_screen.dart` and handed to
/// [GameGrid], the same shape [PulseController] uses — the button lives
/// outside the grid (it sits in the screen's own corner), the state lives
/// inside it, and this is the wire between them.
///
/// A COUNTER, not a bool: the settled orientation belongs to [GameGridState],
/// which also owns the animation and the reset-on-new-level. What travels
/// through here is only "the player tapped", and a fresh value every tap is
/// what makes a [ValueNotifier] fire on the second one — the same reason
/// [PulseSignal] carries a nonce.
final class GridRotationController {
  final ValueNotifier<int> _requests = ValueNotifier<int>(0);

  ValueListenable<int> get requests => _requests;

  void rotate() => _requests.value++;

  void dispose() => _requests.dispose();
}

/// The pulse's own visual: a soft, low-alpha glow — deliberately NOT
/// [_HintHighlight]'s outlined ring, so a player can never mistake a free,
/// silent nudge for the ring a spent hint draws.
///
/// One-shot fade in/out under normal motion; a static (not merely
/// instantaneous) translucent disc under reduce-motion, checked directly via
/// [MediaQuery.disableAnimationsOf] rather than [Motion.reduced] — a
/// collapsed-to-zero animation duration would land this widget on its FINAL
/// frame (faded back OUT, alpha 0), which would make the nudge invisible to
/// exactly the reduce-motion players Ch03 says still need the feedback.
class _PulseHighlight extends StatelessWidget {
  const _PulseHighlight({required this.color});

  final Color color;

  static const Duration _pulseDuration = Duration(milliseconds: 900);
  static const double _peakAlpha = 0.55;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: _peakAlpha * 0.7),
        ),
      );
    }

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: _pulseDuration,
      curve: Curves.easeInOut,
      builder: (context, t, child) {
        // Fades in over the first half, out over the second — a single
        // breath, not a loop; a fresh nonce is what replays it.
        final wave = (t < 0.5 ? t * 2 : (1 - t) * 2).clamp(0.0, 1.0);
        return Opacity(
          opacity: _peakAlpha * wave,
          child: DecoratedBox(
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
        );
      },
    );
  }
}
