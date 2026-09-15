import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/app/theme/app_theme.dart';
import 'package:word_search_master/domain/grid/cell.dart';
import 'package:word_search_master/domain/grid/grid_directions.dart';
import 'package:word_search_master/domain/grid/grid_generator.dart';
import 'package:word_search_master/domain/grid/grid_result.dart';
import 'package:word_search_master/domain/text/language.dart';
import 'package:word_search_master/presentation/game/game_grid.dart';
import 'package:word_search_master/services/audio/combo_pitch_ladder.dart';

import '../../support/recording_services.dart';

/// PLAYER-REQUESTED: a bubble as each letter joins the drag.
///
/// Driven through a REAL pointer — `tester.startGesture` and `moveTo` across
/// the cells — rather than by calling the grid's release callback the way
/// `game_screen_test.dart` does for its own purposes. The whole of this
/// behaviour lives in `GestureLayer._publish`, which only runs when a finger
/// actually crosses into a new cell, so a shortcut past it would assert
/// nothing about the feature.
void main() {
  const gridSize = 8;
  const boxSize = 400.0;
  late GridResult grid;

  setUpAll(() {
    grid = GridGenerator.generate(
      seed: 4242,
      size: gridSize,
      words: const ['WATER', 'STONE', 'RIVER'],
      lang: Language.english,
      allowedDirections: GridDirections.forLanguage(
        Language.english,
        DirectionTier.all,
      ),
    );
  });

  Future<(GlobalKey<GameGridState>, RecordingAudioService)> pumpGrid(
    WidgetTester tester,
  ) async {
    final key = GlobalKey<GameGridState>();
    final audio = RecordingAudioService();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: boxSize,
              height: boxSize,
              child: GameGrid(
                key: key,
                cells: grid.cells,
                language: Language.english,
                foundWordCells: const [],
                audioService: audio,
                onSelectionReleased: (state, _) => true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return (key, audio);
  }

  Offset centerOf(WidgetTester tester, GameGridState state, Cell cell) =>
      tester.getTopLeft(find.byType(GameGrid)) +
      state.geometry!.cellCenter(cell);

  testWidgets('one bubble per letter, rising as the drag grows', (
    tester,
  ) async {
    final (key, audio) = await pumpGrid(tester);
    final state = key.currentState!;

    const word = [Cell(2, 1), Cell(2, 2), Cell(2, 3), Cell(2, 4)];
    final gesture = await tester.startGesture(
      centerOf(tester, state, word.first),
    );
    await tester.pump();
    for (final cell in word.skip(1)) {
      await gesture.moveTo(centerOf(tester, state, cell));
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();

    expect(audio.selectLengths, [
      1,
      2,
      3,
      4,
    ], reason: 'one per cell the finger newly reached, counting up');
  });

  testWidgets('DRAGGING BACK IS SILENT — the bubble marks progress, and '
      'replaying it on the way out would read as an error', (tester) async {
    // The same rule the selection HAPTIC has always followed. The two are
    // fired from one place precisely so they cannot disagree about it.
    final (key, audio) = await pumpGrid(tester);
    final state = key.currentState!;

    final gesture = await tester.startGesture(
      centerOf(tester, state, const Cell(2, 1)),
    );
    await tester.pump();
    await gesture.moveTo(centerOf(tester, state, const Cell(2, 2)));
    await tester.pump();
    await gesture.moveTo(centerOf(tester, state, const Cell(2, 3)));
    await tester.pump();
    expect(audio.selectLengths, [1, 2, 3]);

    // Back the way it came.
    await gesture.moveTo(centerOf(tester, state, const Cell(2, 2)));
    await tester.pump();
    await gesture.moveTo(centerOf(tester, state, const Cell(2, 1)));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(audio.selectLengths, [
      1,
      2,
      3,
    ], reason: 'shrinking the selection must add no further bubbles');
  });

  group('SelectionPitchLadder', () {
    test('climbs with the drag and never falls back', () {
      var previous = 0.0;
      for (var length = 1; length <= 12; length++) {
        final rate = SelectionPitchLadder.rateForLength(length);
        expect(rate, greaterThanOrEqualTo(previous));
        previous = rate;
      }
    });

    test('the first letter plays the clip at its own pitch', () {
      expect(SelectionPitchLadder.rateForLength(1), 1.0);
    });

    test('a word longer than the table HOLDS the top note rather than '
        'wrapping back down mid-trace', () {
      final top = SelectionPitchLadder.rateForLength(11);
      expect(SelectionPitchLadder.rateForLength(12), top);
      expect(SelectionPitchLadder.rateForLength(40), top);
    });

    test('clamps a nonsensical length rather than throwing', () {
      expect(SelectionPitchLadder.rateForLength(0), 1.0);
      expect(SelectionPitchLadder.rateForLength(-3), 1.0);
    });

    test('spans two octaves, so a long word still reads as a phrase', () {
      expect(SelectionPitchLadder.rateForLength(11), closeTo(4.0, 0.001));
    });
  });
}
