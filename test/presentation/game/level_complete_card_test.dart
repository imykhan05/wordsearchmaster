import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/app/theme/app_theme.dart';
import 'package:word_search_master/application/game_controller.dart';
import 'package:word_search_master/l10n/app_localizations.dart';
import 'package:word_search_master/presentation/game/level_complete_card.dart';

/// Ch03's LEVEL COMPLETE choreography: confetti, staggered stars and the
/// score/coin roll are already covered for the stars/score piece by P07 —
/// this file is scoped to what P09 actually added: the confetti burst, and
/// reduce-motion turning it off entirely rather than just speeding it up.
void main() {
  const summary = LevelCompletionSummary(
    level: 3,
    score: 103,
    stars: 2,
    maxCombo: 4,
    coinsEarned: 20,
  );

  Widget wrap({required bool reduceMotion}) {
    return MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: LevelCompleteCard(summary: summary, onContinue: () {}),
        ),
      ),
    );
  }

  /// `_ConfettiPainter` is file-private — matched by its runtime type name
  /// rather than exporting it just for this check, the same trade every
  /// `CustomPainter` in this codebase makes (`grid_painter.dart`'s own
  /// painters are unexported too).
  int confettiLayerCount(WidgetTester tester) {
    return tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .where((w) => w.painter.runtimeType.toString() == '_ConfettiPainter')
        .length;
  }

  testWidgets('confetti bursts during the reveal', (tester) async {
    await tester.pumpWidget(wrap(reduceMotion: false));
    await tester.pump(const Duration(milliseconds: 200));

    expect(confettiLayerCount(tester), greaterThan(0));
  });

  testWidgets(
    'reduce-motion skips confetti entirely — Ch03 says "skipped", not "instant"',
    (tester) async {
      await tester.pumpWidget(wrap(reduceMotion: true));
      await tester.pump();

      expect(confettiLayerCount(tester), 0);
    },
  );

  testWidgets(
    'reduce-motion still lands on the correct final score/coins immediately',
    (tester) async {
      await tester.pumpWidget(wrap(reduceMotion: true));
      await tester.pump();

      expect(find.text('103'), findsOneWidget);
      expect(find.text('20'), findsOneWidget);
    },
  );

  testWidgets('the coin-fly glyph appears alongside the coins figure', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(reduceMotion: false));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byIcon(Icons.monetization_on_rounded), findsOneWidget);
  });
}
