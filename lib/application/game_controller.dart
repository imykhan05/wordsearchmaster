/// The playable game's state machine (P07, extended in P11).
///
/// ARCHITECTURE DECISIONS, IN ONE PLACE:
///
/// 1. EVENTS ARE THE SOURCE OF TRUTH. [GameState] stores an ordered
///    [ScoreEvent] log, not `score`/`combo`/`hintsUsed` counters. Those are
///    derived getters on [GameState] itself, computed by replaying the log
///    through `Scoring` (see the spec header in
///    lib/domain/scoring/scoring.dart). This mirrors Ch08's anti-cheat shape
///    on purpose: the log this controller builds is exactly what a future
///    submission sends to the server, so there is only ever one code path
///    that turns events into a number.
///
/// 2. NO LIVE SELECTION IN STATE. The bible's GameState shape names a
///    `selection` field; it is deliberately absent here. P06 spent an entire
///    prompt making sure a moving finger repaints one capsule through a
///    `ValueNotifier` and rebuilds NOTHING — routing per-frame drag updates
///    through Riverpod would rebuild the word-list panel and the top bar 60
///    times a second and undo that work. [GameGrid] keeps owning the live
///    drag exactly as P06 left it; this controller only ever sees a FINISHED
///    drag, via [GameController.processSelection], which returns the outcome
///    directly to the caller instead of parking it in state — nothing else
///    needs to remember it once the caller's particle burst has fired.
///
/// 3. THE ZEIGARNIK SWAP (Ch02) IS ATOMIC, AND JOURNEY-ONLY. The moment a
///    journey level is won, `_prepareLevelComplete` both freezes a
///    [LevelCompletionSummary] of the level just finished AND regenerates the
///    grid for the NEXT level, in the same state update. `phase` becomes
///    `levelComplete` while `level`, `grid` and the word list already describe
///    the level after it — so the result card sits on top of a fully playable
///    next board, and dismissing the card is just a phase flip, never a new
///    load. A DAILY does not swap: there is no next daily today, so the board
///    stays put and the card's dismiss sends the player back rather than into
///    another puzzle.
///
/// 4. CONTENT COMES FROM `ContentRepository`, NOT FROM DART (P10/P11). The
///    seed, grid size, word count, direction tier and word list of every
///    puzzle are read from `assets/content/`. P07's `_demoWords` constant and
///    its inline size ladder are gone; a level's identity now lives in the
///    same validated content pack `tool/validate_content.dart` checks.
///
/// 5. AWARDS ARE NOT COMPUTED HERE. Coins, chests, the streak and collection
///    badges all follow a completion, but all of them need the database and
///    all of them are async. Mixing them into `processSelection` would make
///    the synchronous, purely-derived heart of this controller await I/O. So
///    the summary this file freezes is the GAMEPLAY result — level, score,
///    stars, combo — and `ProgressionController` turns that into rewards on
///    the phase transition. See its header for the seam.
library;

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../app/language/selected_language.dart';
import '../data/content/content_repository.dart';
import '../domain/grid/cell.dart';
import '../domain/grid/grid_directions.dart';
import '../domain/grid/grid_generator.dart';
import '../domain/grid/grid_result.dart';
import '../domain/grid/selection_resolver.dart';
import '../domain/models/level_definition.dart';
import '../domain/progression/daily_puzzle.dart';
import '../domain/scoring/score_event.dart';
import '../domain/scoring/scoring.dart';
import '../domain/text/language.dart';
import 'game_session.dart';

export 'game_session.dart';

part 'game_controller.freezed.dart';
part 'game_controller.g.dart';

/// Where the game screen is in its lifecycle.
enum GamePhase {
  /// [GameController.build] is still generating the initial grid.
  loading,
  playing,
  levelComplete,
  paused,
}

/// A snapshot of one finished level, frozen at the moment it was won.
///
/// Captured once rather than derived live: by the time the result card shows
/// it, [GameController] has already moved [GameState] on to the NEXT level's
/// grid and word list (the Zeigarnik swap above), so the numbers this level
/// scored are no longer recoverable from live state.
///
/// GAMEPLAY ONLY — no coins, no chest, no streak. Decision 5 above: those are
/// `ProgressionController`'s output, keyed off this.
final class LevelCompletionSummary {
  const LevelCompletionSummary({
    required this.session,
    required this.language,
    required this.level,
    required this.score,
    required this.stars,
    required this.maxCombo,
    required this.hintsUsed,
    required this.events,
  });

