/// The journey map's regions (Ch02) — every 10 levels is a themed stretch of
/// the path with its own accent and its own unlock moment.
///
/// PURE DART: a region knows which levels it spans and which ACCENT INDEX it
/// wears, never a `Color`. `lib/domain/` cannot import `dart:ui` (CLAUDE.md →
/// Architecture), and the indirection is worth having anyway — the palette is
/// a theme concern that changes per theme, while "region 4 is the fourth
/// accent" is a fact about the map that must not.
library;

import '../models/level_definition.dart';

/// A block of [JourneyRegion.levelsPerRegion] consecutive levels.
final class JourneyRegion {
  const JourneyRegion({
    required this.index,
    required this.firstLevel,
    required this.lastLevel,
  });

  /// Ch02's cadence. Ten is short enough that a player sees a new region in
  /// their first sitting and long enough that arriving at one still reads as
  /// an event.
  static const int levelsPerRegion = 10;

  /// How many accents the palette cycles through before repeating. Six rather
  /// than thirty: thirty visually distinct accents do not exist, and a player
  /// only ever sees two or three regions at once on a scrolling map, so a
  /// cycle reads as variety while staying inside a palette that was actually
  /// designed.
  static const int accentCount = 6;

  /// 0-based. Region 0 holds levels 1–10.
  final int index;

  /// Inclusive bounds, 1-based level numbers.
  final int firstLevel;
  final int lastLevel;

  /// 1-based, for display ("Region 3").
  int get number => index + 1;

  /// Which entry of the theme's region palette this region wears.
  int get accentIndex => index % accentCount;

  int get levelCount => lastLevel - firstLevel + 1;

  bool contains(int level) => level >= firstLevel && level <= lastLevel;

  /// The region [level] belongs to. Levels are 1-based; anything below 1 is
  /// clamped into region 0 rather than throwing, matching
  /// `DirectionTier.forLevel` and `ContentRepository.getLevel` — a corrupt
  /// level number must degrade, never crash a player's session.
  static JourneyRegion forLevel(int level) {
    final safe = level < 1 ? 1 : level;
    final index = (safe - 1) ~/ levelsPerRegion;
    return JourneyRegion(
      index: index,
      firstLevel: index * levelsPerRegion + 1,
      lastLevel: (index + 1) * levelsPerRegion,
    );
  }

  /// Every region covering levels 1..[lastLevel], in order.
  static List<JourneyRegion> upTo(int lastLevel) {
    final count = (lastLevel + levelsPerRegion - 1) ~/ levelsPerRegion;
    return [
      for (var index = 0; index < count; index++)
        JourneyRegion(
          index: index,
          firstLevel: index * levelsPerRegion + 1,
          lastLevel: (index + 1) * levelsPerRegion,
        ),
    ];
  }

  @override
  bool operator ==(Object other) =>
      other is JourneyRegion &&
      other.index == index &&
      other.firstLevel == firstLevel &&
      other.lastLevel == lastLevel;

  @override
  int get hashCode => Object.hash(index, firstLevel, lastLevel);

  @override
  String toString() => 'JourneyRegion($number: $firstLevel-$lastLevel)';
}

/// One node on the map.
enum JourneyNodeStatus {
  /// Finished. Carries stars.
  completed,

  /// The node the map auto-scrolls to: the lowest level not yet finished.
  current,

  /// Reachable but not started — only ever the levels after [current] inside
  /// the same unlocked stretch.
  unlocked,

  /// Visible but dimmed. Ch02 is explicit that locked nodes stay on screen:
  /// a visible future is motivating, and hiding it turns the map into a list
  /// that happens to scroll.
  locked,
}

/// A level's place on the journey map.
final class JourneyNode {
  const JourneyNode({
    required this.level,
    required this.region,
    required this.status,
    required this.stars,
  });

  final int level;
  final JourneyRegion region;
  final JourneyNodeStatus status;

