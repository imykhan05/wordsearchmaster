import 'dart:math';

import '../text/language.dart';
import '../text/script_normalizer.dart';
import 'cell.dart';
import 'filler_strategy.dart';
import 'grid_result.dart';
import 'grid_vector.dart';
import 'word_placer.dart';

/// Builds a complete word-search grid from a seed.
///
/// PURE DART — the entire game brain runs and is tested without a device.
///
/// Grids are never stored: a level is a seed plus its word list, and this
/// rebuilds the identical grid on every device, every install, forever
/// (Ch06). That is also what lets the Daily Challenge work offline with no
/// server — the date is the seed.
///
/// NOTE ON THE SIGNATURE: Ch06 writes `allowedDirections` as `List<Offset>`.
/// This takes [GridVector] instead, because `Offset` comes from `dart:ui` and
/// `lib/domain/` must stay runnable as plain Dart (CLAUDE.md → Architecture).
/// Grid movement is discrete anyway. `LanguageX.gridPrimaryDirection` in the
/// app layer converts for painting and hit-testing.
abstract final class GridGenerator {
  /// How many times the grid may grow by one before the generator settles for
  /// the best partial result it found.
  static const int defaultMaxGrowth = 6;

  /// Absolute ceiling on side length, so a corrupt level definition cannot
  /// make this allocate unboundedly.
  static const int maxSize = 40;

  /// Blocklist re-roll passes. Re-rolling a cell can itself create a new
  /// accidental word, so the scan repeats — but only a bounded number of
  /// times.
  static const int maxBlocklistPasses = 12;

  /// The healthy intersection band from Ch06. Below it the words sit in
  /// isolation and the puzzle solves itself; above it the grid turns to mush.
  static const double minIntersectionRatio = 0.15;
  static const double maxIntersectionRatio = 0.30;

  /// How many complete grids to build before choosing one.
  ///
  /// Ch06 says to SCORE the grid, not merely to produce one — and measurement
  /// says why that matters: a single randomised run lands inside the band only
  /// about 56% of the time. Building candidates and keeping the best-scoring
  /// one takes that to ~92% across the Ch07 curve. The search stops the moment
  /// a candidate is both complete and in band, so the common case pays for one
  /// or two, not twenty.
  static const int defaultGridCandidates = 20;

  /// Generates the grid for one level.
  ///
  /// Never throws and never loops forever. When a word set cannot be
  /// satisfied even after growing the grid, the words that did not fit are
  /// reported in [GridResult.unplacedWords] rather than raised — a player
  /// mid-session must never eat an exception from bad content.
  static GridResult generate({
    required int seed,
    required int size,
    required List<String> words,
    required Language lang,
    required List<GridVector> allowedDirections,
    Set<String> blocklist = const {},
    int maxGrowth = defaultMaxGrowth,
    int gridCandidates = defaultGridCandidates,
  }) {
    // One RNG for the whole run, drawn from in a fixed order. This is the
    // entire basis of determinism — nothing here may use any other source of
    // randomness, or the same seed would stop meaning the same grid.
    final random = Random(seed);

    final entries = _prepareWords(words, lang);
    final graphemeLists = [for (final entry in entries) entry.graphemes];

    final longest = graphemeLists.fold<int>(
      0,
      (longest, word) => max(longest, word.length),
    );
    // A word can never fit in a grid shorter than itself.
    final startSize = min(max(max(size, 1), longest), maxSize);

    PlacementOutcome? best;
    List<List<String?>>? bestGrid;
    var bestSize = startSize;
    var totalAttempts = 0;

    var settled = false;

    for (var grow = 0; grow <= maxGrowth && !settled; grow++) {
      final currentSize = min(startSize + grow, maxSize);

      for (var candidate = 0; candidate < gridCandidates; candidate++) {
        final placer = WordPlacer(size: currentSize, random: random);
        final outcome = placer.place(graphemeLists, allowedDirections);
        totalAttempts += outcome.attempts;

        if (best == null || _isBetter(outcome, best)) {
          best = outcome;
          bestGrid = placer.grid;
          bestSize = currentSize;
        }

        // Good enough: every word placed and the grid reads well. Stop paying
        // for candidates nobody will use.
        if (outcome.isComplete &&
            _bandDistance(outcome.intersectionRatio) == 0) {
          settled = true;
          break;
        }
      }

      // Every word fits at this size, so growing would only make the puzzle
      // emptier. Keep the best candidate we found.
      if (best!.isComplete) break;
      if (currentSize == maxSize) break;
    }

    final outcome = best!;
    final cells = _fill(
      grid: bestGrid!,
      size: bestSize,
      language: lang,
      words: graphemeLists,
      random: random,
    );

    _rerollAccidentalWords(
      cells: cells,
      size: bestSize,
      language: lang,
      blocklist: blocklist,
      placements: outcome.placements,
      words: graphemeLists,
      random: random,
    );

    return GridResult(
      size: bestSize,
      cells: cells,
      placementDetails: outcome.placements,
      intersectionRatio: outcome.intersectionRatio,
      attempts: totalAttempts,
      unplacedWords: outcome.unplaced,
    );
  }

  /// Ranks two candidate grids. Placing every word always beats a prettier
  /// ratio — a missing word is a broken level, a dull ratio is only a dull
  /// level.
  static bool _isBetter(
    PlacementOutcome candidate,
    PlacementOutcome incumbent,
  ) {
    if (candidate.placements.length != incumbent.placements.length) {
      return candidate.placements.length > incumbent.placements.length;
    }
    return _bandDistance(candidate.intersectionRatio) <
        _bandDistance(incumbent.intersectionRatio);
  }

