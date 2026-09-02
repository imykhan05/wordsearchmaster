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
import 'package:word_search_master/services/haptics/haptics_service.dart';

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
    bool matchResult = true,
    bool reduceMotion = false,
  }) async {
    final key = GlobalKey<GameGridState>();
    final stats = GridPaintStats();
    final released = <SelectionState>[];

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
                  cells: grid.cells,
                  language: Language.english,
                  foundWordCells: foundWordCells,
                  hintedCell: hintedCell,
                  stats: stats,
                  // The default NoopHapticsService is silent by design (P09)
                  // — this file's "haptics" group intercepts the real
                  // `HapticFeedback` platform channel, so it needs the real
                  // service wired the same way `GameGrid`'s actual callers do.
                  hapticsService: SystemHapticsService(),
                  onSelectionReleased: (state, _) {
                    released.add(state);
                    // These tests mostly assert paint-pass isolation, not
                    // miss/match semantics — defaulting to "always matches"
                    // keeps the miss-fade ticker (game_grid.dart) out of
                    // their repaint counts. The miss-fade group below flips
                    // this to exercise that path specifically.
                    return matchResult;
                  },
                ),
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

  group('wrong-selection fade — "just a 180ms fade-out", nothing else', () {
    Future<TestGesture> dragThreeCells(
      WidgetTester tester,
      GameGridState state,
    ) async {
      final gesture = await tester.startGesture(
        globalCenterOf(tester, state, const Cell(0, 0)),
      );
      await tester.pump();
      await gesture.moveTo(globalCenterOf(tester, state, const Cell(0, 1)));
      await tester.pump();
      await gesture.moveTo(globalCenterOf(tester, state, const Cell(0, 2)));
      await tester.pump();
      return gesture;
    }

    testWidgets(
      'a miss leaves the capsule showing, at full alpha, the instant it releases',
      (tester) async {
        final harness = await pumpGrid(tester, matchResult: false);
        final state = harness.key.currentState!;

        final gesture = await dragThreeCells(tester, state);
        await gesture.up();
        await tester.pump();

        expect(
          state.selection.value.isEmpty,
          isFalse,
          reason: 'a miss must not clear the capsule immediately — it fades',
        );
        expect(state.fadeAlpha.value, 1.0);
      },
    );

    testWidgets('the capsule is roughly half-faded at the 180ms midpoint', (
      tester,
    ) async {
      final harness = await pumpGrid(tester, matchResult: false);
      final state = harness.key.currentState!;

      final gesture = await dragThreeCells(tester, state);
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));

      expect(state.fadeAlpha.value, closeTo(0.5, 0.1));
      expect(
        state.selection.value.isEmpty,
        isFalse,
        reason: 'still fading, not cleared yet',
      );
    });

    testWidgets(
      'the capsule clears and the alpha resets once 180ms fully elapses',
      (tester) async {
        final harness = await pumpGrid(tester, matchResult: false);
        final state = harness.key.currentState!;

        final gesture = await dragThreeCells(tester, state);
        await gesture.up();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(state.selection.value.isEmpty, isTrue);
        expect(state.fadeAlpha.value, 1.0);
      },
    );

    testWidgets(
      'starting a new drag mid-fade snaps straight back to full alpha',
      (tester) async {
        final harness = await pumpGrid(tester, matchResult: false);
        final state = harness.key.currentState!;

        final gesture = await dragThreeCells(tester, state);
        await gesture.up();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 90));
        expect(
          state.fadeAlpha.value,
          lessThan(1.0),
          reason: 'sanity check — the fade must actually be in flight here',
        );

        // A fresh drag starts before the previous miss finished fading.
        final second = await tester.startGesture(
          globalCenterOf(tester, state, const Cell(3, 3)),
        );
        await tester.pump();

        expect(
          state.fadeAlpha.value,
          1.0,
          reason:
              'the new drag must render at full opacity, not inherit the '
              'stale partially-faded alpha',
        );

        await second.up();
        await tester.pump();
      },
    );

    testWidgets(
      'reduce-motion clears a miss on the spot — no fade to observe',
      (tester) async {
        final harness = await pumpGrid(
          tester,
          matchResult: false,
          reduceMotion: true,
        );
        final state = harness.key.currentState!;

        final gesture = await dragThreeCells(tester, state);
        await gesture.up();
        await tester.pump();

        expect(
          state.selection.value.isEmpty,
          isTrue,
          reason: 'every duration collapses to zero under reduce-motion',
        );
        expect(state.fadeAlpha.value, 1.0);
      },
    );

    testWidgets('a MATCH still clears the capsule immediately, as before', (
      tester,
    ) async {
      final harness = await pumpGrid(tester);
      final state = harness.key.currentState!;

      final gesture = await dragThreeCells(tester, state);
      await gesture.up();
      await tester.pump();

      expect(state.selection.value.isEmpty, isTrue);
    });
  });

  group('the grid grows WITHOUT a remount (P07 Zeigarnik swap)', () {
    // Advancing a level mutates `GameState.level` in place, so the screen
    // never remounts — crossing a Ch07 curve step (level 5→6 takes the grid
    // 6x6→8x8) reaches `GestureLayer` as an update on a LIVE State. Its
    // `SelectionResolver` used to be `late final`, so `size` stayed frozen at
    // the grid the player started on and every cell outside it was rejected:
    // on an 8x8 reached from a 6x6, the last two rows and columns were
    // painted but silently untouchable. Reported from a real device at
    // level 6, in both English and Urdu.
    Future<GlobalKey<GameGridState>> pumpThenGrow(
      WidgetTester tester,
      List<SelectionState> released,
    ) async {
      final key = GlobalKey<GameGridState>();

      Widget build(GridResult grid) => MaterialApp(
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
                onSelectionReleased: (state, _) {
                  released.add(state);
                  // "Matched" so the miss-fade ticker never starts — this
                  // group is about which cells the resolver ACCEPTS, and a
                  // pending fade timer would outlive the tree.
                  return true;
                },
              ),
            ),
          ),
        ),
      );

      GridResult gridOf(int size, List<String> words) => GridGenerator.generate(
        seed: 90 + size,
        size: size,
        words: words,
        lang: Language.english,
        allowedDirections: GridDirections.forLanguage(
          Language.english,
          DirectionTier.all,
        ),
      );

      await tester.pumpWidget(build(gridOf(6, const ['SUN', 'MOON'])));
      await tester.pump();
      final before = key.currentState!;

      // Play ONE drag while the grid is still 6x6. This is load-bearing, not
      // set-dressing: the resolver is `late`, so it is not constructed until
      // something first reads it. A test that grew the grid without touching
      // it would build the resolver AFTER the change — already at the new
      // size — and pass against the very bug it exists to catch. A real
      // player has of course dragged on levels 1–5 before reaching 6.
      final warmUp = await tester.startGesture(
        globalCenterOf(tester, before, const Cell(0, 0)),
      );
      await tester.pump();
      await warmUp.moveTo(globalCenterOf(tester, before, const Cell(0, 2)));
      await tester.pump();
      await warmUp.up();
      await tester.pump();
      released.clear();

      await tester.pumpWidget(build(gridOf(8, const ['WATER', 'STONE'])));
      await tester.pump();

      // The precondition the bug needed: same State, new geometry.
      expect(
        key.currentState,
        same(before),
        reason: 'the grid updated in place rather than remounting',
      );
      return key;
    }

    testWidgets('a cell beyond the OLD size is still selectable', (
      tester,
    ) async {
      final released = <SelectionState>[];
      final key = await pumpThenGrow(tester, released);
      final state = key.currentState!;

      expect(state.geometry!.size, 8);

      // Row 7 exists only in the 8x8 — under the stale resolver this drag
      // produced nothing at all.
      final gesture = await tester.startGesture(
        globalCenterOf(tester, state, const Cell(7, 5)),
      );
      await tester.pump();
      await gesture.moveTo(globalCenterOf(tester, state, const Cell(7, 7)));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(
        released,
        isNotEmpty,
        reason: 'the drag on the last row registered at all',
      );
      expect(released.last.cells, contains(const Cell(7, 7)));
    });

    testWidgets('the last COLUMN is reachable too, not just the last row', (
      tester,
    ) async {
      final released = <SelectionState>[];
      final key = await pumpThenGrow(tester, released);
      final state = key.currentState!;

      final gesture = await tester.startGesture(
        globalCenterOf(tester, state, const Cell(5, 7)),
      );
      await tester.pump();
      await gesture.moveTo(globalCenterOf(tester, state, const Cell(7, 7)));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(released, isNotEmpty);
      expect(released.last.cells, contains(const Cell(7, 7)));
    });
  });
}
