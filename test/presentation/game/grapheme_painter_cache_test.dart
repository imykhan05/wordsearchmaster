import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/domain/grid/grid_directions.dart';
import 'package:word_search_master/domain/grid/grid_generator.dart';
import 'package:word_search_master/domain/text/language.dart';
import 'package:word_search_master/presentation/game/grapheme_painter_cache.dart';
import 'package:word_search_master/presentation/game/grid_geometry.dart';
import 'package:word_search_master/presentation/game/grid_painter.dart';

/// Verifies the P06 criterion — "TextPainter cache hit rate > 95%" — by
/// measuring it, on a real 12x12 grid, rather than asserting the cache exists.
void main() {
  const gridSize = 12;
  const canvasSize = Size(480, 480);

  List<List<String>> buildCells(Language language) {
    final result = GridGenerator.generate(
      seed: 4242,
      size: gridSize,
      words: switch (language) {
        Language.english => const [
          'WATER',
          'STONE',
          'RIVER',
          'FOREST',
          'LIGHT',
          'EARTH',
        ],
        Language.urdu => const ['پانی', 'بادل', 'زمین', 'دریا', 'سورج'],
        Language.hindi => const ['पानी', 'बादल', 'धरती', 'नदी', 'सूरज'],
      },
      lang: language,
      allowedDirections: GridDirections.forLanguage(
        language,
        DirectionTier.all,
      ),
    );
    return result.cells;
  }

  ({int paints, GraphemePainterCache cache}) paintTimes(
    int times, {
    Language language = Language.english,
  }) {
    final cells = buildCells(language);
    final cache = GraphemePainterCache();
    final painter = GridLettersPainter(
      cells: cells,
      geometry: GridGeometry.fit(size: gridSize, available: canvasSize),
      textStyle: const TextStyle(fontSize: 18, color: Color(0xFF000000)),
      cellColor: const Color(0xFF111111),
      cornerRadius: 4,
      cache: cache,
      textDirection: TextDirection.ltr,
    );

    for (var i = 0; i < times; i++) {
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), canvasSize);
      recorder.endRecording().dispose();
    }

    return (paints: times, cache: cache);
  }

  test('layout runs once per UNIQUE grapheme, not once per cell', () {
    // The trap this class exists to avoid: 144 layouts per frame.
    final cells = buildCells(Language.english);
    final unique = <String>{for (final row in cells) ...row}.length;

    final result = paintTimes(1);

    expect(result.cache.misses, unique);
    expect(result.cache.hits, gridSize * gridSize - unique);
    expect(
      unique,
      lessThan(gridSize * gridSize),
      reason: 'a 12x12 grid draws far fewer than 144 distinct letters',
    );
  });

  test('every paint after the first is 100% hits — zero layouts', () {
    final result = paintTimes(1);
    final missesAfterWarmup = result.cache.misses;

    result.cache.resetStats();

    final recorder = ui.PictureRecorder();
    GridLettersPainter(
      cells: buildCells(Language.english),
      geometry: GridGeometry.fit(size: gridSize, available: canvasSize),
      textStyle: const TextStyle(fontSize: 18, color: Color(0xFF000000)),
      cellColor: const Color(0xFF111111),
      cornerRadius: 4,
      cache: result.cache,
      textDirection: TextDirection.ltr,
    ).paint(Canvas(recorder), canvasSize);
    recorder.endRecording().dispose();

    expect(result.cache.misses, 0, reason: 'no layout on a warm cache');
    expect(result.cache.hitRate, 1.0);
    expect(missesAfterWarmup, greaterThan(0), reason: 'warm-up did happen');
  });

  for (final language in Language.values) {
    test('${language.code}: hit rate over a short session exceeds 95%', () {
      // Ten paints is a conservative stand-in for a level: the letters layer
      // repaints on rotation, theme change, or a rebuild, and every one of
      // those is free once the cache is warm.
      final result = paintTimes(10, language: language);

      expect(
        result.cache.hitRate,
        greaterThan(0.95),
        reason:
            '${language.code} hit rate was '
            '${(result.cache.hitRate * 100).toStringAsFixed(1)}%',
      );
      expect(result.cache.evictions, 0, reason: 'working set must fit');
    });
  }

  test('a different style is cached separately, not silently reused', () {
    // Otherwise a theme or cell-size change would paint stale glyphs.
    final cache = GraphemePainterCache();
    const small = TextStyle(fontSize: 12, color: Color(0xFF000000));
    const large = TextStyle(fontSize: 24, color: Color(0xFF000000));

    cache.get('A', style: small, textDirection: TextDirection.ltr);
    cache.get('A', style: large, textDirection: TextDirection.ltr);

    expect(cache.misses, 2);
    expect(cache.entryCount, 2);

    cache.get('A', style: small, textDirection: TextDirection.ltr);
    expect(cache.hits, 1);
  });

  test('the cache is bounded and reports eviction', () {
    final cache = GraphemePainterCache(maxEntries: 4);
    for (final letter in ['A', 'B', 'C', 'D', 'E', 'F']) {
      cache.get(
        letter,
        style: const TextStyle(fontSize: 12, color: Color(0xFF000000)),
        textDirection: TextDirection.ltr,
      );
    }

    expect(cache.entryCount, 4);
    expect(cache.evictions, 2);
  });
}
