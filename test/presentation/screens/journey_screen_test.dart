import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/app/config/app_config.dart';
import 'package:word_search_master/app/theme/app_theme.dart';
import 'package:word_search_master/domain/progression/journey_region.dart';
import 'package:word_search_master/l10n/app_localizations.dart';
import 'package:word_search_master/presentation/meta/journey_providers.dart';
import 'package:word_search_master/presentation/screens/journey_screen.dart';

/// Ch02's journey map: regions of ten, locked nodes VISIBLE but dimmed, and
/// an auto-scroll that lands on the current node.
///
/// ---------------------------------------------------------------------------
/// THE PROVIDER IS OVERRIDDEN, NOT DRIVEN THROUGH A DATABASE
///
/// `JourneyScreen` renders what `journeyMapProvider` hands it and decides
/// nothing — the content/progress JOIN lives in the provider, and is covered
/// where it belongs (`journey_region_test.dart` for the pure rules,
/// `progression_controller_test.dart` and the repository tests for the reads).
/// Feeding a live Drift query stream into a widget test instead would test
/// those layers a second time AND drag Drift's own stream bookkeeping into
/// `flutter_test`'s fake clock, where cancelling a query schedules a cleanup
/// timer the harness then reports as a leak. So: a plain value in, and the
/// screen's own behaviour under test.
void main() {
  /// A map state built straight from the pure rules — same function the real
  /// provider calls, so the fixture cannot drift from production semantics.
  JourneyMapState mapState({
    int levelCount = 30,
    Map<int, int> starsByLevel = const {},
  }) => JourneyMapState(
    nodes: JourneyMap.build(levelCount: levelCount, starsByLevel: starsByLevel),
    currentLevel: JourneyMap.currentLevel(
      levelCount: levelCount,
      starsByLevel: starsByLevel,
    ),
    regionThemes: {
      for (final region in JourneyRegion.upTo(levelCount))
        region.index: 'Nature',
    },
  );

  Future<void> pumpJourney(
    WidgetTester tester, {
    Map<int, int> starsByLevel = const {},
    int levelCount = 30,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(AppConfig.prod()),
          journeyMapProvider.overrideWith(
            (ref) => Stream.value(
              mapState(levelCount: levelCount, starsByLevel: starsByLevel),
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const JourneyScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('groups the path into ten-level regions', (tester) async {
    await pumpJourney(tester);

    expect(find.text('Region 1'), findsOneWidget);
    // Region 2 starts at level 11, below the fold on a default test viewport.
    expect(find.text('Region 2'), findsNothing);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('Region 2'), findsOneWidget);
  });

  testWidgets(
    'LOCKED NODES ARE STILL RENDERED, only dimmed — Ch02 keeps the future '
    'visible rather than hiding it',
    (tester) async {
      await pumpJourney(tester);

      // Level 1 is current; 2+ are locked. Both are in the tree.
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);

      double opacityAround(String label) => tester
          .widgetList<Opacity>(
            find.ancestor(of: find.text(label), matching: find.byType(Opacity)),
          )
          .first
          .opacity;

      expect(opacityAround('2'), lessThan(1.0), reason: 'locked reads dimmed');
      expect(
        opacityAround('1'),
        1.0,
        reason: 'the current node is full strength',
      );
    },
  );

  testWidgets('a locked node is not tappable, an unlocked one is', (
    tester,
  ) async {
    await pumpJourney(tester);

    InkWell inkFor(String label) => tester.widget<InkWell>(
      find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first,
    );

    expect(inkFor('1').onTap, isNotNull, reason: 'level 1 is current');
    expect(inkFor('2').onTap, isNull, reason: 'level 2 is locked');
  });

  testWidgets('completed nodes show their stars, unplayed ones show none', (
    tester,
  ) async {
    await pumpJourney(tester, starsByLevel: const {1: 3, 2: 1});

    Finder starsUnder(String label) => find.descendant(
      of: find
          .ancestor(of: find.text(label), matching: find.byType(InkWell))
          .first,
      matching: find.byIcon(Icons.star_rounded),
    );

    // Every completed node draws three slots and fills `stars` of them.
    expect(starsUnder('1'), findsNWidgets(3));
    expect(starsUnder('2'), findsNWidgets(3));
    // Level 3 is current and unplayed — no star row at all.
    expect(starsUnder('3'), findsNothing);
  });

  testWidgets('a locked node is still labelled for a screen reader', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpJourney(tester);

    // A RegExp, not the bare string: each node is its own semantics container
    // and merges its level number in, so the label reads like "2\nLocked".
    expect(
      find.bySemanticsLabel(RegExp('Locked')),
      findsWidgets,
      reason: '"visible future" has to include non-visually',
    );
    handle.dispose();
  });

  testWidgets('opens at the current level rather than at the top', (
    tester,
  ) async {
    await pumpJourney(
      tester,
      starsByLevel: {for (var level = 1; level <= 12; level++) level: 3},
    );

    final scrollable = tester.widget<Scrollable>(find.byType(Scrollable).first);
    expect(
      scrollable.controller!.offset,
      JourneyScreen.scrollOffsetFor(13),
      reason: 'level 13 is the lowest unfinished one',
    );
    expect(scrollable.controller!.offset, greaterThan(0));
  });

  testWidgets('a brand-new player opens at the very top', (tester) async {
    await pumpJourney(tester);

    final scrollable = tester.widget<Scrollable>(find.byType(Scrollable).first);
    expect(scrollable.controller!.offset, 0);
  });

  group('auto-scroll offset', () {
    test('level 1 parks at the very top', () {
      expect(JourneyScreen.scrollOffsetFor(1), 0);
    });

    test('a later level scrolls proportionally down the path', () {
      final atFive = JourneyScreen.scrollOffsetFor(5);
      final atFifty = JourneyScreen.scrollOffsetFor(50);

      expect(atFive, greaterThan(0));
      expect(atFifty, greaterThan(atFive));
    });

    test('the offset lands the node inside the viewport, not at its edge', () {
      // Two rows of headroom above the current node, by construction.
      const level = 25;
      final region = JourneyRegion.forLevel(level);
      final nodeTop =
          region.index * JourneyScreen.regionExtent +
          JourneyScreen.regionHeaderHeight +
          (level - region.firstLevel) * JourneyScreen.nodeRowHeight;

      expect(
        nodeTop - JourneyScreen.scrollOffsetFor(level),
        JourneyScreen.nodeRowHeight * 2,
      );
    });

    test('never negative', () {
      for (var level = 1; level <= 300; level++) {
        expect(JourneyScreen.scrollOffsetFor(level), greaterThanOrEqualTo(0));
      }
    });

    test('the region extent matches its own parts', () {
      expect(
        JourneyScreen.regionExtent,
        JourneyScreen.regionHeaderHeight +
            JourneyScreen.nodeRowHeight * JourneyRegion.levelsPerRegion,
      );
    });
  });
}
