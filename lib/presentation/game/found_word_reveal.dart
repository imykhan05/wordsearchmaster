import 'dart:math';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../domain/grid/cell.dart';
import 'grid_geometry.dart';
import 'grid_painter.dart';

/// Fires the correct-word reveal. Held by the game screen and handed to
/// [FoundWordRevealLayer] — same shape as `ParticleController`.
final class FoundWordRevealController extends ChangeNotifier {
  final List<FoundWordReveal> _pending = [];

  void reveal({
    required List<Cell> cells,
    required Color color,
    required double borderWidth,
  }) {
    _pending.add(
      FoundWordReveal(cells: cells, color: color, borderWidth: borderWidth),
    );
    notifyListeners();
  }

  List<FoundWordReveal> takePending() {
    final taken = List<FoundWordReveal>.from(_pending);
    _pending.clear();
    return taken;
  }
}

final class FoundWordReveal {
  const FoundWordReveal({
    required this.cells,
    required this.color,
    required this.borderWidth,
  });

  final List<Cell> cells;
  final Color color;
  final double borderWidth;
}

/// The 0–120ms correct-word flash/punch (Ch03), in its own [RepaintBoundary]
/// on top of the grid's static found-words pass.
///
/// This layer is PURELY the transient handoff. `GameGrid`'s existing
/// `FoundWordsPainter` (pass 2, unmodified by P09) already renders the
/// word's STEADY-STATE capsule underneath the moment the word is added to
/// `GameState.foundWords` — this one draws on top for its first 120ms and
/// then removes itself, the same "spawn, tick, auto-stop" shape
/// `ParticleLayer` uses next door. The fill alpha eases from a bright flash
/// value down to the static layer's own 0.28 across that window specifically
/// so the removal at 120ms is invisible rather than a pop.
///
/// Skipped entirely under reduce-motion, same rule as particles: the static
/// layer still shows the word highlighted (that is not an animation, just a
/// state change), it just never gets the flash/punch on top of it.
class FoundWordRevealLayer extends StatefulWidget {
  const FoundWordRevealLayer({
    required this.controller,
    required this.geometry,
    required this.flashColor,
    this.stats,
    super.key,
  });

  final FoundWordRevealController controller;
  final GridGeometry geometry;

  /// `tokens.colors.foundWordFlash`, resolved once by the caller — a
  /// [CustomPainter] has no [BuildContext] of its own to read the ambient
  /// theme from, so this is threaded down the same way `SelectionPainter`'s
  /// `color` already is.
  final Color flashColor;

  final GridPaintStats? stats;

  /// Ch03: "0–90ms white flash into the word's assigned colour".
  static const Duration flashDuration = Duration(milliseconds: 90);

  /// Ch03: "60–120ms 1.0→1.12→1.0 scale punch". The reveal's own lifetime is
  /// the longer of the two windows.
  static const Duration punchStart = Duration(milliseconds: 60);
  static const Duration totalDuration = Duration(milliseconds: 120);
  static const double punchPeakScale = 0.12;

  @override
  State<FoundWordRevealLayer> createState() => _FoundWordRevealLayerState();
}

