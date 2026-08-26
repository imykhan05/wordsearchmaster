import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_route.dart';
import '../../app/config/app_config.dart';
import '../../app/theme/theme.dart';
import '../../application/game_controller.dart';
import '../../domain/grid/selection_resolver.dart';
import '../../domain/text/language.dart';
import '../../l10n/app_localizations.dart';
import '../../services/audio/audio_service.dart';
import '../../services/haptics/haptics_service.dart';
import '../game/found_word_reveal.dart';
import '../game/game_debug_panel.dart';
import '../game/game_grid.dart';
import '../game/grid_geometry.dart';
import '../game/level_complete_card.dart';
import '../game/particles.dart';
import '../game/pause_sheet.dart';
import '../widgets/rolling_counter.dart';

/// The core gameplay screen. Assembled entirely from [GameController] —
/// see its file header for the state-machine decisions this screen relies
/// on (events as the score source of truth, no live selection in state, the
/// atomic Zeigarnik swap).
///
/// The one thing this screen still owns locally is [ParticleController]: it
/// is an animation driver, not game state, and P06 already established that
/// pattern for it.
class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({required this.levelId, super.key});

  final String levelId;

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  final ParticleController _particles = ParticleController();
  final FoundWordRevealController _reveal = FoundWordRevealController();

  /// The family key. Stays fixed for this screen's lifetime — advancing
  /// levels mutates `GameState.level` in place (Zeigarnik) rather than
  /// creating a new provider instance, so this never has to change.
  int get _initialLevel => int.tryParse(widget.levelId) ?? 1;

  @override
  void dispose() {
    _particles.dispose();
    _reveal.dispose();
    super.dispose();
  }

  /// The correct-word sequence (Ch03), timed against the millisecond table
  /// rather than approximated: 0ms audio + haptic + the grid's flash/punch
  /// reveal, all synchronous with the match itself; particles pushed out to
  /// start at 90ms (their own 170ms lifetime then ends them at 260ms,
  /// exactly the spec's window); the word chip's strike-through delay lives
  /// on `_WordChip` itself, since it only needs to react to `found` flipping
  /// true, not to anything computed here.
  ///
  /// Returns whether the drag matched — `GameGrid`/`GestureLayer` use this
  /// to decide between clearing the selection immediately or fading it out.
  bool _onSelectionReleased(SelectionState selection, GridGeometry geometry) {
    final notifier = ref.read(gameControllerProvider(_initialLevel).notifier);
    final outcome = notifier.processSelection(selection);
    if (!outcome.isValid) return false;

    final state = ref.read(gameControllerProvider(_initialLevel)).value;
    if (state == null) return true;

    final tokens = AppTokens.of(context);
    // The just-found word is always the newest entry, so its index is the
    // last one — matches the colour a found chip renders with.
    final colorIndex =
        (state.foundWords.length - 1) % tokens.colors.foundWord.length;
    final color = tokens.colors.foundWord[colorIndex];
    final borderWidth =
        AppTokens.foundWordBorderWidths[colorIndex %
            AppTokens.foundWordBorderWidths.length];

    ref.read(audioServiceProvider).playFound(combo: state.combo);
    ref.read(hapticsServiceProvider).wordFound();
    _reveal.reveal(
      cells: outcome.cells,
      color: color,
      borderWidth: borderWidth,
    );

    // Burst from the middle of the word, per Ch03 — delayed to 90ms so it
    // lands inside the spec's 90–260ms window (the burst's own 170ms
    // lifetime supplies the other end).
    final first = geometry.cellCenter(outcome.cells.first);
    final last = geometry.cellCenter(outcome.cells.last);
    final origin = Offset((first.dx + last.dx) / 2, (first.dy + last.dy) / 2);
    final seed = outcome.matchedWord.hashCode;
    final particleDelay = Motion.reduced(context, Motion.instant);
    if (particleDelay == Duration.zero) {
      // Reduce-motion: no async gap to schedule at all, not just a shorter
      // one — matches every other P09 layer skipping outright rather than
      // merely speeding up.
      _particles.burst(origin: origin, color: color, seed: seed);
    } else {
      Future.delayed(particleDelay, () {
        if (!mounted) return;
        _particles.burst(origin: origin, color: color, seed: seed);
      });
    }

    return true;
  }

  /// `button_tap` (Ch03) — audio + a light haptic tick, fired from every UI
  /// button on this screen that isn't already covered by its own
  /// choreography (pause, hint, continue on the level-complete card).
  void _tapFeedback() {
    ref.read(audioServiceProvider).playButtonTap();
    ref.read(hapticsServiceProvider).buttonTap();
  }

  Future<void> _openPauseSheet() async {
    _tapFeedback();
    final notifier = ref.read(gameControllerProvider(_initialLevel).notifier);
    notifier.pause();

    final action = await showModalBottomSheet<PauseAction>(
      context: context,
      builder: (_) => const PauseSheet(),
    );
    if (!mounted) return;

    switch (action) {
      case PauseAction.restart:
        notifier.restart();
      case PauseAction.home:
        context.go(const HomeRoute().location);
      case PauseAction.resume:
      case null:
        notifier.resume();
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncState = ref.watch(gameControllerProvider(_initialLevel));
    // Read once: everything below — the AppBar and the body alike — is a
    // pure function of this one settled value.
    final state = asyncState.value;

    // LEVEL COMPLETE (Ch03): confetti/stars/score are the card's own
    // TweenAnimationBuilder timeline (`level_complete_card.dart`) — this
    // listener only owns the two side effects that timeline can't reach,
    // firing exactly once on the phase TRANSITION into levelComplete, never
    // on every rebuild while already there.
    ref.listen(gameControllerProvider(_initialLevel), (previous, next) {
      final wasComplete = previous?.value?.phase == GamePhase.levelComplete;
      final isComplete = next.value?.phase == GamePhase.levelComplete;
      if (!wasComplete && isComplete) {
        ref.read(audioServiceProvider).playLevelComplete();
        ref.read(hapticsServiceProvider).levelComplete();
      }
    });

    return Scaffold(
      // No banner ad on this screen, ever (CLAUDE.md → Never do).
      appBar: state == null ? null : _buildAppBar(context, state),
      body: SafeArea(
        child: asyncState.when(
          // A language switch re-runs GameController.build; the previous
          // grid stays on screen instead of flashing a spinner underneath it.
          skipLoadingOnReload: true,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => Center(child: Text('$error')),
          data: (state) => _GameContent(
            state: state,
            particles: _particles,
            foundWordReveal: _reveal,
            onSelectionReleased: _onSelectionReleased,
            onLevelComplete: () {
              _tapFeedback();
              ref
                  .read(gameControllerProvider(_initialLevel).notifier)
                  .dismissLevelComplete();
            },
          ),
        ),
      ),
    );
  }

  /// Placed at the Scaffold level rather than built inline: a plain
  /// `BackButton` pops the Navigator, but this route is reached with
  /// go_router's `.go()`, which leaves nothing to pop — so `leading` here
  /// always sends the player home explicitly instead.
  AppBar _buildAppBar(BuildContext context, GameState state) {
    final l10n = AppLocalizations.of(context);

    return AppBar(
      leading: BackButton(
        onPressed: () => context.go(const HomeRoute().location),
      ),
      title: Text(l10n.gameLevel('${state.level}')),
      actions: [
        Center(
          child: RollingCounter(
            value: state.score,
            // Ch03 correct-word sequence: "160ms score roll starts" — the
            // roll waits, the number itself is already correct underneath.
            startDelay: RollingCounter.scoreRollDelay,
            style: AppTypography.uiTextStyle(
              Language.english,
              UiRole.title,
              color: AppTokens.of(context).colors.primary,
              weight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: AppTokens.space12),
        _HintButton(
          state: state,
          onPressed: () {
            _tapFeedback();
            ref.read(gameControllerProvider(_initialLevel).notifier).useHint();
          },
        ),
        IconButton(
          tooltip: l10n.pauseButtonLabel,
          onPressed: state.phase == GamePhase.playing ? _openPauseSheet : null,
          icon: const Icon(Icons.pause_rounded),
        ),
        const SizedBox(width: AppTokens.space8),
      ],
    );
  }
}

class _HintButton extends StatelessWidget {
  const _HintButton({required this.state, required this.onPressed});

  final GameState state;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final canHint =
        state.phase == GamePhase.playing && state.remainingWords.isNotEmpty;

    return Badge(
      label: Text('${state.hintsUsed}'),
      isLabelVisible: state.hintsUsed > 0,
      child: IconButton(
        tooltip: l10n.hintButtonLabel,
        onPressed: canHint ? onPressed : null,
        icon: const Icon(Icons.lightbulb_outline),
      ),
    );
  }
}

/// Everything below the top bar: the grid (with the dev debug panel docked
/// over it) and the word-list panel, plus the level-complete overlay when
/// `state.phase` calls for it.
///
/// A separate widget purely so `GameScreen.build` doesn't have to thread the
/// `AsyncValue` unwrap through a long body — `state` here is always the
/// settled [GameState].
class _GameContent extends ConsumerWidget {
  const _GameContent({
    required this.state,
    required this.particles,
    required this.foundWordReveal,
    required this.onSelectionReleased,
    required this.onLevelComplete,
  });

  final GameState state;
  final ParticleController particles;
  final FoundWordRevealController foundWordReveal;
  final bool Function(SelectionState, GridGeometry) onSelectionReleased;
  final VoidCallback onLevelComplete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDev = ref.watch(appConfigProvider).flavor == Flavor.dev;
    final tokens = AppTokens.of(context);

    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppTokens.space16),
                child: Stack(
                  children: [
                    GameGrid(
                      cells: state.grid.cells,
                      language: state.language,
                      foundWordCells: [
                        for (final word in state.foundWords)
                          state.grid.placements[word]!,
                      ],
                      hintedCell: state.hintedCell,
                      onSelectionReleased: onSelectionReleased,
                      particleController: particles,
                      foundWordRevealController: foundWordReveal,
                      hapticsService: ref.watch(hapticsServiceProvider),
                      showPerfOverlay: isDev,
                    ),
                    if (isDev)
                      Positioned(
                        right: AppTokens.space8,
                        bottom: AppTokens.space8,
                        child: GameDebugPanel(level: state.level),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppTokens.space16),
              child: Wrap(
                spacing: AppTokens.space8,
                runSpacing: AppTokens.space8,
                alignment: WrapAlignment.center,
                children: [
                  for (final word in state.allWords)
                    _WordChip(
                      key: ValueKey(word),
                      word: word,
                      language: state.language,
                      found: state.foundWords.contains(word),
                      color:
                          tokens.colors.foundWord[state.foundWords.indexOf(
                                word,
                              ) %
                              tokens.colors.foundWord.length],
                    ),
                ],
              ),
            ),
          ],
        ),
        // Zeigarnik (Ch02): GameController has already generated the NEXT
        // level's grid and word list by the time phase reaches here, so the
        // Column above is already showing it, behind this card.
        if (state.phase == GamePhase.levelComplete &&
            state.completedSummary != null)
          Positioned.fill(
            child: LevelCompleteCard(
              summary: state.completedSummary!,
              onContinue: onLevelComplete,
            ),
          ),
      ],
    );
  }
}

