import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_route.dart';
import '../../app/theme/theme.dart';
import '../../domain/progression/journey_region.dart';
import '../../domain/text/language.dart';
import '../../l10n/app_localizations.dart';
import '../meta/journey_providers.dart';
import '../widgets/app_background.dart';
import '../widgets/system_back_handler.dart';
import '../widgets/tap_feedback.dart';

/// The journey map (Ch02) — a vertically scrolling path of level nodes,
/// grouped into ten-level regions, replacing a flat level list.
///
/// ---------------------------------------------------------------------------
/// WHY A `CustomScrollView` OF REGIONS, NOT A `ListView` OF 300 NODES
///
/// Ch02 asks for locked nodes to stay VISIBLE but dimmed — a visible future is
/// motivating — which means the map genuinely holds all 300, not just the
/// reachable ones. On the 2GB-RAM target that rules out building them eagerly.
/// `SliverList.builder` inside a `CustomScrollView` builds one region at a
/// time as it scrolls into view, and each region is ten nodes, so the widget
/// count on screen stays in the dozens no matter how far along the player is.
///
/// AUTO-SCROLL uses a fixed per-region extent rather than measuring: the
/// current node's offset has to be known BEFORE the list has laid anything
/// out, and every region is the same height by construction, so multiplying is
/// both exact and available on the first frame. `initialScrollOffset` then
/// puts the player at their current node with no visible jump — a
/// `Scrollable.ensureVisible` after mount would animate from the top, which
/// reads as the map scrolling away from them.
class JourneyScreen extends ConsumerWidget {
  const JourneyScreen({super.key});

  /// Height budget for one region: its header plus ten nodes. Pinned here
  /// because [_scrollOffsetFor] depends on it — a node whose real height
  /// drifted from this would put the auto-scroll slightly off, so
  /// `journey_screen_test.dart` asserts a rendered region matches it.
  static const double regionHeaderHeight = 56;
  static const double nodeRowHeight = 72;
  static const double regionExtent =
      regionHeaderHeight + nodeRowHeight * JourneyRegion.levelsPerRegion;

  /// Where to park the viewport so [currentLevel]'s node sits comfortably
  /// in view rather than pinned to the very top edge.
  static double scrollOffsetFor(int currentLevel) {
    final region = JourneyRegion.forLevel(currentLevel);
    final withinRegion = currentLevel - region.firstLevel;
    final raw =
        region.index * regionExtent +
        regionHeaderHeight +
        withinRegion * nodeRowHeight -
        nodeRowHeight * 2;
    return raw < 0 ? 0 : raw;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final mapAsync = ref.watch(journeyMapProvider);

    // Reached with `.go()`, so there is nothing to pop: both the arrow and
    // the Android system back have to navigate explicitly, or the app closes.
    void goHome() {
      ref.tapFeedback();
      context.go(const HomeRoute().location);
    }

    return SystemBackHandler(
      onBack: goHome,
      // The map is safe over artwork without any extra treatment: every node
      // is an opaque disc of its own (`surfaceElevated`, or the region accent
      // once completed), so the picture only ever shows in the gaps between
      // them — the nodes are cards, in the sense the scrim was written for.
      child: BackgroundScaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: goHome),
          title: Text(l10n.navJourney),
        ),
        body: mapAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('$error')),
          data: (map) => _JourneyPath(map: map),
        ),
      ),
    );
  }
}

class _JourneyPath extends ConsumerStatefulWidget {
  const _JourneyPath({required this.map});

  final JourneyMapState map;

  @override
  ConsumerState<_JourneyPath> createState() => _JourneyPathState();
}

class _JourneyPathState extends ConsumerState<_JourneyPath> {
  late final ScrollController _controller = ScrollController(
    initialScrollOffset: JourneyScreen.scrollOffsetFor(widget.map.currentLevel),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _openLevel(int level) {
    ref.tapFeedback();
    context.go(GameRoute('$level').location);
  }

  @override
  Widget build(BuildContext context) {
    final regions = JourneyRegion.upTo(widget.map.nodes.length);

    return CustomScrollView(
      controller: _controller,
      slivers: [
        SliverList.builder(
          itemCount: regions.length,
          itemBuilder: (context, index) => _RegionBlock(
            region: regions[index],
            nodes: widget.map.nodes
                .where((node) => regions[index].contains(node.level))
                .toList(),
            theme: widget.map.regionThemes[regions[index].index] ?? '',
            onOpenLevel: _openLevel,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: AppTokens.space48)),
      ],
    );
  }
}

class _RegionBlock extends StatelessWidget {
  const _RegionBlock({
    required this.region,
    required this.nodes,
    required this.theme,
    required this.onOpenLevel,
  });

