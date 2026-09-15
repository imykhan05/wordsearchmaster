/// Turns a finished level into rewards, and writes them (P11).
///
/// ---------------------------------------------------------------------------
/// WHY THIS EXISTS SEPARATELY FROM `GameController`
///
/// `GameController` is synchronous and pure-derived on purpose (its own file
/// header, decision 1): every getter on `GameState` is a replay of `events`,
/// with no I/O anywhere in the chain. Coins, chests, the streak and
/// collection badges all need the database, and the database is async. Mixing
/// them into `GameController.processSelection` would make the moment a word
/// is found — the hottest path in the whole app — await a transaction. So the
/// fork is exact: `GameController` freezes the GAMEPLAY facts
/// (`LevelCompletionSummary`) the instant a level is won; this controller
/// turns that summary into everything that touches a repository, on its own
/// time, after the fact.
///
/// `game_screen.dart` is the seam: its existing `ref.listen` for the
/// `levelComplete` phase transition (already firing the completion audio/
/// haptic) is where [ProgressionController.recordCompletion] is called.
///
/// ---------------------------------------------------------------------------
/// EVERY `ref` READ HAPPENS BEFORE THE FIRST `await`. THIS IS LOAD-BEARING.
///
/// A `Ref` is only valid while its provider is alive, and a provider is
/// disposed the moment nothing is watching it. Nothing WATCHES this one — it
/// is reached through `ref.read(...notifier)` and called — so a read placed
/// after an `await` races its own disposal and throws
/// `UnmountedRefException`. That is not a theoretical hazard: it is exactly
/// what happens when a player taps back out of the game screen while the
/// award for the level they just finished is still being written, and the
/// visible symptom is coins that silently never arrive.
///
/// Two things guard it. [keepAlive] keeps the provider itself alive across
/// that gap, and — belt and braces, because `keepAlive` is one annotation
/// away from being deleted by someone tidying up — every method below
/// resolves ITS ENTIRE dependency set synchronously at the top, then awaits.
/// The repository providers are futures, so this means holding the `Future`
/// and awaiting it later, never re-reading `ref` to get it.
library;

import 'dart:math';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/content/content_repository.dart';
import '../data/repositories/ad_repository.dart';
import '../data/repositories/coins_repository.dart';
import '../data/repositories/collections_repository.dart';
import '../data/repositories/daily_repository.dart';
import '../data/repositories/dda_repository.dart';
import '../data/repositories/progress_repository.dart';
import '../data/repositories/streak_repository.dart';
import '../domain/progression/coin_economy.dart';
import '../domain/progression/collections.dart';
import '../domain/progression/streak.dart';
import '../domain/text/language.dart';
import '../services/remote_config/remote_config.dart';
import '../services/time/trusted_clock.dart';
import 'game_controller.dart';

part 'progression_controller.g.dart';

/// Everything one completion paid out.
final class LevelReward {
  const LevelReward({
    required this.coinsEarned,
    required this.streak,
    this.chest,
    this.newBadges = const [],
    this.alreadyRecorded = false,
  });

  /// Total coins credited, level base + star bonus + any [chest]. What
  /// `LevelCompleteCard.coinsEarned` shows.
  final int coinsEarned;

  final ChestReward? chest;

  /// What happened to the streak — see `StreakEvent` for why this is a value
  /// worth returning rather than swallowing: a freeze firing silently is the
  /// one streak outcome that would read as a bug to the player who has one.
  final StreakTransition streak;

  final List<CategoryBadge> newBadges;

  /// True only for a DAILY whose one attempt was already spent — see
  /// [ProgressionController.recordCompletion]. Nothing was written and
  /// nothing was paid out; the caller should not celebrate a second time.
  final bool alreadyRecorded;

  @override
  String toString() =>
      'LevelReward(coins: $coinsEarned, chest: $chest, '
      'streak: ${streak.event.name}, badges: ${newBadges.length}'
      '${alreadyRecorded ? ', ALREADY RECORDED' : ''})';
}

@Riverpod(keepAlive: true)
class ProgressionController extends _$ProgressionController {
  @override
  void build() {}

  /// The combined tail of every [recordCompletion] write started so far.
  /// See [awaitPendingCompletion] for why this exists.
  Future<void> _pending = Future<void>.value();

  /// Waits for every [recordCompletion] write started so far to actually
  /// land in the database — including ones already in flight.
  ///
  /// EVERY PATH OFF THE GAME SCREEN MUST AWAIT THIS BEFORE NAVIGATING AWAY.
  /// `recordCompletion` starts writing the instant a level is won and
  /// returns to its caller immediately — `game_screen.dart`'s `ref.listen`
  /// never awaits it itself, by design (see this class's own header on why
  /// a `Ref` read cannot sit after an `await` in that listener). That is
  /// fine as long as the write gets to finish somewhere before the screen
  /// can leave; it is NOT fine if the player finishes several levels back
  /// to back and backs out (or the OS kills the app) faster than each save
  /// can land. The level that write was for then reappears LOCKED next time
  /// the journey map loads, because `JourneyMap.build` trusts nothing but
  /// the rows Drift actually holds (that function's own doc) — a save that
  /// never finished landing is, from the map's point of view, a level that
  /// was never played. This is the one seam that closes that gap without
  /// making the hot completion path itself block on I/O.
  Future<void> awaitPendingCompletion() => _pending;

