import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../domain/grid/selection_resolver.dart';
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
    this.enableHaptics = true,
    this.child,
    super.key,
  });

  final GridGeometry geometry;

  /// The live drag, shared with [SelectionPainter].
  final ValueNotifier<SelectionState> selection;

  /// Called on pointer up with the final state, before it is cleared. The game
  /// controller (P07) matches it against the remaining words.
  final void Function(SelectionState state) onReleased;

  /// TODO(P09): replace with HapticsService so the settings master toggle
  /// reaches this. Ch03 makes that toggle mandatory — some players dislike
  /// haptics entirely.
  final bool enableHaptics;

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
    widget.selection.value = SelectionState.empty;
    if (!finished.isEmpty) widget.onReleased(finished);
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
    if (widget.enableHaptics && next.cells.length > previous.cells.length) {
      HapticFeedback.selectionClick();
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
