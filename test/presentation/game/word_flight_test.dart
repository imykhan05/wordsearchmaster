import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/app/theme/app_theme.dart';
import 'package:word_search_master/domain/grid/cell.dart';
import 'package:word_search_master/domain/text/language.dart';
import 'package:word_search_master/presentation/game/grid_geometry.dart';
import 'package:word_search_master/presentation/game/word_flight.dart';

/// The found word's letters flying from the grid to their word chip.
///
/// The two ends live in different subtrees, so the thing worth testing is the
/// MEASUREMENT: that a flight only happens when both ends resolve, and that it
/// runs for the length it claims to. Frame counting is how that is asserted —
/// a running `Ticker` keeps scheduling frames, so "how long does this animate
/// for" is answerable without reaching into any private state.
void main() {
  const word = 'WATER';
  const graphemes = ['W', 'A', 'T', 'E', 'R'];
  const cells = [Cell(0, 0), Cell(0, 1), Cell(0, 2), Cell(0, 3), Cell(0, 4)];

  final geometry = GridGeometry.fit(
    size: 6,
    available: const Size(300, 300),
    gap: 2,
  );

  /// Builds the two ends the layer measures between — a grid box carrying
  /// `anchors.gridKey`, and a chip box that registers itself — with the layer
  /// stretched over both, the same shape `_GameContent` assembles.
  Future<WordFlightController> pumpFlightHarness(
    WidgetTester tester, {
    bool registerChip = true,
    bool reduceMotion = false,
  }) async {
    final controller = WordFlightController();
    addTearDown(controller.dispose);
    final anchors = WordFlightAnchors();

    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: Stack(
              children: [
                Column(
                  children: [
                    SizedBox(key: anchors.gridKey, width: 300, height: 300),
                    Builder(
                      builder: (context) {
                        if (registerChip) anchors.registerChip(word, context);
                        return const SizedBox(width: 80, height: 24);
                      },
                    ),
                  ],
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: WordFlightLayer(
                      controller: controller,
                      anchors: anchors,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // The first frame of a `MaterialApp` leaves one more scheduled behind it,
    // and every assertion below reads `hasScheduledFrame` as "is the flight
    // layer animating" — so the tree has to be genuinely at rest first.
    await tester.pumpAndSettle();
    return controller;
  }

  void fly(WordFlightController controller) => controller.fly(
    word: word,
    graphemes: graphemes,
    cells: cells,
    geometry: geometry,
    language: Language.english,
    // A test file is outside `check_no_raw_colors`'s remit (it scans `lib/`),
    // and the layer only ever reads this colour back out — it never has to be
    // a real token for any assertion here.
    color: const Color(0xFF4CAF50),
  );

  /// Pumps until the layer stops scheduling frames, and reports how long that
  /// took. Capped so a stuck ticker fails as a timeout rather than hanging.
  Future<Duration> runAnimation(WidgetTester tester) async {
    const step = Duration(milliseconds: 16);
    var elapsed = Duration.zero;
    while (tester.binding.hasScheduledFrame &&
        elapsed < const Duration(seconds: 5)) {
      await tester.pump(step);
      elapsed += step;
    }
    return elapsed;
  }

  testWidgets('an idle layer schedules no frames at all', (tester) async {
    await pumpFlightHarness(tester);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a found word animates, and finishes on its own', (tester) async {
    final controller = await pumpFlightHarness(tester);

    fly(controller);
    await tester.pump();
    expect(
      tester.binding.hasScheduledFrame,
      isTrue,
      reason: 'the ticker started',
    );

    final took = await runAnimation(tester);

    // The last letter leaves after 4 staggers and then flies for its own
    // duration; everything is gone shortly after that, never left running.
    final expected =
        WordFlightLayer.letterDuration +
        WordFlightLayer.letterStagger * (graphemes.length - 1);
    expect(took, greaterThanOrEqualTo(expected));
    expect(took, lessThan(expected + const Duration(milliseconds: 100)));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('reduce-motion skips it outright rather than shortening it', (
    tester,
  ) async {
    final controller = await pumpFlightHarness(tester, reduceMotion: true);

    fly(controller);
    await tester.pump();

    expect(
      tester.binding.hasScheduledFrame,
      isFalse,
      reason: 'decorative, so it is never spawned — not spawned at zero length',
    );
  });

  testWidgets('a word with no chip registered has nowhere to land, so nothing '
      'flies', (tester) async {
    final controller = await pumpFlightHarness(tester, registerChip: false);

    fly(controller);
    await tester.pump();

    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets(
    'REGRESSION: the second word of a level animates for the same length as '
    'the first',
    (tester) async {
      // A `Ticker`'s elapsed restarts at zero on every start, so a layer that
      // kept its clock at the previous run's final value would stamp the
      // second flight into the future — it would sit frozen for exactly the
      // first flight's length before moving, and the ticker would run for
      // twice as long. Measuring both runs is what catches that.
      final controller = await pumpFlightHarness(tester);

      fly(controller);
      await tester.pump();
      final first = await runAnimation(tester);

      // Idle for a while, the way a player hunting for the next word is.
      await tester.pump(const Duration(seconds: 3));

      fly(controller);
      await tester.pump();
      final second = await runAnimation(tester);

      expect(second, first);
    },
  );

  group('WordFlightAnchors', () {
    testWidgets('a chip disposing after its replacement registered cannot '
        'delete the live entry', (tester) async {
      final anchors = WordFlightAnchors();
      late BuildContext oldContext;
      late BuildContext newContext;

      await tester.pumpWidget(
        Column(
          textDirection: TextDirection.ltr,
          children: [
            Builder(
              builder: (context) {
                oldContext = context;
                return const SizedBox(width: 10, height: 10);
              },
            ),
            Builder(
              builder: (context) {
                newContext = context;
                return const SizedBox(width: 10, height: 10);
              },
            ),
          ],
        ),
      );

      anchors.registerChip(word, oldContext);
      anchors.registerChip(word, newContext);
      // The old chip disposes last — the order two chips for one word swap in
      // during a level change.
      anchors.unregisterChip(word, oldContext);

      expect(anchors.chipBox(word), isNotNull);
    });

    testWidgets('an unregistered word resolves to no box', (tester) async {
      final anchors = WordFlightAnchors();
      expect(anchors.chipBox(word), isNull);
      expect(anchors.gridBox, isNull, reason: 'the key is on nothing yet');
    });
  });
}