  /// Which puzzle this summarises. Carried so `ProgressionController` can tell
  /// a journey completion (progress row + coins + streak) from a daily one
  /// (daily_results row + streak, no journey progress) without guessing from
  /// the level number.
  final GameSession session;

  /// `GameState.language` at the moment of completion — `level_progress` and
  /// `daily_results` are both keyed by (language, ...) (P10/CLAUDE.md), and
  /// this summary is `ProgressionController`'s only input, so it has to carry
  /// its own copy rather than the caller re-reading live state that may have
  /// already moved on (Zeigarnik).
  final Language language;

  final int level;
  final int score;
  final int stars;
  final int maxCombo;
  final int hintsUsed;

  /// The ordered log this level produced. Handed to the repositories so the
  /// outbox payload carries the events the server replays (Ch08/P14) rather
  /// than the client's total.
  final List<ScoreEvent> events;

  bool get isDaily => session is DailySession;

  @override
  bool operator ==(Object other) =>
      other is LevelCompletionSummary &&
      other.session == session &&
      other.language == language &&
      other.level == level &&
      other.score == score &&
      other.stars == stars &&
      other.maxCombo == maxCombo &&
      other.hintsUsed == hintsUsed;

  @override
  int get hashCode =>
      Object.hash(session, language, level, score, stars, maxCombo, hintsUsed);

  @override
  String toString() =>
      'LevelCompletionSummary($session, ${language.code}, level: $level, '
      'score: $score, stars: $stars, maxCombo: $maxCombo, '
      'hints: $hintsUsed)';
}

/// The game screen's entire state, minus the live drag (see decision 2
/// above). Immutable; [GameController] always replaces it wholesale.
///
/// Uses freezed rather than a hand-written class, unlike most value types in
/// `lib/domain/` — this one earns it: ten fields, mutated from eight
/// different call sites in [GameController], is exactly the shape a
/// hand-written `copyWith` gets tedious and error-prone for.
@freezed
sealed class GameState with _$GameState {
  const GameState._();

  const factory GameState({
    required GameSession session,
    required int level,
    required Language language,
    required GridResult grid,

    /// Normalized words found so far, in the order found — the order the
    /// word-list panel assigns found-word colours by (Ch03).
    required List<String> foundWords,
    required List<ScoreEvent> events,

    /// The cell [GameController.useHint] most recently pointed at. Cleared
    /// whenever any word is found, since the remaining-word set has just
    /// changed underneath it.
    required Cell? hintedCell,
    required DateTime startedAt,
    required GamePhase phase,
    required LevelCompletionSummary? completedSummary,
  }) = _GameState;

  bool get isDaily => session is DailySession;

  /// Every target word for this level, in the grid's own placement order.
  List<String> get allWords => grid.placements.keys.toList(growable: false);

  /// Words not yet found, in the same order as [allWords]. What
  /// [GameController] hands `SelectionResolver.release` as the candidate set.
  List<String> get remainingWords =>
      allWords.where((word) => !foundWords.contains(word)).toList();

  bool get isLevelWon => remainingWords.isEmpty && allWords.isNotEmpty;

  /// Replays [events]. See the scoring spec header in
  /// lib/domain/scoring/scoring.dart for why this is a replay and not a
  /// running counter.
  int get score => Scoring.computeScore(events);

  int get hintsUsed => Scoring.hintsIn(events);

  int get stars => Scoring.computeStars(hintsUsed: hintsUsed);

  /// The RUNNING combo — consecutive correct words since the last miss, for
  /// the top bar. Distinct from `Scoring.maxComboIn`, which is the best run
  /// of the whole level and is only read once, at completion.
  int get combo => _runningCombo(events);

  /// Wall-clock time since the level started. Relaxed mode never renders
  /// this — `Scoring.computeStars` deliberately takes no time input — but it
  /// still feeds level-completion analytics (Ch11).
  Duration get elapsed => DateTime.now().difference(startedAt);
}