  /// How far a ratio sits outside the healthy band; zero when inside it.
  static double _bandDistance(double ratio) {
    if (ratio < minIntersectionRatio) return minIntersectionRatio - ratio;
    if (ratio > maxIntersectionRatio) return ratio - maxIntersectionRatio;
    return 0;
  }

  /// Normalizes, drops empties, de-duplicates and orders the word list.
  ///
  /// Longest-first is not a nicety: long words have the fewest legal
  /// positions, so placing them into an empty grid is what keeps the search
  /// from thrashing. Ties break on the word itself so the ordering is total
  /// and the result stays deterministic — Dart's sort is not stable.
  static List<_WordEntry> _prepareWords(List<String> words, Language language) {
    final seen = <String>{};
    final entries = <_WordEntry>[];

    for (final raw in words) {
      final normalized = ScriptNormalizer.normalize(raw, language);
      if (normalized.isEmpty || !seen.add(normalized)) continue;
      entries.add(
        _WordEntry(
          word: normalized,
          graphemes: ScriptNormalizer.graphemes(normalized, language),
        ),
      );
    }

    entries.sort((a, b) {
      final byLength = b.graphemes.length.compareTo(a.graphemes.length);
      return byLength != 0 ? byLength : a.word.compareTo(b.word);
    });

    return entries;
  }

  static List<List<String>> _fill({
    required List<List<String?>> grid,
    required int size,
    required Language language,
    required List<List<String>> words,
    required Random random,
  }) {
    final filler = FillerStrategy(
      language: language,
      words: words,
      random: random,
    );

    return [
      for (var row = 0; row < size; row++)
        [for (var col = 0; col < size; col++) grid[row][col] ?? filler.next()],
    ];
  }

  /// Scans every line for blocklisted words and re-rolls the filler cells that
  /// formed them.
  ///
  /// This step is not optional. Random letters WILL eventually spell something
  /// offensive, and when they do it becomes a screenshot and a one-star review
  /// (Ch06). Only filler cells are re-rolled — a cell belonging to a real word
  /// placement is left alone, so fixing the noise never breaks the puzzle.
  static void _rerollAccidentalWords({
    required List<List<String>> cells,
    required int size,
    required Language language,
    required Set<String> blocklist,
    required List<WordPlacement> placements,
    required List<List<String>> words,
    required Random random,
  }) {
    if (blocklist.isEmpty) return;

    final banned = <List<String>>[
      for (final entry in blocklist)
        if (ScriptNormalizer.normalize(entry, language).isNotEmpty)
          ScriptNormalizer.graphemes(entry, language),
    ];
    if (banned.isEmpty) return;

    final protectedCells = <Cell>{
      for (final placement in placements) ...placement.cells,
    };

    final filler = FillerStrategy(
      language: language,
      words: words,
      random: random,
    );
    final lines = _lines(size);

    for (var pass = 0; pass < maxBlocklistPasses; pass++) {
      var dirty = false;

      for (final line in lines) {
        final graphemes = [for (final cell in line) cells[cell.row][cell.col]];

        for (final word in banned) {
          // Both directions: a blocklisted word reads just as badly backwards.
          for (final reversed in const [false, true]) {
            final haystack = reversed ? graphemes.reversed.toList() : graphemes;
            final cellsInOrder = reversed ? line.reversed.toList() : line;

            final at = _indexOfSequence(haystack, word);
            if (at == -1) continue;

            final match = cellsInOrder.sublist(at, at + word.length);
            final rerollable = [
              for (final cell in match)
                if (!protectedCells.contains(cell)) cell,
            ];
            // Formed entirely by real word placements — nothing safe to
            // change, so leave the puzzle intact and move on.
            if (rerollable.isEmpty) continue;

            final target = rerollable[random.nextInt(rerollable.length)];
            cells[target.row][target.col] = filler.next();
            dirty = true;
          }
        }
      }

      if (!dirty) return;
    }
  }

  /// Every line a word could be read along: rows, columns and both diagonal
  /// families. Each is returned once; the caller checks it in both directions.
  static List<List<Cell>> _lines(int size) {
    final lines = <List<Cell>>[];

    for (var row = 0; row < size; row++) {
      lines.add([for (var col = 0; col < size; col++) Cell(row, col)]);
    }
    for (var col = 0; col < size; col++) {
      lines.add([for (var row = 0; row < size; row++) Cell(row, col)]);
    }

    // Down-right diagonals, anchored on the left column and the top row.
    for (var row = 0; row < size; row++) {
      lines.add(_ray(Cell(row, 0), GridVector.southEast, size));
    }
    for (var col = 1; col < size; col++) {
      lines.add(_ray(Cell(0, col), GridVector.southEast, size));
    }

    // Down-left diagonals, anchored on the right column and the top row.
    for (var row = 0; row < size; row++) {
      lines.add(_ray(Cell(row, size - 1), GridVector.southWest, size));
    }
    for (var col = size - 2; col >= 0; col--) {
      lines.add(_ray(Cell(0, col), GridVector.southWest, size));
    }

    return [
      for (final line in lines)
        if (line.length > 1) line,
    ];
  }

  static List<Cell> _ray(Cell start, GridVector direction, int size) {
    final cells = <Cell>[];
    var cell = start;
    while (cell.isInside(size)) {
      cells.add(cell);
      cell = cell.step(direction);
    }
    return cells;
  }

  static int _indexOfSequence(List<String> haystack, List<String> needle) {
    if (needle.isEmpty || needle.length > haystack.length) return -1;

    outer:
    for (var i = 0; i <= haystack.length - needle.length; i++) {
      for (var j = 0; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) continue outer;
      }
      return i;
    }
    return -1;
  }
}

final class _WordEntry {
  const _WordEntry({required this.word, required this.graphemes});

  final String word;
  final List<String> graphemes;
}
