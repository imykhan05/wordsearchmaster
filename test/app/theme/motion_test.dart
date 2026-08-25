import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/app/theme/motion.dart';

void main() {
  group('named constants', () {
    test('match the Ch03 game-feel spec', () {
      expect(Motion.instant, const Duration(milliseconds: 90));
      expect(Motion.quick, const Duration(milliseconds: 140));
      expect(Motion.base, const Duration(milliseconds: 220));
      expect(Motion.slow, const Duration(milliseconds: 340));
    });

    test('curves are the specified ones', () {
      expect(Motion.punch, Curves.easeOutBack);
      expect(Motion.settle, Curves.easeOutCubic);
      expect(Motion.fade, Curves.easeInOutQuad);
    });

    test('durations ascend', () {
      expect(Motion.instant, lessThan(Motion.quick));
      expect(Motion.quick, lessThan(Motion.base));
      expect(Motion.base, lessThan(Motion.slow));
    });
  });

  group('reduce motion', () {
    Widget harness({
      required bool disableAnimations,
      required void Function(BuildContext) onBuild,
    }) {
      return MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Builder(
          builder: (context) {
            onBuild(context);
            return const SizedBox.shrink();
          },
        ),
      );
    }

    testWidgets('EVERY named duration collapses to zero when enabled', (
      tester,
    ) async {
      late ResolvedMotion motion;
      await tester.pumpWidget(
        harness(
          disableAnimations: true,
          onBuild: (context) => motion = Motion.of(context),
        ),
      );

      expect(motion.disabled, isTrue);
      expect(motion.instant, Duration.zero);
      expect(motion.quick, Duration.zero);
      expect(motion.base, Duration.zero);
      expect(motion.slow, Duration.zero);
      // Arbitrary durations (staggers, per-cell offsets) collapse too.
      expect(motion(const Duration(seconds: 5)), Duration.zero);
    });

    testWidgets('durations are untouched when reduce motion is off', (
      tester,
    ) async {
      late ResolvedMotion motion;
      await tester.pumpWidget(
        harness(
          disableAnimations: false,
          onBuild: (context) => motion = Motion.of(context),
        ),
      );

      expect(motion.disabled, isFalse);
      expect(motion.instant, Motion.instant);
      expect(motion.quick, Motion.quick);
      expect(motion.base, Motion.base);
      expect(motion.slow, Motion.slow);
    });

    testWidgets('Motion.reduced honours the same flag', (tester) async {
      late Duration reducedOn;
      await tester.pumpWidget(
        harness(
          disableAnimations: true,
          onBuild: (context) =>
              reducedOn = Motion.reduced(context, Motion.slow),
        ),
      );
      expect(reducedOn, Duration.zero);

      late Duration reducedOff;
      await tester.pumpWidget(
        harness(
          disableAnimations: false,
          onBuild: (context) =>
              reducedOff = Motion.reduced(context, Motion.slow),
        ),
      );
      expect(reducedOff, Motion.slow);
    });

    testWidgets('an animation actually finishes in one frame when reduced', (
      tester,
    ) async {
      // Proves the end-to-end effect, not just the returned value.
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Builder(
              builder: (context) => AnimatedContainer(
                duration: Motion.of(context).slow,
                curve: Motion.settle,
                width: 200,
                height: 10,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      // No pending frames scheduled: the transition was instantaneous.
      expect(tester.hasRunningAnimations, isFalse);
    });
  });
}