  /// Records [summary] and returns what it paid out. THE WRITE PATH for every
  /// P11 retention system at once — coins, chest, streak, collections,
  /// progress/daily persistence — because they all key off the same
  /// completion and a caller that fired them separately could see them land
  /// out of order (a badge computed before the progress row it depends on is
  /// visible, say).
  Future<LevelReward> recordCompletion(LevelCompletionSummary summary) {
    final result = _recordCompletion(summary);
    // Chained onto whatever was already pending — not run after it, just
    // tracked alongside it — so two completions started close together
    // (exactly the "cleared 2 levels back to back" case this exists for)
    // leave [awaitPendingCompletion] waiting for BOTH, not just whichever
    // started last. The `onError` here only stops one failed write from
    // poisoning an UNRELATED caller's wait; [result] itself still carries
    // the real error to whoever is awaiting this specific completion.
    final previousPending = _pending;
    _pending = Future.wait([
      previousPending,
      result.then((_) {}, onError: (_) {}),
    ]).then((_) {});
    return result;
  }

  Future<LevelReward> _recordCompletion(LevelCompletionSummary summary) async {
    // ---- every ref read, before any await. See the library header. ----
    final economy = ref.read(coinEconomyProvider);
    final clock = ref.read(trustedClockProvider);
    final streakRepoFuture = ref.read(streakRepositoryProvider.future);
    final coinsRepoFuture = ref.read(coinsRepositoryProvider.future);
    final dailyRepoFuture = ref.read(dailyRepositoryProvider.future);
    final progressRepoFuture = ref.read(progressRepositoryProvider.future);
    final collectionsRepoFuture = ref.read(
      collectionsRepositoryProvider.future,
    );
    final contentFuture = ref.read(contentRepositoryProvider.future);
    final ddaRepoFuture = ref.read(ddaRepositoryProvider.future);
    final adRepoFuture = ref.read(adRepositoryProvider.future);
    // -------------------------------------------------------------------

    final today = await clock.today();
    final streakRepo = await streakRepoFuture;
    final streak = await streakRepo.registerPlay(today);

    final coinsRepo = await coinsRepoFuture;

    switch (summary.session) {
      case DailySession():
        final dailyRepo = await dailyRepoFuture;
        final recorded = await dailyRepo.recordDailyComplete(
          day: today,
          language: summary.language,
          score: summary.score,
          stars: summary.stars,
          events: summary.events,
        );
        // One attempt per day (Ch12): a second completion of an
        // already-recorded daily — replaying via the debug panel, or a stale
        // card the player dismissed and reopened — pays out nothing further.
        // The streak still registered above; a player who is only replaying
        // for fun should not lose today's streak credit over it.
        if (!recorded) {
          return LevelReward(
            coinsEarned: 0,
            streak: streak,
            alreadyRecorded: true,
          );
        }

        final coins = economy.coinsForLevel(stars: summary.stars);
        await coinsRepo.record(
          delta: coins,
          reason: 'daily:${summary.language.code}:$today',
        );

        return LevelReward(coinsEarned: coins, streak: streak);

      case JourneySession():
        // THE LEVEL COMES FROM THE SUMMARY, NEVER FROM THE SESSION.
        //
        // This branch used to read `case JourneySession(:final level)`, and
        // that one word cost a player every level they cleared without
        // leaving the screen. A journey session is the family key, and its
        // `level` is the level the SCREEN WAS OPENED WITH — the Zeigarnik
        // swap (`GameController._prepareLevelComplete`) advances
        // `GameState.level` IN PLACE and deliberately does not build a new
        // session, so from the second level onward `session.level` is stale
        // by exactly the number of times Continue has been tapped.
        //
        // The visible bug: clear 1, Continue, clear 2, Continue, clear 3,
        // then back out — and levels 2 and 3 had both been written into
        // LEVEL 1's row (best-of upsert, same (language, level) key), so the
        // map showed one level cleared, two unlocked, the rest locked. It
        // could only ever look right when the player backed out after every
        // level, because that remounts the screen with a fresh
        // `JourneySession(n)` whose level happens to match again.
        //
        // `LevelCompletionSummary` carries its own `level` for exactly this
        // reason, the same reason its `language` doc already gives: it is
        // this controller's ONLY input, and live state has already moved on
        // by the time this runs.
        final level = summary.level;
        final progressRepo = await progressRepoFuture;
        // Read BEFORE the write. `Collections.newlyEarnedBy` needs the set as
        // it was, not as it will be — see its doc for why reconstructing
        // "before" from "after" gets a replay wrong.
        final completedBefore = await progressRepo.completedLevels(
          summary.language,
        );

        await progressRepo.recordLevelComplete(
          language: summary.language,
          level: level,
          stars: summary.stars,
          score: summary.score,
          hintsUsed: summary.hintsUsed,
          events: summary.events,
        );

        // Ch02/P12: finishing the level breaks whatever consecutive-abandon
        // streak `DdaRepository` was counting for it — see
        // `domain/progression/dda.dart`'s `DdaAbandonRules` header.
        final ddaRepo = await ddaRepoFuture;
        await ddaRepo.clearAbandon(summary.language, level);

        // Pre-P18: advances the interstitial pacing counters. Journey only
        // (never Daily) — see `AdRepository`'s own header for why. The
        // eligibility CHECK and the actual `AdGateway.showInterstitial()`
        // call live at `game_screen.dart`'s "Continue" seam, not here —
        // showing an ad is a presentation action, and this controller's own
        // header is explicit that it owns repository writes only.
        final adRepo = await adRepoFuture;
        await adRepo.recordLevelCompleted();

        final coins = economy.coinsForLevel(stars: summary.stars);
        // Rolled with a fresh, unseeded Random rather than the level's own
        // seed: unlike the grid (which must reproduce byte-identically on
        // every device forever), a chest is a one-time reward paid out once
        // and never regenerated, so there is nothing here that needs to be
        // reproducible.
        final chest = economy.awardsChest(level)
            ? economy.rollChest(Random())
            : null;

        await coinsRepo.record(
          delta: coins,
          reason: 'level_complete:${summary.language.code}:$level',
        );
        if (chest != null) {
          await coinsRepo.record(
            delta: chest.coins,
            reason: 'chest:${chest.tier.id}:${summary.language.code}:$level',
          );
        }

        final newBadges = await _recordNewBadges(
          content: await contentFuture,
          collectionsRepo: await collectionsRepoFuture,
          language: summary.language,
          completedBefore: completedBefore,
          justCompleted: level,
        );

        return LevelReward(
          coinsEarned: coins + (chest?.coins ?? 0),
          chest: chest,
          streak: streak,
          newBadges: newBadges,
        );
    }
  }

