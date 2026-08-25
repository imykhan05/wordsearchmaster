import 'package:flutter/material.dart';

/// Every animation in the app references these constants — never a raw
/// `Duration(milliseconds: ...)` or a bare `Curves.*` at the call site.
/// The millisecond values come from the game-feel spec (Ch03), where the
/// found-word choreography is timed against them.
abstract final class Motion {
  /// Colour/opacity swaps that should read as immediate but not jarring.
  static const Duration instant = Duration(milliseconds: 90);

  /// Small transforms: scale punches, chip strike-throughs.
  static const Duration quick = Duration(milliseconds: 140);

  /// The default for most transitions.
  static const Duration base = Duration(milliseconds: 220);

  /// Celebratory / full-screen movement: level-complete, chest open.
  static const Duration slow = Duration(milliseconds: 340);

  /// Overshoot, for things that should feel physical (scale punch on a
  /// found word, stars landing on the result card).
  static const Curve punch = Curves.easeOutBack;

  /// Decelerate into rest — particles, counters, list settles.
  static const Curve settle = Curves.easeOutCubic;

  /// Symmetric ease for cross-fades and strike-through draws.
  static const Curve fade = Curves.easeInOutQuad;

  /// Returns [duration], or [Duration.zero] when the platform asks for
  /// reduced motion (`MediaQuery.disableAnimations`).
  ///
  /// Per Ch03 accessibility: with reduce-motion on, particles are skipped and
  /// every duration collapses to zero — but audio and haptics still fire, so
  /// the player keeps the feedback, just without the movement.
  static Duration reduced(BuildContext context, Duration duration) {
    return MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
  }

  /// All four named durations, already resolved against reduce-motion.
  ///
  /// Prefer this when a widget animates several things at once, so a single
  /// `MediaQuery` read decides all of them:
  ///
  /// ```dart
  /// final motion = Motion.of(context);
  /// AnimatedContainer(duration: motion.base, curve: Motion.settle, ...);
  /// ```
  static ResolvedMotion of(BuildContext context) {
    return ResolvedMotion._(disabled: MediaQuery.disableAnimationsOf(context));
  }
}

/// The named durations with reduce-motion already applied. Obtained from
/// [Motion.of].
@immutable
final class ResolvedMotion {
  const ResolvedMotion._({required this.disabled});

  /// True when the platform requested reduced motion, in which case every
  /// duration below is [Duration.zero].
  final bool disabled;

  Duration get instant => disabled ? Duration.zero : Motion.instant;
  Duration get quick => disabled ? Duration.zero : Motion.quick;
  Duration get base => disabled ? Duration.zero : Motion.base;
  Duration get slow => disabled ? Duration.zero : Motion.slow;

  /// Resolve an arbitrary duration (e.g. a staggered offset) the same way.
  Duration call(Duration duration) => disabled ? Duration.zero : duration;

  @override
  bool operator ==(Object other) =>
      other is ResolvedMotion && other.disabled == disabled;

  @override
  int get hashCode => disabled.hashCode;
}
