import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_route.dart';
import '../../app/config/app_config.dart';
import '../../app/theme/theme.dart';
import '../../application/achievements_controller.dart';
import '../../application/game_controller.dart';
import '../../application/progression_controller.dart';
import '../../data/repositories/dda_repository.dart';
import '../../domain/grid/selection_resolver.dart';
import '../../domain/progression/dda.dart';
import '../../domain/text/language.dart';
import '../../domain/text/script_normalizer.dart';
import '../../l10n/app_localizations.dart';
import '../../services/analytics/analytics_service.dart';
import '../../services/audio/audio_service.dart';
import '../../services/haptics/haptics_service.dart';
import '../../services/remote_config/remote_config.dart';
import '../../services/settings/ui_settings_store.dart';
import '../../services/time/trusted_clock.dart';
import '../game/found_word_reveal.dart';
import '../game/game_debug_panel.dart';
import '../game/game_grid.dart';
import '../game/grid_geometry.dart';
import '../game/level_complete_card.dart';
import '../game/particles.dart';
import '../game/pause_sheet.dart';
import '../meta/chest_open.dart';
import '../widgets/rolling_counter.dart';
import '../widgets/system_back_handler.dart';

/// The core gameplay screen. Assembled entirely from [GameController] — see
/// its file header for the state-machine decisions this screen relies on
/// (events as the score source of truth, no live selection in state, the
/// atomic Zeigarnik swap for journey levels, no swap for a daily).
///
/// TWO WAYS IN: [GameScreen.new] for a numbered journey level, [GameScreen.daily]
/// for today's puzzle. The daily's [GameSession] cannot be known synchronously
/// — it needs [TrustedClock] to resolve "today", which may touch the network
/// — so this outer widget is a thin, stateless resolver: it either builds a
/// [JourneySession] on the spot or watches [currentDayProvider] and only
/// mounts the real screen (`_GameScreenBody`) once a [DailySession] exists.
/// Everything P07 originally put directly on `GameScreen` now lives on that
/// body, parameterized by [GameSession] instead of a raw level number.
// The lint below suggests `this._levelId`, which Dart rejects outright: a
// named parameter's external name cannot be private, and router.dart (a
// different library) has to be able to call `GameScreen(levelId: ...)`. Same
// situation as `AppDatabase`'s reporter and `TrustedClock`'s marks.
// ignore_for_file: prefer_initializing_formals
class GameScreen extends StatelessWidget {
  const GameScreen({required String levelId, super.key})
    : _levelId = levelId,
      _isDaily = false;

  const GameScreen.daily({super.key}) : _levelId = null, _isDaily = true;

  final String? _levelId;
  final bool _isDaily;

  @override
  Widget build(BuildContext context) {
    if (!_isDaily) {
      final level = int.tryParse(_levelId!) ?? 1;
      // Ch02/P12: resolves whether THIS entry should downshift its word
      // count BEFORE constructing the session — exactly the same shape as
      // the Daily branch below resolving "today" first, and for the same
      // reason: `GameController.build` must stay database-free (its own file
      // header, decision 5), so the one DB read this feature needs happens
      // here, once, per level entry — never inside the controller itself.
      return Consumer(
        builder: (context, ref, _) {
          final downshiftAsync = ref.watch(journeyDownshiftProvider(level));
          return downshiftAsync.when(
            loading: () => const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
            // Fail OPEN, never blocked: a broken read simply means this one
            // attempt is not downshifted, not that the level refuses to load.
            error: (error, _) =>
                _GameScreenBody(session: JourneySession(level)),
            data: (downshift) => _GameScreenBody(
              session: JourneySession(level, downshift: downshift),
            ),
          );
        },
      );
    }

    return Consumer(
      builder: (context, ref, _) {
        final dayAsync = ref.watch(currentDayProvider);
        return dayAsync.when(
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (error, _) => Scaffold(body: Center(child: Text('$error'))),
          data: (day) => _GameScreenBody(session: DailySession(day)),
        );
      },
    );
  }
}

class _GameScreenBody extends ConsumerStatefulWidget {
  const _GameScreenBody({required this.session});

  final GameSession session;

  @override
  ConsumerState<_GameScreenBody> createState() => _GameScreenBodyState();
}

