import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/app/theme/app_theme.dart';
import 'package:word_search_master/app/theme/app_typography.dart';
import 'package:word_search_master/domain/text/language.dart';
import 'package:word_search_master/presentation/widgets/grid_cell_text.dart';

void main() {
  group('gridTextStyle', () {
    test('NEVER returns Nastaliq, for any language or size', () {
      // The single most important rule in Ch04: Nastaliq is calligraphic and
      // steeply sloped, so inside a square cell it is unreadable. A regression
      // here breaks the game for every Urdu player.
      for (final language in Language.values) {
        for (final cellSize in [24.0, 40.0, 72.0]) {
          final style = AppTypography.gridTextStyle(
            language,
            cellSize: cellSize,
          );
          expect(
            style.fontFamily,
            isNot(AppFonts.nastaliq),
            reason: 'grid cell for $language at $cellSize must not be Nastaliq',
          );
        }
      }
    });

    test('picks the right family per script', () {
      expect(
        AppTypography.gridTextStyle(Language.urdu).fontFamily,
        AppFonts.naskh,
      );
      expect(
        AppTypography.gridTextStyle(Language.hindi).fontFamily,
        AppFonts.devanagari,
      );
      expect(
        AppTypography.gridTextStyle(Language.english).fontFamily,
        AppFonts.latin,
      );
    });

    test('scales the glyph with the cell', () {
      final small = AppTypography.gridTextStyle(Language.urdu, cellSize: 20);
      final large = AppTypography.gridTextStyle(Language.urdu, cellSize: 60);

      expect(large.fontSize, greaterThan(small.fontSize!));
      expect(large.fontSize, closeTo(small.fontSize! * 3, 0.001));
    });

    test('gives Devanagari more leading than Latin, for matras', () {
      final hindi = AppTypography.gridTextStyle(Language.hindi);
      final english = AppTypography.gridTextStyle(Language.english);

      expect(hindi.height, greaterThan(english.height!));
      // ...and a smaller glyph box, so the akshara plus its matras fit.
      expect(hindi.fontSize, lessThan(english.fontSize!));
    });
  });

  group('uiTextStyle', () {
    test('uses Nastaliq for Urdu display-class roles only', () {
      for (final role in UiRole.values) {
        final family = AppTypography.uiTextStyle(
          Language.urdu,
          role,
        ).fontFamily;
        if (AppTypography.nastaliqRoles.contains(role)) {
          expect(family, AppFonts.nastaliq, reason: '$role should be Nastaliq');
        } else {
          expect(family, AppFonts.naskh, reason: '$role should be Naskh');
        }
      }
    });

    test('never uses Nastaliq for Hindi or English', () {
      for (final language in [Language.hindi, Language.english]) {
        for (final role in UiRole.values) {
          expect(
            AppTypography.uiTextStyle(language, role).fontFamily,
            isNot(AppFonts.nastaliq),
          );
        }
      }
    });

    test('gives Nastaliq extra leading over Naskh at the same role', () {
      // Nastaliq's tall ascenders and deep descenders collide without it.
      final nastaliq = AppTypography.uiTextStyle(Language.urdu, UiRole.heading);
      final naskh = AppTypography.uiTextStyle(Language.urdu, UiRole.body);

      expect(nastaliq.fontFamily, AppFonts.nastaliq);
      expect(naskh.fontFamily, AppFonts.naskh);
      expect(nastaliq.height, greaterThan(naskh.height!));
    });

    test('role sizes descend from display to caption', () {
      double size(UiRole role) =>
          AppTypography.uiTextStyle(Language.english, role).fontSize!;

      expect(size(UiRole.display), greaterThan(size(UiRole.heading)));
      expect(size(UiRole.heading), greaterThan(size(UiRole.title)));
      expect(size(UiRole.title), greaterThan(size(UiRole.body)));
      expect(size(UiRole.body), greaterThan(size(UiRole.caption)));
    });
  });

  group('text scaling', () {
    Widget harness({required double textScale, required Widget child}) {
      return MaterialApp(
        theme: AppTheme.dark(),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(body: child),
        ),
      );
    }

    testWidgets('grid cells ignore the system text scale', (tester) async {
      await tester.pumpWidget(
        harness(
          textScale: 2,
          child: const GridCellText(grapheme: 'پ', language: Language.urdu),
        ),
      );

      final text = tester.widget<Text>(find.text('پ'));
      expect(
        text.textScaler,
        TextScaler.noScaling,
        reason:
            'the grid scales via cell size; OS scaling on top overflows cells',
      );
    });

    testWidgets('grid cell glyph size is identical at 1.0x and 2.0x', (
      tester,
    ) async {
      Future<double> renderedFontSize(double scale) async {
        await tester.pumpWidget(
          harness(
            textScale: scale,
            child: const GridCellText(
              grapheme: 'W',
              language: Language.english,
              cellSize: 48,
            ),
          ),
        );
        final text = tester.widget<Text>(find.text('W'));
        return text.textScaler!.scale(text.style!.fontSize!);
      }

      expect(await renderedFontSize(1), await renderedFontSize(2));
    });

    testWidgets('ordinary UI text DOES respect the system text scale', (
      tester,
    ) async {
      // The rule is grid-cells-only; everywhere else must scale, since the
      // 45+ audience this game targets frequently runs a large system font.
      await tester.pumpWidget(
        harness(textScale: 2, child: const Text('Word Search')),
      );

      final text = tester.widget<Text>(find.text('Word Search'));
      final effective =
          text.textScaler ??
          MediaQuery.textScalerOf(tester.element(find.text('Word Search')));
      expect(effective.scale(10), 20);
    });
  });
}
