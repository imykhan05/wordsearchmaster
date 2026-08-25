import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/application/game_controller.dart';
import 'package:word_search_master/domain/grid/cell.dart';
import 'package:word_search_master/domain/grid/grid_vector.dart';
import 'package:word_search_master/domain/grid/selection_resolver.dart';
import 'package:word_search_master/domain/scoring/score_event.dart';
import 'package:word_search_master/domain/scoring/scoring.dart';

/// Covers P07's GameController: the events-as-source-of-truth derivations,
/// the Zeigarnik swap, and the phase-guarded actions. See the doc header in
/// lib/application/game_controller.dart for the design this exercises.
void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  /// Selects a real placed word by tracing its own cells — mirrors the
  /// pattern in game_grid_test.dart, so this never depends on knowing the
  /// (private) demo word list's actual content.
  SelectionState selectionFor(GameState state, int index) {
    final placement = state.grid.placementDetails[index];
    return SelectionState(
      anchor: placement.cells.first,
      direction: placement.direction,
      cells: placement.cells,
    );
  }

  group('build', () {
    test('loads the requested level, ready to play', () async {
      final state = await container.read(gameControllerProvider(1).future);

      expect(state.level, 1);
      expect(state.phase, GamePhase.playing);
      expect(state.foundWords, isEmpty);
      expect(state.events, isEmpty);
      expect(state.hintedCell, isNull);
      expect(state.completedSummary, isNull);
      expect(state.remainingWords, state.allWords);
      expect(state.allWords, isNotEmpty);
      expect(state.score, 0);
      expect(state.combo, 0);
      expect(state.hintsUsed, 0);
      expect(state.isLevelWon, isFalse);
    });

    test(
      'the same level always loads the same grid (P04 determinism)',
      () async {
        final first = await container.read(gameControllerProvider(3).future);

        final other = ProviderContainer();
        addTearDown(other.dispose);
        final second = await other.read(gameControllerProvider(3).future);

        expect(second.grid.cells, first.grid.cells);
      },
    );
  });

  group('processSelection', () {
    test('a correct word is scored and added to foundWords', () async {
      final state = await container.read(gameControllerProvider(1).future);
      final notifier = container.read(gameControllerProvider(1).notifier);
      final placement = state.grid.placementDetails.first;

      final outcome = notifier.processSelection(selectionFor(state, 0));

      expect(outcome.matchedWord, placement.word);
      final next = container.read(gameControllerProvider(1)).value!;
      expect(next.foundWords, [placement.word]);
      expect(next.events, [WordFound(graphemeCount: placement.cells.length)]);
      expect(next.score, placement.cells.length * 10);
      expect(next.combo, 1);
    });

    test(
      'a selection matching nothing logs a wrong selection, not points',
      () async {
        await container.read(gameControllerProvider(1).future);
        final notifier = container.read(gameControllerProvider(1).notifier);
        final state = container.read(gameControllerProvider(1)).value!;

        // Two adjacent corner cells are never a real placed word at this size.
        final outcome = notifier.processSelection(
          SelectionState(
            anchor: const Cell(0, 0),
            direction: GridVector.east,
            cells: const [Cell(0, 0), Cell(0, 1)],
          ),
        );

        expect(outcome.matchedWord, isNull);
        final next = container.read(gameControllerProvider(1)).value!;
        expect(next.events, [const WrongSelection()]);
        expect(next.foundWords, isEmpty);
        expect(next.combo, 0);
        expect(state.grid.cells, next.grid.cells);
      },
    );

    test('a wrong selection resets a running combo', () async {
      final state = await container.read(gameControllerProvider(1).future);
      final notifier = container.read(gameControllerProvider(1).notifier);

      notifier.processSelection(selectionFor(state, 0));
      expect(container.read(gameControllerProvider(1)).value!.combo, 1);

      notifier.processSelection(
        SelectionState(
          anchor: const Cell(0, 0),
          direction: GridVector.east,
          cells: const [Cell(0, 0), Cell(0, 1)],
        ),
      );

      expect(container.read(gameControllerProvider(1)).value!.combo, 0);
    });

    test('a tap (single cell) is not an attempt', () async {
      await container.read(gameControllerProvider(1).future);
      final notifier = container.read(gameControllerProvider(1).notifier);

      final outcome = notifier.processSelection(
        const SelectionState(
          anchor: Cell(0, 0),
          direction: null,
          cells: [Cell(0, 0)],
        ),
      );

      expect(outcome.matchedWord, isNull);
      expect(container.read(gameControllerProvider(1)).value!.events, isEmpty);
    });

    test('re-tracing an already-found word does not double count it', () async {
      final state = await container.read(gameControllerProvider(1).future);
      final notifier = container.read(gameControllerProvider(1).notifier);
      final placement = state.grid.placementDetails.first;

      notifier.processSelection(selectionFor(state, 0));
      final outcome = notifier.processSelection(selectionFor(state, 0));

      expect(
        outcome.matchedWord,
        isNull,
        reason: 'the word is no longer in remainingWords once found',
      );
      final next = container.read(gameControllerProvider(1)).value!;
      expect(next.foundWords, [placement.word]);
    });
  });

  group('useHint', () {
    test(
      'points at the first remaining word and logs a HintUsed event',
      () async {
        final state = await container.read(gameControllerProvider(1).future);
        final notifier = container.read(gameControllerProvider(1).notifier);
        final firstRemainingWord = state.remainingWords.first;
        final expectedCell = state.grid.placements[firstRemainingWord]!.first;

        notifier.useHint();

        final next = container.read(gameControllerProvider(1)).value!;
        expect(next.hintedCell, expectedCell);
        expect(next.events, [const HintUsed()]);
        expect(next.hintsUsed, 1);
        expect(next.stars, 2, reason: 'one hint costs a star (Ch08 rule)');
      },
    );

    test('finding the hinted word clears the hint', () async {
      final state = await container.read(gameControllerProvider(1).future);
      final notifier = container.read(gameControllerProvider(1).notifier);

      notifier.useHint();
      expect(
        container.read(gameControllerProvider(1)).value!.hintedCell,
        isNotNull,
      );

      notifier.processSelection(selectionFor(state, 0));

      expect(
        container.read(gameControllerProvider(1)).value!.hintedCell,
        isNull,
      );
    });

    test('does nothing while paused', () async {
      await container.read(gameControllerProvider(1).future);
      final notifier = container.read(gameControllerProvider(1).notifier);

      notifier.pause();
      notifier.useHint();

      expect(container.read(gameControllerProvider(1)).value!.events, isEmpty);
    });
  });

  group('pause / resume', () {
    test('pause then resume round-trips the phase', () async {
      await container.read(gameControllerProvider(1).future);
      final notifier = container.read(gameControllerProvider(1).notifier);

      notifier.pause();
      expect(
        container.read(gameControllerProvider(1)).value!.phase,
        GamePhase.paused,
      );

      notifier.resume();
      expect(
        container.read(gameControllerProvider(1)).value!.phase,
        GamePhase.playing,
      );
    });

    test('resume while not paused is a no-op', () async {
      await container.read(gameControllerProvider(1).future);
      final notifier = container.read(gameControllerProvider(1).notifier);

      notifier.resume();

      expect(
        container.read(gameControllerProvider(1)).value!.phase,
        GamePhase.playing,
      );
    });
  });

  test('restart reloads the same level from scratch', () async {
    final state = await container.read(gameControllerProvider(1).future);
    final notifier = container.read(gameControllerProvider(1).notifier);

    notifier.processSelection(selectionFor(state, 0));
    notifier.pause();
    expect(
      container.read(gameControllerProvider(1)).value!.foundWords,
      isNotEmpty,
    );

    notifier.restart();

    final next = container.read(gameControllerProvider(1)).value!;
    expect(next.level, 1);
    expect(next.phase, GamePhase.playing);
    expect(next.foundWords, isEmpty);
    expect(next.events, isEmpty);
    expect(next.grid.cells, state.grid.cells, reason: 'same seed, same grid');
  });

  group('the Zeigarnik swap', () {
    Future<GameState> completeLevel(
      ProviderContainer container,
      int level,
    ) async {
      final state = await container.read(gameControllerProvider(level).future);
      final notifier = container.read(gameControllerProvider(level).notifier);

      for (var i = 0; i < state.grid.placementDetails.length; i++) {
        notifier.processSelection(selectionFor(state, i));
      }
      return container.read(gameControllerProvider(level)).value!;
    }

    test(
      'finishing the last word already shows the NEXT level, behind the card',
      () async {
        final after = await completeLevel(container, 1);

        expect(after.phase, GamePhase.levelComplete);
        expect(after.level, 2, reason: 'already advanced, not still level 1');
        expect(after.foundWords, isEmpty);
        expect(
          after.remainingWords,
          after.allWords,
          reason: 'level 2 word list, nothing found in it yet',
        );
        expect(after.allWords, isNotEmpty);
      },
    );

    test(
      'the pre-loaded next grid is the SAME canonical grid for that level',
      () async {
        final after = await completeLevel(container, 1);
        final zeigarnikGrid = after.grid;

        container.read(gameControllerProvider(1).notifier).jumpToLevel(2);
        final direct = container.read(gameControllerProvider(1)).value!;

        expect(direct.grid.cells, zeigarnikGrid.cells);
      },
    );

    test(
      'the frozen summary reports the level that was just finished',
      () async {
        final after = await completeLevel(container, 1);
        final summary = after.completedSummary;

        expect(summary, isNotNull);
        expect(summary!.level, 1);
        expect(summary.stars, 3, reason: 'no hints were used');
        expect(summary.coinsEarned, 30);
        expect(summary.maxCombo, greaterThan(0));
      },
    );

    test('dismissing the card keeps the already-advanced level and clears the summary', () async {
      await completeLevel(container, 1);
      final notifier = container.read(gameControllerProvider(1).notifier);

      notifier.dismissLevelComplete();

      final next = container.read(gameControllerProvider(1)).value!;
      expect(next.phase, GamePhase.playing);
      expect(next.level, 2);
      expect(next.completedSummary, isNull);
    });
  });

  group('dev-only controls', () {
    test('jumpToLevel loads an arbitrary level fresh', () async {
      await container.read(gameControllerProvider(1).future);
      final notifier = container.read(gameControllerProvider(1).notifier);

      notifier.jumpToLevel(7);

      final next = container.read(gameControllerProvider(1)).value!;
      expect(next.level, 7);
      expect(next.phase, GamePhase.playing);
      expect(next.foundWords, isEmpty);
    });

    test(
      'debugForcePhase(levelComplete) still runs the real Zeigarnik swap',
      () async {
        final state = await container.read(gameControllerProvider(1).future);
        final notifier = container.read(gameControllerProvider(1).notifier);

        notifier.debugForcePhase(GamePhase.levelComplete);

        final next = container.read(gameControllerProvider(1)).value!;
        expect(next.phase, GamePhase.levelComplete);
        expect(next.level, 2);
        expect(next.completedSummary, isNotNull);
        expect(next.completedSummary!.level, 1);
        expect(
          next.grid.cells,
          isNot(state.grid.cells),
          reason: 'forcing the phase must not leave level 1 on screen',
        );
      },
    );

    test('debugForcePhase(paused) only flips the phase', () async {
      final state = await container.read(gameControllerProvider(1).future);
      final notifier = container.read(gameControllerProvider(1).notifier);

      notifier.debugForcePhase(GamePhase.paused);

      final next = container.read(gameControllerProvider(1)).value!;
      expect(next.phase, GamePhase.paused);
      expect(next.level, state.level);
      expect(next.grid.cells, state.grid.cells);
    });
  });

  test('GameState.score always agrees with Scoring.computeScore', () async {
    final state = await container.read(gameControllerProvider(1).future);
    final notifier = container.read(gameControllerProvider(1).notifier);

    notifier.processSelection(selectionFor(state, 0));
    notifier.processSelection(
      SelectionState(
        anchor: const Cell(0, 0),
        direction: GridVector.east,
        cells: const [Cell(0, 0), Cell(0, 1)],
      ),
    );
    notifier.useHint();

    final next = container.read(gameControllerProvider(1)).value!;
    expect(next.score, Scoring.computeScore(next.events));
  });
}