int _runningCombo(List<ScoreEvent> events) {
  var combo = 0;
  for (final event in events) {
    switch (event) {
      case WordFound():
        combo++;
      case WrongSelection():
        combo = 0;
      case HintUsed():
        break;
    }
  }
  return combo;
}

/// Drives one game screen, keyed by the session it was OPENED with.
///
/// For a journey session the key is the STARTING level only — advancing
/// (Zeigarnik) mutates `state.level` in place rather than creating a new
/// provider instance, so the screen never has to re-navigate or remount.
@riverpod
class GameController extends _$GameController {
  @override
  Future<GameState> build(GameSession session) async {
    // Watched, not read: switching language mid-session must regenerate the
    // grid for the new script, exactly as P06's screen-level rebuild did.
    final language = ref.watch(selectedLanguageProvider);
    final content = await ref.watch(contentRepositoryProvider.future);

    return _loadSession(
      session: session,
      language: language,
      content: content,
      level: session.level,
    );
  }

  /// Resolves a finished drag against the puzzle and applies its effect.
  ///
  /// Returns the outcome so the caller can fire a particle burst — see
  /// decision 2 above for why that value is never stored in [GameState].
  SelectionOutcome processSelection(SelectionState selection) {
    final current = state.value;
    if (current == null || current.phase != GamePhase.playing) {
      return SelectionOutcome.none;
    }
    // A tap is not an attempt (Ch06); do not log it as a wrong selection.
    if (selection.cells.length < 2) return SelectionOutcome.none;

    final resolver = SelectionResolver(size: current.grid.size);
    final outcome = resolver.release(
      state: selection,
      grid: current.grid.cells,
      remainingWords: current.remainingWords,
      language: current.language,
    );

    final matchedWord = outcome.matchedWord;
    final event = matchedWord != null
        ? WordFound(graphemeCount: outcome.cells.length)
        : const WrongSelection();

    var next = current.copyWith(
      events: [...current.events, event],
      foundWords: matchedWord != null
          ? [...current.foundWords, matchedWord]
          : current.foundWords,
      hintedCell: matchedWord != null ? null : current.hintedCell,
    );

    if (matchedWord != null && next.isLevelWon) {
      next = _prepareLevelComplete(next);
    }

    state = AsyncData(next);
    return outcome;
  }

  /// Spends a hint on the next unfound word, revealing only its starting
  /// cell — enough to nudge, not enough to solve the word for the player.
  ///
  /// THE COINS ARE NOT SPENT HERE. `ProgressionController.tryBuyHint` debits
  /// the ledger and calls this only if the debit succeeded, for the same
  /// reason awards are not computed here (decision 5): the wallet is async and
  /// this is not. A caller that skips that step gets a free hint, which is why
  /// `game_screen.dart` routes every hint tap through the progression
  /// controller and nothing else calls this.
  void useHint() {
    final current = state.value;
    if (current == null || current.phase != GamePhase.playing) return;

    final remaining = current.remainingWords;
    if (remaining.isEmpty) return;
    final targetCell = current.grid.placements[remaining.first]!.first;

    state = AsyncData(
      current.copyWith(
        events: [...current.events, const HintUsed()],
        hintedCell: targetCell,
      ),
    );
  }

  void pause() {
    final current = state.value;
    if (current == null || current.phase != GamePhase.playing) return;
    state = AsyncData(current.copyWith(phase: GamePhase.paused));
  }

  void resume() {
    final current = state.value;
    if (current == null || current.phase != GamePhase.paused) return;
    state = AsyncData(current.copyWith(phase: GamePhase.playing));
  }

  /// Reloads the CURRENT level from scratch and unpauses. Same seed, same
  /// grid (P04 determinism) — only the found words and score reset.
  Future<void> restart() async {
    final current = state.value;
    if (current == null) return;

    final content = await ref.read(contentRepositoryProvider.future);
    state = AsyncData(
      _loadSession(
        session: current.session,
        language: current.language,
        content: content,
        level: current.level,
      ),
    );
  }

  void dismissLevelComplete() {
    final current = state.value;
    if (current == null || current.phase != GamePhase.levelComplete) return;
    state = AsyncData(
      current.copyWith(phase: GamePhase.playing, completedSummary: null),
    );
  }