class _FoundWordRevealLayerState extends State<FoundWordRevealLayer>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);

  final ValueNotifier<double> _clockMs = ValueNotifier<double>(0);

  final List<_LiveReveal> _reveals = [];
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onRevealRequested);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
  }

  @override
  void didUpdateWidget(FoundWordRevealLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onRevealRequested);
      widget.controller.addListener(_onRevealRequested);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onRevealRequested);
    _ticker.dispose();
    _clockMs.dispose();
    super.dispose();
  }

  void _onRevealRequested() {
    final pending = widget.controller.takePending();
    if (_reduceMotion || pending.isEmpty) return;

    for (final reveal in pending) {
      _reveals.add(_LiveReveal(reveal: reveal, startMs: _clockMs.value));
    }
    if (!_ticker.isActive) _ticker.start();
  }

  void _onTick(Duration elapsed) {
    final nowMs = elapsed.inMicroseconds / 1000.0;
    final totalMs = FoundWordRevealLayer.totalDuration.inMilliseconds
        .toDouble();

    _reveals.removeWhere((live) => nowMs - live.startMs >= totalMs);
    _clockMs.value = nowMs;

    // Nothing left to animate: stop the ticker so an idle grid costs no
    // frames at all.
    if (_reveals.isEmpty) _ticker.stop();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _FoundWordRevealPainter(
          clockMs: _clockMs,
          reveals: _reveals,
          geometry: widget.geometry,
          flashColor: widget.flashColor,
          stats: widget.stats,
        ),
        size: Size.infinite,
      ),
    );
  }
}

final class _LiveReveal {
  const _LiveReveal({required this.reveal, required this.startMs});

  final FoundWordReveal reveal;
  final double startMs;
}

final class _FoundWordRevealPainter extends CustomPainter {
  _FoundWordRevealPainter({
    required this.clockMs,
    required this.reveals,
    required this.geometry,
    required this.flashColor,
    this.stats,
  }) : super(repaint: clockMs);

  final ValueNotifier<double> clockMs;
  final List<_LiveReveal> reveals;
  final GridGeometry geometry;
  final Color flashColor;
  final GridPaintStats? stats;

  static final double _flashMs = FoundWordRevealLayer
      .flashDuration
      .inMilliseconds
      .toDouble();
  static final double _totalMs = FoundWordRevealLayer
      .totalDuration
      .inMilliseconds
      .toDouble();
  static final double _punchStartMs = FoundWordRevealLayer
      .punchStart
      .inMilliseconds
      .toDouble();
  static final double _punchWindowMs = _totalMs - _punchStartMs;

  /// Brighter than the static layer's steady 0.28 fill — the "flash" half of
  /// the effect — and eased back down to it across the full window, so pass
  /// 2's capsule is already showing the same alpha by the time this one
  /// disappears.
  static const double _startAlpha = 0.9;
  static const double _endAlpha = 0.28;

  @override
  void paint(Canvas canvas, Size size) {
    if (reveals.isEmpty) return;
    stats?.foundWords++;

    final now = clockMs.value;

    for (final live in reveals) {
      final elapsed = now - live.startMs;
      if (elapsed < 0) continue;

      // 0–90ms: the flash colour eases into the word's own assigned hue.
      final flashT = (elapsed / _flashMs).clamp(0.0, 1.0);
      final hue = Color.lerp(flashColor, live.reveal.color, flashT)!;

      // 0–120ms: fill alpha eases from the flash down to the static layer's
      // own steady alpha, so this layer's removal at 120ms is seamless.
      final alphaT = (elapsed / _totalMs).clamp(0.0, 1.0);
      final fillAlpha = _startAlpha + (_endAlpha - _startAlpha) * alphaT;

      // 60–120ms: 1.0 → 1.12 → 1.0 scale punch, peaking at the midpoint.
      var scale = 1.0;
      if (elapsed > _punchStartMs) {
        final punchT = ((elapsed - _punchStartMs) / _punchWindowMs).clamp(
          0.0,
          1.0,
        );
        scale = 1.0 + FoundWordRevealLayer.punchPeakScale * sin(pi * punchT);
      }

      paintCapsule(
        canvas: canvas,
        geometry: geometry,
        cells: live.reveal.cells,
        fill: hue.withValues(alpha: fillAlpha),
        border: hue,
        borderWidth: live.reveal.borderWidth,
        scale: scale,
      );
    }
  }

  @override
  bool shouldRepaint(_FoundWordRevealPainter old) =>
      !identical(old.reveals, reveals) ||
      old.geometry != geometry ||
      old.flashColor != flashColor ||
      !identical(old.clockMs, clockMs);
}
