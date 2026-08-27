import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/domain/grid/grid_directions.dart';
import 'package:word_search_master/domain/models/level_definition.dart';
import 'package:word_search_master/domain/progression/journey_region.dart';
import 'package:word_search_master/domain/text/language.dart';

void main() {
  group('JourneyRegion.forLevel', () {
    test('every 10 levels is a region (Ch02)', () {
      expect(JourneyRegion.forLevel(1).index, 0);
      expect(JourneyRegion.forLevel(10).index, 0);
      expect(JourneyRegion.forLevel(11).index, 1);
      expect(JourneyRegion.forLevel(20).index, 1);
      expect(JourneyRegion.forLevel(300).index, 29);
    });

    test('bounds are inclusive and contiguous', () {
      final region = JourneyRegion.forLevel(47);

      expect(region.firstLevel, 41);
      expect(region.lastLevel, 50);
      expect(region.levelCount, JourneyRegion.levelsPerRegion);
      expect(region.contains(41), isTrue);
      expect(region.contains(50), isTrue);
      expect(region.contains(40), isFalse);
      expect(region.contains(51), isFalse);
    });

    test('number is 1-based for display', () {
      expect(JourneyRegion.forLevel(1).number, 1);
      expect(JourneyRegion.forLevel(300).number, 30);
    });

    test('an out-of-range level clamps rather than throwing', () {
      expect(JourneyRegion.forLevel(0).index, 0);
      expect(JourneyRegion.forLevel(-5).index, 0);
    });

    test('accents cycle through the palette, never off the end', () {
      for (var level = 1; level <= 300; level++) {
        final accent = JourneyRegion.forLevel(level).accentIndex;
        expect(accent, inInclusiveRange(0, JourneyRegion.accentCount - 1));
      }
      expect(JourneyRegion.forLevel(1).accentIndex, 0);
      expect(
        JourneyRegion.forLevel(61).accentIndex,
        0,
        reason: 'region 6 wraps',
      );
    });

    test('upTo covers every level with no gaps or overlaps', () {
      final regions = JourneyRegion.upTo(300);
      expect(regions, hasLength(30));

      for (var level = 1; level <= 300; level++) {
        final matching = regions.where((r) => r.contains(level));
        expect(matching, hasLength(1), reason: 'level $level');
      }
    });

    test('value equality', () {
      expect(JourneyRegion.forLevel(5), JourneyRegion.forLevel(7));
      expect(
        JourneyRegion.forLevel(5).hashCode,
        JourneyRegion.forLevel(7).hashCode,
      );
      expect(JourneyRegion.forLevel(5), isNot(JourneyRegion.forLevel(15)));
    });
  });

  group('JourneyMap.build', () {
    test('an untouched map has level 1 current and everything else locked', () {
      final nodes = JourneyMap.build(levelCount: 30, starsByLevel: const {});

      expect(nodes.first.status, JourneyNodeStatus.current);
      expect(nodes.first.level, 1);
      for (final node in nodes.skip(1)) {
        expect(node.status, JourneyNodeStatus.locked);
      }
    });

    test('completed levels carry their stars; the next one is current', () {
      final nodes = JourneyMap.build(
        levelCount: 30,
        starsByLevel: const {1: 3, 2: 2, 3: 1},
      );

      expect(nodes[0].status, JourneyNodeStatus.completed);
      expect(nodes[0].stars, 3);
      expect(nodes[2].stars, 1);
      expect(nodes[3].status, JourneyNodeStatus.current);
      expect(nodes[3].stars, 0);
      expect(nodes[4].status, JourneyNodeStatus.locked);
    });

    test('a skipped level below the highest reads as unlocked, not locked', () {
      // Possible after a debug jump, or a progress row dropped on an
      // integrity failure — the node must stay playable, not strand the map.
      final nodes = JourneyMap.build(
        levelCount: 30,
        starsByLevel: const {1: 3, 5: 3},
      );

      expect(nodes[5 - 1].status, JourneyNodeStatus.completed);
      expect(nodes[6 - 1].status, JourneyNodeStatus.current);
      expect(nodes[2 - 1].status, JourneyNodeStatus.unlocked);
      expect(nodes[3 - 1].status, JourneyNodeStatus.unlocked);
    });

    test(
      'locked nodes are still IN the list — Ch02 keeps the future visible',
      () {
        final nodes = JourneyMap.build(levelCount: 300, starsByLevel: const {});

        expect(nodes, hasLength(300));
        expect(nodes.last.level, 300);
        expect(nodes.last.status, JourneyNodeStatus.locked);
        expect(nodes.last.isPlayable, isFalse);
      },
    );

    test('isRegionFinale marks the last level of each region', () {
      final nodes = JourneyMap.build(levelCount: 30, starsByLevel: const {});

      expect(nodes[10 - 1].isRegionFinale, isTrue);
      expect(nodes[20 - 1].isRegionFinale, isTrue);
      expect(nodes[9 - 1].isRegionFinale, isFalse);
    });
  });

  group('JourneyMap.currentLevel', () {
    test('is the lowest unfinished level', () {
      expect(
        JourneyMap.currentLevel(levelCount: 300, starsByLevel: const {}),
        1,
      );
      expect(
        JourneyMap.currentLevel(
          levelCount: 300,
          starsByLevel: const {1: 3, 2: 3, 3: 3},
        ),
        4,
      );
    });

    test('clamps for a player who has finished everything', () {
      expect(
        JourneyMap.currentLevel(
          levelCount: 3,
          starsByLevel: const {1: 3, 2: 3, 3: 3},
        ),
        3,
      );
    });
  });

  group('regionUnlockedBy', () {
    test('finishing a region finale unlocks the next region', () {
      final unlocked = JourneyMap.regionUnlockedBy(level: 10, levelCount: 300);

      expect(unlocked, isNotNull);
      expect(unlocked!.number, 2);
      expect(unlocked.firstLevel, 11);
    });

    test('finishing a mid-region level unlocks nothing', () {
      expect(JourneyMap.regionUnlockedBy(level: 7, levelCount: 300), isNull);
    });

    test(
      'the very last level unlocks nothing — there is nothing beyond it',
      () {
        expect(
          JourneyMap.regionUnlockedBy(level: 300, levelCount: 300),
          isNull,
        );
      },
    );
  });

  group('journeyRegionTheme', () {
    LevelDefinition level(int id, String theme) => LevelDefinition(
      id: id,
      language: Language.english,
      seed: id,
      gridSize: 6,
      wordCount: 4,
      categoryPool: const ['nature'],
      directionTier: DirectionTier.starter,
      theme: theme,
    );

    test('reads the theme off the levels the region actually spans', () {
      final levels = {
        for (var id = 1; id <= 10; id++) id: level(id, 'Animals'),
      };

      expect(journeyRegionTheme(JourneyRegion.forLevel(1), levels), 'Animals');
    });

    test('a region with no loaded definitions yields an empty label', () {
      expect(journeyRegionTheme(JourneyRegion.forLevel(1), const {}), '');
    });
  });
}
