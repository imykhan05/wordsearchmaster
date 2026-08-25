import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/domain/grid/grid_directions.dart';
import 'package:word_search_master/domain/grid/grid_vector.dart';
import 'package:word_search_master/domain/text/language.dart';

void main() {
  group('Language reading direction', () {
    test('Urdu runs horizontally WEST — the column index decreases', () {
      // Ch04, Masla 5. Not a rendering hack applied later: the generator
      // places words this way, so hit-testing agrees by construction.
      expect(Language.urdu.primaryDirection, GridVector.west);
      expect(Language.urdu.primaryDirection.dx, -1);
    });

    test('Hindi and English run EAST', () {
      expect(Language.hindi.primaryDirection, GridVector.east);
      expect(Language.english.primaryDirection, GridVector.east);
    });

    test('reverse is the opposite of primary, per language', () {
      for (final language in Language.values) {
        expect(language.reverseDirection, language.primaryDirection.opposite);
      }
    });
  });

  group('DirectionTier.forLevel follows the Ch07 curve', () {
    const expectations = {
      1: DirectionTier.starter,
      5: DirectionTier.starter,
      6: DirectionTier.basic,
      20: DirectionTier.basic,
      21: DirectionTier.diagonal,
      60: DirectionTier.diagonal,
      61: DirectionTier.reverse,
      150: DirectionTier.reverse,
      151: DirectionTier.all,
      300: DirectionTier.all,
    };

    expectations.forEach((level, tier) {
      test('level $level is ${tier.name}', () {
        expect(DirectionTier.forLevel(level), tier);
      });
    });

    test('an out-of-range level clamps to the hardest tier, never throws', () {
      // Bad content should degrade, not crash a player's session.
      expect(DirectionTier.forLevel(99999), DirectionTier.all);
      expect(DirectionTier.forLevel(0), DirectionTier.starter);
      expect(DirectionTier.forLevel(-5), DirectionTier.starter);
    });
  });

  group('GridDirections.forLanguage', () {
    test('starter is reading direction plus straight down', () {
      expect(
        GridDirections.forLanguage(Language.english, DirectionTier.starter),
        [GridVector.east, GridVector.south],
      );
      expect(GridDirections.forLanguage(Language.urdu, DirectionTier.starter), [
        GridVector.west,
        GridVector.south,
      ]);
    });

    test('no diagonals below the diagonal tier', () {
      for (final language in Language.values) {
        for (final tier in [DirectionTier.starter, DirectionTier.basic]) {
          expect(
            GridDirections.forLanguage(
              language,
              tier,
            ).where((v) => v.isDiagonal),
            isEmpty,
            reason: '$language $tier',
          );
        }
      }
    });

    test('diagonals appear exactly at the diagonal tier', () {
      for (final language in Language.values) {
        expect(
          GridDirections.forLanguage(
            language,
            DirectionTier.diagonal,
          ).where((v) => v.isDiagonal),
          hasLength(2),
        );
      }
    });

    test('diagonals lean the SAME way the script reads', () {
      // An Urdu diagonal must lean opposite to an English one, or the tier
      // would feel harder in one language than the other.
      final english = GridDirections.forLanguage(
        Language.english,
        DirectionTier.diagonal,
      ).where((v) => v.isDiagonal);
      final urdu = GridDirections.forLanguage(
        Language.urdu,
        DirectionTier.diagonal,
      ).where((v) => v.isDiagonal);

      expect(english.every((v) => v.dx == 1), isTrue);
      expect(urdu.every((v) => v.dx == -1), isTrue);
    });

    test('reverse direction appears only at the reverse tier and above', () {
      for (final language in Language.values) {
        final reverse = language.reverseDirection;

        expect(
          GridDirections.forLanguage(language, DirectionTier.diagonal),
          isNot(contains(reverse)),
        );
        expect(
          GridDirections.forLanguage(language, DirectionTier.reverse),
          contains(reverse),
        );
      }
    });

    test('the all tier is exactly the eight unique directions', () {
      for (final language in Language.values) {
        final directions = GridDirections.forLanguage(
          language,
          DirectionTier.all,
        );

        expect(directions, hasLength(8));
        expect(directions.toSet(), hasLength(8), reason: 'no duplicates');
        expect(directions.toSet(), GridVector.all.toSet());
      }
    });

    test('each tier is a superset of the one below it', () {
      // A level should never LOSE a direction as difficulty rises.
      for (final language in Language.values) {
        final tiers = DirectionTier.values
            .map((t) => GridDirections.forLanguage(language, t).toSet())
            .toList();

        for (var i = 1; i < tiers.length; i++) {
          expect(
            tiers[i].containsAll(tiers[i - 1]),
            isTrue,
            reason:
                '$language: ${DirectionTier.values[i].name} dropped a direction',
          );
        }
      }
    });

    test('every tier contains no duplicates', () {
      for (final language in Language.values) {
        for (final tier in DirectionTier.values) {
          final directions = GridDirections.forLanguage(language, tier);
          expect(directions.toSet(), hasLength(directions.length));
        }
      }
    });

    test(
      'returned lists are unmodifiable, so a caller cannot corrupt a tier',
      () {
        final directions = GridDirections.forLanguage(
          Language.urdu,
          DirectionTier.all,
        );
        expect(() => directions.add(GridVector.east), throwsUnsupportedError);
      },
    );

    test('forLevel matches forLanguage with the level tier', () {
      for (final level in [1, 12, 47, 120, 260]) {
        expect(
          GridDirections.forLevel(Language.hindi, level),
          GridDirections.forLanguage(
            Language.hindi,
            DirectionTier.forLevel(level),
          ),
        );
      }
    });
  });

  group('GridVector', () {
    test('y grows downward, so south is (0, 1)', () {
      expect(GridVector.south.dy, 1);
      expect(GridVector.north.dy, -1);
    });

    test('opposite negates both components', () {
      expect(GridVector.southEast.opposite, GridVector.northWest);
      expect(GridVector.west.opposite, GridVector.east);
    });

    test('classifies orientation', () {
      expect(GridVector.east.isHorizontal, isTrue);
      expect(GridVector.east.isDiagonal, isFalse);
      expect(GridVector.south.isVertical, isTrue);
      expect(GridVector.northWest.isDiagonal, isTrue);
    });

    test('value equality, so vectors work as map keys and in sets', () {
      expect(const GridVector(1, 0), GridVector.east);
      expect(const GridVector(1, 0).hashCode, GridVector.east.hashCode);

      // Built from a list so the analyzer does not fold it into a const set
      // literal — collapsing to one entry is exactly what is being asserted.
      final vectors = <GridVector>[GridVector.east, const GridVector(1, 0)];
      expect(vectors.toSet(), hasLength(1));
    });
  });
}
