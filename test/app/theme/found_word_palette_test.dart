import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/app/theme/app_tokens.dart';

import '../../support/color_vision.dart';

/// Verifies the accessibility claim in `AppColors.foundWord` instead of taking
/// it on trust. Two found words highlighted at the same time must stay
/// obviously different — including for the ~8% of men with a colour vision
/// deficiency (Ch03).
///
/// If this fails after a palette edit, pick different hues; do not lower the
/// threshold.
void main() {
  /// CIE76 ΔE. An order of magnitude above the ~2.3 just-noticeable
  /// threshold, so the two colours read as plainly different at a glance.
  /// The shipped palettes clear this with roughly 9 ΔE of headroom.
  const minimumDeltaE = 25.0;

  /// WCAG contrast ratio of a highlight against the surface it sits on. The
  /// border is drawn at full strength, so this is what decides whether a
  /// found-word capsule is visible at all.
  const minimumContrast = 3.0;

  final palettes = {
    'dark': (
      colors: AppTokens.darkColors.foundWord,
      surface: AppTokens.darkColors.surfaceElevated,
    ),
    'light': (
      colors: AppTokens.lightColors.foundWord,
      surface: AppTokens.lightColors.surfaceElevated,
    ),
  };

  for (final entry in palettes.entries) {
    final themeName = entry.key;
    final palette = entry.value.colors;
    final surface = entry.value.surface;

    group('$themeName found-word palette', () {
      test('every colour has enough contrast against the surface', () {
        for (var i = 0; i < palette.length; i++) {
          expect(
            contrastRatio(palette[i], surface),
            greaterThanOrEqualTo(minimumContrast),
            reason: '$themeName found-word colour $i is too faint to see',
          );
        }
      });

      test('has exactly 6 colours', () {
        expect(palette, hasLength(6));
      });

      test('has a border weight for every colour', () {
        // Colour is never the only cue — each highlight also differs by stroke.
        expect(AppTokens.foundWordBorderWidths, hasLength(palette.length));
      });

      test('every colour is distinct', () {
        expect(palette.toSet(), hasLength(palette.length));
      });

      for (final vision in ColorVision.values) {
        test('stays distinguishable under ${vision.name}', () {
          final closest = closestPair(palette, vision);

          expect(
            closest.distance,
            greaterThan(minimumDeltaE),
            reason:
                'Under ${vision.name} the closest pair in the $themeName '
                'palette is index ${closest.a} and ${closest.b}, only '
                'ΔE ${closest.distance.toStringAsFixed(1)} apart '
                '(need > $minimumDeltaE). Two found words in those slots '
                'would look like the same colour.',
          );
        });
      }
    });
  }

  test('reports the margin for each palette and vision type', () {
    // Not an assertion — prints the actual numbers so a palette edit shows how
    // much headroom is left before the threshold above starts failing.
    for (final entry in palettes.entries) {
      for (final vision in ColorVision.values) {
        final closest = closestPair(entry.value.colors, vision);
        // ignore: avoid_print
        print(
          '${entry.key.padRight(5)} ${vision.name.padRight(13)} '
          'closest ΔE ${closest.distance.toStringAsFixed(1)} '
          '(indices ${closest.a}/${closest.b})',
        );
      }
    }
  });
}
