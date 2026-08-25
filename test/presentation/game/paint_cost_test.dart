import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/domain/grid/cell.dart';
import 'package:word_search_master/domain/grid/grid_directions.dart';
import 'package:word_search_master/domain/grid/grid_generator.dart';
import 'package:word_search_master/domain/grid/grid_vector.dart';
import 'package:word_search_master/domain/grid/selection_resolver.dart';
import 'package:word_search_master/domain/text/language.dart';
import 'package:word_search_master/presentation/game/grapheme_painter_cache.dart';
import 'package:word_search_master/presentation/game/grid_geometry.dart';
import 'package:word_search_master/presentation/game/grid_painter.dart';

/// Measures what each paint pass actually costs.
///
/// Wall-clock numbers vary by machine, so the ASSERTION here is a ratio, which
/// does not: the live selection layer must be dramatically cheaper to paint
/// than the full grid of letters. That ratio is the entire justification for
/// splitting the passes, and it is what protects the frame budget on a 2GB
/// phone. The absolute numbers are printed for whoever is profiling.
void main() {
  const gridSize = 12;
  const canvasSize = Size(480, 480);
  const iterations = 60;

  late List<List<String>> cells;
  late GridGeometry geometry;

  setUpAll(() {
    cells = GridGenerator.generate(
      seed: 4242,
      size: gridSize,
      words: const ['WATER', 'STONE', 'RIVER', 'FOREST', 'LIGHT', 'EARTH'],
      lang: Language.english,
      allowedDirections: GridDirections.forLanguage(
        Language.english,
        DirectionTier.all,
      ),
    ).cells;
    geometry = GridGeometry.fit(size: gridSize, available: canvasSize);
  });

  /// Per-call cost, taken as the FASTEST of several batches rather than the
  /// mean of one.
  ///
  /// `flutter test` runs files in parallel, so any single batch can be
  /// preempted mid-measurement. Noise only ever ADDS time, so the minimum is
  /// the sample least polluted by the scheduler — and it is the ratio between
  /// two such minima that this file asserts on. Averaging instead made the
  /// ratio swing between 26x and 92x run to run, and occasionally dip under
  /// the threshold with nothing about the rendering code having changed.
  double timeMicros(
    void Function() body, {
    int runs = iterations,
    int batches = 5,
  }) {
    // Warm up first so JIT and lazy allocation are not counted.
    for (var i = 0; i < 5; i++) {
      body();
    }

    var best = double.infinity;
    for (var batch = 0; batch < batches; batch++) {
      final stopwatch = Stopwatch()..start();
      for (var i = 0; i < runs; i++) {
        body();
      }
      stopwatch.stop();
      best = min(best, stopwatch.elapsedMicroseconds / runs);
    }
    return best;
  }

  void paintOnce(CustomPainter painter) {
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), canvasSize);
    recorder.endRecording().dispose();
  }

  test(
    'the selection layer is far cheaper to paint than the letters layer',
    () {
      final cache = GraphemePainterCache();

      final letters = GridLettersPainter(
        cells: cells,
        geometry: geometry,
        textStyle: const TextStyle(fontSize: 18, color: Color(0xFF000000)),
        cellColor: const Color(0xFF111111),
        cornerRadius: 4,
        cache: cache,
        textDirection: TextDirection.ltr,
      );

      final selection = ValueNotifier<SelectionState>(
        const SelectionState(
          anchor: Cell(5, 2),
          direction: GridVector.east,
          cells: [Cell(5, 2), Cell(5, 3), Cell(5, 4), Cell(5, 5), Cell(5, 6)],
        ),
      );
      addTearDown(selection.dispose);

      final selectionPainter = SelectionPainter(
        selection: selection,
        geometry: geometry,
        color: const Color(0xFFE8A33D),
        borderWidth: 2.5,
      );

      final lettersUs = timeMicros(() => paintOnce(letters));
      final selectionUs = timeMicros(() => paintOnce(selectionPainter));

      // ignore: avoid_print
      print(
        'paint cost per call (12x12, warm cache): '
        'letters ${(lettersUs / 1000).toStringAsFixed(3)}ms · '
        'selection ${(selectionUs / 1000).toStringAsFixed(3)}ms · '
        'ratio ${(lettersUs / selectionUs).toStringAsFixed(1)}x',
      );

      expect(
        lettersUs / selectionUs,
        greaterThan(5),
        reason:
            'if the live layer costs anything like a full grid repaint, the '
            'three-pass split has stopped buying anything',
      );

      // A loose absolute ceiling. Generous enough not to flake on a slow CI
      // box, tight enough that losing the cache — which would make this an
      // order of magnitude worse — trips it.
      expect(
        lettersUs / 1000,
        lessThan(16.0),
        reason: 'a full 144-glyph repaint should still fit in one frame',
      );
    },
  );

  test('painting the letters does not grow the cache after warm-up', () {
    // The per-frame guarantee, stated as a measurement: after the first paint,
    // repeated painting performs zero layouts no matter how many frames pass.
    final cache = GraphemePainterCache();
    final painter = GridLettersPainter(
      cells: cells,
      geometry: geometry,
      textStyle: const TextStyle(fontSize: 18, color: Color(0xFF000000)),
      cellColor: const Color(0xFF111111),
      cornerRadius: 4,
      cache: cache,
      textDirection: TextDirection.ltr,
    );

    paintOnce(painter);
    final entriesAfterFirst = cache.entryCount;
    cache.resetStats();

    for (var i = 0; i < 120; i++) {
      paintOnce(painter);
    }

    expect(cache.misses, 0);
    expect(cache.entryCount, entriesAfterFirst);
    expect(cache.hits, 120 * gridSize * gridSize);
  });
}
