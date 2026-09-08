import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../app/theme/theme.dart';
import '../../domain/grid/cell.dart';
import '../../domain/text/language.dart';
import 'grapheme_painter_cache.dart';
import 'grid_geometry.dart';

/// Where a flight starts and where it lands.
///
/// ---------------------------------------------------------------------------
/// WHY THIS EXISTS AT ALL — THE TWO ENDS ARE IN DIFFERENT SUBTREES
///
/// Every other animation on the game screen lives inside ONE coordinate space:
/// the particle burst, the found-word reveal and the live selection are all
/// drawn in the grid's own box, from cell positions `GridGeometry` already
/// hands out. This one is not. A letter leaves a grid cell and lands on its
/// word chip, which sits in a `Wrap` BELOW the grid card — a sibling subtree
/// with no shared geometry and a layout that reflows as chips wrap.
///
/// So the two ends have to be MEASURED rather than computed, and measuring
/// needs a handle on each end's render object. That is all this class is: the
/// grid's key, and a live map of which chip is currently rendering which word.
/// Chips register themselves on mount and unregister on dispose, so the map
/// never holds a word whose chip has gone (which is also what keeps it from
/// growing across 300 levels' worth of word lists).
///
/// Reading a render object is only safe once layout has run. Every caller here
/// resolves positions during a POINTER EVENT — `onSelectionReleased`, fired on
/// pointer-up — which is after layout by definition, so there is no frame where
/// these are asked for a box that does not exist yet.
final class WordFlightAnchors {
  /// Goes on `GameGrid` itself, so `cellCenter`'s coordinates and this box's
  /// local space are the same one — `game_grid_test.dart` pins that pairing
  /// (`getTopLeft(GameGrid) + geometry.cellCenter(cell)` is the global centre).
  final GlobalKey gridKey = GlobalKey();

  final Map<String, BuildContext> _chips = {};

  void registerChip(String word, BuildContext context) =>
      _chips[word] = context;

  /// Identity-checked so a chip disposing AFTER its replacement registered —
  /// the order two `_WordChip`s for the same word swap in during a level
  /// change — cannot delete the live one's entry.
  void unregisterChip(String word, BuildContext context) {
    if (identical(_chips[word], context)) _chips.remove(word);
  }

  RenderBox? get gridBox => _boxOf(gridKey.currentContext);

  RenderBox? chipBox(String word) => _boxOf(_chips[word]);

  static RenderBox? _boxOf(BuildContext? context) {
    if (context == null || !context.mounted) return null;
    final object = context.findRenderObject();
    return object is RenderBox && object.hasSize ? object : null;
  }
}

/// Fires letter flights. Held by the game screen and handed to
/// [WordFlightLayer] — same shape as `ParticleController`.
final class WordFlightController extends ChangeNotifier {
  final List<WordFlight> _pending = [];

  /// [graphemes] and [cells] are index-paired: `SelectionOutcome.cells` comes
  /// back RE-ORIENTED TO THE WORD (P05), so letter i really does live in cell
  /// i even when the player traced the word backwards.
  void fly({
    required String word,
    required List<String> graphemes,
    required List<Cell> cells,
    required GridGeometry geometry,
    required Language language,
    required Color color,
  }) {
    _pending.add(
      WordFlight(
        word: word,
        graphemes: graphemes,
        cells: cells,
        geometry: geometry,
        language: language,
        color: color,
      ),
    );
    notifyListeners();
  }

  List<WordFlight> takePending() {
    final taken = List<WordFlight>.from(_pending);
    _pending.clear();
    return taken;
  }
}

@immutable
final class WordFlight {
  const WordFlight({
    required this.word,
    required this.graphemes,
    required this.cells,
    required this.geometry,
    required this.language,
    required this.color,
  });

  final String word;
  final List<String> graphemes;
  final List<Cell> cells;
  final GridGeometry geometry;
  final Language language;
  final Color color;
}

