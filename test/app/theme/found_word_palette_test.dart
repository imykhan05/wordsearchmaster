import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/app/theme/app_tokens.dart';
import 'package:word_search_master/domain/theme/app_theme_variant.dart';

import '../../support/color_vision.dart';

/// Verifies the accessibility claims in [AppColors] instead of taking them on
/// trust — for EVERY palette the app can wear, not only the two it shipped
/// with. Two found words highlighted at the same time must stay obviously
/// different, including for the ~8% of men with a colour vision deficiency
/// (Ch03), and every piece of text must stay readable on whatever ground the
/// player picked.
///
/// If this fails after a palette edit, pick different hues; do not lower the
/// thresholds. That instruction is what makes adding a ninth theme a bounded
/// piece of work rather than an accessibility regression nobody notices.
void main() {
  /// CIE76 ΔE. An order of magnitude above the ~2.3 just-noticeable
  /// threshold, so the two colours read as plainly different at a glance.
  /// The shipped palettes clear this with roughly 9 ΔE of headroom.
  const minimumDeltaE = 25.0;

  /// WCAG contrast ratio of a highlight against the surface it sits on. The
  /// border is drawn at full strength, so this is what decides whether a
  /// found-word capsule is visible at all.
  const minimumContrast = 3.0;

  /// WCAG AA for normal-size body text. [AppColors.onSurface] is what the word
  /// list, the score and every label are drawn in.
  const minimumBodyContrast = 4.5;

  /// Large/secondary text and non-text UI: muted and faint labels, and the
  /// accent itself against the ground it sits on.
  const minimumSecondaryContrast = 3.0;

  final palettes = {
    for (final variant in AppThemeVariant.values)
      variant.id: AppTokens.colorsFor(variant),
  };

  /// How far the SHIPPED accent already sits from its own family's found-word
  /// six. Every added palette has to clear its family's own number.
  ///
  /// A measured bar rather than a chosen one: this is the separation the live
  /// app has always had between the selection capsule under the player's
  /// finger and the words already found, so "at least as distinguishable as
  /// the app people are playing today" is a claim with a value behind it.
  double accentSeparation(AppColors colors) {
    var worst = double.infinity;
    for (final vision in ColorVision.values) {
      final accent = simulate(colors.primary, vision);
      for (final found in colors.foundWord) {
        final distance = deltaE(accent, simulate(found, vision));
        if (distance < worst) worst = distance;
      }
    }
    return worst;
  }

  final darkBar = accentSeparation(AppTokens.darkColors);
  final lightBar = accentSeparation(AppTokens.lightColors);

  test('every variant has a palette, and no two share one', () {
    // `AppTokens.colorsFor` is an exhaustive switch, so a variant with no
    // palette cannot compile — but two variants returning the SAME palette
    // would, and would ship a picker where one of the chips does nothing.
    expect(palettes, hasLength(AppThemeVariant.values.length));
    final grounds = palettes.values.map((colors) => colors.background).toSet();
    expect(
      grounds,
      hasLength(AppThemeVariant.values.length),
      reason: 'two themes paint the same page colour',
    );
  });

  test('the two original palettes are reachable, unchanged, by name', () {
    // A player pinning "Midnight" must get exactly the app they already had.
    expect(
      AppTokens.colorsFor(AppThemeVariant.midnight),
      same(AppTokens.darkColors),
    );
    expect(
      AppTokens.colorsFor(AppThemeVariant.daylight),
      same(AppTokens.lightColors),
    );
  });

  for (final variant in AppThemeVariant.values) {
    final colors = palettes[variant.id]!;
    final palette = colors.foundWord;
    final surface = colors.surfaceElevated;

    group('${variant.id} palette', () {
      test(
        'every found-word colour has enough contrast against the surface',
        () {
          for (var i = 0; i < palette.length; i++) {
            expect(
              contrastRatio(palette[i], surface),
              greaterThanOrEqualTo(minimumContrast),
              reason: '${variant.id} found-word colour $i is too faint to see',
            );
          }
        },
      );

      test('has exactly 6 found-word colours', () {
        expect(palette, hasLength(6));
      });

      test('has a border weight for every colour', () {
        // Colour is never the only cue — each highlight also differs by stroke.
        expect(AppTokens.foundWordBorderWidths, hasLength(palette.length));
      });

      test('every found-word colour is distinct', () {
        expect(palette.toSet(), hasLength(palette.length));
      });

      test('body text is readable on this ground', () {
        expect(
          contrastRatio(colors.onSurface, colors.surface),
          greaterThanOrEqualTo(minimumBodyContrast),
          reason: '${variant.id} body text fails WCAG AA on its own surface',
        );
      });

      test('muted and faint text stay readable on this ground', () {
        for (final entry in {
          'onSurfaceMuted': colors.onSurfaceMuted,
          'onSurfaceFaint': colors.onSurfaceFaint,
        }.entries) {
          expect(
            contrastRatio(entry.value, colors.surface),
            greaterThanOrEqualTo(minimumSecondaryContrast),
            reason: '${variant.id} ${entry.key} is too faint on its surface',
          );
        }
      });

      test('the accent is visible, and carries readable text of its own', () {
        // `primary` is the live selection capsule, every filled button and the
        // progress bar; `onPrimary` is the text drawn on top of it.
        expect(
          contrastRatio(colors.primary, colors.surface),
          greaterThanOrEqualTo(minimumSecondaryContrast),
          reason: '${variant.id} accent disappears into its own ground',
        );
        expect(
          contrastRatio(colors.onPrimary, colors.primary),
          greaterThanOrEqualTo(minimumBodyContrast),
          reason: '${variant.id} button text fails WCAG AA on its own accent',
        );
      });

      test('the accent stays distinguishable from the found-word palette', () {
        // The capsule under a moving finger and a word already found must not
        // read as the same colour — including for a dichromat player.
        final bar = variant.isDark ? darkBar : lightBar;
        expect(
          accentSeparation(colors),
          greaterThanOrEqualTo(bar),
          reason:
              "${variant.id}'s accent sits closer to its found-word palette "
              'than the shipped one does (bar ΔE ${bar.toStringAsFixed(1)})',
        );
      });

      for (final vision in ColorVision.values) {
        test('found words stay distinguishable under ${vision.name}', () {
          final closest = closestPair(palette, vision);

          expect(
            closest.distance,
            greaterThan(minimumDeltaE),
            reason:
                'Under ${vision.name} the closest pair in the ${variant.id} '
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
    // much headroom is left before the thresholds above start failing.
    // ignore: avoid_print
    print(
      'accent-vs-foundWord bar: dark ${darkBar.toStringAsFixed(1)}, '
      'light ${lightBar.toStringAsFixed(1)}',
    );
    for (final entry in palettes.entries) {
      final colors = entry.value;
      final body = contrastRatio(colors.onSurface, colors.surface);
      final accent = accentSeparation(colors);
      for (final vision in ColorVision.values) {
        final closest = closestPair(colors.foundWord, vision);
        // ignore: avoid_print
        print(
          '${entry.key.padRight(13)} ${vision.name.padRight(13)} '
          'closest ΔE ${closest.distance.toStringAsFixed(1)} '
          '(indices ${closest.a}/${closest.b})  '
          'body ${body.toStringAsFixed(1)}:1  '
          'accent ΔE ${accent.toStringAsFixed(1)}',
        );
      }
    }
  });
}
