import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/application/game_controller.dart';
import 'package:word_search_master/domain/grid/cell.dart';
import 'package:word_search_master/domain/grid/grid_vector.dart';
import 'package:word_search_master/domain/grid/selection_resolver.dart';
import 'package:word_search_master/domain/progression/day_key.dart';
import 'package:word_search_master/domain/scoring/score_event.dart';
import 'package:word_search_master/domain/scoring/scoring.dart';

/// Covers GameController: the events-as-source-of-truth derivations, the
/// Zeigarnik swap, and the phase-guarded actions (P07), now built on the real
/// content pack rather than a hardcoded demo word list (P10/P11). See the doc
/// header in lib/application/game_controller.dart for the design this
/// exercises. Daily-mode behaviour (no Zeigarnik swap) lives in its own test
/// group below; `daily_repository_test.dart` covers the offline/one-attempt
/// contract.
void main() {
  // GameController now resolves content through ContentRepository, which
  // reads real assets via rootBundle — needs the test binding, same as
  // content_repository_test.dart's real-asset case.
  TestWidgetsFlutterBinding.ensureInitialized();

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
      final state = await container.read(
        gameControllerProvider(JourneySession(1)).future,
      );

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
        final first = await container.read(
          gameControllerProvider(JourneySession(3)).future,
        );

        final other = ProviderContainer();
        addTearDown(other.dispose);
        final second = await other.read(
          gameControllerProvider(JourneySession(3)).future,
        );

        expect(second.grid.cells, first.grid.cells);
      },
    );
  });

  group('processSelection', () {
    test('a correct word is scored and added to foundWords', () async {
      final state = await container.read(
        gameControllerProvider(JourneySession(1)).future,
      );
      final notifier = container.read(
        gameControllerProvider(JourneySession(1)).notifier,
      );
      final placement = state.grid.placementDetails.first;

      final outcome = notifier.processSelection(selectionFor(state, 0));

      expect(outcome.matchedWord, placement.word);
      final next = container
          .read(gameControllerProvider(JourneySession(1)))
          .value!;
      expect(next.foundWords, [placement.word]);
      expect(next.events, [WordFound(graphemeCount: placement.cells.length)]);
      expect(next.score, placement.cells.length * 10);
      expect(next.combo, 1);
    });

    test(
      'a selection matching nothing logs a wrong selection, not points',
      () async {
        await container.read(gameControllerProvider(JourneySession(1)).future);
        final notifier = container.read(
          gameControllerProvider(JourneySession(1)).notifier,
        );
        final state = container
            .read(gameControllerProvider(JourneySession(1)))
            .value!;

        // Two adjacent corner cells are never a real placed word at this size.
        final outcome = notifier.processSelection(
          SelectionState(
            anchor: const Cell(0, 0),
            direction: GridVector.east,
            cells: const [Cell(0, 0), Cell(0, 1)],
          ),
        );

        expect(outcome.matchedWord, isNull);
        final next = container
            .read(gameControllerProvider(JourneySession(1)))
            .value!;
        expect(next.events, [const WrongSelection()]);
        expect(next.foundWords, isEmpty);
        expect(next.combo, 0);
        expect(state.grid.cells, next.grid.cells);
      },
    );

    test('a wrong selection resets a running combo', () async {
      final state = await container.read(
        gameControllerProvider(JourneySession(1)).future,
      );
      final notifier = container.read(
        gameControllerProvider(JourneySession(1)).notifier,
      );

      notifier.processSelection(selectionFor(state, 0));
      expect(
        container.read(gameControllerProvider(JourneySession(1))).value!.combo,
        1,
      );

      notifier.processSelection(
        SelectionState(
          anchor: const Cell(0, 0),
          direction: GridVector.east,
          cells: const [Cell(0, 0), Cell(0, 1)],
        ),
      );

      expect(
        container.read(gameControllerProvider(JourneySession(1))).value!.combo,
        0,
      );
    });

    test('a tap (single cell) is not an attempt', () async {
      await container.read(gameControllerProvider(JourneySession(1)).future);
      final notifier = container.read(
        gameControllerProvider(JourneySession(1)).notifier,
      );

      final outcome = notifier.processSelection(
        const SelectionState(
          anchor: Cell(0, 0),
          direction: null,
          cells: [Cell(0, 0)],
        ),
      );

      expect(outcome.matchedWord, isNull);
      expect(
        container.read(gameControllerProvider(JourneySession(1))).value!.events,
        isEmpty,
      );
    });

    test('re-tracing an already-found word does not double count it', () async {
      final state = await container.read(
        gameControllerProvider(JourneySession(1)).future,
      );
      final notifier = container.read(
        gameControllerProvider(JourneySession(1)).notifier,
      );
      final placement = state.grid.placementDetails.first;

      notifier.processSelection(selectionFor(state, 0));
      final outcome = notifier.processSelection(selectionFor(state, 0));

      expect(
        outcome.matchedWord,
        isNull,
        reason: 'the word is no longer in remainingWords once found',
      );
      final next = container
          .read(gameControllerProvider(JourneySession(1)))
          .value!;
      expect(next.foundWords, [placement.word]);
    });
  });

  group('useHint', () {
    test(
      'points at the first remaining word and logs a HintUsed event',
      () async {
        final state = await container.read(
          gameControllerProvider(JourneySession(1)).future,
        );
        final notifier = container.read(
          gameControllerProvider(JourneySession(1)).notifier,
        );
        final firstRemainingWord = state.remainingWords.first;
        final expectedCell = state.grid.placements[firstRemainingWord]!.first;

        notifier.useHint();

        final next = container
            .read(gameControllerProvider(JourneySession(1)))
            .value!;
        expect(next.hintedCell, expectedCell);
        expect(next.events, [const HintUsed()]);
        expect(next.hintsUsed, 1);
        expect(next.stars, 2, reason: 'one hint costs a star (Ch08 rule)');
      },
    );

    test('finding the hinted word clears the hint', () async {
      final state = await container.read(
        gameControllerProvider(JourneySession(1)).future,
      );
      final notifier = container.read(
        gameControllerProvider(JourneySession(1)).notifier,
      );

      notifier.useHint();
      expect(
        container
            .read(gameControllerProvider(JourneySession(1)))
            .value!
            .hintedCell,
        isNotNull,
      );

      notifier.processSelection(selectionFor(state, 0));

      expect(
        container
            .read(gameControllerProvider(JourneySession(1)))
            .value!
            .hintedCell,
        isNull,
      );
    });

    test('does nothing while paused', () async {
      await container.read(gameControllerProvider(JourneySession(1)).future);
      final notifier = container.read(
        gameControllerProvider(JourneySession(1)).notifier,
      );

      notifier.pause();
      notifier.useHint();

      expect(
        container.read(gameControllerProvider(JourneySession(1))).value!.events,
        isEmpty,
      );
    });
  });

  group('pause / resume', () {
    test('pause then resume round-trips the phase', () async {
      await container.read(gameControllerProvider(JourneySession(1)).future);
      final notifier = container.read(
        gameControllerProvider(JourneySession(1)).notifier,
      );

      notifier.pause();
      expect(
        container.read(gameControllerProvider(JourneySession(1))).value!.phase,
        GamePhase.paused,
      );

      notifier.resume();
      expect(
        container.read(gameControllerProvider(JourneySession(1))).value!.phase,
        GamePhase.playing,
      );
    });

    test('resume while not paused is a no-op', () async {
      await container.read(gameControllerProvider(JourneySession(1)).future);
      final notifier = container.read(
        gameControllerProvider(JourneySession(1)).notifier,
      );

      notifier.resume();

      expect(
        container.read(gameControllerProvider(JourneySession(1))).value!.phase,
        GamePhase.playing,
      );
    });
  });

  test('restart reloads the same level from scratch', () async {
    final state = await container.read(
      gameControllerProvider(JourneySession(1)).future,
    );
    final notifier = container.read(
      gameControllerProvider(JourneySession(1)).notifier,
    );

    notifier.processSelection(selectionFor(state, 0));
    notifier.pause();
    expect(
      container
          .read(gameControllerProvider(JourneySession(1)))
          .value!
          .foundWords,
      isNotEmpty,
    );

    await notifier.restart();

    final next = container
        .read(gameControllerProvider(JourneySession(1)))
        .value!;
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
      final state = await container.read(
        gameControllerProvider(JourneySession(level)).future,
      );
      final notifier = container.read(
        gameControllerProvider(JourneySession(level)).notifier,
      );

      for (var i = 0; i < state.grid.placementDetails.length; i++) {
        notifier.processSelection(selectionFor(state, i));
      }
      return container
          .read(gameControllerProvider(JourneySession(level)))
          .value!;
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

        await container
            .read(gameControllerProvider(JourneySession(1)).notifier)
            .jumpToLevel(2);
        final direct = container
            .read(gameControllerProvider(JourneySession(1)))
            .value!;

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
        expect(summary.hintsUsed, 0);
        expect(summary.maxCombo, greaterThan(0));
        expect(
          summary.session,
          const JourneySession(1),
          reason:
              'ProgressionController keys its award (coins/chest/streak) off '
              'this — see progression_controller_test.dart',
        );
      },
    );

    test('dismissing the card keeps the already-advanced level and clears the summary', () async {
      await completeLevel(container, 1);
      final notifier = container.read(
        gameControllerProvider(JourneySession(1)).notifier,
      );

      notifier.dismissLevelComplete();

      final next = container
          .read(gameControllerProvider(JourneySession(1)))
          .value!;
      expect(next.phase, GamePhase.playing);
      expect(next.level, 2);
      expect(next.completedSummary, isNull);
    });
  });

  group('dev-only controls', () {
    test('jumpToLevel loads an arbitrary level fresh', () async {
      await container.read(gameControllerProvider(JourneySession(1)).future);
      final notifier = container.read(
        gameControllerProvider(JourneySession(1)).notifier,
      );

      await notifier.jumpToLevel(7);

      final next = container
          .read(gameControllerProvider(JourneySession(1)))
          .value!;
      expect(next.level, 7);
      expect(next.phase, GamePhase.playing);
      expect(next.foundWords, isEmpty);
    });

    test(
      'debugForcePhase(levelComplete) still runs the real Zeigarnik swap',
      () async {
        final state = await container.read(
          gameControllerProvider(JourneySession(1)).future,
        );
        final notifier = container.read(
          gameControllerProvider(JourneySession(1)).notifier,
        );

        notifier.debugForcePhase(GamePhase.levelComplete);

        final next = container
            .read(gameControllerProvider(JourneySession(1)))
            .value!;
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
      final state = await container.read(
        gameControllerProvider(JourneySession(1)).future,
      );
      final notifier = container.read(
        gameControllerProvider(JourneySession(1)).notifier,
      );

      notifier.debugForcePhase(GamePhase.paused);

      final next = container
          .read(gameControllerProvider(JourneySession(1)))
          .value!;
      expect(next.phase, GamePhase.paused);
      expect(next.level, state.level);
      expect(next.grid.cells, state.grid.cells);
    });
  });

  test('GameState.score always agrees with Scoring.computeScore', () async {
    final state = await container.read(
      gameControllerProvider(JourneySession(1)).future,
    );
    final notifier = container.read(
      gameControllerProvider(JourneySession(1)).notifier,
    );

    notifier.processSelection(selectionFor(state, 0));
    notifier.processSelection(
      SelectionState(
        anchor: const Cell(0, 0),
        direction: GridVector.east,
        cells: const [Cell(0, 0), Cell(0, 1)],
      ),
    );
    notifier.useHint();

    final next = container
        .read(gameControllerProvider(JourneySession(1)))
        .value!;
    expect(next.score, Scoring.computeScore(next.events));
  });

  group('DailySession', () {
    final today = DayKey.parse('2026-08-26');

    test('loads a fixed-shape puzzle, not a journey level', () async {
      final state = await container.read(
        gameControllerProvider(DailySession(today)).future,
      );

      expect(state.isDaily, isTrue);
      expect(state.level, 0, reason: 'DailyPuzzle.levelId, never a real level');
      expect(state.grid.size, 10);
      expect(state.allWords, hasLength(8));
      expect(state.phase, GamePhase.playing);
    });

    test('the same day+language always builds the same puzzle', () async {
      final first = await container.read(
        gameControllerProvider(DailySession(today)).future,
      );

      final other = ProviderContainer();
      addTearDown(other.dispose);
      final second = await other.read(
        gameControllerProvider(DailySession(today)).future,
      );

      expect(second.grid.cells, first.grid.cells);
      expect(second.allWords, first.allWords);
    });

    test('a different day is a different puzzle', () async {
      final first = await container.read(
        gameControllerProvider(DailySession(today)).future,
      );
      final other = ProviderContainer();
      addTearDown(other.dispose);
      final second = await other.read(
        gameControllerProvider(DailySession(today.next)).future,
      );

      expect(second.grid.cells, isNot(first.grid.cells));
    });

    test('finishing it does NOT swap to a new puzzle — there is no next daily today', () async {
      final state = await container.read(
        gameControllerProvider(DailySession(today)).future,
      );
      final notifier = container.read(
        gameControllerProvider(DailySession(today)).notifier,
      );

      for (var i = 0; i < state.grid.placementDetails.length; i++) {
        final placement = state.grid.placementDetails[i];
        notifier.processSelection(
          SelectionState(
            anchor: placement.cells.first,
            direction: placement.direction,
            cells: placement.cells,
          ),
        );
      }

      final after = container
          .read(gameControllerProvider(DailySession(today)))
          .value!;
      expect(after.phase, GamePhase.levelComplete);
      // The Zeigarnik swap's whole signature — a new grid already showing,
      // a fresh empty foundWords — must NOT appear for a daily: this is
      // still the board the player just solved, fully found.
      expect(after.grid.cells, state.grid.cells);
      expect(after.foundWords, hasLength(state.allWords.length));
      expect(after.completedSummary, isNotNull);
      expect(after.completedSummary!.isDaily, isTrue);
    });
  });
}
