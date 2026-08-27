import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/domain/progression/day_key.dart';
import 'package:word_search_master/domain/progression/streak.dart';

/// P11 acceptance criterion 2, and the rest of `StreakRules`' contract:
/// "streak freeze ek din miss karne par khud consume hota hai" — a freeze is
/// consumed AUTOMATICALLY on a missed day, with no player action.
///
/// See `lib/domain/progression/streak.dart`'s library header for the three
/// decisions Ch02 leaves open that this file pins down.
void main() {
  DayKey day(int n) => DayKey.parse('2026-03-01').addDays(n);

  /// Plays [days] consecutive days from day 0, returning the final state.
  StreakState playConsecutive(int days) {
    var state = StreakState.empty;
    for (var i = 0; i < days; i++) {
      state = StreakRules.registerPlay(state, day(i)).state;
    }
    return state;
  }

  group('registerPlay', () {
    test('a first completion starts the streak at 1', () {
      final result = StreakRules.registerPlay(StreakState.empty, day(0));

      expect(result.event, StreakEvent.started);
      expect(result.state.current, 1);
      expect(result.state.longest, 1);
      expect(result.state.lastPlayedDay, day(0));
      expect(result.state.freezes, 0);
    });

    test('consecutive days extend it', () {
      final after3 = playConsecutive(3);

      expect(after3.current, 3);
      expect(after3.longest, 3);
      expect(after3.lastActiveDay, day(2));
    });

    test('a second completion the SAME day does not double-count', () {
      final first = StreakRules.registerPlay(StreakState.empty, day(0)).state;
      final second = StreakRules.registerPlay(first, day(0));

      expect(second.state.current, 1, reason: 'Ch02 counts DAYS, not levels');
      expect(second.state, first);
    });

    test('longest survives a break, current does not', () {
      final after5 = playConsecutive(5);
      // Day 5 and 6 missed entirely; no freezes held at this point.
      final resumed = StreakRules.registerPlay(after5, day(8));

      expect(resumed.state.current, 1);
      expect(resumed.state.longest, 5);
    });
  });

  group('freeze grants', () {
    test('one is granted on the 7th consecutive day', () {
      expect(playConsecutive(6).freezes, 0);

      final after7 = playConsecutive(7);
      expect(after7.freezes, 1);
      expect(after7.current, 7);
    });

    test('a second on the 14th', () {
      expect(playConsecutive(14).freezes, StreakRules.maxFreezes);
    });

    test('capped at maxFreezes — the 21st day grants nothing further', () {
      final after21 = playConsecutive(21);

      expect(after21.freezes, StreakRules.maxFreezes);
      expect(after21.current, 21);
    });

    test('a grant that hits the cap reports 0 granted, not 1', () {
      // At 14 days the player already holds the maximum; day 21's grant is
      // notionally earned but never banked, and telling the player "+1 freeze"
      // while the counter stays at 2 would read as a bug.
      var state = playConsecutive(20);
      final day21 = StreakRules.registerPlay(state, day(20));

      expect(day21.freezesGranted, 0);
      expect(day21.state.freezes, StreakRules.maxFreezes);

      // Contrast: the 7th day, from zero held.
      state = playConsecutive(6);
      final day7 = StreakRules.registerPlay(state, day(6));
      expect(day7.freezesGranted, 1);
    });
  });

  group('settle — a freeze is spent automatically on a missed day', () {
    test(
      'THE ACCEPTANCE CRITERION: one missed day consumes one held freeze and '
      'the streak survives, with no player action',
      () {
        // Seven days played: streak 7, one freeze banked.
        final earned = playConsecutive(7);
        expect(earned.current, 7);
        expect(earned.freezes, 1);

        // Day 7 is missed entirely. The player opens the app on day 8 — a
        // READ, not a completion. Settling is what fires the freeze.
        final settled = StreakRules.settle(earned, day(8));

        expect(settled.event, StreakEvent.frozen);
        expect(settled.freezesSpent, 1);
        expect(
          settled.state.current,
          7,
          reason: 'the freeze PRESERVES the streak; it does not extend it',
        );
        expect(settled.state.freezes, 0, reason: 'the freeze was spent');
        expect(
          settled.state.lastActiveDay,
          day(7),
          reason: 'alive through yesterday, so playing today extends to 8',
        );
      },
    );

    test('and playing that same day then extends to 8', () {
      final earned = playConsecutive(7);
      final resumed = StreakRules.registerPlay(earned, day(8));

      expect(resumed.state.current, 8);
      expect(resumed.freezesSpent, 1);
      expect(resumed.state.freezes, 0);
    });

    test('settling is idempotent — twice is the same as once', () {
      final earned = playConsecutive(7);
      final once = StreakRules.settle(earned, day(8)).state;
      final twice = StreakRules.settle(once, day(8)).state;

      expect(twice, once);
    });

    test('two missed days consume two freezes', () {
      final earned = playConsecutive(14);
      expect(earned.freezes, 2);

      // Days 14 and 15 missed; the player returns on day 16.
      final settled = StreakRules.settle(earned, day(16));

      expect(settled.event, StreakEvent.frozen);
      expect(settled.freezesSpent, 2);
      expect(settled.state.current, 14);
      expect(settled.state.freezes, 0);
    });

    test('freezes that cannot cover the whole gap are NOT spent — the streak '
        'breaks and they are kept for a gap they can bridge', () {
      final earned = playConsecutive(7);
      expect(earned.freezes, 1);

      // Three days missed against one freeze.
      final settled = StreakRules.settle(earned, day(11));

      expect(settled.event, StreakEvent.broken);
      expect(settled.freezesSpent, 0);
      expect(settled.state.current, 0);
      expect(
        settled.state.freezes,
        1,
        reason: 'earned, and burning it for nothing would be strictly worse',
      );
      expect(settled.state.longest, 7, reason: 'longest never decreases');
    });

    test('a missed day with no freezes breaks the streak', () {
      final earned = playConsecutive(3);
      expect(earned.freezes, 0);

      final settled = StreakRules.settle(earned, day(5));

      expect(settled.event, StreakEvent.broken);
      expect(settled.state.current, 0);
    });

    test('same day or next day settles to nothing — today is never missed', () {
      final earned = playConsecutive(3);

      expect(StreakRules.settle(earned, day(2)).event, StreakEvent.unchanged);
      expect(StreakRules.settle(earned, day(3)).event, StreakEvent.unchanged);
      expect(StreakRules.settle(earned, day(2)).state, earned);
    });

    test('a player who has never played settles to nothing', () {
      final settled = StreakRules.settle(StreakState.empty, day(100));

      expect(settled.event, StreakEvent.unchanged);
      expect(settled.state, StreakState.empty);
    });

    test('a BACKWARDS clock is treated as nothing missed, never as a rescue', () {
      // The real defence is `TrustedClock`'s monotonic floor; this only has to
      // not do something stupid when handed a day in the past.
      final earned = playConsecutive(7);
      final settled = StreakRules.settle(earned, day(2));

      expect(settled.event, StreakEvent.unchanged);
      expect(settled.state.freezes, 1, reason: 'no freeze spent going back');
    });
  });

  group('registerPlay settles first', () {
    test('an absence is accounted for before the new day is added', () {
      final earned = playConsecutive(7);
      final resumed = StreakRules.registerPlay(earned, day(9));

      // Days 7 and 8 missed, one freeze held — cannot cover both.
      expect(resumed.state.current, 1, reason: 'broken, then restarted at 1');
      expect(resumed.state.longest, 7);
    });

    test(
      'a freeze fired on this very call is still reported to the caller',
      () {
        final earned = playConsecutive(7);
        final resumed = StreakRules.registerPlay(earned, day(8));

        expect(
          resumed.freezesSpent,
          1,
          reason: 'the home screen has to be able to tell the player',
        );
      },
    );
  });

  test('daysUntilNextFreeze counts down and resets', () {
    expect(StreakRules.daysUntilNextFreeze(0), 7);
    expect(StreakRules.daysUntilNextFreeze(1), 6);
    expect(StreakRules.daysUntilNextFreeze(6), 1);
    expect(StreakRules.daysUntilNextFreeze(7), 7);
  });

  test('a full year of unbroken play never exceeds the freeze cap', () {
    var state = StreakState.empty;
    for (var i = 0; i < 365; i++) {
      state = StreakRules.registerPlay(state, day(i)).state;
      expect(state.freezes, lessThanOrEqualTo(StreakRules.maxFreezes));
    }
    expect(state.current, 365);
    expect(state.longest, 365);
  });
}
