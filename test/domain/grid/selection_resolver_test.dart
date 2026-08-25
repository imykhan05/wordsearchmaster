import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/domain/grid/cell.dart';
import 'package:word_search_master/domain/grid/grid_point.dart';
import 'package:word_search_master/domain/grid/grid_vector.dart';
import 'package:word_search_master/domain/grid/selection_resolver.dart';
import 'package:word_search_master/domain/text/language.dart';

/// A Latin grid written as rows of letters.
List<List<String>> latinGrid(List<String> rows) => [
  for (final row in rows) row.split(''),
];

void main() {
  // WATER runs east along row 0; WIND runs south down column 0. They share
  // cell (0,0) — the 'W'.
  final crossingGrid = latinGrid(const [
    'WATER',
    'IBCDF',
    'NGHJK',
    'DLMPQ',
    'STUVX',
  ]);

  const resolver = SelectionResolver(size: 5);

  SelectionState dragThrough(List<Cell> path) {
    var state = resolver.begin(GridPoint.centerOf(path.first));
    for (final cell in path.skip(1)) {
      state = resolver.extendTo(state, GridPoint.centerOf(cell));
    }
    return state;
  }

  SelectionOutcome releaseOn(
    SelectionState state,
    Iterable<String> remaining, {
    List<List<String>>? grid,
    Language language = Language.english,
  }) => resolver.release(
    state: state,
    grid: grid ?? crossingGrid,
    remainingWords: remaining,
    language: language,
  );

  group('anchor and direction lock', () {
    test('the first touch locks the anchor and selects one cell', () {
      final state = resolver.begin(GridPoint.centerOf(const Cell(2, 2)));

      expect(state.anchor, const Cell(2, 2));
      expect(state.cells, [const Cell(2, 2)]);
      expect(state.direction, isNull, reason: 'nothing to aim at yet');
      expect(state.isTap, isTrue);
    });

    test('a touch outside the grid selects nothing', () {
      expect(resolver.begin(const GridPoint(9.5, 9.5)), SelectionState.empty);
      expect(resolver.begin(const GridPoint(-1, 0)).isEmpty, isTrue);
    });

    test('the second cell locks the direction to one of the eight vectors', () {
      final east = dragThrough(const [Cell(2, 2), Cell(2, 3)]);
      expect(east.direction, GridVector.east);

      final northWest = dragThrough(const [Cell(2, 2), Cell(1, 1)]);
      expect(northWest.direction, GridVector.northWest);
    });

    test('an off-axis drag snaps to the nearest of the eight', () {
      // Two right and one down is closer to east than to south-east.
      var state = resolver.begin(GridPoint.centerOf(const Cell(2, 0)));
      state = resolver.extendTo(state, const GridPoint(2.5, 2.9));

      expect(state.direction, GridVector.east);
    });
  });

  group('stickiness — the required feel property', () {
    test('wandering off the line does NOT break the selection', () {
      // Lock east, then let the finger stray a long way off the row.
      var state = dragThrough(const [Cell(2, 2), Cell(2, 3)]);
      expect(state.cells, hasLength(2));

      state = resolver.extendTo(state, const GridPoint(4.5, 0.4));

      expect(state.direction, GridVector.east, reason: 'direction must hold');
      expect(state.cells, const [Cell(2, 2), Cell(2, 3), Cell(2, 4)]);
    });

    test('only the along-line component matters once locked', () {
      final state = dragThrough(const [Cell(0, 0), Cell(0, 1)]);

      // Same x, wildly different y: identical selection.
      final low = resolver.extendTo(state, const GridPoint(3.5, 0.5));
      final high = resolver.extendTo(state, const GridPoint(3.5, 4.4));

      expect(low.cells, high.cells);
      expect(low.cells, hasLength(4));
    });
  });

  group('dragging backwards', () {
    test('pulling back toward the anchor removes cells', () {
      var state = dragThrough(const [
        Cell(0, 0),
        Cell(0, 1),
        Cell(0, 2),
        Cell(0, 3),
      ]);
      expect(state.cells, hasLength(4));

      state = resolver.extendTo(state, GridPoint.centerOf(const Cell(0, 1)));
      expect(state.cells, hasLength(2));
    });

    test(
      'returning to the anchor unlocks the direction so a new one can be aimed',
      () {
        // Without this a player who set off the wrong way would have to lift
        // their finger and start again.
        var state = dragThrough(const [Cell(2, 2), Cell(2, 3)]);
        expect(state.direction, GridVector.east);

        state = resolver.extendTo(state, GridPoint.centerOf(const Cell(2, 2)));
        expect(state.direction, isNull);
        expect(state.cells, [const Cell(2, 2)]);

        state = resolver.extendTo(state, GridPoint.centerOf(const Cell(3, 2)));
        expect(state.direction, GridVector.south);
        expect(state.cells, const [Cell(2, 2), Cell(3, 2)]);
      },
    );
  });

  group('grid edges', () {
    test('a diagonal dragged past the corner clamps inside the grid', () {
      var state = resolver.begin(GridPoint.centerOf(const Cell(0, 0)));
      // Far beyond the bottom-right corner.
      state = resolver.extendTo(state, const GridPoint(40, 40));

      expect(state.direction, GridVector.southEast);
      expect(state.cells, hasLength(5));
      expect(state.cells.last, const Cell(4, 4));
      for (final cell in state.cells) {
        expect(cell.isInside(5), isTrue, reason: '$cell escaped the grid');
      }
    });

    test('a diagonal with no room at all stays a single cell', () {
      var state = resolver.begin(GridPoint.centerOf(const Cell(4, 4)));
      state = resolver.extendTo(state, const GridPoint(40, 40));

      expect(state.cells, [const Cell(4, 4)]);
      expect(state.direction, isNull);
    });

    test('every direction clamps at its own edge', () {
      for (final direction in GridVector.all) {
        var state = resolver.begin(GridPoint.centerOf(const Cell(2, 2)));
        state = resolver.extendTo(
          state,
          GridPoint(2.5 + direction.dx * 50, 2.5 + direction.dy * 50),
        );

        for (final cell in state.cells) {
          expect(cell.isInside(5), isTrue, reason: '$direction produced $cell');
        }
      }
    });
  });

  group('matching on release', () {
    test('a single-cell tap never matches, even against a listed word', () {
      final state = resolver.begin(GridPoint.centerOf(const Cell(0, 0)));

      final outcome = releaseOn(state, const ['W', 'WATER']);

      expect(outcome.matchedWord, isNull);
      expect(outcome.isValid, isFalse);
    });

    test('tracing a word forwards matches it', () {
      final state = dragThrough(const [
        Cell(0, 0),
        Cell(0, 1),
        Cell(0, 2),
        Cell(0, 3),
        Cell(0, 4),
      ]);

      final outcome = releaseOn(state, const ['WATER', 'WIND']);

      expect(outcome.matchedWord, 'WATER');
      expect(outcome.cells.first, const Cell(0, 0));
    });

    test(
      'tracing a word BACKWARDS matches, and hands back cells word-first',
      () {
        // Dragged right-to-left, spelling RETAW.
        final state = dragThrough(const [
          Cell(0, 4),
          Cell(0, 3),
          Cell(0, 2),
          Cell(0, 1),
          Cell(0, 0),
        ]);

        final outcome = releaseOn(state, const ['WATER']);

        expect(outcome.matchedWord, 'WATER');
        // Reversed relative to the finger, so the strike-through animation runs
        // along the word rather than along the drag.
        expect(outcome.cells.first, const Cell(0, 0));
        expect(outcome.cells.last, const Cell(0, 4));
      },
    );

    test(
      'a selection that spells nothing returns no match but keeps its cells',
      () {
        final state = dragThrough(const [Cell(1, 1), Cell(1, 2), Cell(1, 3)]);

        final outcome = releaseOn(state, const ['WATER', 'WIND']);

        expect(outcome.matchedWord, isNull);
        expect(outcome.cells, hasLength(3));
      },
    );

    test('two overlapping words are found separately', () {
      // WATER (east, row 0) and WIND (south, column 0) share the 'W'.
      final water = releaseOn(
        dragThrough(const [
          Cell(0, 0),
          Cell(0, 1),
          Cell(0, 2),
          Cell(0, 3),
          Cell(0, 4),
        ]),
        const ['WATER', 'WIND'],
      );
      expect(water.matchedWord, 'WATER');

      // WATER is now found, so it leaves the remaining list — and WIND still
      // matches through the shared cell.
      final wind = releaseOn(
        dragThrough(const [Cell(0, 0), Cell(1, 0), Cell(2, 0), Cell(3, 0)]),
        const ['WIND'],
      );
      expect(wind.matchedWord, 'WIND');
      expect(wind.cells, const [
        Cell(0, 0),
        Cell(1, 0),
        Cell(2, 0),
        Cell(3, 0),
      ]);
    });

    test('an already-found word cannot be scored twice', () {
      final state = dragThrough(const [
        Cell(0, 0),
        Cell(0, 1),
        Cell(0, 2),
        Cell(0, 3),
        Cell(0, 4),
      ]);

      // Caller passes only the words still outstanding.
      expect(releaseOn(state, const ['WIND']).matchedWord, isNull);
    });

    test('matching is case- and whitespace-insensitive via the normalizer', () {
      final state = dragThrough(const [
        Cell(0, 0),
        Cell(0, 1),
        Cell(0, 2),
        Cell(0, 3),
        Cell(0, 4),
      ]);

      expect(releaseOn(state, const ['  water  ']).matchedWord, 'WATER');
    });
  });

  group('Urdu — right-to-left', () {
    // پانی placed running WEST from column 3, so the row reads (col 0..3):
    // ی ن ا پ
    final urduGrid = [
      const ['ی', 'ن', 'ا', 'پ'],
      const ['ب', 'د', 'ر', 'م'],
      const ['ک', 'ل', 'س', 'ت'],
      const ['ہ', 'و', 'گ', 'ز'],
    ];
    const urduResolver = SelectionResolver(size: 4);

    test('a horizontal Urdu drag runs right-to-left and matches', () {
      var state = urduResolver.begin(GridPoint.centerOf(const Cell(0, 3)));
      for (final col in [2, 1, 0]) {
        state = urduResolver.extendTo(state, GridPoint.centerOf(Cell(0, col)));
      }

      expect(state.direction, GridVector.west);
      // The column index decreases as the word is traced (Ch04, Masla 5).
      for (var i = 1; i < state.cells.length; i++) {
        expect(state.cells[i].col, lessThan(state.cells[i - 1].col));
      }

      final outcome = urduResolver.release(
        state: state,
        grid: urduGrid,
        remainingWords: const ['پانی'],
        language: Language.urdu,
      );
      expect(outcome.matchedWord, 'پانی');
    });

    test('the same word typed on an Arabic keyboard still matches', () {
      var state = urduResolver.begin(GridPoint.centerOf(const Cell(0, 3)));
      for (final col in [2, 1, 0]) {
        state = urduResolver.extendTo(state, GridPoint.centerOf(Cell(0, col)));
      }

      // Arabic Yeh U+064A instead of Farsi Yeh U+06CC.
      final arabicSpelling = String.fromCharCodes([
        0x067E,
        0x0627,
        0x0646,
        0x064A,
      ]);

      final outcome = urduResolver.release(
        state: state,
        grid: urduGrid,
        remainingWords: [arabicSpelling],
        language: Language.urdu,
      );
      expect(outcome.matchedWord, 'پانی');
    });
  });

  group('Hindi — multi-codepoint aksharas', () {
    // Each cell holds ONE akshara, so "पानी" is two cells, not four.
    final hindiGrid = [
      const ['पा', 'नी', 'क'],
      const ['र', 'म', 'स'],
      const ['त', 'न', 'ल'],
    ];
    const hindiResolver = SelectionResolver(size: 3);

    test('a two-cell drag spells a four-code-point word', () {
      var state = hindiResolver.begin(GridPoint.centerOf(const Cell(0, 0)));
      state = hindiResolver.extendTo(
        state,
        GridPoint.centerOf(const Cell(0, 1)),
      );

      expect(state.cells, hasLength(2));

      final outcome = hindiResolver.release(
        state: state,
        grid: hindiGrid,
        remainingWords: const ['पानी'],
        language: Language.hindi,
      );

      expect(outcome.matchedWord, 'पानी');
      expect(
        outcome.cells,
        hasLength(2),
        reason: 'two cells, though the word is four code points',
      );
      expect('पानी'.runes.length, 4, reason: 'the naive count this avoids');
    });

    test('a Hindi word traced backwards also matches', () {
      var state = hindiResolver.begin(GridPoint.centerOf(const Cell(0, 1)));
      state = hindiResolver.extendTo(
        state,
        GridPoint.centerOf(const Cell(0, 0)),
      );

      final outcome = hindiResolver.release(
        state: state,
        grid: hindiGrid,
        remainingWords: const ['पानी'],
        language: Language.hindi,
      );

      expect(outcome.matchedWord, 'पानी');
      expect(outcome.cells.first, const Cell(0, 0));
    });
  });
}