  /// DEV-ONLY: jumps straight to [level], bypassing normal progression.
  Future<void> jumpToLevel(int level) async {
    final current = state.value;
    final language = current?.language ?? Language.english;
    final content = await ref.read(contentRepositoryProvider.future);

    state = AsyncData(
      _loadSession(
        session: JourneySession(level),
        language: language,
        content: content,
        level: level,
      ),
    );
  }

  /// DEV-ONLY: forces [phase] without playing to it. Forcing
  /// [GamePhase.levelComplete] still runs the real Zeigarnik swap, so the
  /// debug panel exercises the same path a genuine win does rather than
  /// showing a result card over a stale board.
  void debugForcePhase(GamePhase phase) {
    final current = state.value;
    if (current == null) return;

    if (phase == GamePhase.levelComplete) {
      state = AsyncData(_prepareLevelComplete(current));
      return;
    }
    state = AsyncData(
      current.copyWith(
        phase: phase,
        completedSummary: phase == GamePhase.playing
            ? null
            : current.completedSummary,
      ),
    );
  }

  GameState _loadSession({
    required GameSession session,
    required Language language,
    required ContentRepository content,
    required int level,
  }) {
    final definition = _definitionFor(
      session: session,
      language: language,
      content: content,
      level: level,
    );

    return GameState(
      session: session,
      level: level,
      language: language,
      grid: _generateGrid(definition: definition, content: content),
      foundWords: const [],
      events: const [],
      hintedCell: null,
      startedAt: DateTime.now(),
      phase: GamePhase.playing,
      completedSummary: null,
    );
  }

  /// The Zeigarnik swap for a journey level: freeze this level's summary and
  /// move [wonState] on to the next level's grid, all at once (decision 3).
  ///
  /// A DAILY skips the swap entirely and keeps its own finished board on
  /// screen behind the card — regenerating "the next daily" would mean
  /// showing tomorrow's puzzle a day early, and there is nothing else to move
  /// to.
  GameState _prepareLevelComplete(GameState wonState) {
    final summary = LevelCompletionSummary(
      session: wonState.session,
      language: wonState.language,
      level: wonState.level,
      score: wonState.score,
      stars: wonState.stars,
      maxCombo: Scoring.maxComboIn(wonState.events),
      hintsUsed: wonState.hintsUsed,
      events: List.unmodifiable(wonState.events),
    );

    switch (wonState.session) {
      case DailySession():
        return wonState.copyWith(
          phase: GamePhase.levelComplete,
          completedSummary: summary,
        );

      case JourneySession():
        final content = ref.read(contentRepositoryProvider).value;
        // Only reachable if the content pack failed to load, in which case
        // the state we are in was built from it too. Freeze the summary and
        // hold the finished board rather than crashing on the win.
        if (content == null) {
          return wonState.copyWith(
            phase: GamePhase.levelComplete,
            completedSummary: summary,
          );
        }

        final nextLevel = wonState.level + 1;
        final definition = _definitionFor(
          session: JourneySession(nextLevel),
          language: wonState.language,
          content: content,
          level: nextLevel,
        );

        return wonState.copyWith(
          level: nextLevel,
          grid: _generateGrid(definition: definition, content: content),
          foundWords: const [],
          events: const [],
          hintedCell: null,
          startedAt: DateTime.now(),
          phase: GamePhase.levelComplete,
          completedSummary: summary,
        );
    }
  }

  static LevelDefinition _definitionFor({
    required GameSession session,
    required Language language,
    required ContentRepository content,
    required int level,
  }) => switch (session) {
    JourneySession() => content.getLevel(level, language),
    DailySession(:final day) => DailyPuzzle.definitionFor(
      day: day,
      language: language,
      seed: content.getDailySeed(day.utcMidnight, language),
      categories: content.categoriesFor(language),
    ),
  };

  static GridResult _generateGrid({
    required LevelDefinition definition,
    required ContentRepository content,
  }) {
    final words = content.getWordsForLevel(definition);

    return GridGenerator.generate(
      // The definition's own seed — the same one `validate_content.dart`
      // proved places completely for all 900 (level, language) combinations,
      // so a grid built here is a grid that has already been checked.
      seed: definition.seed,
      size: definition.gridSize,
      words: [for (final entry in words) entry.word],
      lang: definition.language,
      allowedDirections: GridDirections.forLanguage(
        definition.language,
        definition.directionTier,
      ),
    );
  }
}