/// The found word's letters lifting off the grid and landing on its chip, in
/// their own [RepaintBoundary] over both.
///
/// Decorative, not informational: the word is already struck through on its
/// chip and already capsuled on the grid whether or not this ever runs, so
/// reduce-motion SKIPS it outright rather than collapsing it to an instant
/// jump — the same treatment particles and confetti get, and for the same
/// reason.
///
/// Positions are captured ONCE, at spawn, as plain offsets. Nothing here holds
/// a render object past that moment, which is what makes the last word of a
/// level safe: `GameController`'s Zeigarnik swap replaces the whole word list
/// in the very next frame, and a flight already in the air simply finishes to
/// where its chip was rather than chasing a chip that no longer exists.
class WordFlightLayer extends StatefulWidget {
  const WordFlightLayer({
    required this.controller,
    required this.anchors,
    super.key,
  });

  final WordFlightController controller;
  final WordFlightAnchors anchors;

  /// One letter's own journey. Long enough to read as travel, short enough
  /// that the last letter of a nine-grapheme word still lands well before the
  /// player has found the next one.
  static const Duration letterDuration = Duration(milliseconds: 300);

  /// Gap between consecutive letters leaving, so the word streams off the
  /// grid in reading order instead of teleporting as a block.
  static const Duration letterStagger = Duration(milliseconds: 30);

  @override
  State<WordFlightLayer> createState() => _WordFlightLayerState();
}

class _WordFlightLayerState extends State<WordFlightLayer>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);

  final ValueNotifier<double> _clockMs = ValueNotifier<double>(0);
  final GraphemePainterCache _cache = GraphemePainterCache();

  final List<_LiveLetter> _letters = [];
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onFlightRequested);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
  }

  @override
  void didUpdateWidget(WordFlightLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onFlightRequested);
      widget.controller.addListener(_onFlightRequested);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onFlightRequested);
    _ticker.dispose();
    _clockMs.dispose();
    _cache.clear();
    super.dispose();
  }

  void _onFlightRequested() {
    final pending = widget.controller.takePending();
    if (_reduceMotion || pending.isEmpty) return;

    // A `Ticker`'s elapsed restarts at zero every time it is started, so a
    // clock still holding the LAST run's final value would date every new
    // letter into the future: `elapsed - startMs` stays negative until the
    // fresh ticker catches up, and the word would sit invisible for exactly
    // as long as the previous flight lasted. Rezeroing while idle is the
    // whole fix, and it is only safe here — mid-run the value is live.
    if (!_ticker.isActive) _clockMs.value = 0;

    for (final flight in pending) {
      _spawn(flight);
    }
    if (_letters.isNotEmpty && !_ticker.isActive) _ticker.start();
  }

  void _spawn(WordFlight flight) {
    // This layer's own box is the space every offset below is expressed in.
    final self = context.findRenderObject();
    final gridBox = widget.anchors.gridBox;
    final chipBox = widget.anchors.chipBox(flight.word);
    if (self is! RenderBox || !self.hasSize || gridBox == null) return;
    // No chip for this word means there is nowhere to fly TO, so nothing
    // flies — rather than inventing a destination off screen. In practice a
    // flight is requested from a pointer callback, before the frame that
    // could remove the chip, so this is a guard rather than a common path.
    if (chipBox == null) return;

    final target = self.globalToLocal(
      chipBox.localToGlobal(chipBox.size.center(Offset.zero)),
    );
    final style = AppTypography.gridTextStyle(
      flight.language,
      cellSize: flight.geometry.cellSize,
      color: flight.color,
    );
    final staggerMs = WordFlightLayer.letterStagger.inMilliseconds.toDouble();
    final now = _clockMs.value;

    final count = flight.graphemes.length < flight.cells.length
        ? flight.graphemes.length
        : flight.cells.length;

    for (var i = 0; i < count; i++) {
      final origin = self.globalToLocal(
        gridBox.localToGlobal(flight.geometry.cellCenter(flight.cells[i])),
      );
      _letters.add(
        _LiveLetter(
          grapheme: flight.graphemes[i],
          style: style,
          color: flight.color,
          from: origin,
          to: target,
          startMs: now + i * staggerMs,
        ),
      );
    }
  }

  void _onTick(Duration elapsed) {
    final nowMs = elapsed.inMicroseconds / 1000.0;
    final durationMs = WordFlightLayer.letterDuration.inMilliseconds.toDouble();

    _letters.removeWhere((letter) => nowMs - letter.startMs >= durationMs);
    _clockMs.value = nowMs;

    if (_letters.isEmpty) _ticker.stop();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _WordFlightPainter(
          clockMs: _clockMs,
          letters: _letters,
          cache: _cache,
          durationMs: WordFlightLayer.letterDuration.inMilliseconds.toDouble(),
        ),
        size: Size.infinite,
      ),
    );
  }
}