class _GameScreenBodyState extends ConsumerState<_GameScreenBody> {
  final ParticleController _particles = ParticleController();
  final FoundWordRevealController _reveal = FoundWordRevealController();

  /// Ch02/P12: the FTUE glow and the DDA stuck-pulse share this one
  /// mechanism — see `game_grid.dart`'s [PulseController] header.
  final PulseController _pulse = PulseController();

  /// Which DDA intervention is currently offered, if any. Only
  /// [DdaState.hintOffer] changes what's on screen (the inline banner);
  /// [DdaState.pulse] only drives [_pulse] and never touches this.
  final ValueNotifier<DdaState> _ddaState = ValueNotifier(DdaState.none);

  /// Whether the one-time Urdu connected-form illustration has been
  /// dismissed THIS SESSION — seeded from the persisted flag in [initState]
  /// so a player who already saw it never sees it mount at all.
  late final ValueNotifier<bool> _urduIntroDismissed = ValueNotifier<bool>(
    ref.read(uiSettingsStoreProvider).urduConnectedFormIntroShown,
  );

  /// Ticks once a second while this screen is alive; see [_onIdleTick]. A
  /// plain `Timer.periodic` rather than routing "idle seconds" through
  /// Riverpod state — the same reasoning `GameState` itself gives for having
  /// no live `selection` field (this file's own header, decision 2):
  /// ticking Riverpod state every second would rebuild the top bar and word
  /// list a second at a time for no reason, when only an occasional glow or
  /// banner ever needs to reach the screen.
  Timer? _idleTimer;

  /// Seconds of no player activity, counted by [_idleTimer]'s own ticks
  /// rather than a `DateTime.now()` delta — deliberately: a `Timer` fires on
  /// simulated time under `flutter_test`'s fake clock (this codebase already
  /// depends on that for P09's choreography delays), but a raw
  /// `DateTime.now()` call inside the callback is NOT guaranteed to agree
  /// with that simulated clock. Counting ticks sidesteps the question
  /// entirely — this is a count of "how many times has the timer fired since
  /// the last reset", nothing else.
  int _idleSeconds = 0;

  /// The last [DdaState] actually acted on, so [_tickDda] fires an
  /// intervention (and `dda_applied`) once per TRANSITION rather than once a
  /// second for as long as the idle period continues.
  DdaState _lastFiredDdaState = DdaState.none;

  /// The [_idleSeconds] value the next FTUE glow is due at — null means "not
  /// yet scheduled since the last reset", which [_tickFtueGlow] fills in with
  /// `+2` on its first look. Re-armed to `+6` after every glow, giving the
  /// "2s then every 6s" cadence Ch02 asks for.
  int? _nextFtueGlowAtSecond;

  GameSession get _session => widget.session;

  /// The reward for the completion currently shown on the card, or null
  /// before [ProgressionController] has resolved one. `LevelCompleteCard`
  /// reads `.coinsEarned` off this rather than off `GameState` — see
  /// `GameController`'s decision 5: awards are this screen's job, not the
  /// state machine's. A `ValueNotifier`, not `setState` — the same idiom
  /// every other piece of widget-local state on this screen already uses
  /// (P06's live selection, P09's fade/reveal controllers); CLAUDE.md bans
  /// `setState` in game screens outright, `Riverpod only`, and
  /// `game_screen_test.dart` enforces it by scanning this file's own source.
  final ValueNotifier<LevelReward?> _reward = ValueNotifier(null);

