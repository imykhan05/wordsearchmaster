import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/domain/theme/app_theme_variant.dart';

/// The eight looks and the clock rule that picks one. Everything here is a
/// pure function of a `DateTime` handed in, so every boundary in the day is
/// walked in a loop rather than waited for.
void main() {
  group('AppThemeVariant', () {
    test('every variant has a distinct, non-empty id', () {
      final ids = AppThemeVariant.values.map((variant) => variant.id).toSet();
      expect(ids, hasLength(AppThemeVariant.values.length));
      expect(ids.every((id) => id.isNotEmpty), isTrue);
    });

    test('no variant claims the id AUTO is persisted under', () {
      // `AppThemeSelection` stores one string, and 'auto' is the reserved
      // value in that space. A variant taking it would make a stored AUTO
      // read back as a fixed palette.
      expect(
        AppThemeVariant.values.map((variant) => variant.id),
        isNot(contains(AppThemeSelection.autoId)),
      );
    });

    test('fromId round-trips every value, and degrades otherwise', () {
      for (final variant in AppThemeVariant.values) {
        expect(AppThemeVariant.fromId(variant.id), variant);
      }
      expect(
        AppThemeVariant.fromId('a_palette_this_build_predates'),
        AppThemeVariant.defaultVariant,
      );
      expect(AppThemeVariant.fromId(null), AppThemeVariant.defaultVariant);
    });

    test('defaultVariant is midnight — the palette the app shipped with', () {
      // Pinned: a player who pins a look must be able to pin the one they
      // already had, and `darkColors` is that palette unchanged.
      expect(AppThemeVariant.defaultVariant, AppThemeVariant.midnight);
    });

    test('dark and light partition the whole set', () {
      expect(
        AppThemeVariant.dark.length + AppThemeVariant.light.length,
        AppThemeVariant.values.length,
      );
      expect(AppThemeVariant.dark.every((variant) => variant.isDark), isTrue);
      expect(AppThemeVariant.light.any((variant) => variant.isDark), isFalse);
      // Both families have to be non-empty or AUTO could never cross between
      // a light day and a dark evening, which is the whole feature.
      expect(AppThemeVariant.dark, isNotEmpty);
      expect(AppThemeVariant.light, isNotEmpty);
    });
  });

  group('TimeOfDaySlot', () {
    test('start hours are strictly ascending and inside a day', () {
      // `AutoTheme.slotAt` walks the values in declaration order and keeps the
      // last one whose start hour it has passed — which is only correct while
      // they are sorted.
      final hours = [for (final slot in TimeOfDaySlot.values) slot.startHour];
      for (var i = 1; i < hours.length; i++) {
        expect(hours[i], greaterThan(hours[i - 1]));
      }
      expect(hours.first, greaterThanOrEqualTo(0));
      expect(hours.last, lessThan(24));
    });

    test('the day both starts and ends dark', () {
      // Not decoration: AUTO exists so the app is bright in daylight and dim
      // at night. A slot table where the small hours were a light palette
      // would be the feature doing the opposite of its job.
      expect(TimeOfDaySlot.lateNight.variant.isDark, isTrue);
      expect(TimeOfDaySlot.night.variant.isDark, isTrue);
      expect(TimeOfDaySlot.day.variant.isDark, isFalse);
    });
  });

  group('AutoTheme.slotAt', () {
    DateTime at(int hour, [int minute = 0]) =>
        DateTime(2026, 9, 9, hour, minute);

    test('every hour of the day lands in exactly one slot', () {
      for (var hour = 0; hour < 24; hour++) {
        final slot = AutoTheme.slotAt(at(hour));
        expect(slot, isNotNull, reason: 'hour $hour resolved to nothing');
      }
    });

    test('the small hours belong to the slot that wraps past midnight', () {
      // 00:00-04:59 is before EVERY start hour in the table, so it can only be
      // right if the search falls back to the wrapping slot rather than to the
      // first one declared.
      for (var hour = 0; hour < TimeOfDaySlot.morning.startHour; hour++) {
        expect(
          AutoTheme.slotAt(at(hour)),
          TimeOfDaySlot.lateNight,
          reason: '$hour:00 should still be late night',
        );
      }
    });

    test('a slot begins ON its start hour, not a minute after', () {
      for (final slot in TimeOfDaySlot.values) {
        expect(AutoTheme.slotAt(at(slot.startHour)), slot);
        expect(AutoTheme.slotAt(at(slot.startHour, 59)), slot);
      }
    });

    test('the hour before a start hour still belongs to the previous slot', () {
      for (final slot in TimeOfDaySlot.values) {
        if (slot.startHour == 0) continue;
        expect(
          AutoTheme.slotAt(at(slot.startHour - 1, 59)),
          isNot(slot),
          reason: '${slot.name} started an hour early',
        );
      }
    });

    test('variantAt agrees with slotAt for all 24 hours', () {
      for (var hour = 0; hour < 24; hour++) {
        expect(
          AutoTheme.variantAt(at(hour)),
          AutoTheme.slotAt(at(hour)).variant,
        );
      }
    });
  });

  group('AutoTheme.timeUntilNextSlot', () {
    test('always lands on a moment in a DIFFERENT slot', () {
      // The property that actually matters. A timer armed with this has to
      // wake up to a changed answer, or AUTO silently stops advancing.
      for (var hour = 0; hour < 24; hour++) {
        for (final minute in [0, 17, 59]) {
          final now = DateTime(2026, 9, 9, hour, minute);
          final later = now.add(AutoTheme.timeUntilNextSlot(now));
          expect(
            AutoTheme.slotAt(later),
            isNot(AutoTheme.slotAt(now)),
            reason: 'from $now the timer woke inside the same slot',
          );
        }
      }
    });

    test('never returns zero or a negative delay', () {
      // A zero-delay timer would re-arm itself forever. The floor is what
      // makes a clock that moves under us cost one wasted wake-up rather than
      // a spin.
      for (var hour = 0; hour < 24; hour++) {
        final delay = AutoTheme.timeUntilNextSlot(DateTime(2026, 9, 9, hour));
        expect(delay, greaterThanOrEqualTo(const Duration(minutes: 1)));
      }
    });

    test('the last slot of the day waits for TOMORROW morning', () {
      final late = DateTime(2026, 9, 9, 23, 30);
      final next = late.add(AutoTheme.timeUntilNextSlot(late));
      expect(next.day, 10);
      expect(next.hour, TimeOfDaySlot.morning.startHour);
    });

    test('rolls over a month, and a year, without special-casing either', () {
      for (final end in [
        DateTime(2026, 9, 30, 23, 5),
        DateTime(2026, 12, 31, 23, 5),
      ]) {
        final next = end.add(AutoTheme.timeUntilNextSlot(end));
        expect(next.hour, TimeOfDaySlot.morning.startHour);
        expect(next.isAfter(end), isTrue);
      }
    });
  });

  group('AppThemeSelection', () {
    test('auto resolves from the clock; a fixed pick ignores it', () {
      const auto = AppThemeSelection.auto();
      const fixed = AppThemeSelection.fixed(AppThemeVariant.forest);

      for (var hour = 0; hour < 24; hour++) {
        final now = DateTime(2026, 9, 9, hour);
        expect(auto.resolve(now), AutoTheme.variantAt(now));
        expect(fixed.resolve(now), AppThemeVariant.forest);
      }
    });

    test('id round-trips through fromId, auto included', () {
      final selections = [
        const AppThemeSelection.auto(),
        for (final variant in AppThemeVariant.values)
          AppThemeSelection.fixed(variant),
      ];
      for (final selection in selections) {
        expect(AppThemeSelection.fromId(selection.id), selection);
      }
    });

    test('an unknown or missing id degrades to AUTO', () {
      expect(AppThemeSelection.fromId(null), const AppThemeSelection.auto());
      expect(
        AppThemeSelection.fromId('sunrise_gradient_v2'),
        const AppThemeSelection.auto(),
      );
    });

    test('AUTO is the default, and that is a deliberate exception', () {
      // `BackgroundStyle.defaultStyle` is pinned the other way — it defaults
      // to the look the app already had, because that picker only ADDED a
      // choice nobody asked to have moved. Here the moving IS the feature: a
      // theme system that shipped defaulted to one fixed palette would be
      // invisible to every player who never opens Settings. Any one of the
      // eight, including the exact palette the app shipped with, is one tap
      // away.
      expect(AppThemeSelection.defaultSelection.isAuto, isTrue);
    });

    test('two selections of the same thing are equal', () {
      expect(
        const AppThemeSelection.fixed(AppThemeVariant.slate),
        const AppThemeSelection.fixed(AppThemeVariant.slate),
      );
      expect(const AppThemeSelection.auto(), const AppThemeSelection.auto());
      expect(
        const AppThemeSelection.auto(),
        isNot(const AppThemeSelection.fixed(AppThemeVariant.midnight)),
      );
    });
  });
}