final class _LiveLetter {
  const _LiveLetter({
    required this.grapheme,
    required this.style,
    required this.color,
    required this.from,
    required this.to,
    required this.startMs,
  });

  final String grapheme;
  final TextStyle style;

  /// The same token colour already on [style]. Carried separately because
  /// `TextStyle.color` is nullable and the painter needs a non-null one to
  /// build its opacity paint from — see `paint`'s saveLayer.
  final Color color;

  final Offset from;
  final Offset to;
  final double startMs;

  /// The arc's control point: the straight line's midpoint, lifted against
  /// gravity. A letter that rises before it falls reads as thrown; a letter
  /// sliding down the straight line reads as a UI transition.
  Offset get control {
    final mid = Offset((from.dx + to.dx) / 2, (from.dy + to.dy) / 2);
    final lift = ((to - from).distance * 0.22).clamp(12.0, 64.0);
    return mid.translate(0, -lift);
  }
}

final class _WordFlightPainter extends CustomPainter {
  _WordFlightPainter({
    required this.clockMs,
    required this.letters,
    required this.cache,
    required this.durationMs,
  }) : super(repaint: clockMs);

  final ValueNotifier<double> clockMs;
  final List<_LiveLetter> letters;
  final GraphemePainterCache cache;
  final double durationMs;

  /// Where the letter starts fading. It arrives and is absorbed into the chip
  /// rather than blinking out on top of it.
  static const double _fadeFrom = 0.65;

  /// Size at landing, as a fraction of the grid's own letter size — a chip's
  /// text is smaller than a cell's, so shrinking on the way is what makes the
  /// two ends look like the same letter.
  static const double _endScale = 0.55;

  @override
  void paint(Canvas canvas, Size size) {
    if (letters.isEmpty) return;

    final now = clockMs.value;

    for (final letter in letters) {
      final elapsed = now - letter.startMs;
      // Staggered letters are in the list before their own turn comes.
      if (elapsed < 0) continue;

      final t = (elapsed / durationMs).clamp(0.0, 1.0);
      final eased = Motion.fade.transform(t);
      final position = _pointOn(letter, eased);

      final scale = 1.0 - (1.0 - _endScale) * Motion.settle.transform(t);
      final opacity = t <= _fadeFrom
          ? 1.0
          : 1.0 - (t - _fadeFrom) / (1 - _fadeFrom);

      final painter = cache.get(
        letter.grapheme,
        style: letter.style,
        textDirection: TextDirection.ltr,
      );

      canvas.save();
      canvas.translate(position.dx, position.dy);
      canvas.scale(scale);
      // saveLayer rather than a colour override on the style: the cache keys
      // on the style, so fading by colour would mint a fresh TextPainter (and
      // a fresh layout) on every frame of every letter.
      //
      // Only the paint's ALPHA is read here — srcOver composites the layer
      // through it — so the letter's own token colour is reused rather than a
      // literal white, which is also what keeps `check_no_raw_colors` happy.
      canvas.saveLayer(
        Rect.fromCenter(
          center: Offset.zero,
          width: painter.width + 2,
          height: painter.height + 2,
        ),
        Paint()..color = letter.color.withValues(alpha: opacity),
      );
      painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
      canvas.restore();
      canvas.restore();
    }
  }

  /// Quadratic bezier, so the letter arcs instead of sliding.
  Offset _pointOn(_LiveLetter letter, double t) {
    final inverse = 1 - t;
    final control = letter.control;
    return Offset(
      inverse * inverse * letter.from.dx +
          2 * inverse * t * control.dx +
          t * t * letter.to.dx,
      inverse * inverse * letter.from.dy +
          2 * inverse * t * control.dy +
          t * t * letter.to.dy,
    );
  }

  @override
  bool shouldRepaint(_WordFlightPainter old) =>
      !identical(old.letters, letters) ||
      old.durationMs != durationMs ||
      !identical(old.clockMs, clockMs);
}