  /// Whether the chest celebration for the CURRENT completion has been
  /// dismissed. Reset alongside [_reward] on every new completion, so the
  /// next chest opens rather than being skipped by a stale `true`.
  final ValueNotifier<bool> _chestDismissed = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    _idleTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _onIdleTick();
    });
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _particles.dispose();
    _reveal.dispose();
    _pulse.dispose();
    _ddaState.dispose();
    _urduIntroDismissed.dispose();
    _reward.dispose();
    _chestDismissed.dispose();
    super.dispose();
  }

  /// Any player action that should postpone the FTUE glow and the DDA
  /// thresholds — a released drag (matched or not), a hint accepted, or the
  /// screen becoming playable again after a pause/restart/level-advance.
  void _resetIdleClock() {
    _idleSeconds = 0;
    _nextFtueGlowAtSecond = null;
    _lastFiredDdaState = DdaState.none;
    _ddaState.value = DdaState.none;
    _pulse.clear();
  }

  void _onIdleTick() {
    if (!mounted) return;
    _idleSeconds++;
    final state = ref.read(gameControllerProvider(_session)).value;
    if (state == null || state.phase != GamePhase.playing) return;

    // Ch02: the FTUE glow is level 1's own onboarding moment and OWNS the
    // idle clock while it is live — DDA's broader 25s/60s thresholds would
    // otherwise race the exact same clock during the exact window FTUE
    // already covers. Once the first word is found (or the player is past
    // level 1), DDA takes over as normal.
    if (state.level == 1 &&
        state.foundWords.isEmpty &&
        state.session is JourneySession) {
      _tickFtueGlow(state);
      return;
    }

    _tickDda(state);
  }

  /// Ch02 FTUE: "At 2s of inactivity, softly glow the first letter of one
  /// target word. Repeat every 6s until the first word is found." Always the
  /// SAME word (`allWords.first`) every cycle, unlike DDA's pulse below,
  /// which is deliberately random — the FTUE moment is teaching the player
  /// to find ONE thing, not sampling the board.
  void _tickFtueGlow(GameState state) {
    _nextFtueGlowAtSecond ??= 2;
    if (_idleSeconds < _nextFtueGlowAtSecond!) return;

    final words = state.allWords;
    final target = words.isEmpty ? null : words.first;
    final cell = target == null ? null : state.grid.placements[target]?.first;
    if (cell != null) _pulse.pulse(cell);
    _nextFtueGlowAtSecond = _idleSeconds + 6;
  }

  /// Ch02 DDA: 25s idle → silent pulse on a RANDOM remaining word; 60s idle →
  /// offer a free hint. [DdaEngine.stateFor] is pure — this method's only job
  /// is noticing the TRANSITION into a new state (so an intervention and its
  /// `dda_applied` event fire once, not once a second) and translating it
  /// into the pulse / banner.
  void _tickDda(GameState state) {
    final config = ref.read(ddaConfigProvider);
    final next = DdaEngine.stateFor(
      idleFor: Duration(seconds: _idleSeconds),
      config: config,
    );
    if (next == _lastFiredDdaState) return;
    _lastFiredDdaState = next;

    final analytics = ref.read(analyticsServiceProvider);
    switch (next) {
      case DdaState.none:
        break;
      case DdaState.pulse:
        final remaining = state.remainingWords;
        if (remaining.isNotEmpty) {
          final word = remaining[Random().nextInt(remaining.length)];
          final cell = state.grid.placements[word]?.first;
          if (cell != null) _pulse.pulse(cell);
        }
        analytics.ddaApplied(
          type: 'pulse',
          language: state.language.code,
          level: state.level,
        );
      case DdaState.hintOffer:
        analytics.ddaApplied(
          type: 'hint_offer',
          language: state.language.code,
          level: state.level,
        );
    }
    _ddaState.value = next;
  }

  /// Ch02: "two consecutive abandons of the same level" — recorded when the
  /// player explicitly leaves a JOURNEY level mid-play (the back button, or
  /// "Home" from the pause sheet) rather than finishing it. There is no
  /// reliable, testable signal for "the app was backgrounded" within this
  /// prompt's scope, so that case is deliberately not covered — see
  /// `domain/progression/dda.dart`'s `DdaAbandonRules` header.
  ///
  /// `ref.read` happens before the only `await` in this call chain (the
  /// `.then` continuation captures a plain `DdaRepository`, not `ref`) — this
  /// widget is about to navigate away and may be disposed before the write
  /// lands, so re-reading `ref` after that point would race disposal, the
  /// same hazard `ProgressionController`'s own header warns about.
  void _recordAbandonIfNeeded() {
    if (_session is! JourneySession) return;
    final state = ref.read(gameControllerProvider(_session)).value;
    if (state == null || state.phase == GamePhase.levelComplete) return;

    final language = state.language;
    final level = state.level;
    unawaited(
      ref
          .read(ddaRepositoryProvider.future)
          .then((repo) => repo.recordAbandon(language, level)),
    );
  }

  /// The DDA hint offer's accept action. Calls [GameController.useHint]
  /// DIRECTLY rather than `ProgressionController.tryBuyHint` — Ch02 is
  /// explicit this hint is free, never a rewarded ad, so it must not touch
  /// the coin ledger the paid hint button spends from.
  void _acceptFreeHint() {
    _tapFeedback();
    ref.read(gameControllerProvider(_session).notifier).useHint();
    _resetIdleClock();
  }

  void _dismissHintOffer() {
    _ddaState.value = DdaState.none;
    _resetIdleClock();
  }

  void _dismissUrduIntro() {
    _urduIntroDismissed.value = true;
    unawaited(
      ref.read(uiSettingsStoreProvider).setUrduConnectedFormIntroShown(true),
    );
  }

  /// DEV-ONLY: forces a DDA intervention without waiting on the idle timer —
  /// wired from [GameDebugPanel]. Goes through the same code paths a real
  /// idle period would (`_pulse`/`_ddaState`), never a stub, so the debug
  /// panel is a faithful preview — the same rule `GameController
  /// .debugForcePhase` already keeps for level-complete.
  void _debugForceDda(DdaState target) {
    final state = ref.read(gameControllerProvider(_session)).value;
    if (state == null) return;

    switch (target) {
      case DdaState.none:
        _resetIdleClock();
      case DdaState.pulse:
        final remaining = state.remainingWords;
        if (remaining.isNotEmpty) {
          final word = remaining[Random().nextInt(remaining.length)];
          final cell = state.grid.placements[word]?.first;
          if (cell != null) _pulse.pulse(cell);
        }
        _ddaState.value = DdaState.pulse;
      case DdaState.hintOffer:
        _ddaState.value = DdaState.hintOffer;
    }
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
    _resetIdleClock();
    final notifier = ref.read(gameControllerProvider(_session).notifier);
    final outcome = notifier.processSelection(selection);
    if (!outcome.isValid) return false;

    final state = ref.read(gameControllerProvider(_session)).value;
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
    final notifier = ref.read(gameControllerProvider(_session).notifier);
    notifier.pause();

    final action = await showModalBottomSheet<PauseAction>(
      context: context,
      builder: (_) => const PauseSheet(),
    );
    if (!mounted) return;

    switch (action) {
      case PauseAction.restart:
        notifier.restart();
        _resetIdleClock();
      case PauseAction.home:
        _recordAbandonIfNeeded();
        context.go(const HomeRoute().location);
      case PauseAction.resume:
      case null:
        notifier.resume();
        _resetIdleClock();
    }
  }

  Future<void> _useHint() async {
    _tapFeedback();
    _resetIdleClock();
    await ref.read(progressionControllerProvider.notifier).tryBuyHint(_session);
    // A denied spend leaves GameState untouched, so the hint button — which
    // renders straight off `GameState`/the coin balance — simply stays as it
    // was. No error dialog (CLAUDE.md → never a user-visible error for a
    // background/economy outcome); the balance itself is the explanation.
  }

  @override
  Widget build(BuildContext context) {
    final asyncState = ref.watch(gameControllerProvider(_session));
    // Read once: everything below — the AppBar and the body alike — is a
    // pure function of this one settled value.
    final state = asyncState.value;

    // LEVEL COMPLETE (Ch03/P11): confetti/stars/score are the card's own
    // TweenAnimationBuilder timeline (`level_complete_card.dart`) — this
    // listener owns the two P09 side effects that timeline can't reach
    // (audio/haptic), AND kicks off the P11 award, firing exactly once on the
    // phase TRANSITION into levelComplete, never on every rebuild while
    // already there.
    ref.listen(gameControllerProvider(_session), (previous, next) {
      final wasComplete = previous?.value?.phase == GamePhase.levelComplete;
      final isComplete = next.value?.phase == GamePhase.levelComplete;
      if (wasComplete || !isComplete) return;

      ref.read(audioServiceProvider).playLevelComplete();
      ref.read(hapticsServiceProvider).levelComplete();

      final summary = next.value?.completedSummary;
      if (summary == null) return;
      _chestDismissed.value = false;
      ref
          .read(progressionControllerProvider.notifier)
          .recordCompletion(summary)
          .then((reward) {
            if (!mounted) return;
            _reward.value = reward;
            // P17: Collector is known LOCALLY the instant a level completes
            // — no server round trip needed, unlike the six named
            // achievements the popup sync provider diffs off a Firestore
            // listener. Same queue either way, so two unlocks never overlap.
            for (final badge in reward.newBadges) {
              ref
                  .read(achievementPopupQueueProvider.notifier)
                  .enqueueIfUnseen(
                    CollectorAchievementUnlock(
                      category: badge.category,
                      language: badge.language,
                    ),
                  );
            }
          });
    });

    return SystemBackHandler(
      onBack: _leaveGame,
      child: Scaffold(
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
              rewardListenable: _reward,
              chestDismissed: _chestDismissed,
              particles: _particles,
              foundWordReveal: _reveal,
              pulseController: _pulse,
              ddaState: _ddaState,
              onAcceptFreeHint: _acceptFreeHint,
              onDismissHintOffer: _dismissHintOffer,
              urduIntroDismissed: _urduIntroDismissed,
              onDismissUrduIntro: _dismissUrduIntro,
              onDebugForceDda: _debugForceDda,
              onSelectionReleased: _onSelectionReleased,
              onLevelComplete: () {
                _tapFeedback();
                _reward.value = null;
                _chestDismissed.value = false;
                ref
                    .read(gameControllerProvider(_session).notifier)
                    .dismissLevelComplete();
                _resetIdleClock();
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Leaves the game the way both back affordances do — the AppBar's arrow
  /// and the Android system back alike, so the two cannot drift apart.
  ///
  /// Goes to the LEVEL MAP rather than Home: a player leaving a level is
  /// usually picking a different one, and the map is where every unlocked
  /// level (including ones already finished, which stay replayable) can be
  /// chosen. Home is one further tap from there. The daily has no map, so it
  /// returns to its own screen instead.
  void _leaveGame() {
    _recordAbandonIfNeeded();
    context.go(
      _session is DailySession
          ? const DailyRoute().location
          : const JourneyRoute().location,
    );
  }

  /// Placed at the Scaffold level rather than built inline: a plain
  /// `BackButton` pops the Navigator, but this route is reached with
  /// go_router's `.go()`, which leaves nothing to pop — so `leading` here
  /// navigates explicitly instead. The system back is handled by the
  /// [SystemBackHandler] wrapping the Scaffold, through the same callback.
  AppBar _buildAppBar(BuildContext context, GameState state) {
    final l10n = AppLocalizations.of(context);

    return AppBar(
      leading: BackButton(onPressed: _leaveGame),
      title: Text(
        state.isDaily ? l10n.navDaily : l10n.gameLevel('${state.level}'),
      ),
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
        _HintButton(state: state, onPressed: _useHint),
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
  final Future<void> Function() onPressed;

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
        onPressed: canHint ? () => unawaited(onPressed()) : null,
        icon: const Icon(Icons.lightbulb_outline),
      ),
    );
  }
}

/// Everything below the top bar: the grid (with the dev debug panel docked
/// over it) and the word-list panel, plus the level-complete overlay when
/// `state.phase` calls for it.
///
/// A separate widget purely so `_GameScreenBody.build` doesn't have to thread
/// the `AsyncValue` unwrap through a long body — `state` here is always the
/// settled [GameState].
class _GameContent extends ConsumerWidget {
  const _GameContent({
    required this.state,
    required this.rewardListenable,
    required this.chestDismissed,
    required this.particles,
    required this.foundWordReveal,
    required this.pulseController,
    required this.ddaState,
    required this.onAcceptFreeHint,
    required this.onDismissHintOffer,
    required this.urduIntroDismissed,
    required this.onDismissUrduIntro,
    required this.onDebugForceDda,
    required this.onSelectionReleased,
    required this.onLevelComplete,
  });

  final GameState state;

  /// `null` while `ProgressionController` is still resolving the award —
  /// `LevelCompleteCard` defaults its coins display to 0 in that gap, which
  /// reads as the roll simply not having started yet rather than as an error.
  /// A `ValueListenable` rather than a plain value so the card can pick up the
  /// award the moment it resolves without this whole subtree needing a
  /// Riverpod-driven rebuild — see `_GameScreenBodyState._reward`'s own doc.
  final ValueListenable<LevelReward?> rewardListenable;

  /// See `_GameScreenBodyState._chestDismissed`.
  final ValueNotifier<bool> chestDismissed;
  final ParticleController particles;
  final FoundWordRevealController foundWordReveal;

  /// Ch02/P12: drives the FTUE glow / DDA stuck-pulse on the grid.
  final PulseController pulseController;

  /// Ch02/P12: whether the free-hint offer banner is currently shown.
  final ValueListenable<DdaState> ddaState;
  final VoidCallback onAcceptFreeHint;
  final VoidCallback onDismissHintOffer;

  /// Ch02/P12: whether the one-time Urdu connected-form illustration has
  /// been dismissed (so it renders at most once, ever).
  final ValueListenable<bool> urduIntroDismissed;
  final VoidCallback onDismissUrduIntro;

  /// DEV-ONLY: forces [GameDebugPanel]'s DDA buttons through the real code
  /// paths. Null-safe to call — see `GameDebugPanel`'s own dev-only gating.
  final void Function(DdaState) onDebugForceDda;

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
            ValueListenableBuilder<bool>(
              valueListenable: urduIntroDismissed,
              builder: (context, dismissed, child) {
                final show =
                    !dismissed &&
                    state.language == Language.urdu &&
                    state.level == 1 &&
                    state.session is JourneySession;
                if (!show) return const SizedBox.shrink();
                return _UrduConnectedFormIntro(
                  word: state.allWords.isEmpty ? '' : state.allWords.first,
                  onDismiss: onDismissUrduIntro,
                );
              },
            ),
            ValueListenableBuilder<DdaState>(
              valueListenable: ddaState,
              builder: (context, dda, child) {
                if (dda != DdaState.hintOffer) return const SizedBox.shrink();
                return _DdaHintOfferBanner(
                  onAccept: onAcceptFreeHint,
                  onDismiss: onDismissHintOffer,
                );
              },
            ),
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
                      pulseController: pulseController,
                      onSelectionReleased: onSelectionReleased,
                      particleController: particles,
                      foundWordRevealController: foundWordReveal,
                      hapticsService: ref.watch(hapticsServiceProvider),
                      showPerfOverlay: isDev,
                    ),
                    if (isDev && state.session is JourneySession)
                      Positioned(
                        right: AppTokens.space8,
                        bottom: AppTokens.space8,
                        child: GameDebugPanel(
                          level: state.level,
                          onForceDda: onDebugForceDda,
                        ),
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
        // Zeigarnik (Ch02): for a journey level, GameController has already
        // generated the NEXT level's grid and word list by the time phase
        // reaches here, so the Column above is already showing it, behind
        // this card. A daily does not swap (there is no next daily today),
        // so the Column instead still shows the just-finished, fully-found
        // board.
        if (state.phase == GamePhase.levelComplete &&
            state.completedSummary != null)
          Positioned.fill(
            // Merged rather than a `ValueListenableBuilder` on the reward
            // alone: the chest's dismissal is a second, independent piece of
            // state this subtree renders from, and nesting two builders to
            // read two flags would be more machinery than one merge.
            child: AnimatedBuilder(
              animation: Listenable.merge([rewardListenable, chestDismissed]),
              builder: (context, child) {
                final reward = rewardListenable.value;
                // A chest (every `chest_every_n_levels`-th level, Ch02) takes
                // the screen FIRST and the result card waits behind it — the
                // chest is the rarer, louder moment, and stacking it on top of
                // an already-celebrating card would bury it. Dismissing the
                // chest reveals the card underneath, with the chest's coins
                // already included in the figure it rolls up to.
                final chest = reward?.chest;
                if (chest != null && !chestDismissed.value) {
                  return ChestOpenCard(
                    reward: chest,
                    onDismiss: () => chestDismissed.value = true,
                  );
                }
                return LevelCompleteCard(
                  summary: state.completedSummary!,
                  coinsEarned: reward?.coinsEarned ?? 0,
                  onContinue: onLevelComplete,
                );
              },
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

/// The Ch02 60s DDA offer: "a soft inline prompt", never a dialog — the
/// grid stays fully visible and playable underneath it (CLAUDE.md → never
/// block gameplay on anything, including the game's own systems). Copy is
/// deliberately neutral: no mention of being stuck, of difficulty, or of the
/// game doing anything different — see `dda.dart`'s [DdaState] doc and
/// CLAUDE.md's "never surface any message implying the game was made
/// easier".
class _DdaHintOfferBanner extends StatelessWidget {
  const _DdaHintOfferBanner({required this.onAccept, required this.onDismiss});

  final VoidCallback onAccept;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = AppTokens.of(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppTokens.space16,
        AppTokens.space8,
        AppTokens.space16,
        0,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.space16,
        vertical: AppTokens.space8,
      ),
      decoration: BoxDecoration(
        color: tokens.elevation1.surface,
        borderRadius: AppTokens.borderRadius16,
        border: Border.all(color: tokens.colors.outlineSoft),
        boxShadow: tokens.elevation1.shadows,
      ),
      child: Row(
        children: [
          Icon(Icons.lightbulb_outline, color: tokens.colors.info),
          const SizedBox(width: AppTokens.space12),
          Expanded(child: Text(l10n.ddaHintOfferMessage)),
          TextButton(onPressed: onAccept, child: Text(l10n.ddaHintOfferAccept)),
          IconButton(
            tooltip: l10n.ddaHintOfferDismiss,
            onPressed: onDismiss,
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }
}

/// Ch02 FTUE: "For Urdu only, on the very first level, show a one-time
/// inline illustration mapping the connected word form to its isolated
/// letters, with an arrow. Once. Never again." [word] renders as a whole
/// (its own font shaping joins the letters, exactly as the word chip below
/// the grid already shows it); the row underneath re-splits it through
/// [ScriptNormalizer.graphemes] — the SAME call `GridGenerator` used to place
/// it — so each letter renders alone, in the isolated presentation form the
/// grid itself shows.
class _UrduConnectedFormIntro extends StatelessWidget {
  const _UrduConnectedFormIntro({required this.word, required this.onDismiss});

  final String word;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = AppTokens.of(context);
    final letters = word.isEmpty
        ? const <String>[]
        : ScriptNormalizer.graphemes(word, Language.urdu);

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppTokens.space16,
        AppTokens.space8,
        AppTokens.space16,
        0,
      ),
      padding: const EdgeInsets.all(AppTokens.space16),
      decoration: BoxDecoration(
        color: tokens.elevation1.surface,
        borderRadius: AppTokens.borderRadius16,
        border: Border.all(color: tokens.colors.outline),
        boxShadow: tokens.elevation1.shadows,
      ),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.urduLetterFormIntro,
              textAlign: TextAlign.center,
              style: AppTypography.uiTextStyle(
                Language.urdu,
                UiRole.body,
                color: tokens.colors.onSurface,
              ),
            ),
            const SizedBox(height: AppTokens.space12),
            Text(
              word,
              textAlign: TextAlign.center,
              style: AppTypography.uiTextStyle(
                Language.urdu,
                UiRole.title,
                color: tokens.colors.onSurface,
              ),
            ),
            const SizedBox(height: AppTokens.space8),
            Icon(
              Icons.arrow_downward_rounded,
              color: tokens.colors.onSurfaceMuted,
            ),
            const SizedBox(height: AppTokens.space8),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: AppTokens.space8,
              runSpacing: AppTokens.space8,
              children: [
                for (final letter in letters)
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tokens.colors.surfaceElevated,
                      borderRadius: AppTokens.borderRadius8,
                      border: Border.all(color: tokens.colors.outline),
                    ),
                    child: Text(
                      letter,
                      style: AppTypography.gridTextStyle(
                        Language.urdu,
                        cellSize: 36,
                        color: tokens.colors.onSurface,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppTokens.space12),
            Align(
              alignment: Alignment.center,
              child: TextButton(
                onPressed: onDismiss,
                child: Text(l10n.gotItButtonLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
