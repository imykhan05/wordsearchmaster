import 'dart:math';

import 'cell.dart';
import 'grid_result.dart';
import 'grid_vector.dart';

/// What [WordPlacer.place] achieved.
final class PlacementOutcome {
  const PlacementOutcome({
    required this.placements,
    required this.unplaced,
    required this.attempts,
    required this.letters,
    required this.occupiedCells,
  });

  final List<WordPlacement> placements;
  final List<String> unplaced;
  final int attempts;

  /// Total graphemes across all placed words, counting a shared cell once per
  /// word that uses it.
  final int letters;

  /// Distinct cells the placed words occupy.
  final int occupiedCells;

  bool get isComplete => unplaced.isEmpty;

  /// Fraction of placed letters sitting on a shared cell. See
  /// [GridResult.intersectionRatio].
  double get intersectionRatio =>
      letters == 0 ? 0 : 1 - (occupiedCells / letters);
}

/// Places words into a square grid by randomised search with backtracking.
///
/// PURE DART. Every random draw comes from the injected [Random], so a given
/// seed always produces the same grid — the whole content model depends on it
/// (Ch06: store seeds, not grids).
///
/// Never throws and never loops forever. If a word set cannot be satisfied the
/// placer gives up and reports it in [PlacementOutcome.unplaced]; growing the
/// grid and retrying is [GridGenerator]'s job.
final class WordPlacer {
  WordPlacer({
    required this.size,
    required this.random,
    this.maxAttemptsPerWord = 220,
    this.maxBacktracks = 200,
    this.crossingBias = 0.85,
  });

  final int size;
  final Random random;

  /// How often an attempt is *seeded from a crossing* rather than thrown at a
  /// uniformly random cell.
  ///
  /// This matters more than it sounds. Sampling start positions uniformly
  /// almost never lands on an existing letter — on a 6x6 grid holding one
  /// 5-letter word, 31 of 36 cells are empty — so blind sampling produced a
  /// median intersectionRatio near 0.13 and left many grids with no crossings
  /// at all, well under the Ch06 target band. Seeding instead picks a letter
  /// of the incoming word, finds a cell already holding that grapheme, and
  /// aligns the word onto it. The attempts stay randomised and bounded; they
  /// are just drawn from a distribution that can actually succeed.
  final double crossingBias;

  /// Randomised (position, direction) tries per word before the placer
  /// concludes this word does not fit and backtracks. Ch06 specifies 220.
  final int maxAttemptsPerWord;

  /// Total backtracks allowed across the whole run. Bounding this is what
  /// makes "never loop forever" true — without it a pathological word set can
  /// thrash between two words indefinitely.
  final int maxBacktracks;

  late List<List<String?>> _grid;

  /// How many placed words use each cell, so erasing one word does not blank
  /// a cell another word is still sharing.
  late List<List<int>> _refs;

  /// Grapheme → the cells currently holding it. Maintained incrementally so
  /// crossing-seeded attempts are cheap.
  late Map<String, List<Cell>> _byGrapheme;

  int _attempts = 0;

  /// Places [words] (each already normalized and split into graphemes) along
  /// [directions].
  ///
  /// [words] must be ordered longest-first: long words have the fewest legal
  /// positions, so placing them while the grid is empty is what makes the
  /// search tractable.
  PlacementOutcome place(
    List<List<String>> words,
    List<GridVector> directions,
  ) {
    _grid = List.generate(size, (_) => List<String?>.filled(size, null));
    _refs = List.generate(size, (_) => List<int>.filled(size, 0));
    _byGrapheme = {};
    _attempts = 0;

    if (words.isEmpty || directions.isEmpty) {
      return PlacementOutcome(
        placements: const [],
        unplaced: [for (final word in words) word.join()],
        attempts: 0,
        letters: 0,
        occupiedCells: 0,
      );
    }

    final placed = List<_Candidate?>.filled(words.length, null);

    // Placements already rejected at each index. A backtrack adds the
    // placement it just undid, so the retry is genuinely a DIFFERENT position
    // and every backtrack makes progress rather than re-deriving the same
    // dead end.
    final forbidden = List.generate(words.length, (_) => <String>{});

    var index = 0;
    var backtracks = 0;

    while (index < words.length) {
      final candidate = _findPlacement(
        words[index],
        directions,
        forbidden[index],
      );

      if (candidate != null) {
        _write(words[index], candidate);
        placed[index] = candidate;
        index++;
        // Arriving at the next index forward: its old rejections were about a
        // different grid, so they no longer apply.
        if (index < words.length) forbidden[index].clear();
        continue;
      }

      if (index == 0 || backtracks >= maxBacktracks) break;

      backtracks++;
      index--;
      final undone = placed[index]!;
      _erase(undone);
      forbidden[index].add(undone.key);
      placed[index] = null;
    }

    final placements = <WordPlacement>[];
    final unplaced = <String>[];
    final occupied = <Cell>{};
    var letters = 0;

    for (var i = 0; i < words.length; i++) {
      final candidate = placed[i];
      if (candidate == null) {
        unplaced.add(words[i].join());
        continue;
      }
      placements.add(
        WordPlacement(
          word: words[i].join(),
          graphemes: List.unmodifiable(words[i]),
          direction: candidate.direction,
          cells: List.unmodifiable(candidate.cells),
        ),
      );
      letters += words[i].length;
      occupied.addAll(candidate.cells);
    }

    return PlacementOutcome(
      placements: placements,
      unplaced: unplaced,
      attempts: _attempts,
      letters: letters,
      occupiedCells: occupied.length,
    );
  }

