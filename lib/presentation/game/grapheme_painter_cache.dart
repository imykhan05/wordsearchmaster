import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

/// Laid-out [TextPainter]s, cached per grapheme and style.
///
/// THE SINGLE BIGGEST PERFORMANCE TRAP in this app is calling `layout()` inside
/// `paint()`. A 12x12 grid is 144 glyphs; laying each out every frame is ~8600
/// layouts a second at 60fps, and on a 2GB phone that alone misses the frame
/// budget. Layout happens once per unique grapheme, then every subsequent frame
/// only paints.
///
/// A word-search grid is the ideal case for this: 144 cells draw from a few
/// dozen distinct letters, so the cache is warm within one frame and stays
/// warm for the whole level. [hitRate] is instrumented so that claim is
/// measured rather than assumed.
final class GraphemePainterCache {
  GraphemePainterCache({this.maxEntries = 512});

  /// Bounded so a long session cannot grow it without limit. Far larger than
  /// any single script's working set, so eviction should never happen in
  /// practice — if it does, [evictions] says so.
  final int maxEntries;

  final Map<_CacheKey, TextPainter> _painters = {};

  int _hits = 0;
  int _misses = 0;
  int _evictions = 0;

  int get hits => _hits;
  int get misses => _misses;
  int get evictions => _evictions;
  int get entryCount => _painters.length;

  /// Fraction of lookups served without a layout. The P06 acceptance criterion
  /// is > 0.95.
  double get hitRate {
    final total = _hits + _misses;
    return total == 0 ? 1 : _hits / total;
  }

  void resetStats() {
    _hits = 0;
    _misses = 0;
    _evictions = 0;
  }

  void clear() {
    _painters.clear();
    resetStats();
  }

  /// The laid-out painter for [grapheme] in [style], laying out only on a miss.
  ///
  /// The returned painter is owned by the cache — paint it, never dispose it.
  TextPainter get(
    String grapheme, {
    required TextStyle style,
    required TextDirection textDirection,
  }) {
    final key = _CacheKey(
      grapheme: grapheme,
      fontFamily: style.fontFamily,
      fontSize: style.fontSize,
      fontWeight: style.fontWeight,
      color: style.color,
      height: style.height,
      textDirection: textDirection,
    );

    final cached = _painters[key];
    if (cached != null) {
      _hits++;
      return cached;
    }

    _misses++;
    if (_painters.length >= maxEntries) {
      // Dart maps preserve insertion order, so the first key is the oldest.
      _painters.remove(_painters.keys.first);
      _evictions++;
    }

    final painter = TextPainter(
      text: TextSpan(text: grapheme, style: style),
      textDirection: textDirection,
      // Grid cells opt out of system text scaling: the grid scales by cell
      // size, and OS scaling on top would overflow cells (P02).
      textScaler: TextScaler.noScaling,
      maxLines: 1,
    )..layout();

    _painters[key] = painter;
    return painter;
  }
}

@immutable
final class _CacheKey {
  const _CacheKey({
    required this.grapheme,
    required this.fontFamily,
    required this.fontSize,
    required this.fontWeight,
    required this.color,
    required this.height,
    required this.textDirection,
  });

  final String grapheme;
  final String? fontFamily;
  final double? fontSize;
  final FontWeight? fontWeight;
  final Color? color;
  final double? height;
  final TextDirection textDirection;

  @override
  bool operator ==(Object other) =>
      other is _CacheKey &&
      other.grapheme == grapheme &&
      other.fontFamily == fontFamily &&
      other.fontSize == fontSize &&
      other.fontWeight == fontWeight &&
      other.color == color &&
      other.height == height &&
      other.textDirection == textDirection;

  @override
  int get hashCode => Object.hash(
    grapheme,
    fontFamily,
    fontSize,
    fontWeight,
    color,
    height,
    textDirection,
  );
}
