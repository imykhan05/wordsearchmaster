/// The playable game's state machine (P07).
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
/// 3. THE ZEIGARNIK SWAP (Ch02) IS ATOMIC. The moment a level is won,
///    `_prepareLevelComplete` both freezes a [LevelCompletionSummary] of the
///    level just finished AND regenerates the grid for the NEXT level, in
///    the same state update. `phase` becomes `levelComplete` while `level`,
///    `grid` and the word list already describe the level after it — so the
///    result card sits on top of a fully playable next board, and dismissing
///    the card is just a phase flip, never a new load.
library;

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../app/language/selected_language.dart';
import '../domain/grid/cell.dart';
import '../domain/grid/grid_directions.dart';
import '../domain/grid/grid_generator.dart';
import '../domain/grid/grid_result.dart';
import '../domain/grid/selection_resolver.dart';
import '../domain/scoring/score_event.dart';
import '../domain/scoring/scoring.dart';
import '../domain/text/language.dart';

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
final class LevelCompletionSummary {
  const LevelCompletionSummary({
    required this.level,
    required this.score,
    required this.stars,
    required this.maxCombo,
    required this.coinsEarned,
  });

  final int level;
  final int score;
  final int stars;
  final int maxCombo;

  /// TODO(P15/P16): placeholder formula. The real coin economy lives in
  /// `lib/domain/progression/`, which does not exist yet — this keeps the
  /// result card honest (a real, earned number) without inventing a chest /
  /// currency system ahead of the prompt that owns it.
  final int coinsEarned;

  @override
  bool operator ==(Object other) =>
      other is LevelCompletionSummary &&
      other.level == level &&
      other.score == score &&
      other.stars == stars &&
      other.maxCombo == maxCombo &&
      other.coinsEarned == coinsEarned;

  @override
  int get hashCode => Object.hash(level, score, stars, maxCombo, coinsEarned);

  @override
  String toString() =>
      'LevelCompletionSummary(level: $level, score: $score, stars: $stars, '
      'maxCombo: $maxCombo, coinsEarned: $coinsEarned)';
}

/// The game screen's entire state, minus the live drag (see decision 2
/// above). Immutable; [GameController] always replaces it wholesale.
///
/// Uses freezed rather than a hand-written class, unlike most value types in
/// `lib/domain/` — this one earns it: nine fields, mutated from eight
/// different call sites in [GameController], is exactly the shape a
/// hand-written `copyWith` gets tedious and error-prone for.
@freezed
sealed class GameState with _$GameState {
  const GameState._();

  const factory GameState({
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

  /// Every target word for this level, in the grid's own placement order.
  List<String> get allWords => grid.placements.keys.toList(growable: false);

  /// Words not yet found, in the same order as [allWords]. What
  /// [GameController] hands `SelectionResolver.release` as the candidate set.
  List<String> get remainingWords =>
      allWords.where((word) => !foundWords.contains(word)).toList();

  bool get isLevelWon => remainingWords.isEmpty;

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

/// Coins awarded per star on completion. See the TODO on
/// [LevelCompletionSummary.coinsEarned].
const int _coinsPerStar = 10;

/// TODO(P10): comes from the content pack. Inline here only so the game is
/// playable end to end; moved verbatim from P06's `game_screen.dart`.
const Map<Language, List<String>> _demoWords = {
  Language.english: [
    'WATER',
    'STONE',
    'RIVER',
    'FOREST',
    'LIGHT',
    'EARTH',
    'STORM',
    'SEED',
  ],
  Language.urdu: ['پانی', 'بادل', 'ہوا', 'زمین', 'درخت', 'دریا', 'سورج', 'برف'],
  Language.hindi: ['पानी', 'बादल', 'हवा', 'धरती', 'नदी', 'सूरज', 'रात', 'तारा'],
};

/// Drives one game screen. Family-keyed by the STARTING level only —
/// advancing to the next level (Zeigarnik) mutates `state.level` in place
/// rather than creating a new provider instance, so the screen never has to
/// re-navigate or remount to keep playing.
@riverpod
class GameController extends _$GameController {
  @override
  Future<GameState> build(int initialLevel) async {
    // Watched, not read: switching language mid-session must regenerate the
    // grid for the new script, exactly as P06's screen-level rebuild did.
    final language = ref.watch(selectedLanguageProvider);
    return _loadLevel(level: initialLevel, language: language);
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
  void restart() {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(
      _loadLevel(level: current.level, language: current.language),
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
  void jumpToLevel(int level) {
    final language = state.value?.language ?? Language.english;
    state = AsyncData(_loadLevel(level: level, language: language));
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

  GameState _loadLevel({required int level, required Language language}) {
    return GameState(
      level: level,
      language: language,
      grid: _generateGrid(level: level, language: language),
      foundWords: const [],
      events: const [],
      hintedCell: null,
      startedAt: DateTime.now(),
      phase: GamePhase.playing,
      completedSummary: null,
    );
  }

  /// The Zeigarnik swap: freeze this level's summary and move [wonState] on
  /// to the next level's grid, all at once. See decision 3 above.
  GameState _prepareLevelComplete(GameState wonState) {
    final summary = LevelCompletionSummary(
      level: wonState.level,
      score: wonState.score,
      stars: wonState.stars,
      maxCombo: Scoring.maxComboIn(wonState.events),
      coinsEarned: wonState.stars * _coinsPerStar,
    );

    final nextLevel = wonState.level + 1;
    return wonState.copyWith(
      level: nextLevel,
      grid: _generateGrid(level: nextLevel, language: wonState.language),
      foundWords: const [],
      events: const [],
      hintedCell: null,
      startedAt: DateTime.now(),
      phase: GamePhase.levelComplete,
      completedSummary: summary,
    );
  }

  static GridResult _generateGrid({
    required int level,
    required Language language,
  }) {
    return GridGenerator.generate(
      // The level number IS the seed, so the same level always rebuilds the
      // same grid (P04). P10 stores a real per-level seed.
      seed: level * 7919,
      size: level <= 5
          ? 6
          : level <= 20
          ? 8
          : level <= 60
          ? 10
          : 12,
      words: _demoWords[language]!,
      lang: language,
      allowedDirections: GridDirections.forLevel(language, level),
    );
  }
}