  final JourneyRegion region;
  final List<JourneyNode> nodes;
  final String theme;
  final void Function(int level) onOpenLevel;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final accent = tokens
        .colors
        .regionAccent[region.accentIndex % tokens.colors.regionAccent.length];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RegionHeader(region: region, theme: theme, accent: accent),
        // The nodes sit ON the trail, so the two share one box and the
        // painter can place its curve from the same numbers the rows lay
        // themselves out with — see `_TrailPainter` for why that is derived
        // rather than measured.
        SizedBox(
          height: JourneyScreen.nodeRowHeight * nodes.length,
          child: Stack(
            children: [
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _TrailPainter(
                      nodes: nodes,
                      accent: accent,
                      untrodden: tokens.colors.outlineSoft,
                    ),
                  ),
                ),
              ),
              Column(
                children: [
                  for (final node in nodes)
                    _NodeRow(node: node, accent: accent, onOpen: onOpenLevel),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The band above each region: a filled accent tag carrying the number, the
/// region title, and the level's theme.
///
/// Previously a 4px rule and two pieces of text, which read as a list
/// separator rather than as the chapter break it marks. The tag is the same
/// accent the region's own trail and completed nodes use, so a player
/// scrolling sees one colour carry through the whole stretch.
class _RegionHeader extends StatelessWidget {
  const _RegionHeader({
    required this.region,
    required this.theme,
    required this.accent,
  });

  final JourneyRegion region;
  final String theme;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = AppLocalizations.of(context);

    return SizedBox(
      height: JourneyScreen.regionHeaderHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.space24,
          vertical: AppTokens.space8,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.space12,
                vertical: AppTokens.space4,
              ),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.22),
                borderRadius: AppTokens.borderRadius16,
                border: Border.all(color: accent.withValues(alpha: 0.55)),
              ),
              child: Text(
                l10n.regionTitle(region.number),
                style: AppTypography.uiTextStyle(
                  Language.english,
                  UiRole.label,
                  color: tokens.colors.onSurface,
                  weight: FontWeight.w700,
                ),
              ),
            ),
            if (theme.isNotEmpty) ...[
              const SizedBox(width: AppTokens.space12),
              Expanded(
                child: Text(
                  theme,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.uiTextStyle(
                    Language.english,
                    UiRole.caption,
                    color: tokens.colors.onSurfaceMuted,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One level on the path.
///
/// The zig-zag is computed from the level number rather than stored: a path
/// that alternates sides reads as a journey instead of a column, and deriving
/// it means nothing about the map's shape has to be persisted or synced.
class _NodeRow extends StatelessWidget {
  const _NodeRow({
    required this.node,
    required this.accent,
    required this.onOpen,
  });

  final JourneyNode node;
  final Color accent;
  final void Function(int level) onOpen;

  static const double nodeSize = 52;

  /// Where level [level] sits across the width, as an `Alignment` x.
  ///
  /// Shared with `_TrailPainter` rather than duplicated there: the trail has
  /// to arrive exactly at the node it is drawn under, so one table decides
  /// the swing and both read it. Widest at the ends of each four-level cycle,
  /// which is what makes the path read as a journey instead of a column.
  static double swingFor(int level) {
    const swing = [0.0, 0.35, 0.0, -0.35];
    return swing[(level - 1) % swing.length];
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = AppLocalizations.of(context);

    final isLocked = node.status == JourneyNodeStatus.locked;
    final isCurrent = node.status == JourneyNodeStatus.current;
    final isDone = node.status == JourneyNodeStatus.completed;

    final alignment = swingFor(node.level);

    return SizedBox(
      height: JourneyScreen.nodeRowHeight,
      child: Align(
        alignment: Alignment(alignment, 0),
        child: Semantics(
          // Locked nodes stay in the tree and stay reachable by a screen
          // reader, labelled as locked — Ch02 wants the future visible, and
          // "visible" has to include non-visually.
          //
          // `container: true` so each node is its OWN semantics node rather
          // than an annotation that merges into whatever encloses it: without
          // it the "Locked" label has nothing of its own to attach to and a
          // screen reader just reads the level number.
          container: true,
          label: isLocked ? l10n.levelLocked : null,
          button: !isLocked,
          child: Opacity(
            // Dimmed, never hidden (Ch02).
            opacity: isLocked ? 0.35 : 1,
            child: _NodeHalo(
              // Only the node the player is standing on breathes — one
              // animation on the whole map, and it is the one thing the eye
              // should land on when the map opens.
              active: isCurrent,
              color: tokens.colors.primary,
              child: Material(
                color: isDone
                    ? accent.withValues(alpha: 0.30)
                    : tokens.colors.surfaceElevated,
                shape: CircleBorder(
                  side: BorderSide(
                    color: isCurrent ? tokens.colors.primary : accent,
                    width: isCurrent ? 3 : 1.5,
                  ),
                ),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: isLocked ? null : () => onOpen(node.level),
                  child: SizedBox(
                    width: nodeSize,
                    height: nodeSize,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${node.level}',
                          style: AppTypography.uiTextStyle(
                            Language.english,
                            UiRole.body,
                            color: tokens.colors.onSurface,
                            weight: isCurrent ? FontWeight.w700 : null,
                          ),
                        ),
                        if (isDone)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (var i = 0; i < 3; i++)
                                Icon(
                                  Icons.star_rounded,
                                  size: 9,
                                  color: i < node.stars
                                      ? tokens.colors.primary
                                      : tokens.colors.outline,
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The winding trail the nodes sit on, and the part of it already walked.
///
/// ---------------------------------------------------------------------------
/// THE GEOMETRY IS DERIVED, NOT MEASURED
///
/// A node's centre is a pure function of its level: the row is
/// [JourneyScreen.nodeRowHeight] tall and the node is centred in it, and the
/// horizontal swing comes from the same `_NodeRow.swingFor` table the rows
/// align themselves with. So this painter and the widgets above it cannot
/// drift — there is one definition of where a node goes, and both read it.
/// Measuring instead would mean a first frame with no trail (nothing has been
/// laid out yet) and a second with one, which reads as a flicker on every
/// region that scrolls into view.
///
/// TWO PASSES, and the second is the point: the whole path is stroked in a
/// muted tone, then the stretch up to the player's furthest node is stroked
/// over it in the region's accent. The trail therefore fills in as the
/// journey is walked, which is the thing a flat list of circles could never
/// show.
class _TrailPainter extends CustomPainter {
  const _TrailPainter({
    required this.nodes,
    required this.accent,
    required this.untrodden,
  });

  final List<JourneyNode> nodes;
  final Color accent;
  final Color untrodden;

  static const double _width = 5;

  @override
  void paint(Canvas canvas, Size size) {
    if (nodes.length < 2) return;

    final centres = [
      for (var i = 0; i < nodes.length; i++) _centreOf(i, nodes[i], size),
    ];

    canvas.drawPath(
      _curveThrough(centres),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _width
        ..strokeCap = StrokeCap.round
        ..color = untrodden,
    );

    // How far the player has actually got. `completed` and `current` both
    // count: the trail should reach the node they are standing on, not stop
    // one short of it.
    final walked = nodes.lastIndexWhere(
      (node) => node.status != JourneyNodeStatus.locked,
    );
    if (walked < 1) return;

    canvas.drawPath(
      _curveThrough(centres.sublist(0, walked + 1)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _width
        ..strokeCap = StrokeCap.round
        ..color = accent,
    );
  }

  Offset _centreOf(int index, JourneyNode node, Size size) {
    final swing = _NodeRow.swingFor(node.level);
    final half = (size.width - _NodeRow.nodeSize) / 2;
    return Offset(
      size.width / 2 + swing * half,
      index * JourneyScreen.nodeRowHeight + JourneyScreen.nodeRowHeight / 2,
    );
  }

  /// A cubic through the centres with purely VERTICAL control points, which
  /// is what gives the trail its S-bend: the curve leaves each node straight
  /// down and arrives at the next one straight down, so the horizontal swing
  /// happens in the middle rather than as a corner at the node.
  Path _curveThrough(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final from = points[i - 1];
      final to = points[i];
      final lift = (to.dy - from.dy) / 2;
      path.cubicTo(from.dx, from.dy + lift, to.dx, to.dy - lift, to.dx, to.dy);
    }
    return path;
  }

  @override
  bool shouldRepaint(_TrailPainter old) =>
      old.accent != accent ||
      old.untrodden != untrodden ||
      !_sameStatuses(old.nodes, nodes);

  static bool _sameStatuses(List<JourneyNode> a, List<JourneyNode> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].status != b[i].status || a[i].level != b[i].level) return false;
    }
    return true;
  }
}

/// A slow breathing ring behind the node the player is standing on.
///
/// The ONLY animation on this screen, and deliberately so: the map holds 300
/// nodes and exactly one of them is `current`, so this is one controller for
/// the whole journey however far down it the player has got. It exists to
/// answer "where am I" at a glance on a screen that is otherwise a long
/// column of similar circles.
///
/// IT BREATHES A FEW TIMES AND THEN RESTS as a steady ring, rather than
/// pulsing for as long as the screen is open. Two reasons, and the second is
/// not cosmetic:
///
///  * The map auto-scrolls to this node as it opens, so the arrival is
///    exactly when the movement is worth anything; after that it is a
///    blinking light on a screen a player is trying to read.
///  * An animation that never ends schedules frames forever, and
///    `pumpAndSettle()` waits for frames to STOP. A permanent pulse hangs
///    every widget test that so much as visits this screen — the same trap
///    CLAUDE.md already records for indeterminate spinners, met from the
///    other side.
///
/// REDUCE-MOTION KEEPS THE RING AND DROPS THE BREATHING — the halo carries
/// information (this is your level), so removing it outright would take the
/// answer away rather than the movement. Same call `_PulseHighlight`
/// (`game_grid.dart`) already makes, and the controller is never created in
/// that case rather than being run at zero duration, which would spin.
class _NodeHalo extends StatefulWidget {
  const _NodeHalo({
    required this.active,
    required this.color,
    required this.child,
  });

  final bool active;
  final Color color;
  final Widget child;

  /// How far past the node the ring reaches at its widest.
  static const double maxSpread = 10;

  /// Breaths on arrival before the ring settles.
  static const int breaths = 3;

  @override
  State<_NodeHalo> createState() => _NodeHaloState();
}

class _NodeHaloState extends State<_NodeHalo>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  int _breathsLeft = 0;

  /// One breath is out and back. Counted here rather than with `repeat()`
  /// plus a timer, so the animation ENDS on its own — see the class doc for
  /// why that matters beyond taste.
  void _onBreath(AnimationStatus status) {
    final controller = _controller;
    if (controller == null) return;
    if (status == AnimationStatus.completed) {
      controller.reverse();
    } else if (status == AnimationStatus.dismissed) {
      _breathsLeft--;
      if (_breathsLeft > 0) controller.forward();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncController();
  }

  @override
  void didUpdateWidget(_NodeHalo old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) _syncController();
  }

  void _syncController() {
    final wanted = widget.active && !Motion.of(context).disabled;
    if (wanted == (_controller != null)) return;

    if (!wanted) {
      _controller?.dispose();
      _controller = null;
      return;
    }
    _breathsLeft = _NodeHalo.breaths;
    _controller =
        AnimationController(
            vsync: this,
            // Slower than anything in `Motion`, which names one-shot UI
            // durations — a breath that ran at `Motion.slow` would read as a
            // blink. Its own constant for its own job, the same way
            // `ParticleLayer.lifetime` keeps one.
            duration: const Duration(milliseconds: 1600),
          )
          ..addStatusListener(_onBreath)
          ..forward();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;

    final controller = _controller;
    if (controller == null) {
      // Reduce-motion: the ring, held still at its midpoint.
      return _halo(0.5, widget.child);
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) => _halo(controller.value, child!),
      child: widget.child,
    );
  }

  Widget _halo(double t, Widget child) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: widget.color.withValues(alpha: 0.38 * (1 - t)),
            blurRadius: _NodeHalo.maxSpread * (0.4 + t),
            spreadRadius: _NodeHalo.maxSpread * t,
          ),
        ],
      ),
      child: child,
    );
  }
}
