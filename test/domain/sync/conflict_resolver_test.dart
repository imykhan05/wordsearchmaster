import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/domain/progression/account_merge.dart';
import 'package:word_search_master/domain/progression/day_key.dart';
import 'package:word_search_master/domain/progression/streak.dart';
import 'package:word_search_master/domain/sync/conflict_resolver.dart';
import 'package:word_search_master/domain/text/language.dart';

/// P16's second acceptance criterion, literally: A TEST PER ROW OF CH10'S
/// CONFLICT TABLE.
///
/// The coverage claim is not left to a reader counting `group` blocks. Every
/// group registers the [ConflictRule] it covers, and the final test asserts
/// that the registered set is exactly `ConflictRule.values` — so a row added
/// to the table without a test fails the build, and a row deleted from the
/// table without deleting its test does too.
void main() {
  final covered = <ConflictRule>{};

  /// Declares which table row a group is for.
  void covers(ConflictRule rule) => covered.add(rule);

  // -------------------------------------------------------------------------
  // Row 1 — the server's recomputation wins, in both directions.
  // -------------------------------------------------------------------------
  group('rule 1: a recomputed score', () {
    setUp(() => covers(ConflictRule.serverRecomputedScore));

    ServerScoreAck ack({
      int score = 156,
      int stars = 3,
      int? bestScore,
      int? bestStars,
    }) => ServerScoreAck(
      score: score,
      stars: stars,
      bestScore: bestScore ?? score,
      bestStars: bestStars ?? stars,
    );

    test('changes nothing when the two agree, which is the normal case', () {
      final result = ConflictResolver.resolveSubmittedLevel(
        localStars: 3,
        localBestScore: 156,
        ack: ack(),
      );
      expect(result.changed, isFalse);
      expect(result.bestScore, 156);
      expect(result.stars, 3);
    });

    test('MOVES A LOCAL SCORE DOWN when the server computed less', () {
      // The one rule in the whole codebase that resolves against the player,
      // and the reason it exists: a client claiming more than its own events
      // justify is either tampered with or built against different rules, and
      // "keep the bigger number" would make the first of those an exploit.
      final result = ConflictResolver.resolveSubmittedLevel(
        localStars: 3,
        localBestScore: 999999,
        ack: ack(score: 156, stars: 3),
      );
      expect(result.changed, isTrue);
      expect(result.bestScore, 156);
    });

    test('moves a local score up when the server computed more', () {
      final result = ConflictResolver.resolveSubmittedLevel(
        localStars: 1,
        localBestScore: 10,
        ack: ack(score: 156, stars: 3),
      );
      expect(result.bestScore, 156);
      expect(result.stars, 3);
    });

    test('takes the account BEST, never this attempt', () {
      // A player replaying level 5 for fun and doing worse must not lose their
      // best result — the same rule `recordLevelComplete` already keeps
      // locally, enforced here against the server's answer.
      final result = ConflictResolver.resolveSubmittedLevel(
        localStars: 3,
        localBestScore: 300,
        ack: ack(score: 40, stars: 1, bestScore: 300, bestStars: 3),
      );
      expect(result.changed, isFalse);
      expect(result.bestScore, 300);
      expect(result.stars, 3);
    });

    test('rebuilds a row that was missing entirely', () {
      // A local row dropped for failing its integrity tag reads as absent, and
      // the reconcile quietly repairs it from the authoritative side.
      final result = ConflictResolver.resolveSubmittedLevel(
        localStars: -1,
        localBestScore: -1,
        ack: ack(),
      );
      expect(result.changed, isTrue);
      expect(result.bestScore, 156);
    });
  });

  // -------------------------------------------------------------------------
  // Row 2 — better row wins, whole.
  // -------------------------------------------------------------------------
  group('rule 2: two devices finished the same level', () {
    setUp(() => covers(ConflictRule.levelProgress));

    LevelSnapshot level({
      int stars = 2,
      int bestScore = 100,
      int hintsUsed = 1,
      int completedAt = 1000,
    }) => LevelSnapshot(
      language: Language.english,
      level: 5,
      stars: stars,
      bestScore: bestScore,
      hintsUsed: hintsUsed,
      completedAt: completedAt,
    );

    test('more stars wins', () {
      final winner = ConflictResolver.resolveLevel(
        local: level(stars: 2, bestScore: 500),
        remote: level(stars: 3, bestScore: 100),
      );
      expect(winner.stars, 3);
    });

    test('score breaks a tie on stars', () {
      final winner = ConflictResolver.resolveLevel(
        local: level(stars: 3, bestScore: 100),
        remote: level(stars: 3, bestScore: 500),
      );
      expect(winner.bestScore, 500);
    });

    test('THE ROW WINS ENTIRE, never field by field', () {
      // Taking max(stars) from one side and max(score) from the other would
      // synthesise a run that never happened: three stars means no hints, so a
      // three-star row carrying a one-hint score describes nobody's attempt.
      final winner = ConflictResolver.resolveLevel(
        local: level(stars: 2, bestScore: 900, hintsUsed: 1, completedAt: 10),
        remote: level(stars: 3, bestScore: 400, hintsUsed: 0, completedAt: 20),
      );
      expect(winner.stars, 3);
      expect(winner.bestScore, 400);
      expect(winner.hintsUsed, 0);
      expect(winner.completedAt, 20);
    });

    test('a dead tie keeps local, so resolving twice is stable', () {
      final local = level();
      expect(
        ConflictResolver.resolveLevel(local: local, remote: level()),
        same(local),
      );
    });

    test('agrees with AccountMerge on the same pair', () {
      // One implementation, shared. A level resolved at sync time and the same
      // level resolved at account-link time must not pick different winners.
      final local = level(stars: 1, bestScore: 50);
      final remote = level(stars: 3, bestScore: 20);
      final merged = AccountMerge.merge(
        local: AccountSnapshot(levels: {local.key: local}),
        remote: AccountSnapshot(levels: {remote.key: remote}),
      );
      expect(
        merged.levels[local.key],
        ConflictResolver.resolveLevel(local: local, remote: remote),
      );
    });
  });

  // -------------------------------------------------------------------------
  // Row 3 — the first attempt is the attempt.
  // -------------------------------------------------------------------------
  group('rule 3: the same daily, twice', () {
    setUp(() => covers(ConflictRule.dailyResult));

    DailySnapshot daily({required int completedAt, int score = 100}) =>
        DailySnapshot(
          day: DayKey.parse('2026-09-01'),
          language: Language.english,
          score: score,
          stars: 3,
          completedAt: completedAt,
        );

    test('the earlier completion wins even with a lower score', () {
      final winner = ConflictResolver.resolveDaily(
        local: daily(completedAt: 2000, score: 900),
        remote: daily(completedAt: 1000, score: 10),
      );
      expect(winner.completedAt, 1000);
      expect(winner.score, 10);
    });

    test('a later, higher attempt does not displace the first', () {
      final winner = ConflictResolver.resolveDaily(
        local: daily(completedAt: 1000, score: 10),
        remote: daily(completedAt: 5000, score: 9999),
      );
      expect(winner.score, 10);
    });

    test('a tie keeps local', () {
      final local = daily(completedAt: 1000);
      expect(
        ConflictResolver.resolveDaily(
          local: local,
          remote: daily(completedAt: 1000),
        ),
        same(local),
      );
    });

    test(
      'DELIBERATELY DISAGREES with AccountMerge, which takes the better',
      () {
        // Not a contradiction — different questions. Linking two accounts joins
        // separate histories where neither played "first"; syncing reconciles
        // one account against a server that already decided which attempt
        // counted. Pinned so neither gets "fixed" into the other.
        final first = daily(completedAt: 1000, score: 10);
        final better = daily(completedAt: 5000, score: 9999);

        expect(
          ConflictResolver.resolveDaily(local: first, remote: better).score,
          10,
          reason: 'sync keeps the first attempt',
        );

        final merged = AccountMerge.merge(
          local: AccountSnapshot(dailies: {first.key: first}),
          remote: AccountSnapshot(dailies: {better.key: better}),
        );
        expect(
          merged.dailies[first.key]!.score,
          9999,
          reason: 'linking keeps the better result',
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // Row 4 — coins are summed, as a delta.
  // -------------------------------------------------------------------------
  group('rule 4: coin balances', () {
    setUp(() => covers(ConflictRule.coinBalance));

    test('credits the remote balance, not the sum', () {
      // The local rows are already in the append-only ledger. Crediting the
      // sum would pay the player their own coins a second time.
      expect(ConflictResolver.resolveCoinCredit(remoteBalance: 120), 120);
    });

    test('credits nothing when the remote side has nothing', () {
      expect(ConflictResolver.resolveCoinCredit(remoteBalance: 0), 0);
    });

    test('a negative remote balance can never DEBIT the wallet', () {
      // A cloud read that came back nonsense must fail to credit, never take.
      expect(ConflictResolver.resolveCoinCredit(remoteBalance: -500), 0);
    });
  });

  // -------------------------------------------------------------------------
  // Row 5 — union, max progress, earliest unlock.
  // -------------------------------------------------------------------------
  group('rule 5: an achievement on both sides', () {
    setUp(() => covers(ConflictRule.achievement));

    test('keeps the higher progress', () {
      final winner = ConflictResolver.resolveAchievement(
        local: const AchievementSnapshot(id: 'a', progress: 3),
        remote: const AchievementSnapshot(id: 'a', progress: 7),
      );
      expect(winner.progress, 7);
    });

    test('keeps the EARLIEST unlock, because it is a fact about the past', () {
      final winner = ConflictResolver.resolveAchievement(
        local: const AchievementSnapshot(
          id: 'a',
          progress: 10,
          unlockedAt: 5000,
        ),
        remote: const AchievementSnapshot(
          id: 'a',
          progress: 10,
          unlockedAt: 1000,
        ),
      );
      expect(winner.unlockedAt, 1000);
    });

    test('an unlocked side beats a still-in-progress one', () {
      final winner = ConflictResolver.resolveAchievement(
        local: const AchievementSnapshot(id: 'a', progress: 4),
        remote: const AchievementSnapshot(
          id: 'a',
          progress: 4,
          unlockedAt: 900,
        ),
      );
      expect(winner.unlockedAt, 900);
    });

    test('agrees with AccountMerge, because it IS AccountMerge', () {
      const local = AchievementSnapshot(id: 'a', progress: 2, unlockedAt: 700);
      const remote = AchievementSnapshot(id: 'a', progress: 9, unlockedAt: 300);
      expect(
        ConflictResolver.resolveAchievement(local: local, remote: remote),
        AccountMerge.mergeAchievement(local, remote),
      );
    });
  });

  // -------------------------------------------------------------------------
  // Row 6 — per field, unlike every other row.
  // -------------------------------------------------------------------------
  group('rule 6: streak state from two devices', () {
    setUp(() => covers(ConflictRule.streak));

    test('KEEPS BOTH DAYS, because both sides are the same person', () {
      final winner = ConflictResolver.resolveStreak(
        local: StreakState(
          current: 4,
          longest: 9,
          lastActiveDay: DayKey.parse('2026-08-30'),
          lastPlayedDay: DayKey.parse('2026-08-30'),
          freezes: 1,
        ),
        remote: StreakState(
          current: 2,
          longest: 3,
          lastActiveDay: DayKey.parse('2026-09-01'),
          lastPlayedDay: DayKey.parse('2026-09-01'),
          freezes: 0,
        ),
      );
      expect(winner.current, 4, reason: 'counts take max');
      expect(winner.longest, 9);
      expect(
        winner.lastActiveDay,
        DayKey.parse('2026-09-01'),
        reason: 'the later day genuinely happened',
      );
    });

    test('caps freezes so reconciling is not a way to hoard them', () {
      final winner = ConflictResolver.resolveStreak(
        local: StreakState.empty.copyWith(freezes: StreakRules.maxFreezes),
        remote: StreakState.empty.copyWith(freezes: StreakRules.maxFreezes),
      );
      expect(winner.freezes, StreakRules.maxFreezes);
    });

    test('agrees with AccountMerge, because it IS AccountMerge', () {
      final local = StreakState.empty.copyWith(current: 5);
      final remote = StreakState.empty.copyWith(current: 2, longest: 8);
      expect(
        ConflictResolver.resolveStreak(local: local, remote: remote),
        AccountMerge.mergeStreaks(local, remote),
      );
    });
  });

  // -------------------------------------------------------------------------
  // Row 7 — last write wins, tie keeps local.
  // -------------------------------------------------------------------------
  group('rule 7: a display name edited in two places', () {
    setUp(() => covers(ConflictRule.profileDisplay));

    test('the more recent edit wins', () {
      final winner = ConflictResolver.resolveProfile(
        local: const ProfileDisplay(displayName: 'phone', updatedAt: 100),
        remote: const ProfileDisplay(displayName: 'tablet', updatedAt: 200),
      );
      expect(winner.displayName, 'tablet');
    });

    test('an older remote value never overwrites a newer local one', () {
      final winner = ConflictResolver.resolveProfile(
        local: const ProfileDisplay(displayName: 'phone', updatedAt: 900),
        remote: const ProfileDisplay(displayName: 'stale', updatedAt: 100),
      );
      expect(winner.displayName, 'phone');
    });

    test('A TIE KEEPS LOCAL, because two devices share a coarse clock', () {
      // The edit the player is looking at right now must not lose to a cloud
      // value stamped in the same millisecond.
      final winner = ConflictResolver.resolveProfile(
        local: const ProfileDisplay(displayName: 'mine', updatedAt: 500),
        remote: const ProfileDisplay(displayName: 'theirs', updatedAt: 500),
      );
      expect(winner.displayName, 'mine');
    });

    test('carries the photo with the name, as one edit', () {
      final winner = ConflictResolver.resolveProfile(
        local: const ProfileDisplay(
          displayName: 'a',
          photoUrl: 'a.png',
          updatedAt: 1,
        ),
        remote: const ProfileDisplay(
          displayName: 'b',
          photoUrl: 'b.png',
          updatedAt: 2,
        ),
      );
      expect(winner.displayName, 'b');
      expect(winner.photoUrl, 'b.png');
    });
  });

  // -------------------------------------------------------------------------
  // Row 8 — local always.
  // -------------------------------------------------------------------------
  group('rule 8: device settings', () {
    setUp(() => covers(ConflictRule.deviceSettings));

    test('never take the remote value, whatever it is', () {
      // Muting a phone in a meeting must not mute a tablet at home.
      expect(
        ConflictResolver.resolveDeviceSetting(local: false, remote: true),
        isFalse,
      );
      expect(
        ConflictResolver.resolveDeviceSetting(local: true, remote: false),
        isTrue,
      );
    });

    test('holds for a chosen language too', () {
      expect(
        ConflictResolver.resolveDeviceSetting(
          local: Language.urdu,
          remote: Language.hindi,
        ),
        Language.urdu,
      );
    });
  });

  // -------------------------------------------------------------------------
  // Row 9 — an unreadable remote value changes nothing.
  // -------------------------------------------------------------------------
  group('rule 9: a remote value this build cannot read', () {
    setUp(() => covers(ConflictRule.unreadableRemoteValue));

    test('keeps what we already have', () {
      // Treating unreadable as empty is how one bad field wipes a player's
      // progress. Stale is recoverable on the next sync; lost is not.
      expect(ConflictResolver.resolveUnreadable(local: 42, remote: null), 42);
      expect(
        ConflictResolver.resolveUnreadable(local: 'keep', remote: {'weird': 1}),
        'keep',
      );
    });
  });

  // -------------------------------------------------------------------------
  // The coverage claim itself.
  // -------------------------------------------------------------------------
  test('EVERY row of Ch10s conflict table has its own group', () {
    // P16's acceptance criterion, asserted rather than counted by hand.
    expect(covered, ConflictRule.values.toSet());
  });
}