/// A target word, shown in its CONNECTED/display form — the shape the player
/// maps onto the isolated letters in the grid (Ch04).
///
/// Stateful purely to hold the Ch03 "140–260ms strike-through draw" delay:
/// `found` flips to true the instant `GameController` records the match, but
/// this chip's own visual flip waits 140ms behind the grid's flash/punch and
/// the particle burst, which read first. A `ValueNotifier` + `Future.delayed`
/// drives that wait, not `setState` — the same reasoning as `GameGridState`'s
/// miss-fade: this codebase reaches for a notifier over `setState` wherever
/// there's a choice, even for widget-local state like this.
class _WordChip extends StatefulWidget {
  const _WordChip({
    required this.word,
    required this.language,
    required this.found,
    required this.color,
    super.key,
  });

  final String word;
  final Language language;
  final bool found;
  final Color color;

  @override
  State<_WordChip> createState() => _WordChipState();
}

class _WordChipState extends State<_WordChip> {
  /// What the chip currently DISPLAYS as found — lags `widget.found` by the
  /// reveal delay on the way in. Seeded from the current value, not always
  /// `false`: a chip that mounts already-found (e.g. the dev debug panel's
  /// force-complete) must show that immediately, not replay the delay.
  late final ValueNotifier<bool> _displayFound = ValueNotifier<bool>(
    widget.found,
  );