  /// Spends [RemoteConfigKeys.hintCostCoins] and only THEN reveals a hint on
  /// [session]'s controller. Returns false, writing and revealing nothing,
  /// when the wallet cannot cover it.
  ///
  /// The one path that is allowed to call `GameController.useHint` — see that
  /// method's own doc for why a caller that skips this debit gets a free
  /// hint.
  Future<bool> tryBuyHint(GameSession session) async {
    final economy = ref.read(coinEconomyProvider);
    final coinsRepoFuture = ref.read(coinsRepositoryProvider.future);
    // Read BEFORE the await, per the library header — this one is the easiest
    // to get wrong, because it reads so naturally as "now go reveal it".
    final game = ref.read(gameControllerProvider(session).notifier);
    // The LIVE level, not `session.level` — same staleness trap
    // `recordCompletion`'s journey branch documents at length. Only the
    // ledger's audit trail rides on this (the amount is a flat cost), but a
    // reason that names the wrong level is a reason nobody can trust later.
    final level = ref.read(gameControllerProvider(session)).value?.level;

    final coinsRepo = await coinsRepoFuture;
    final spent = await coinsRepo.trySpend(
      amount: economy.hintCostCoins,
      reason: 'hint:${level ?? session.level}',
    );
    if (!spent) return false;

    game.useHint();
    return true;
  }

  /// Badges [justCompleted] pushed over the line, recording each as earned.
  ///
  /// Takes its collaborators as arguments rather than reading them off `ref`:
  /// this runs deep inside [recordCompletion]'s await chain, which is exactly
  /// where a `ref` read is unsafe.
  ///
  /// Records the badges [justCompleted] pushed over the line.
  ///
  /// Takes its collaborators as arguments rather than reading them off `ref`:
  /// this runs deep inside [recordCompletion]'s await chain, which is exactly
  /// where a `ref` read is unsafe.
  Future<List<CategoryBadge>> _recordNewBadges({
    required ContentRepository content,
    required CollectionsRepository collectionsRepo,
    required Language language,
    required Set<int> completedBefore,
    required int justCompleted,
  }) async {
    final newlyEarned = Collections.newlyEarnedBy(
      levels: content.levelsFor(language),
      completedBefore: completedBefore,
      language: language,
      justCompleted: justCompleted,
    );
    if (newlyEarned.isEmpty) return const [];

    for (final badge in newlyEarned) {
      await collectionsRepo.recordEarned(badge);
    }
    return newlyEarned;
  }
}