  /// 0–3. Always 0 unless [status] is [JourneyNodeStatus.completed].
  final int stars;

  bool get isPlayable => status != JourneyNodeStatus.locked;

  /// True on the last level of its region — the node that triggers the
  /// region-unlock celebration when it is finished.
  bool get isRegionFinale => level == region.lastLevel;

  @override
  bool operator ==(Object other) =>
      other is JourneyNode &&
      other.level == level &&
      other.region == region &&
      other.status == status &&
      other.stars == stars;

  @override
  int get hashCode => Object.hash(level, region, status, stars);

  @override
  String toString() => 'JourneyNode($level, ${status.name}, $stars★)';
}

/// Builds the map from progress. Pure — the screen renders what this returns
/// and decides nothing about unlocking itself.
abstract final class JourneyMap {
  /// Nodes for levels 1..[levelCount], given per-level stars.
  ///
  /// UNLOCKING IS DERIVED, NEVER STORED. A level is playable when every level
  /// below it is finished — so the rule is `level <= highestCompleted + 1`,
  /// computed here from the same verified `level_progress` rows the rest of
  /// the app reads. There is no "unlocked" flag anywhere to forge, and a
  /// tampered progress row that gets dropped on read (P08) takes its unlock
  /// with it rather than leaving a level stranded open.
  ///
  /// [starsByLevel] holds only completed levels; a missing entry means not
  /// finished.
  static List<JourneyNode> build({
    required int levelCount,
    required Map<int, int> starsByLevel,
  }) {
    final highestCompleted = starsByLevel.keys.fold(
      0,
      (highest, level) => level > highest ? level : highest,
    );
    final current = highestCompleted + 1;

    return [
      for (var level = 1; level <= levelCount; level++)
        JourneyNode(
          level: level,
          region: JourneyRegion.forLevel(level),
          status: switch (level) {
            _ when starsByLevel.containsKey(level) =>
              JourneyNodeStatus.completed,
            _ when level == current => JourneyNodeStatus.current,
            _ when level < current => JourneyNodeStatus.unlocked,
            _ => JourneyNodeStatus.locked,
          },
          stars: starsByLevel[level] ?? 0,
        ),
    ];
  }

  /// The level the map should scroll to on entry: the lowest unfinished one,
  /// clamped to [levelCount] for a player who has finished everything.
  static int currentLevel({
    required int levelCount,
    required Map<int, int> starsByLevel,
  }) {
    final highestCompleted = starsByLevel.keys.fold(
      0,
      (highest, level) => level > highest ? level : highest,
    );
    final next = highestCompleted + 1;
    return next > levelCount ? levelCount : next;
  }

  /// The region a completion at [level] just unlocked, or null if it did not
  /// finish a region.
  ///
  /// Drives the Ch02 unlock celebration, and returns null rather than the
  /// next region when [level] is the last one on the map — there is nothing
  /// beyond it to celebrate arriving at.
  static JourneyRegion? regionUnlockedBy({
    required int level,
    required int levelCount,
  }) {
    final region = JourneyRegion.forLevel(level);
    if (level != region.lastLevel) return null;
    if (level >= levelCount) return null;
    return JourneyRegion.forLevel(level + 1);
  }
}

/// The theme name shown on a region header.
///
/// Taken from the levels the region spans rather than invented here: P10
/// already writes a `theme` on every [LevelDefinition] (the Title-cased
/// category the level draws its words from), so a region reads as the themes
/// it actually contains. Falls back to the empty string for a region with no
/// definitions loaded, which the header then simply omits.
String journeyRegionTheme(
  JourneyRegion region,
  Map<int, LevelDefinition> levelsById,
) {
  final themes = <String>[];
  for (var level = region.firstLevel; level <= region.lastLevel; level++) {
    final theme = levelsById[level]?.theme;
    if (theme != null && theme.isNotEmpty && !themes.contains(theme)) {
      themes.add(theme);
    }
  }
  return themes.isEmpty ? '' : themes.first;
}
