import 'package:flutter/widgets.dart';

import '../../domain/grid/selection_resolver.dart';
import '../../services/haptics/haptics_service.dart';
import 'grid_geometry.dart';

/// Turns raw pointer events into a selection.
///
/// Uses a bare [Listener], not a [GestureDetector]: the grid needs every move
/// event, and it needs them without the arena delay a gesture recogniser adds
/// while it decides whether some other gesture wins. A drag across a grid is
/// not ambiguous — there is nothing to disambiguate against.
///
/// Cells are found by arithmetic on the pointer's LOCAL position through
/// [GridGeometry], the same geometry the painters use. No `GlobalKey`, no
/// per-cell hit-testing widget, and no way for touch and paint to disagree.
///
/// The live selection is published through a [ValueNotifier] rather than
/// `setState`. Rebuilding the widget tree on every pointer move would undo the
/// entire point of splitting the painting into passes; instead the notifier
/// drives `CustomPaint.repaint` directly and one capsule re-rasterises.
class GestureLayer extends StatefulWidget {
  const GestureLayer({
    required this.geometry,
    required this.selection,
    required this.onReleased,
    required this.hapticsService,
    this.onStarted,
    this.child,
    super.key,
  });

  final GridGeometry geometry;

  /// The live drag, shared with [SelectionPainter].
  final ValueNotifier<SelectionState> selection;

  /// Called on pointer up with the final state, BEFORE it is cleared —
  /// returns whether it matched a word. `GameGridState` uses the return
  /// value to decide whether to fade the capsule out (a miss) or clear it
  /// immediately (a match); this layer only clears on a match itself, since
  /// a miss's capsule has to stay populated for the fade to have something
  /// to paint (Ch03).
  final bool Function(SelectionState state) onReleased;

  /// Routes every haptic through the master toggle (Ch03) — replaces the
  /// raw `HapticFeedback.selectionClick()` this layer called directly
  /// before P09.
  final HapticsService hapticsService;

  /// Fired at the start of a new drag, before the anchor cell is published.
  /// `GameGridState` uses this to cancel any miss-fade still in flight from
  /// the previous release — without it, a fresh drag started mid-fade would
  /// inherit the fade's stale, partially-transparent alpha.
  final VoidCallback? onStarted;

  final Widget? child;

  @override
  State<GestureLayer> createState() => _GestureLayerState();
}

class _GestureLayerState extends State<GestureLayer> {
  late final SelectionResolver _resolver = SelectionResolver(
    size: widget.geometry.size,
  );

  /// The pointer currently drawing. A second finger is ignored rather than
  /// fighting the first for the selection.
  int? _activePointer;

  @override
  void didUpdateWidget(GestureLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.geometry.size != widget.geometry.size) {
      _activePointer = null;
      widget.selection.value = SelectionState.empty;
    }
  }

  void _onDown(PointerDownEvent event) {
    if (_activePointer != null) return;
    _activePointer = event.pointer;
    widget.onStarted?.call();

    final next = _resolver.begin(
      widget.geometry.toGridPoint(event.localPosition),
    );
    _publish(next);
  }

  void _onMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer) return;

    final next = _resolver.extendTo(
      widget.selection.value,
      widget.geometry.toGridPoint(event.localPosition),
    );
    _publish(next);
  }

  void _onUp(PointerEvent event) {
    if (event.pointer != _activePointer) return;
    _activePointer = null;

    final finished = widget.selection.value;
    if (finished.isEmpty) return;

    final matched = widget.onReleased(finished);
    // A miss leaves `selection.value` populated at the finished drag —
    // `GameGridState` owns fading it out over 180ms and clearing it once
    // that completes. "No punishment feedback" (Ch03) means the capsule
    // just fades in its own selection colour; nothing here reacts to a miss.
    if (matched) {
      widget.selection.value = SelectionState.empty;
    }
  }

  void _onCancel(PointerCancelEvent event) {
    if (event.pointer != _activePointer) return;
    _activePointer = null;
    // A cancelled pointer is not an attempt — drop it without scoring a miss.
    widget.selection.value = SelectionState.empty;
  }

  void _publish(SelectionState next) {
    final previous = widget.selection.value;

    // One click per cell the finger newly reaches. Dragging back to un-select
    // is silent — the click marks progress, and buzzing on the way back would
    // read as an error.
    if (next.cells.length > previous.cells.length) {
      widget.hapticsService.selectionTick();
    }

    widget.selection.value = next;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: _onUp,
      onPointerCancel: _onCancel,
      child: widget.child,
    );
  }
}
