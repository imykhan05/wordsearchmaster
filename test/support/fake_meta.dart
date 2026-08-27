// `Override` is not in `flutter_riverpod`'s barrel in Riverpod 3.x — it lives
// in `riverpod/misc.dart`, which is why `riverpod` is a declared DEV
// dependency (it is already there transitively; declaring it just makes this
// one import legitimate rather than implicit).
import 'package:riverpod/misc.dart' show Override;
import 'package:word_search_master/domain/progression/journey_region.dart';
import 'package:word_search_master/domain/progression/streak.dart';
import 'package:word_search_master/presentation/meta/journey_providers.dart';

/// Plain-value overrides for the P11 meta providers.
///
/// ---------------------------------------------------------------------------
/// WHY A SMOKE TEST SHOULD NOT OWN A DATABASE
///
/// Since P11 the home, journey, daily and profile screens all watch Riverpod
/// `StreamProvider`s over LIVE Drift queries. That is right for the app and
/// wrong for a test that only wants to know a route renders: it drags Drift's
/// stream bookkeeping into `flutter_test`'s fake clock, where cancelling a
/// query on teardown schedules a cleanup timer the harness then reports as
/// "a Timer is still pending even after the widget tree was disposed".
///
/// So route-level tests override the joins with settled values. The joins
/// themselves are covered where they belong — the pure rules in
/// `test/domain/progression/`, the reads in the repository tests, and the
/// write path end to end in `progression_controller_test.dart`.
List<Override> fakeMetaOverrides({
  int levelCount = 30,
  Map<int, int> starsByLevel = const {},
  int coins = 0,
  StreakState streak = StreakState.empty,
  DailyOutcome? todaysDaily,
}) => [
  journeyMapProvider.overrideWith(
    (ref) => Stream.value(
      JourneyMapState(
        nodes: JourneyMap.build(
          levelCount: levelCount,
          starsByLevel: starsByLevel,
        ),
        currentLevel: JourneyMap.currentLevel(
          levelCount: levelCount,
          starsByLevel: starsByLevel,
        ),
        regionThemes: {
          for (final region in JourneyRegion.upTo(levelCount))
            region.index: 'Nature',
        },
      ),
    ),
  ),
  coinBalanceProvider.overrideWith((ref) => Stream.value(coins)),
  currentStreakProvider.overrideWith(
    (ref) => Stream.value(
      StreakTransition(state: streak, event: StreakEvent.unchanged),
    ),
  ),
  todaysDailyResultProvider.overrideWith((ref) => Stream.value(todaysDaily)),
  collectionsProvider.overrideWith(
    (ref) => Stream.value(const CollectionsState(badges: [], unlockedAt: {})),
  ),
];
