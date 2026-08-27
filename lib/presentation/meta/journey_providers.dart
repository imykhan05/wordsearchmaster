import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../app/language/selected_language.dart';
import '../../data/content/content_repository.dart';

import '../../data/repositories/coins_repository.dart';
import '../../data/repositories/collections_repository.dart';
import '../../data/repositories/daily_repository.dart';
import '../../data/repositories/progress_repository.dart';
import '../../data/repositories/streak_repository.dart';
import '../../domain/progression/collections.dart';
import '../../domain/progression/journey_region.dart';
import '../../domain/progression/streak.dart';
import '../../services/time/trusted_clock.dart';

part 'journey_providers.g.dart';

/// The read-side providers behind the P11 meta-game screens.
///
/// They live together because they share a shape: each one JOINS content (the
/// level definitions, from assets) with progress (the verified rows, from
/// Drift) and hands the result to a screen that renders it and decides
/// nothing. Keeping the joins here rather than in each screen's `build` is
/// what stops three screens growing three slightly different ideas of what
/// "completed" means.
///
/// All of them are auto-dispose. A meta screen is transient — the player
/// opens the map, taps a level and leaves — and holding a Drift subscription
/// open for the whole session so a screen can rebuild instantly is the wrong
/// trade on a 2GB device.

/// Everything the journey map needs, in one value.
final class JourneyMapState {
  const JourneyMapState({
    required this.nodes,
    required this.currentLevel,
    required this.regionThemes,
  });

  final List<JourneyNode> nodes;

  /// The level the map auto-scrolls to on entry.
  final int currentLevel;

  /// Region index → its theme label, precomputed so a scrolling map does not
  /// re-derive one per region per frame.
  final Map<int, String> regionThemes;
}

@riverpod
Stream<JourneyMapState> journeyMap(Ref ref) async* {
  final language = ref.watch(selectedLanguageProvider);
  final content = await ref.watch(contentRepositoryProvider.future);
  final progress = await ref.watch(progressRepositoryProvider.future);

  final levels = content.levelsFor(language);
  final levelsById = {for (final level in levels) level.id: level};
  final regionThemes = {
    for (final region in JourneyRegion.upTo(levels.length))
      region.index: journeyRegionTheme(region, levelsById),
  };

  yield* progress.watchAll(language).map((rows) {
    final starsByLevel = {for (final row in rows) row.level: row.stars};
    return JourneyMapState(
      nodes: JourneyMap.build(
        levelCount: levels.length,
        starsByLevel: starsByLevel,
      ),
      currentLevel: JourneyMap.currentLevel(
        levelCount: levels.length,
        starsByLevel: starsByLevel,
      ),
      regionThemes: regionThemes,
    );
  });
}

/// The player's coin balance — the sum of verified ledger rows (P08).
@riverpod
Stream<int> coinBalance(Ref ref) async* {
  final coins = await ref.watch(coinsRepositoryProvider.future);
  yield* coins.watchBalance();
}

/// The streak, aged forward to today.
///
/// Resolves "today" through [TrustedClock] rather than `DateTime.now()`, so
/// the counter a player sees is the same day boundary the write path used —
/// see `trusted_clock.dart` for why that is not the device's own answer.
@riverpod
Stream<StreakTransition> currentStreak(Ref ref) async* {
  final today = await ref.watch(currentDayProvider.future);
  final streak = await ref.watch(streakRepositoryProvider.future);
  yield* streak.watchStreakAsOf(today);
}

/// A finished daily, as the screen needs it.
///
/// NOT drift's `DailyResultRow`. Two reasons, one of them practical: the
/// presentation layer has no business depending on a database row shape, and
/// `riverpod_generator` cannot resolve a drift-generated type in a provider's
/// signature at all — both builders run in the same pass, so the row class
/// does not exist yet when the provider is generated.
final class DailyOutcome {
  const DailyOutcome({required this.stars, required this.score});

  final int stars;
  final int score;
}

/// Whether today's Daily has already been played, and its result if so.
@riverpod
Stream<DailyOutcome?> todaysDailyResult(Ref ref) async* {
  final language = ref.watch(selectedLanguageProvider);
  final today = await ref.watch(currentDayProvider.future);
  final daily = await ref.watch(dailyRepositoryProvider.future);

  yield* daily
      .watchResult(today, language)
      .map(
        (row) => row == null
            ? null
            : DailyOutcome(stars: row.stars, score: row.score),
      );
}

/// One badge per category in the selected language, with its unlock time.
final class CollectionsState {
  const CollectionsState({required this.badges, required this.unlockedAt});

  final List<CategoryBadge> badges;

  /// `achievementId` → millis since epoch, for badges the achievements table
  /// has actually recorded. Absent for a badge that is earned by derivation
  /// but whose row has not been written yet (a level completed by an older
  /// build, before P11).
  final Map<String, int> unlockedAt;
}

@riverpod
Stream<CollectionsState> collections(Ref ref) async* {
  final language = ref.watch(selectedLanguageProvider);
  final content = await ref.watch(contentRepositoryProvider.future);
  final progress = await ref.watch(progressRepositoryProvider.future);
  final collections = await ref.watch(collectionsRepositoryProvider.future);

  final levels = content.levelsFor(language);

  await for (final rows in progress.watchAll(language)) {
    final completedLevels = {for (final row in rows) row.level};
    final badges = Collections.forLanguage(
      levels: levels,
      completedLevels: completedLevels,
      language: language,
    );
    final unlocked = await collections.unlockedRows();

    yield CollectionsState(
      badges: badges,
      unlockedAt: {
        for (final entry in unlocked.entries)
          if (entry.value.unlockedAt case final int at) entry.key: at,
      },
    );
  }
}
