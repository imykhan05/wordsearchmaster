import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/app/config/app_config.dart';
import 'package:word_search_master/app/theme/theme.dart';
import 'package:word_search_master/application/game_controller.dart';
import 'package:word_search_master/domain/grid/selection_resolver.dart';
import 'package:word_search_master/l10n/app_localizations.dart';
import 'package:word_search_master/presentation/game/game_grid.dart';
import 'package:word_search_master/presentation/game/level_complete_card.dart';
import 'package:word_search_master/presentation/screens/game_screen.dart';

/// Covers P07's acceptance criteria directly: 20 levels playable back to
/// back without a crash, the next level already loaded behind the result
/// card (Ch02 Zeigarnik), and no `setState` anywhere in the gameplay UI.
void main() {
  Future<ProviderContainer> pumpGameScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appConfigProvider.overrideWithValue(AppConfig.prod())],
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const GameScreen(levelId: '1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(GameScreen)));
  }

  testWidgets(
    'a found word gets a thin strike-through, not a bar covering the text',
    (tester) async {
      final container = await pumpGameScreen(tester);
      final notifier = container.read(gameControllerProvider(1).notifier);
      final state = container.read(gameControllerProvider(1)).value!;
      final placement = state.grid.placementDetails.first;

      notifier.processSelection(
        SelectionState(
          anchor: placement.cells.first,
          direction: placement.direction,
          cells: placement.cells,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      // Regression: Positioned.fill hands down tight constraints, and
      // without an Align to loosen them, the strike bar used to stretch to
      // the chip's full height and blot out the word underneath it. Scoped
      // to this one chip — every chip has its own FractionallySizedBox.
      final thisChip = find.ancestor(
        of: find.text(placement.word),
        matching: find.byType(AnimatedContainer),
      );
      final strikeBarFinder = find.descendant(
        of: thisChip,
        matching: find.byType(FractionallySizedBox),
      );
      final strikeBar = tester.widget<FractionallySizedBox>(strikeBarFinder);
      final renderedSize = tester.getSize(strikeBarFinder);

      expect(strikeBar.widthFactor, closeTo(1.0, 0.01));
      expect(
        renderedSize.height,
        lessThan(8),
        reason: 'the strike-through must stay a thin line, not fill the chip',
      );
      expect(find.text(placement.word), findsOneWidget);
    },
  );

  testWidgets(
    'levels 1 through 20 play continuously, with the next level already '
    'loaded and visible behind the result card',
    (tester) async {
      final container = await pumpGameScreen(tester);
      final notifier = container.read(gameControllerProvider(1).notifier);

      for (var level = 1; level <= 20; level++) {
        final state = container.read(gameControllerProvider(1)).value!;
        expect(state.level, level, reason: 'one level at a time, in order');
        expect(state.phase, GamePhase.playing);

        for (final placement in state.grid.placementDetails) {
          notifier.processSelection(
            SelectionState(
              anchor: placement.cells.first,
              direction: placement.direction,
              cells: placement.cells,
            ),
          );
        }
        await tester.pump();

        expect(
          find.byType(LevelCompleteCard),
          findsOneWidget,
          reason: 'level $level should be complete',
        );

        final behindTheCard = container.read(gameControllerProvider(1)).value!;
        expect(
          behindTheCard.level,
          level + 1,
          reason:
              'Zeigarnik: GameState already advanced before the card '
              'was dismissed',
        );
        // Not just the state — the MOUNTED grid widget is already showing
        // the next level's board, not the one that was just finished.
        final renderedGrid = tester.widget<GameGrid>(find.byType(GameGrid));
        expect(renderedGrid.cells, behindTheCard.grid.cells);
        expect(
          renderedGrid.foundWordCells,
          isEmpty,
          reason: 'the next level starts with nothing found yet',
        );

        notifier.dismissLevelComplete();
        await tester.pump();
        expect(find.byType(LevelCompleteCard), findsNothing);
      }

      expect(
        container.read(gameControllerProvider(1)).value!.level,
        21,
        reason: '20 levels finished back to back without throwing',
      );
    },
  );

  test('no setState in the gameplay widgets — Riverpod drives all of it', () {
    // GameGrid's own local UI concerns (the ValueNotifier-driven drag, the
    // painter cache) are P06 and already proven not to use it; re-checked
    // here because P07 edited the file to add the hint layer.
    const checked = [
      'lib/presentation/screens/game_screen.dart',
      'lib/presentation/game/game_grid.dart',
      'lib/presentation/game/level_complete_card.dart',
      'lib/presentation/game/pause_sheet.dart',
      'lib/presentation/widgets/rolling_counter.dart',
    ];

    for (final path in checked) {
      final content = File(path).readAsStringSync();
      expect(
        content.contains('setState('),
        isFalse,
        reason: '$path must drive state through Riverpod, not setState',
      );
    }
  });
}
