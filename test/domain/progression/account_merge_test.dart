import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/domain/progression/account_merge.dart';
import 'package:word_search_master/domain/progression/day_key.dart';
import 'package:word_search_master/domain/progression/streak.dart';
import 'package:word_search_master/domain/text/language.dart';

/// P13 ACCEPTANCE CRITERION 2, at the layer where it is actually decided:
/// "guest → Google link karne par progress barqarar rehti hai" — linking must
/// never lose guest progress.
///
/// `account_merge_repository_test.dart` covers the write path against a real
/// database; this file covers the rules themselves, which is where a mistake
/// would silently cost a player forty levels.
void main() {
  LevelSnapshot level(
    int n, {
    int stars = 1,
    int score = 100,
    int hints = 0,
    int completedAt = 1000,
    Language language = Language.english,
  }) => LevelSnapshot(
    language: language,
    level: n,
    stars: stars,
    bestScore: score,
    hintsUsed: hints,
    completedAt: completedAt,
  );

  Map<String, LevelSnapshot> levels(List<LevelSnapshot> list) => {
    for (final entry in list) entry.key: entry,
  };

  group('levels — max(), and nothing is ever dropped', () {
    test('a level only the guest has survives the merge', () {
      final merged = AccountMerge.merge(
        local: AccountSnapshot(levels: levels([level(1), level(2)])),
        remote: AccountSnapshot(levels: levels([level(3)])),
      );

      expect(merged.levels.keys, containsAll(['en/1', 'en/2', 'en/3']));
    });

    test('the better row wins on stars', () {
      final merged = AccountMerge.merge(
        local: AccountSnapshot(levels: levels([level(1, stars: 1)])),
        remote: AccountSnapshot(levels: levels([level(1, stars: 3)])),
      );

      expect(merged.levels['en/1']!.stars, 3);
    });

    test('a WORSE remote row never overwrites a better local one', () {
      final merged = AccountMerge.merge(
        local: AccountSnapshot(
          levels: levels([level(1, stars: 3, score: 500)]),
        ),
        remote: AccountSnapshot(
          levels: levels([level(1, stars: 1, score: 10)]),
        ),
      );

      expect(merged.levels['en/1']!.stars, 3);
      expect(merged.levels['en/1']!.bestScore, 500);
    });

    test('score breaks a stars tie', () {
      final merged = AccountMerge.merge(
        local: AccountSnapshot(
          levels: levels([level(1, stars: 2, score: 100)]),
        ),
        remote: AccountSnapshot(
          levels: levels([level(1, stars: 2, score: 300)]),
        ),
      );

      expect(merged.levels['en/1']!.bestScore, 300);
    });

    test(
      'the winning row is kept WHOLE — no Frankenstein row that never happened',
      () {
        // 3 stars means no hints were used (P05's scoring rule). If the merge
        // took max(stars) from one row and max(score) from the other it would
        // produce "3 stars, 999 points, 4 hints", describing a run nobody
        // played. The row that won on stars keeps its own hintsUsed.
        final merged = AccountMerge.merge(
          local: AccountSnapshot(
            levels: levels([level(1, stars: 1, score: 999, hints: 4)]),
          ),
          remote: AccountSnapshot(
            levels: levels([level(1, stars: 3, score: 300, hints: 0)]),
          ),
        );

        final row = merged.levels['en/1']!;
        expect(row.stars, 3);
        expect(row.bestScore, 300, reason: 'the winner keeps its own score');
        expect(row.hintsUsed, 0, reason: 'and its own hint count');
      },
    );

    test('level 47 in Urdu never merges into level 47 in Hindi', () {
      final merged = AccountMerge.merge(
        local: AccountSnapshot(
          levels: levels([level(47, stars: 3, language: Language.urdu)]),
        ),
        remote: AccountSnapshot(
          levels: levels([level(47, stars: 1, language: Language.hindi)]),
        ),
      );

      expect(merged.levels, hasLength(2));
      expect(merged.levels['ur/47']!.stars, 3);
      expect(merged.levels['hi/47']!.stars, 1);
    });
  });

  group('coins — summed, as a delta', () {
    test('coinsToCredit is the REMOTE balance, not the total', () {
      // The guest's own coins are already rows in the local ledger. Crediting
      // the sum would pay them a second time.
      final merged = AccountMerge.merge(
        local: const AccountSnapshot(coinBalance: 100),
        remote: const AccountSnapshot(coinBalance: 250),
      );

      expect(merged.coinsToCredit, 250);
    });

    test('a remote account with no coins credits nothing', () {
      final merged = AccountMerge.merge(
        local: const AccountSnapshot(coinBalance: 100),
        remote: const AccountSnapshot(),
      );

      expect(merged.coinsToCredit, 0);
      expect(merged.mergedCoinBalance, 100, reason: 'the local side stands');
    });

    test('mergedCoinBalance is the SUM — Ch02s "coins are summed"', () {
      // The distinction that matters: `coinsToCredit` is what to append to
      // the append-only ledger; `mergedCoinBalance` is where the player ends
      // up. Confusing them either pays the guest twice or not at all.
      final merged = AccountMerge.merge(
        local: const AccountSnapshot(coinBalance: 100),
        remote: const AccountSnapshot(coinBalance: 250),
      );

      expect(merged.coinsToCredit, 250);
      expect(merged.mergedCoinBalance, 350);
      expect(merged.snapshot.coinBalance, 350);
    });
  });

  group('achievements — unioned, earliest unlock wins', () {
    test('both sides survive', () {
      final merged = AccountMerge.merge(
        local: const AccountSnapshot(
          achievements: {
            'a': AchievementSnapshot(id: 'a', progress: 5, unlockedAt: 10),
          },
        ),
        remote: const AccountSnapshot(
          achievements: {
            'b': AchievementSnapshot(id: 'b', progress: 3, unlockedAt: 20),
          },
        ),
      );

      expect(merged.achievements.keys, containsAll(['a', 'b']));
    });

    test('progress takes max, unlockedAt takes the EARLIEST', () {
      final merged = AccountMerge.merge(
        local: const AccountSnapshot(
          achievements: {
            'a': AchievementSnapshot(id: 'a', progress: 9, unlockedAt: 500),
          },
        ),
        remote: const AccountSnapshot(
          achievements: {
            'a': AchievementSnapshot(id: 'a', progress: 2, unlockedAt: 100),
          },
        ),
      );

      expect(merged.achievements['a']!.progress, 9);
      expect(
        merged.achievements['a']!.unlockedAt,
        100,
        reason: 'when it was earned is a fact about the past',
      );
    });

    test('an unlocked side beats a still-in-progress one', () {
      final merged = AccountMerge.merge(
        local: const AccountSnapshot(
          achievements: {'a': AchievementSnapshot(id: 'a', progress: 4)},
        ),
        remote: const AccountSnapshot(
          achievements: {
            'a': AchievementSnapshot(id: 'a', progress: 4, unlockedAt: 77),
          },
        ),
      );

      expect(merged.achievements['a']!.isUnlocked, isTrue);
      expect(merged.achievements['a']!.unlockedAt, 77);
    });
  });

  group('streak — max, later day wins', () {
    StreakState streak({
      int current = 0,
      int longest = 0,
      String? lastActive,
      String? lastPlayed,
      int freezes = 0,
    }) => StreakState(
      current: current,
      longest: longest,
      lastActiveDay: lastActive == null ? null : DayKey.parse(lastActive),
      lastPlayedDay: lastPlayed == null ? null : DayKey.parse(lastPlayed),
      freezes: freezes,
    );

    test('current and longest take max', () {
      final merged = AccountMerge.mergeStreaks(
        streak(current: 3, longest: 10),
        streak(current: 8, longest: 8),
      );

      expect(merged.current, 8);
      expect(merged.longest, 10);
    });

    test('the LATER day wins each stamp — both days really happened', () {
      final merged = AccountMerge.mergeStreaks(
        streak(lastActive: '2026-03-01', lastPlayed: '2026-03-01'),
        streak(lastActive: '2026-03-05', lastPlayed: '2026-03-04'),
      );

      expect(merged.lastActiveDay, DayKey.parse('2026-03-05'));
      expect(merged.lastPlayedDay, DayKey.parse('2026-03-04'));
    });

    test('a null day on one side takes the other', () {
      final merged = AccountMerge.mergeStreaks(
        streak(lastActive: '2026-03-01'),
        streak(),
      );

      expect(merged.lastActiveDay, DayKey.parse('2026-03-01'));
    });

    test('freezes are CAPPED — linking is not a way to hoard them', () {
      final merged = AccountMerge.mergeStreaks(
        streak(freezes: 2),
        streak(freezes: 2),
      );

      expect(merged.freezes, StreakRules.maxFreezes);
      expect(merged.freezes, lessThanOrEqualTo(2));
    });
  });

  group('the never-lose-progress guarantee', () {
    test('an empty remote leaves the local side completely untouched', () {
      // The airplane-mode / failed-cloud-read case: a merge against nothing
      // must be a no-op, not a wipe.
      final local = AccountSnapshot(
        levels: levels([level(1, stars: 3), level(2, stars: 2)]),
        achievements: const {
          'a': AchievementSnapshot(id: 'a', progress: 5, unlockedAt: 1),
        },
        coinBalance: 400,
        streak: const StreakState(current: 9, longest: 12),
      );

      final merged = AccountMerge.merge(
        local: local,
        remote: AccountSnapshot.empty,
      );

      expect(merged.levels, local.levels);
      expect(merged.achievements, local.achievements);
      expect(merged.streak, local.streak);
      expect(merged.coinsToCredit, 0);
    });

    test('an empty LOCAL side adopts the whole remote account', () {
      // A fresh install signing into an existing account.
      final remote = AccountSnapshot(
        levels: levels([level(1, stars: 3), level(2)]),
        coinBalance: 250,
        streak: const StreakState(current: 4, longest: 4),
      );

      final merged = AccountMerge.merge(
        local: AccountSnapshot.empty,
        remote: remote,
      );

      expect(merged.levels, remote.levels);
      expect(merged.streak, remote.streak);
      expect(merged.coinsToCredit, 250);
    });

    test(
      'THE CRITERION: no key on either side is ever missing from the result, '
      'over 200 randomised pairs',
      () {
        final random = Random(20260829);

        for (var run = 0; run < 200; run++) {
          final localLevels = <LevelSnapshot>[];
          final remoteLevels = <LevelSnapshot>[];
          for (var i = 0; i < 20; i++) {
            final language =
                Language.values[random.nextInt(Language.values.length)];
            if (random.nextBool()) {
              localLevels.add(
                level(
                  i,
                  language: language,
                  stars: random.nextInt(4),
                  score: random.nextInt(1000),
                ),
              );
            }
            if (random.nextBool()) {
              remoteLevels.add(
                level(
                  i,
                  language: language,
                  stars: random.nextInt(4),
                  score: random.nextInt(1000),
                ),
              );
            }
          }

          final local = AccountSnapshot(levels: levels(localLevels));
          final remote = AccountSnapshot(levels: levels(remoteLevels));
          final merged = AccountMerge.merge(local: local, remote: remote);

          for (final key in {...local.levels.keys, ...remote.levels.keys}) {
            expect(
              merged.levels,
              contains(key),
              reason: 'run $run dropped $key',
            );
          }
          // And the surviving row is never worse than the best of the two.
          for (final key in merged.levels.keys) {
            final best = [
              local.levels[key]?.stars ?? -1,
              remote.levels[key]?.stars ?? -1,
            ].reduce((a, b) => a > b ? a : b);
            expect(merged.levels[key]!.stars, best, reason: 'run $run, $key');
          }
        }
      },
    );

    test('merging is COMMUTATIVE over the absolute fields', () {
      // Which side is "local" is an accident of which device the player
      // happened to open. The answer must not depend on it.
      final a = AccountSnapshot(
        levels: levels([level(1, stars: 3), level(2, stars: 1)]),
        streak: const StreakState(current: 5, longest: 9),
      );
      final b = AccountSnapshot(
        levels: levels([level(2, stars: 3), level(3, stars: 2)]),
        streak: const StreakState(current: 7, longest: 7),
      );

      final ab = AccountMerge.merge(local: a, remote: b);
      final ba = AccountMerge.merge(local: b, remote: a);

      expect(ab.levels, ba.levels);
      expect(ab.streak, ba.streak);
    });

    test('merging twice changes nothing further — idempotent', () {
      final local = AccountSnapshot(levels: levels([level(1, stars: 1)]));
      final remote = AccountSnapshot(levels: levels([level(1, stars: 3)]));

      final once = AccountMerge.merge(local: local, remote: remote);
      final twice = AccountMerge.merge(local: once.snapshot, remote: remote);

      expect(twice.levels, once.levels);
    });
  });
}
