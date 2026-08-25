import 'package:flutter/widgets.dart';

import '../../app/theme/motion.dart';

/// A number that animates to a new value rather than snapping to it —
/// P07's score readout in the top bar, and the score/coin roll-up on the
/// level-complete card.
///
/// Built on [TweenAnimationBuilder] rather than an owned
/// [AnimationController]: the builder already tracks the previous [value] as
/// its animation's start point, so a new [RollingCounter] only has to say
/// where it's going.
class RollingCounter extends StatelessWidget {
  const RollingCounter({required this.value, this.style, super.key});

  final int value;
  final TextStyle? style;

  /// 400ms, linear — a literal from the bible's top-bar spec, not on the
  /// Motion scale (Ch03/Ch09). Kept as a named constant, like
  /// `ParticleLayer.lifetime`, rather than an inline magic number.
  static const Duration duration = Duration(milliseconds: 400);

  @override
  Widget build(BuildContext context) {
    // Screen readers should hear the settled number once, not every
    // intermediate frame of the roll.
    return Semantics(
      value: '$value',
      excludeSemantics: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: value.toDouble()),
        duration: Motion.reduced(context, duration),
        curve: Curves.linear,
        builder: (context, animated, child) {
          return Text(
            '${animated.round()}',
            style: style ?? DefaultTextStyle.of(context).style,
          );
        },
      ),
    );
  }
}
