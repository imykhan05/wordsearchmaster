import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/app/theme/app_theme.dart';
import 'package:word_search_master/app/theme/motion.dart';
import 'package:word_search_master/domain/grid/cell.dart';
import 'package:word_search_master/domain/grid/grid_directions.dart';
import 'package:word_search_master/domain/grid/grid_generator.dart';
import 'package:word_search_master/domain/grid/grid_result.dart';
import 'package:word_search_master/domain/grid/selection_resolver.dart';
import 'package:word_search_master/domain/text/language.dart';
import 'package:word_search_master/presentation/game/game_grid.dart';
import 'package:word_search_master/presentation/game/grid_geometry.dart';

/// The rotate button: a 180° VIEW flip, free and unlimited, that must never
/// change the puzzle underneath it.
///
/// The geometry group carries the weight here. A rotation that painted
/// correctly but hit-tested against the old layout would look perfect and be
/// unplayable — the last two rows would simply stop responding, which is the
/// exact bug shape this codebase already shipped once (`GestureLayer`'s
/// `late final` resolver, CLAUDE.md). So the property asserted below is not
/// "the letters moved" but "wherever a letter is drawn, that is where it can
/// be touched", checked over every cell of the board in both orientations.
void main() {
  const gridSize = 12;
  const boxSize = 480.0;

  GridGeometry geometryFor({bool rotated = false}) => GridGeometry.fit(
    size: gridSize,
    available: const Size(boxSize, boxSize),
    rotated: rotated,
  );

  group('GridGeometry — the settled 180°', () {
    test('an upright board is untouched by the feature existing', () {
      final upright = geometryFor();

      expect(upright.rotated, isFalse);
      expect(upright.paintSpin, 0);
      expect(
        upright.cellCenter(const Cell(0, 0)),
        Offset(
          upright.origin.dx + upright.cellSize / 2,
          upright.origin.dy + upright.cellSize / 2,
        ),
      );
    });

    test('every cell is drawn where its opposite number used to be', () {
      final upright = geometryFor();
      final rotated = geometryFor(rotated: true);

      for (var row = 0; row < gridSize; row++) {
        for (var col = 0; col < gridSize; col++) {
          final opposite = Cell(gridSize - 1 - row, gridSize - 1 - col);
          final actual = rotated.cellCenter(Cell(row, col));
          final expected = upright.cellCenter(opposite);

          expect(actual.dx, closeTo(expected.dx, 1e-9));
          expect(actual.dy, closeTo(expected.dy, 1e-9));
        }
      }
    });

    test('the board really moved — a corner does not stay put', () {
      // Guards the test above from passing against a rotation that does
      // nothing: on a 12x12 the two corners are the full extent apart.
      final upright = geometryFor();
      final rotated = geometryFor(rotated: true);

      expect(
        (rotated.cellCenter(const Cell(0, 0)) -
                upright.cellCenter(const Cell(0, 0)))
            .distance,
        greaterThan(upright.extent / 2),
      );
    });

    test('TOUCH FOLLOWS PAINT: every drawn cell resolves back to itself, in '
        'both orientations', () {
      for (final rotated in [false, true]) {
        final geometry = geometryFor(rotated: rotated);

        for (var row = 0; row < gridSize; row++) {
          for (var col = 0; col < gridSize; col++) {
            final cell = Cell(row, col);
            // Where the letter is painted…
            final painted = geometry.cellCenter(cell);
            // …is where a finger has to land to select it.
            final point = geometry.toGridPoint(painted);

            expect(
              point.x.floor(),
              col,
              reason:
                  'rotated=$rotated, $cell resolved to column '
                  '${point.x.floor()}',
            );
            expect(
              point.y.floor(),
              row,
              reason:
                  'rotated=$rotated, $cell resolved to row '
                  '${point.y.floor()}',
            );
          }
        }
      }
    });

    test('rotating twice is the identity — the flip is its own inverse', () {
      final upright = geometryFor();
      final rotated = geometryFor(rotated: true);

      for (var row = 0; row < gridSize; row++) {
        for (var col = 0; col < gridSize; col++) {
          final cell = Cell(row, col);
          // Feeding a rotated board's painted position back through a rotated
          // board's own touch mapping is the same round trip a second tap
          // makes; it has to land back on the upright position.
          final there = rotated.cellCenter(cell);
          final back = rotated.cellCenter(
            Cell(gridSize - 1 - row, gridSize - 1 - col),
          );
          expect(back.dx, closeTo(upright.cellCenter(cell).dx, 1e-9));
          expect(back.dy, closeTo(upright.cellCenter(cell).dy, 1e-9));
          expect(there, isNot(equals(back)));
        }
      }
    });

    test('the fractional part survives — sub-cell precision is kept', () {
      // P05 projects a continuous pointer onto the locked line; a rotation
      // that rounded to whole cells would make the drag feel notchy.
      final geometry = geometryFor(rotated: true);
      final centre = geometry.cellCenter(const Cell(3, 5));
      final nudged = geometry.toGridPoint(centre + const Offset(4, 0));

      expect(nudged.x, isNot(closeTo(nudged.x.roundToDouble(), 1e-6)));
    });
  });

  group('GridGeometry — the spin, which is decoration only', () {
    test('paintSpin moves what is DRAWN', () {
      final still = geometryFor(rotated: true);
      final spinning = still.withPaintSpin(GridGeometry.spinRadians(-0.5));

      expect(
        spinning.cellCenter(const Cell(0, 0)),
        isNot(equals(still.cellCenter(const Cell(0, 0)))),
      );
    });

    test('…and never moves what is TOUCHED', () {
      // The whole reason the spin is a separate field: during the ~340ms swing
      // the letters mean nothing as targets, so hit-testing keeps answering
      // against the settled layout rather than chasing them.
      final still = geometryFor(rotated: true);

      for (final turn in [-1.0, -0.75, -0.5, -0.25]) {
        final spinning = still.withPaintSpin(GridGeometry.spinRadians(turn));
        final probe = still.cellCenter(const Cell(2, 7));

        expect(
          spinning.toGridPoint(probe).x,
          closeTo(still.toGridPoint(probe).x, 1e-12),
        );
        expect(
          spinning.toGridPoint(probe).y,
          closeTo(still.toGridPoint(probe).y, 1e-12),
        );
      }
    });

    test('a completed half-turn lands exactly on the settled layout', () {
      // `spin` reaching 0 is what ends the animation, so the last frame drawn
      // and the first frame after it have to be the same picture.
      final settled = geometryFor(rotated: true);
      final finished = settled.withPaintSpin(GridGeometry.spinRadians(0));

      expect(
        finished.cellCenter(const Cell(4, 9)),
        settled.cellCenter(const Cell(4, 9)),
      );
    });

    test('the scale dips at the midpoint and returns at both ends', () {
      expect(GridGeometry.spinScale(-1), closeTo(1.0, 1e-9));
      expect(GridGeometry.spinScale(0), closeTo(1.0, 1e-9));
      expect(GridGeometry.spinScale(-0.5), lessThan(1.0));
      expect(
        GridGeometry.spinScale(-0.5),
        greaterThan(0.8),
        reason: 'a dip, not a collapse',
      );
    });

    test('spinRadians spans exactly a half turn', () {
      expect(GridGeometry.spinRadians(-1), closeTo(-pi, 1e-12));
      expect(GridGeometry.spinRadians(0), 0);
    });
  });

  group('GameGrid — the button, the animation and the reset', () {
    late GridResult grid;
    late GridResult otherGrid;

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
      otherGrid = GridGenerator.generate(
        seed: 777,
        size: gridSize,
        words: const ['LIGHT', 'EARTH', 'FOREST'],
        lang: Language.english,
        allowedDirections: GridDirections.forLanguage(
          Language.english,
          DirectionTier.all,
        ),
      );
    });

    Future<
      ({
        GlobalKey<GameGridState> key,
        GridRotationController rotation,
        List<SelectionState> released,
      })
    >
    pumpGrid(
      WidgetTester tester, {
      bool reduceMotion = false,
      GridResult? cells,
    }) async {
      final key = GlobalKey<GameGridState>();
      final rotation = GridRotationController();
      final released = <SelectionState>[];
      addTearDown(rotation.dispose);

      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: boxSize,
                  height: boxSize,
                  child: GameGrid(
                    key: key,
                    cells: (cells ?? grid).cells,
                    language: Language.english,
                    foundWordCells: const [],
                    rotationController: rotation,
                    onSelectionReleased: (state, _) {
                      released.add(state);
                      return true;
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      return (key: key, rotation: rotation, released: released);
    }

    Offset globalCenterOf(
      WidgetTester tester,
      GameGridState state,
      Cell cell,
    ) =>
        tester.getTopLeft(find.byType(GameGrid)) +
        state.geometry!.cellCenter(cell);

    testWidgets('a board starts upright', (tester) async {
      final harness = await pumpGrid(tester);
      expect(harness.key.currentState!.rotated.value, isFalse);
      expect(harness.key.currentState!.spin.value, 0);
    });

    testWidgets(
      'ACCEPTANCE: after rotating, a word is still selectable — at its NEW '
      'position on screen',
      (tester) async {
        final harness = await pumpGrid(tester);
        final state = harness.key.currentState!;

        const word = [Cell(0, 0), Cell(0, 1), Cell(0, 2)];
        final before = globalCenterOf(tester, state, word.first);

        harness.rotation.rotate();
        await tester.pumpAndSettle();

        expect(state.rotated.value, isTrue);

        final after = globalCenterOf(tester, state, word.first);
        expect(
          (after - before).distance,
          greaterThan(state.geometry!.cellSize),
          reason: 'the letters genuinely moved, so this is a real test',
        );

        // Drag along where those cells are drawn NOW.
        final gesture = await tester.startGesture(after);
        await tester.pump();
        for (final cell in word.skip(1)) {
          await gesture.moveTo(globalCenterOf(tester, state, cell));
          await tester.pump();
        }
        await gesture.up();
        await tester.pump();

        expect(harness.released, hasLength(1));
        expect(
          harness.released.single.cells,
          word,
          reason:
              'touch must resolve to the LOGICAL cells the player can see, '
              'not to whatever used to be painted at those pixels',
        );
      },
    );

    testWidgets('the spin runs, then settles exactly on zero', (tester) async {
      final harness = await pumpGrid(tester);
      final state = harness.key.currentState!;

      harness.rotation.rotate();
      await tester.pump();
      expect(
        state.spin.value,
        -1,
        reason: 'a full half-turn is owed the moment the flip lands',
      );

      await tester.pump(Motion.slow ~/ 2);
      expect(state.spin.value, greaterThan(-1));
      expect(state.spin.value, lessThan(0));

      await tester.pumpAndSettle();
      expect(state.spin.value, 0);
      expect(state.rotated.value, isTrue);
    });

    testWidgets('a second tap turns it back', (tester) async {
      final harness = await pumpGrid(tester);
      final state = harness.key.currentState!;

      harness.rotation.rotate();
      await tester.pumpAndSettle();
      harness.rotation.rotate();
      await tester.pumpAndSettle();

      expect(state.rotated.value, isFalse);
      expect(state.spin.value, 0);
    });

    testWidgets('a tap MID-SPIN is accepted, not a crash', (tester) async {
      // `Ticker.start()` throws on an already-running ticker, and tapping
      // twice quickly to compare the two views is the obvious thing to do.
      final harness = await pumpGrid(tester);
      final state = harness.key.currentState!;

      harness.rotation.rotate();
      await tester.pump();
      await tester.pump(Motion.slow ~/ 3);
      harness.rotation.rotate();
      await tester.pumpAndSettle();

      expect(state.rotated.value, isFalse);
      expect(state.spin.value, 0);
    });

    testWidgets('reduce-motion keeps the ROTATION and drops the swing', (
      tester,
    ) async {
      // The board really has turned over — a player who asked for that still
      // needs it. Only the movement goes.
      final harness = await pumpGrid(tester, reduceMotion: true);
      final state = harness.key.currentState!;

      harness.rotation.rotate();
      await tester.pump();

      expect(state.rotated.value, isTrue);
      expect(state.spin.value, 0, reason: 'nothing left in flight to animate');
    });

    testWidgets('a live drag is dropped rather than left pointing at moved '
        'cells', (tester) async {
      final harness = await pumpGrid(tester);
      final state = harness.key.currentState!;

      final gesture = await tester.startGesture(
        globalCenterOf(tester, state, const Cell(5, 5)),
      );
      await gesture.moveTo(globalCenterOf(tester, state, const Cell(5, 6)));
      await tester.pump();
      expect(state.selection.value.cells, isNotEmpty);

      harness.rotation.rotate();
      await tester.pump();

      expect(state.selection.value.cells, isEmpty);
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('A NEW LEVEL ARRIVES UPRIGHT', (tester) async {
      // P07's Zeigarnik swap advances the level in place, without remounting
      // this widget — so nothing else would ever clear the flip, and the
      // player would land on the next level already upside down.
      final harness = await pumpGrid(tester);
      final state = harness.key.currentState!;

      harness.rotation.rotate();
      await tester.pumpAndSettle();
      expect(state.rotated.value, isTrue);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(),
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: boxSize,
                  height: boxSize,
                  child: GameGrid(
                    key: harness.key,
                    cells: otherGrid.cells,
                    language: Language.english,
                    foundWordCells: const [],
                    rotationController: harness.rotation,
                    onSelectionReleased: (state, _) => true,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(state.rotated.value, isFalse);
      expect(state.spin.value, 0);
    });
  });
}
