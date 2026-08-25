import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/app/theme/app_theme.dart';
import 'package:word_search_master/app/theme/app_tokens.dart';

void main() {
  group('scales', () {
    test('spacing is exactly the specified scale', () {
      expect(AppTokens.spacingScale, [4.0, 8.0, 12.0, 16.0, 24.0, 32.0, 48.0]);
    });

    test('radii are exactly the specified scale', () {
      expect(AppTokens.radiusScale, [4.0, 8.0, 16.0]);
    });

    test('minimum touch target meets the accessibility floor', () {
      expect(AppTokens.minTouchTarget, greaterThanOrEqualTo(44));
    });
  });

  group('palette', () {
    test('marigold primary is the specified brand colour', () {
      expect(AppTokens.darkColors.primary, const Color(0xFFE8A33D));
    });

    test('both themes define every colour role', () {
      // Guards against a half-finished light theme: if a role were missing it
      // would have to be nullable, and the lerp below would throw.
      expect(
        () => AppTokens.darkColors.lerpTo(AppTokens.lightColors, 0.5),
        returnsNormally,
      );
    });
  });

  group('elevation', () {
    test('all three levels tint the surface AND cast a shadow', () {
      for (final tokens in [AppTokens.dark, AppTokens.light]) {
        for (final elevation in tokens.elevations) {
          expect(
            elevation.shadows,
            isNotEmpty,
            reason: '${tokens.brightness} elevation must cast a shadow',
          );
          expect(
            elevation.surface,
            isNot(tokens.colors.surfaceElevated),
            reason:
                '${tokens.brightness} elevation must tint the surface too — '
                'a shadow alone is invisible on a near-black ground',
          );
        }
      }
    });

    test('higher levels tint further from the base surface', () {
      for (final tokens in [AppTokens.dark, AppTokens.light]) {
        final base = tokens.colors.surfaceElevated;
        double distance(Color color) =>
            (color.r - base.r).abs() +
            (color.g - base.g).abs() +
            (color.b - base.b).abs();

        expect(
          distance(tokens.elevation2.surface),
          greaterThan(distance(tokens.elevation1.surface)),
        );
        expect(
          distance(tokens.elevation3.surface),
          greaterThan(distance(tokens.elevation2.surface)),
        );
      }
    });

    test('higher levels cast a softer, further shadow', () {
      for (final tokens in [AppTokens.dark, AppTokens.light]) {
        final levels = tokens.elevations;
        for (var i = 1; i < levels.length; i++) {
          expect(
            levels[i].shadows.first.blurRadius,
            greaterThan(levels[i - 1].shadows.first.blurRadius),
          );
          expect(
            levels[i].shadows.first.offset.dy,
            greaterThan(levels[i - 1].shadows.first.offset.dy),
          );
        }
      }
    });
  });

  group('ThemeExtension wiring', () {
    Future<AppTokens> resolveUnder(WidgetTester tester, ThemeData theme) async {
      late AppTokens resolved;
      await tester.pumpWidget(
        MaterialApp(
          // A distinct key per theme forces a fresh element, so the Builder
          // re-runs instead of the framework reusing the previous subtree.
          key: ValueKey(theme.brightness),
          theme: theme,
          home: Builder(
            builder: (context) {
              resolved = AppTokens.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return resolved;
    }

    testWidgets('AppTokens.of resolves the dark theme', (tester) async {
      final resolved = await resolveUnder(tester, AppTheme.dark());

      expect(resolved.brightness, Brightness.dark);
      expect(resolved.colors.background, AppTokens.darkColors.background);
    });

    testWidgets('AppTokens.of resolves the light theme', (tester) async {
      final resolved = await resolveUnder(tester, AppTheme.light());

      expect(resolved.brightness, Brightness.light);
      expect(resolved.colors.background, AppTokens.lightColors.background);
    });

    testWidgets('AppTokens.of throws a helpful error when not installed', (
      tester,
    ) async {
      // A missing extension is a wiring bug (app built without AppTheme), so
      // it should fail loudly rather than silently fall back to a default.
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(),
          home: Builder(
            builder: (context) {
              expect(
                () => AppTokens.of(context),
                throwsA(
                  isA<FlutterError>().having(
                    (error) => error.message,
                    'message',
                    contains('AppTokens not found'),
                  ),
                ),
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });

    test('lerp blends colours and does not throw', () {
      final mid = AppTokens.dark.lerp(AppTokens.light, 0.5);
      expect(mid, isA<AppTokens>());
      expect(mid.colors.foundWord, hasLength(6));
    });
  });
}
