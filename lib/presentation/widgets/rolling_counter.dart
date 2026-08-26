import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../app/theme/motion.dart';

/// A number that animates to a new value rather than snapping to it —
/// P07's score readout in the top bar, and the score/coin roll-up on the
/// level-complete card.
///
/// Built on [TweenAnimationBuilder] rather than an owned
/// [AnimationController]: the builder already tracks the previous displayed
/// value as its animation's start point, so this only has to say where it's
/// going.
class RollingCounter extends StatefulWidget {
  const RollingCounter({
    required this.value,
    this.style,
    this.startDelay = Duration.zero,
    super.key,
  });

  final int value;
  final TextStyle? style;

  /// Waits this long after [value] changes before the roll begins — e.g.
  /// Ch03's "160ms score roll starts" in the correct-word sequence, via
  /// [scoreRollDelay]. Zero (the default) starts immediately, which is what
  /// every caller outside that one sequence wants.
  final Duration startDelay;

  /// 400ms, linear — a literal from the bible's top-bar spec, not on the
  /// Motion scale (Ch03/Ch09). Kept as a named constant, like
  /// `ParticleLayer.lifetime`, rather than an inline magic number.
  static const Duration duration = Duration(milliseconds: 400);

  /// Ch03's correct-word sequence: "160ms score roll starts". Named here,
  /// next to [duration], because both describe this widget's own timeline —
  /// `game_screen.dart` just points its top-bar counter at it.
  static const Duration scoreRollDelay = Duration(milliseconds: 160);

  @override
  State<RollingCounter> createState() => _RollingCounterState();
}

class _RollingCounterState extends State<RollingCounter> {
  /// The value the tween animates TOWARD. Separate from `widget.value` so a
  /// delayed roll can hold at the OLD value for [RollingCounter.startDelay]
  /// before this — and the animation — moves at all.
  late final ValueNotifier<int> _target = ValueNotifier<int>(widget.value);

  Timer? _delayTimer;

  @override
  void didUpdateWidget(RollingCounter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value == widget.value) return;

    _delayTimer?.cancel();
    final delay = Motion.reduced(context, widget.startDelay);
    if (delay == Duration.zero) {
      _target.value = widget.value;
    } else {
      _delayTimer = Timer(delay, () => _target.value = widget.value);
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _target.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Screen readers should hear the settled number once, not every
    // intermediate frame of the roll — and not wait for a delayed roll to
    // even start.
    return Semantics(
      value: '${widget.value}',
      excludeSemantics: true,
      child: ValueListenableBuilder<int>(
        valueListenable: _target,
        builder: (context, target, child) {
          return TweenAnimationBuilder<double>(
            tween: Tween<double>(end: target.toDouble()),
            duration: Motion.reduced(context, RollingCounter.duration),
            curve: Curves.linear,
            builder: (context, animated, child) {
              return Text(
                '${animated.round()}',
                style: widget.style ?? DefaultTextStyle.of(context).style,
              );
            },
          );
        },
      ),
    );
  }
}
