import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/domain/theme/app_theme_variant.dart';
import 'package:word_search_master/services/settings/ui_settings_store.dart';
import 'package:word_search_master/services/theme/theme_settings.dart';

/// AUTO mode's live half: resolving from the clock, and keeping up when a
/// boundary passes while the app is open.
///
/// Every case here is a `testWidgets` rather than a plain `test`, and that is
/// not incidental — `ResolvedThemeVariant` arms a real `Timer`, and only
/// `flutter_test`'s binding gives a fake clock that `tester.pump` can move.
/// A plain `test` would either wait hours or prove nothing.
void main() {
  /// Fixed dates inside each slot, so the expected answer is readable.
  const evening = AppThemeVariant.twilight;
  const night = AppThemeVariant.midnight;

  ProviderContainer containerAt(
    DateTime Function() clock, {
    UiSettingsStore? store,
  }) {
    return ProviderContainer(
      overrides: [
        themeClockProvider.overrideWithValue(clock),
        if (store != null) uiSettingsStoreProvider.overrideWithValue(store),
      ],
    );
  }

  testWidgets('a fixed pick ignores the clock entirely', (tester) async {
    var now = DateTime(2026, 9, 9, 10);
    final container = containerAt(
      () => now,
      store: InMemoryUiSettingsStore(
        appTheme: const AppThemeSelection.fixed(AppThemeVariant.forest),
      ),
    );

    expect(
      container.read(resolvedThemeVariantProvider),
      AppThemeVariant.forest,
    );

    // Right across a boundary and well past it: a pinned palette does not
    // move, and nothing is armed that could move it.
    now = DateTime(2026, 9, 9, 23, 30);
    await tester.pump(const Duration(hours: 14));
    expect(
      container.read(resolvedThemeVariantProvider),
      AppThemeVariant.forest,
    );

    container.dispose();
  });

  testWidgets('auto resolves from the clock it is given', (tester) async {
    for (var hour = 0; hour < 24; hour++) {
      final now = DateTime(2026, 9, 9, hour);
      final container = containerAt(() => now);
      expect(
        container.read(resolvedThemeVariantProvider),
        AutoTheme.variantAt(now),
        reason: 'auto picked the wrong palette at $hour:00',
      );
      container.dispose();
    }
  });

  testWidgets('auto follows a boundary that passes while the app is open', (
    tester,
  ) async {
    // 18:30 is inside the evening slot; 19:00 starts the night one.
    var now = DateTime(2026, 9, 9, 18, 30);
    final container = containerAt(() => now);

    expect(container.read(resolvedThemeVariantProvider), evening);

    // The timer was armed for 19:00. Move the wall clock there and let the
    // fake one catch up — the palette has to change with NO widget rebuild,
    // no navigation and nothing else prompting it.
    now = DateTime(2026, 9, 9, 19, 0);
    await tester.pump(const Duration(minutes: 30));

    expect(container.read(resolvedThemeVariantProvider), night);

    container.dispose();
  });

  testWidgets('auto keeps re-arming across several boundaries', (tester) async {
    // One timer that fires once and stops would pass the test above and still
    // leave the app stuck on whatever palette it reached first.
    var now = DateTime(2026, 9, 9, 4, 55);
    final container = containerAt(() => now);
    final seen = <AppThemeVariant>[
      container.read(resolvedThemeVariantProvider),
    ];

    for (final boundary in AutoTheme.boundaryHours) {
      now = DateTime(2026, 9, 9, boundary);
      await tester.pump(const Duration(hours: 5));
      seen.add(container.read(resolvedThemeVariantProvider));
    }

    expect(
      seen.toSet().length,
      greaterThan(2),
      reason: 'the palette stopped moving after the first boundary',
    );
    expect(seen.last, AutoTheme.variantAt(now));

    container.dispose();
  });

  testWidgets('pinning a palette stops auto from moving it again', (
    tester,
  ) async {
    var now = DateTime(2026, 9, 9, 18, 30);
    final container = containerAt(() => now);
    expect(container.read(resolvedThemeVariantProvider), evening);

    container
        .read(appThemeSettingProvider.notifier)
        .set(const AppThemeSelection.fixed(AppThemeVariant.deepSea));
    expect(
      container.read(resolvedThemeVariantProvider),
      AppThemeVariant.deepSea,
    );

    // The build that armed the timer has been torn down. If its `onDispose`
    // did not cancel, the old timer would still fire here and overwrite the
    // player's explicit choice with a clock-derived one.
    now = DateTime(2026, 9, 9, 19, 0);
    await tester.pump(const Duration(hours: 1));
    expect(
      container.read(resolvedThemeVariantProvider),
      AppThemeVariant.deepSea,
    );

    container.dispose();
  });

  testWidgets('switching back to auto resumes following the clock', (
    tester,
  ) async {
    var now = DateTime(2026, 9, 9, 18, 30);
    final container = containerAt(
      () => now,
      store: InMemoryUiSettingsStore(
        appTheme: const AppThemeSelection.fixed(AppThemeVariant.slate),
      ),
    );
    expect(container.read(resolvedThemeVariantProvider), AppThemeVariant.slate);

    container
        .read(appThemeSettingProvider.notifier)
        .set(const AppThemeSelection.auto());
    expect(container.read(resolvedThemeVariantProvider), evening);

    now = DateTime(2026, 9, 9, 19, 0);
    await tester.pump(const Duration(hours: 1));
    expect(container.read(resolvedThemeVariantProvider), night);

    container.dispose();
  });

  testWidgets('the choice is written through to the settings store', (
    tester,
  ) async {
    final store = InMemoryUiSettingsStore();
    final container = containerAt(() => DateTime(2026, 9, 9, 12), store: store);

    container
        .read(appThemeSettingProvider.notifier)
        .set(const AppThemeSelection.fixed(AppThemeVariant.desertSand));

    expect(
      store.appTheme,
      const AppThemeSelection.fixed(AppThemeVariant.desertSand),
    );

    container.dispose();
  });

  testWidgets('a stored choice is what the app opens on', (tester) async {
    final container = containerAt(
      () => DateTime(2026, 9, 9, 12),
      store: InMemoryUiSettingsStore(
        appTheme: const AppThemeSelection.fixed(AppThemeVariant.morningMint),
      ),
    );

    expect(
      container.read(resolvedThemeVariantProvider),
      AppThemeVariant.morningMint,
      reason: 'a returning player got a palette they never picked',
    );

    container.dispose();
  });
}
