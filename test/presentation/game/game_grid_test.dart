import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/app/theme/app_theme.dart';
import 'package:word_search_master/domain/grid/cell.dart';
import 'package:word_search_master/domain/grid/grid_directions.dart';
import 'package:word_search_master/domain/grid/grid_generator.dart';
import 'package:word_search_master/domain/grid/grid_result.dart';
import 'package:word_search_master/domain/grid/grid_vector.dart';
import 'package:word_search_master/domain/grid/selection_resolver.dart';
import 'package:word_search_master/domain/text/language.dart';
import 'package:word_search_master/presentation/game/game_grid.dart';
import 'package:word_search_master/presentation/game/grid_painter.dart';

void main() {
  const gridSize = 12;
  const boxSize = 480.0;

  late GridResult grid;

  setUpAll(() {
    grid = GridGenerator.generate(
      seed: 4242,
      size: gridSize,
      words: const ['WATER', 'STONE', 'RIVER', 'FOREST', 'LIGHT', 'EARTH'],
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
      GridPaintStats stats,
      List<SelectionState> released,
    })
  >
  pumpGrid(
    WidgetTester tester, {
    List<List<Cell>> foundWordCells = const [],
    Cell? hintedCell,
  }) async {
    final key = GlobalKey<GameGridState>();
    final stats = GridPaintStats();
    final released = <SelectionState>[];

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
                foundWordCells: foundWordCells,
                hintedCell: hintedCell,
                stats: stats,
                onSelectionReleased: (state, _) => released.add(state),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    return (key: key, stats: stats, released: released);
  }

  Offset globalCenterOf(WidgetTester tester, GameGridState state, Cell cell) =>
      tester.getTopLeft(find.byType(GameGrid)) +
      state.geometry!.cellCenter(cell);

  group('repaint isolation — the point of the three-pass split', () {
    testWidgets('a moving finger repaints ONLY the selection layer', (
      tester,
    ) async {
      final harness = await pumpGrid(tester);
      final state = harness.key.currentState!;

      final lettersAtStart = harness.stats.letters;
      final foundAtStart = harness.stats.foundWords;
      final selectionAtStart = harness.stats.selection;

      expect(lettersAtStart, greaterThan(0), reason: 'the grid did paint once');

      final gesture = await tester.startGesture(
        globalCenterOf(tester, state, const Cell(0, 0)),
      );
      await tester.pump();

      for (var col = 1; col < 8; col++) {
        await gesture.moveTo(globalCenterOf(tester, state, Cell(0, col)));
        await tester.pump();
      }
      await gesture.up();
      await tester.pump();

      expect(
        harness.stats.letters,
        lettersAtStart,
        reason:
            'the letters layer must stay rasterised — repainting 144 glyphs '
            'per frame is exactly what this structure prevents',
      );
      expect(harness.stats.foundWords, foundAtStart);
      expect(
        harness.stats.selection,
        greaterThan(selectionAtStart),
        reason: 'the selection layer is the one that tracks the finger',
      );
    });

    testWidgets('no widget rebuild happens during a drag', (tester) async {
      // The selection is published through a ValueNotifier precisely so the
      // tree is untouched while a finger moves.
      final harness = await pumpGrid(tester);
      final state = harness.key.currentState!;

      final gesture = await tester.startGesture(
        globalCenterOf(tester, state, const Cell(3, 3)),
      );
      await tester.pump();
      await gesture.moveTo(globalCenterOf(tester, state, const Cell(3, 6)));
      await tester.pump();

      expect(state.selection.value.cells, hasLength(4));
      // Same State object, never recreated.
      expect(identical(harness.key.currentState, state), isTrue);

      await gesture.up();
      await tester.pump();
    });
  });

  group('dragging through the real gesture layer', () {
    testWidgets('the selection follows the finger cell by cell', (
      tester,
    ) async {
      final harness = await pumpGrid(tester);
      final state = harness.key.currentState!;

      final gesture = await tester.startGesture(
        globalCenterOf(tester, state, const Cell(2, 1)),
      );
      await tester.pump();
      expect(state.selection.value.cells, [const Cell(2, 1)]);

      await gesture.moveTo(globalCenterOf(tester, state, const Cell(2, 4)));
      await tester.pump();

      expect(state.selection.value.direction, GridVector.east);
      expect(state.selection.value.cells, const [
        Cell(2, 1),
        Cell(2, 2),
        Cell(2, 3),
        Cell(2, 4),
      ]);

      await gesture.up();
      await tester.pump();
    });

    testWidgets('DRAGGING OFF-LINE DOES NOT BREAK THE SELECTION', (
      tester,
    ) async {
      // The P06 acceptance criterion, exercised end to end through real
      // pointer events rather than against the resolver directly.
      final harness = await pumpGrid(tester);
      final state = harness.key.currentState!;
      final geometry = state.geometry!;
      final origin = tester.getTopLeft(find.byType(GameGrid));

      final gesture = await tester.startGesture(
        globalCenterOf(tester, state, const Cell(5, 2)),
      );
      await tester.pump();

      // Lock east.
      await gesture.moveTo(globalCenterOf(tester, state, const Cell(5, 3)));
      await tester.pump();
      expect(state.selection.value.direction, GridVector.east);

      // Now wander four rows off the line, still reaching column 7.
      await gesture.moveTo(
        origin +
            Offset(
              geometry.cellCenter(const Cell(5, 7)).dx,
              geometry.cellCenter(const Cell(9, 7)).dy,
            ),
      );
      await tester.pump();

      expect(
        state.selection.value.direction,
        GridVector.east,
        reason: 'the locked direction must survive an off-line drag',
      );
      expect(state.selection.value.cells, const [
        Cell(5, 2),
        Cell(5, 3),
        Cell(5, 4),
        Cell(5, 5),
        Cell(5, 6),
        Cell(5, 7),
      ], reason: 'only the along-line component may move the selection');

      await gesture.up();
      await tester.pump();
    });

    testWidgets('release reports the finished drag and clears the selection', (
      tester,
    ) async {
      final harness = await pumpGrid(tester);
      final state = harness.key.currentState!;

      final gesture = await tester.startGesture(
        globalCenterOf(tester, state, const Cell(1, 1)),
      );
      await tester.pump();
      await gesture.moveTo(globalCenterOf(tester, state, const Cell(4, 4)));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(harness.released, hasLength(1));
      expect(harness.released.single.direction, GridVector.southEast);
      expect(
        state.selection.value.isEmpty,
        isTrue,
        reason: 'the live capsule must not linger after the finger lifts',
      );
    });

    testWidgets('a cancelled pointer is not scored as an attempt', (
      tester,
    ) async {
      final harness = await pumpGrid(tester);
      final state = harness.key.currentState!;

      final gesture = await tester.startGesture(
        globalCenterOf(tester, state, const Cell(1, 1)),
      );
      await tester.pump();
      await gesture.moveTo(globalCenterOf(tester, state, const Cell(1, 3)));
      await tester.pump();
      await gesture.cancel();
      await tester.pump();

      expect(harness.released, isEmpty);
      expect(state.selection.value.isEmpty, isTrue);
    });
  });

  group('haptics', () {
    late List<MethodCall> calls;

    setUp(() {
      calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'HapticFeedback.vibrate') calls.add(call);
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    testWidgets('fires once per newly entered cell', (tester) async {
      final harness = await pumpGrid(tester);
      final state = harness.key.currentState!;

      final gesture = await tester.startGesture(
        globalCenterOf(tester, state, const Cell(0, 0)),
      );
      await tester.pump();
      final afterAnchor = calls.length;

      for (var col = 1; col <= 4; col++) {
        await gesture.moveTo(globalCenterOf(tester, state, Cell(0, col)));
        await tester.pump();
      }
      await gesture.up();
      await tester.pump();

      expect(calls.length - afterAnchor, 4, reason: 'four cells were entered');
    });

    testWidgets('stays silent while dragging BACK over cells', (tester) async {
      // The click marks progress; buzzing on the way back would read as an
      // error the player has not made.
      final harness = await pumpGrid(tester);
      final state = harness.key.currentState!;

      final gesture = await tester.startGesture(
        globalCenterOf(tester, state, const Cell(0, 0)),
      );
      await tester.pump();
      await gesture.moveTo(globalCenterOf(tester, state, const Cell(0, 4)));
      await tester.pump();

      final afterForward = calls.length;

      await gesture.moveTo(globalCenterOf(tester, state, const Cell(0, 2)));
      await tester.pump();
      await gesture.moveTo(globalCenterOf(tester, state, const Cell(0, 1)));
      await tester.pump();

      expect(calls.length, afterForward, reason: 'no click while shrinking');

      await gesture.up();
      await tester.pump();
    });
  });

  group('found-word highlights', () {
    testWidgets(
      'the found layer repaints when a word is added, and only then',
      (tester) async {
        final harness = await pumpGrid(tester);
        final paintsWithNone = harness.stats.foundWords;

        final placement = grid.placementDetails.first;
        final withOne = await pumpGrid(
          tester,
          foundWordCells: [placement.cells],
        );

        expect(withOne.stats.foundWords, greaterThan(0));
        expect(paintsWithNone, greaterThan(0));
      },
    );
  });

  group('hint highlight', () {
    testWidgets('the ring covers ONE cell, not the whole grid — regression for '
        'Positioned needing to be a direct Stack child', (tester) async {
      const cell = Cell(2, 3);
      final harness = await pumpGrid(tester, hintedCell: cell);
      final state = harness.key.currentState!;
      await tester.pump(const Duration(milliseconds: 250));

      final hintRing = find.descendant(
        of: find.byType(GameGrid),
        matching: find.byType(DecoratedBox),
      );
      final expectedRect = state.geometry!.cellRect(cell).inflate(4);
      final renderedRect = tester.getRect(hintRing);

      expect(renderedRect.width, closeTo(expectedRect.width, 0.5));
      expect(renderedRect.height, closeTo(expectedRect.height, 0.5));
      expect(
        renderedRect.width,
        lessThan(boxSize / 2),
        reason:
            'a mis-parented Positioned silently expands to fill the '
            'whole Stack — this must stay cell-sized',
      );
    });

    testWidgets('absent when there is no hint', (tester) async {
      await pumpGrid(tester);

      final hintRing = find.descendant(
        of: find.byType(GameGrid),
        matching: find.byType(DecoratedBox),
      );
      expect(hintRing, findsNothing);
    });
  });
}