  /// The grid as placed so far — `null` for cells no word occupies. The
  /// filler strategy fills those.
  List<List<String?>> get grid => _grid;

  _Candidate? _findPlacement(
    List<String> graphemes,
    List<GridVector> directions,
    Set<String> forbidden,
  ) {
    // Overlaps are the point: they are what makes a word search feel woven
    // rather than like a list of words dropped on a page, and they are what
    // holds intersectionRatio in the Ch06 band. Sampling randomly among all
    // legal placements yields a median ratio around 0.13 — below the band —
    // so the search keeps the BEST-crossing candidates it saw and picks among
    // those, tie-broken randomly to preserve variety.
    final candidates = <_Candidate>[];
    var bestOverlaps = 0;

    for (var attempt = 0; attempt < maxAttemptsPerWord; attempt++) {
      _attempts++;
      final direction = directions[random.nextInt(directions.length)];

      final start =
          (random.nextDouble() < crossingBias
              ? _crossingStart(graphemes, direction)
              : null) ??
          Cell(random.nextInt(size), random.nextInt(size));

      final candidate = _evaluate(graphemes, start, direction);
      if (candidate == null || forbidden.contains(candidate.key)) continue;

      if (candidate.overlaps > bestOverlaps) {
        bestOverlaps = candidate.overlaps;
        candidates
          ..clear()
          ..add(candidate);
      } else if (candidate.overlaps == bestOverlaps) {
        candidates.add(candidate);
      }
    }

    if (candidates.isEmpty) return null;
    return candidates[random.nextInt(candidates.length)];
  }

  /// A start position that lands one of [graphemes] on a cell already holding
  /// that same grapheme, so the placement crosses an existing word.
  ///
  /// Returns null when the grid holds none of this word's letters yet — the
  /// first word placed, or a word sharing no letter with what is down.
  Cell? _crossingStart(List<String> graphemes, GridVector direction) {
    final letterIndex = random.nextInt(graphemes.length);
    final occupied = _byGrapheme[graphemes[letterIndex]];
    if (occupied == null || occupied.isEmpty) return null;

    final pivot = occupied[random.nextInt(occupied.length)];
    // Walk back so the chosen letter lands exactly on the pivot cell.
    return pivot.stepBy(direction, -letterIndex);
  }

  /// A placement is legal when every target cell is either empty or already
  /// holds the identical grapheme.
  _Candidate? _evaluate(
    List<String> graphemes,
    Cell start,
    GridVector direction,
  ) {
    final cells = <Cell>[];
    var overlaps = 0;

    for (var i = 0; i < graphemes.length; i++) {
      final cell = start.stepBy(direction, i);
      if (!cell.isInside(size)) return null;

      final existing = _grid[cell.row][cell.col];
      if (existing != null) {
        if (existing != graphemes[i]) return null;
        overlaps++;
      }
      cells.add(cell);
    }

    return _Candidate(cells: cells, direction: direction, overlaps: overlaps);
  }

  void _write(List<String> graphemes, _Candidate candidate) {
    for (var i = 0; i < graphemes.length; i++) {
      final cell = candidate.cells[i];
      final wasEmpty = _refs[cell.row][cell.col] == 0;

      _grid[cell.row][cell.col] = graphemes[i];
      _refs[cell.row][cell.col]++;

      if (wasEmpty) {
        (_byGrapheme[graphemes[i]] ??= <Cell>[]).add(cell);
      }
    }
  }

  void _erase(_Candidate candidate) {
    for (final cell in candidate.cells) {
      _refs[cell.row][cell.col]--;
      if (_refs[cell.row][cell.col] == 0) {
        final grapheme = _grid[cell.row][cell.col];
        _grid[cell.row][cell.col] = null;
        _byGrapheme[grapheme]?.remove(cell);
      }
    }
  }
}

final class _Candidate {
  _Candidate({
    required this.cells,
    required this.direction,
    required this.overlaps,
  });

  final List<Cell> cells;
  final GridVector direction;
  final int overlaps;

  /// Identifies this exact placement, for the forbidden-set bookkeeping.
  String get key =>
      '${cells.first.row},${cells.first.col},${direction.dx},${direction.dy}';
}