  Timer? _delayTimer;

  @override
  void didUpdateWidget(_WordChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.found == widget.found) return;

    _delayTimer?.cancel();
    if (!widget.found) {
      // Un-founding only happens via restart, alongside a fresh grid — no
      // delay is specified or wanted for that case.
      _displayFound.value = false;
      return;
    }

    final delay = Motion.reduced(context, Motion.quick);
    if (delay == Duration.zero) {
      _displayFound.value = true;
    } else {
      _delayTimer = Timer(delay, () => _displayFound.value = true);
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _displayFound.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _displayFound,
      builder: (context, found, child) => _WordChipBody(
        word: widget.word,
        language: widget.language,
        found: found,
        color: widget.color,
      ),
    );
  }
}

class _WordChipBody extends StatelessWidget {
  const _WordChipBody({
    required this.word,
    required this.language,
    required this.found,
    required this.color,
  });

  final String word;
  final Language language;
  final bool found;
  final Color color;

  /// 120ms strike-through draw, in the word's own reading direction — a
  /// literal from the bible, not on the Motion scale.
  static const Duration _strikeDuration = Duration(milliseconds: 120);

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final duration = Motion.reduced(context, _strikeDuration);

    return AnimatedContainer(
      duration: duration,
      curve: Motion.fade,
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.space12,
        vertical: AppTokens.space4,
      ),
      decoration: BoxDecoration(
        color: found
            ? color.withValues(alpha: 0.22)
            : tokens.colors.surfaceElevated,
        borderRadius: AppTokens.borderRadius16,
        border: Border.all(color: found ? color : tokens.colors.outline),
      ),
      child: Stack(
        alignment: AlignmentDirectional.centerStart,
        children: [
          Text(
            word,
            style: AppTypography.uiTextStyle(
              language,
              UiRole.wordChip,
              color: found
                  ? tokens.colors.onSurfaceMuted
                  : tokens.colors.onSurface,
            ),
          ),
          Positioned.fill(
            // Align first: Positioned.fill hands down TIGHT constraints, and
            // without something to loosen them first, FractionallySizedBox's
            // null heightFactor inherits that tightness and the strike bar
            // stretches to the chip's full height instead of staying a thin
            // line — Align is what lets Container's height: 2 win again.
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(end: found ? 1 : 0),
                duration: duration,
                curve: Motion.fade,
                builder: (context, t, child) {
                  return FractionallySizedBox(
                    alignment: AlignmentDirectional.centerStart,
                    widthFactor: t.clamp(0.0, 1.0),
                    child: Container(height: 2, color: color),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
