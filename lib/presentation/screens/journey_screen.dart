import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_route.dart';
import '../../app/theme/theme.dart';
import '../../domain/progression/journey_region.dart';
import '../../domain/text/language.dart';
import '../../l10n/app_localizations.dart';
import '../../services/audio/audio_service.dart';
import '../../services/haptics/haptics_service.dart';
import '../meta/journey_providers.dart';
import '../widgets/system_back_handler.dart';

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
    void goHome() => context.go(const HomeRoute().location);

    return SystemBackHandler(
      onBack: goHome,
      child: Scaffold(
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
    ref.read(audioServiceProvider).playButtonTap();
    ref.read(hapticsServiceProvider).buttonTap();
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
    final l10n = AppLocalizations.of(context);
    final accent = tokens
        .colors
        .regionAccent[region.accentIndex % tokens.colors.regionAccent.length];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: JourneyScreen.regionHeaderHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.space24,
              vertical: AppTokens.space8,
            ),
            child: Row(
              children: [
                Container(
                  width: AppTokens.space4,
                  height: AppTokens.space24,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: AppTokens.borderRadius4,
                  ),
                ),
                const SizedBox(width: AppTokens.space12),
                Text(
                  l10n.regionTitle(region.number),
                  style: AppTypography.uiTextStyle(
                    Language.english,
                    UiRole.title,
                    color: tokens.colors.onSurface,
                  ),
                ),
                if (theme.isNotEmpty) ...[
                  const SizedBox(width: AppTokens.space8),
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
        ),
        for (final node in nodes)
          _NodeRow(node: node, accent: accent, onOpen: onOpenLevel),
      ],
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

  static const double _nodeSize = 52;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = AppLocalizations.of(context);

    final isLocked = node.status == JourneyNodeStatus.locked;
    final isCurrent = node.status == JourneyNodeStatus.current;
    final isDone = node.status == JourneyNodeStatus.completed;

    // Alternating offsets, widest at the ends of each 4-level cycle.
    const swing = [0.0, 0.35, 0.0, -0.35];
    final alignment = swing[(node.level - 1) % swing.length];

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
            child: Material(
              color: isDone
                  ? accent.withValues(alpha: 0.22)
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
                  width: _nodeSize,
                  height: _nodeSize,
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
    );
  }
}
