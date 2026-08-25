import 'dart:math';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'grid_painter.dart';

/// Fires particle bursts. Held by the game screen and handed to
/// [ParticleLayer].
final class ParticleController extends ChangeNotifier {
  final List<ParticleBurst> _pending = [];

  /// Throws a burst outward from [origin] in [color] — one call per found
  /// word, from the centre of the word's capsule.
  void burst({required Offset origin, required Color color, int? seed}) {
    _pending.add(ParticleBurst(origin: origin, color: color, seed: seed));
    notifyListeners();
  }

  List<ParticleBurst> takePending() {
    final taken = List<ParticleBurst>.from(_pending);
    _pending.clear();
    return taken;
  }
}

/// Particles for found words, in their own [RepaintBoundary].
///
/// Isolated from the grid on purpose: particles repaint every frame for 170ms,
/// and without the boundary that would drag the letters layer into a repaint
/// with them — undoing the three-pass split next door.
///
/// Skipped entirely under reduce-motion. Ch03 is specific about this: with
/// reduce-motion on there are no particles and every duration collapses to
/// zero, but the audio and haptics still fire, so the player keeps the
/// feedback without the movement.
class ParticleLayer extends StatefulWidget {
  const ParticleLayer({required this.controller, this.stats, super.key});

  final ParticleController controller;
  final GridPaintStats? stats;

  /// Ch03 / P06: 170ms.
  static const Duration lifetime = Duration(milliseconds: 170);
  static const int minParticles = 8;
  static const int maxParticles = 12;

  @override
  State<ParticleLayer> createState() => _ParticleLayerState();
}

class _ParticleLayerState extends State<ParticleLayer>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);

  /// Drives the painter directly. A ValueNotifier on `CustomPaint.repaint`
  /// repaints without rebuilding any widget.
  final ValueNotifier<double> _clockMs = ValueNotifier<double>(0);

  final List<_LiveBurst> _bursts = [];
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onBurstRequested);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
  }

  @override
  void didUpdateWidget(ParticleLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onBurstRequested);
      widget.controller.addListener(_onBurstRequested);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onBurstRequested);
    _ticker.dispose();
    _clockMs.dispose();
    super.dispose();
  }

  void _onBurstRequested() {
    final pending = widget.controller.takePending();
    if (_reduceMotion || pending.isEmpty) return;

    for (final burst in pending) {
      _bursts.add(_LiveBurst.spawn(burst, _clockMs.value));
    }
    if (!_ticker.isActive) _ticker.start();
  }

  void _onTick(Duration elapsed) {
    final nowMs = elapsed.inMicroseconds / 1000.0;
    final lifetimeMs = ParticleLayer.lifetime.inMilliseconds.toDouble();

    _bursts.removeWhere((burst) => nowMs - burst.startMs >= lifetimeMs);
    _clockMs.value = nowMs;

    // Nothing left to animate: stop the ticker so an idle grid costs no
    // frames at all.
    if (_bursts.isEmpty) _ticker.stop();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _ParticlePainter(
          clockMs: _clockMs,
          bursts: _bursts,
          lifetimeMs: ParticleLayer.lifetime.inMilliseconds.toDouble(),
          stats: widget.stats,
        ),
        size: Size.infinite,
      ),
    );
  }
}

final class ParticleBurst {
  const ParticleBurst({required this.origin, required this.color, this.seed});

  final Offset origin;
  final Color color;
  final int? seed;
}

final class _LiveBurst {
  const _LiveBurst({
    required this.origin,
    required this.color,
    required this.startMs,
    required this.particles,
  });

  factory _LiveBurst.spawn(ParticleBurst burst, double startMs) {
    final random = Random(burst.seed ?? burst.origin.hashCode);
    final count =
        ParticleLayer.minParticles +
        random.nextInt(
          ParticleLayer.maxParticles - ParticleLayer.minParticles + 1,
        );

    return _LiveBurst(
      origin: burst.origin,
      color: burst.color,
      startMs: startMs,
      particles: [
        for (var i = 0; i < count; i++)
          _Particle(
            // Spread evenly and then jitter, so a burst never clumps to one
            // side the way pure random angles sometimes do.
            angle: (i / count) * 2 * pi + random.nextDouble() * 0.5,
            // Biased upward-and-out, per Ch03.
            speed: 26 + random.nextDouble() * 30,
            radius: 1.6 + random.nextDouble() * 2.2,
          ),
      ],
    );
  }

  final Offset origin;
  final Color color;
  final double startMs;
  final List<_Particle> particles;
}

final class _Particle {
  const _Particle({
    required this.angle,
    required this.speed,
    required this.radius,
  });

  final double angle;
  final double speed;
  final double radius;
}

final class _ParticlePainter extends CustomPainter {
  _ParticlePainter({
    required this.clockMs,
    required this.bursts,
    required this.lifetimeMs,
    this.stats,
  }) : super(repaint: clockMs);

  final ValueNotifier<double> clockMs;
  final List<_LiveBurst> bursts;
  final double lifetimeMs;
  final GridPaintStats? stats;

  /// Downward pull, in pixels over the full lifetime. Particles rise and then
  /// fall away rather than drifting outward forever.
  static const double _gravity = 46;

  @override
  void paint(Canvas canvas, Size size) {
    if (bursts.isEmpty) return;
    stats?.particles++;

    final now = clockMs.value;

    for (final burst in bursts) {
      final t = ((now - burst.startMs) / lifetimeMs).clamp(0.0, 1.0);
      final eased = Curves.easeOutCubic.transform(t);
      final paint = Paint()
        ..color = burst.color.withValues(alpha: (1 - t) * 0.9);

      for (final particle in burst.particles) {
        final dx = cos(particle.angle) * particle.speed * eased;
        // Upward first (negative y), with gravity growing as t squared.
        final dy =
            sin(particle.angle) * particle.speed * eased -
            particle.speed * 0.35 * eased +
            _gravity * t * t;

        canvas.drawCircle(
          burst.origin + Offset(dx, dy),
          particle.radius * (1 - t * 0.5),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) =>
      !identical(old.bursts, bursts) ||
      old.lifetimeMs != lifetimeMs ||
      !identical(old.clockMs, clockMs);
}
