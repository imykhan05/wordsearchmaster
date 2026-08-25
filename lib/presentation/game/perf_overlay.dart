import 'dart:async';
import 'dart:collection';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../app/theme/theme.dart';
import '../../domain/text/language.dart';
import 'grid_painter.dart';

/// DEV FLAVOR ONLY. Live frame timings and repaint counts, so the P06 budget
/// is something you can watch rather than something you hope for.
///
/// Reads Flutter's own [FrameTiming] stream — the same numbers DevTools shows —
/// rather than timing anything itself. Raster time is the one that matters
/// here: painting 144 glyphs lands there, not in build.
class PerfOverlay extends StatefulWidget {
  const PerfOverlay({required this.stats, super.key});

  final GridPaintStats stats;

  /// Anything slower than this misses a 60fps frame.
  static const double frameBudgetMs = 1000 / 60;

  @override
  State<PerfOverlay> createState() => _PerfOverlayState();
}

class _PerfOverlayState extends State<PerfOverlay> {
  static const int _window = 120;

  final Queue<FrameTiming> _timings = Queue<FrameTiming>();
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    // Redraw the readout a few times a second. Rebuilding it every frame would
    // make the overlay part of what it is measuring.
    _refresh = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _refresh?.cancel();
    super.dispose();
  }

  void _onTimings(List<FrameTiming> timings) {
    _timings.addAll(timings);
    while (_timings.length > _window) {
      _timings.removeFirst();
    }
  }

  double _averageMs(double Function(FrameTiming) pick) {
    if (_timings.isEmpty) return 0;
    final total = _timings.fold<double>(0, (sum, t) => sum + pick(t));
    return total / _timings.length;
  }

  double get _jankPercent {
    if (_timings.isEmpty) return 0;
    final janky = _timings
        .where(
          (t) => t.totalSpan.inMicroseconds / 1000 > PerfOverlay.frameBudgetMs,
        )
        .length;
    return janky / _timings.length * 100;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);

    final build = _averageMs((t) => t.buildDuration.inMicroseconds / 1000);
    final raster = _averageMs((t) => t.rasterDuration.inMicroseconds / 1000);
    final total = _averageMs((t) => t.totalSpan.inMicroseconds / 1000);
    final fps = total == 0 ? 0.0 : (1000 / total).clamp(0, 120);
    final jank = _jankPercent;

    final overBudget = total > PerfOverlay.frameBudgetMs;

    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.space8,
          vertical: AppTokens.space4,
        ),
        decoration: BoxDecoration(
          color: tokens.colors.background.withValues(alpha: 0.82),
          borderRadius: AppTokens.borderRadius4,
          border: Border.all(
            color: overBudget ? tokens.colors.warn : tokens.colors.outline,
          ),
        ),
        child: DefaultTextStyle(
          style: AppTypography.uiTextStyle(
            Language.english,
            UiRole.caption,
            color: overBudget
                ? tokens.colors.warn
                : tokens.colors.onSurfaceMuted,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${fps.toStringAsFixed(0)} fps · jank ${jank.toStringAsFixed(1)}%',
              ),
              Text(
                'build ${build.toStringAsFixed(1)}ms · '
                'raster ${raster.toStringAsFixed(1)}ms',
              ),
              Text(
                'repaints  L${widget.stats.letters} '
                'F${widget.stats.foundWords} '
                'S${widget.stats.selection} '
                'P${widget.stats.particles}',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
