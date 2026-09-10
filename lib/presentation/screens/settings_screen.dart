import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_route.dart';
import '../../app/theme/theme.dart';
import '../../domain/text/language.dart';
import '../../domain/theme/app_theme_variant.dart';
import '../../domain/theme/background_style.dart';
import '../../l10n/app_localizations.dart';
import '../../services/audio/sound_settings.dart';
import '../../services/background/background_settings.dart';
import '../../services/notifications/notification_settings.dart';
import '../../services/theme/theme_settings.dart';
import '../meta/meta_tiles.dart';
import '../widgets/language_tile.dart';
import '../widgets/system_back_handler.dart';

/// Sound, haptics, music and language, all in one reachable place.
///
/// The pause sheet already carries sound/music toggles for quick access
/// mid-level (Ch03) — this does not replace that, it is the PERMANENT home
/// for the same preferences plus haptics (which had no UI at all despite
/// `HapticsEnabled` existing since P09) and language (previously reachable
/// only from Profile, added post-P17 — see CLAUDE.md's "Switching language
/// after FTUE"). `LanguageTile` is the exact same widget Profile uses, not a
/// second copy, so the two screens cannot drift into different behaviour.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tokens = AppTokens.of(context);
    final soundEnabled = ref.watch(soundEnabledProvider);
    final musicEnabled = ref.watch(musicEnabledProvider);
    final hapticsEnabled = ref.watch(hapticsEnabledProvider);
    final streakRemindersEnabled = ref.watch(streakRemindersEnabledProvider);

    // Reached with `.go()`, so there is nothing to pop: both the arrow and
    // the Android system back have to navigate explicitly, or the app closes
    // (the same rule every other `.go()`-reached screen already follows).
    void goHome() => context.go(const HomeRoute().location);

    return SystemBackHandler(
      onBack: goHome,
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: goHome),
          title: Text(l10n.navSettings),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(AppTokens.space24),
            children: [
              const LanguageTile(),
              const SizedBox(height: AppTokens.space16),
              MetaCard(
                // `MetaCard` is a plain decorated `Container`, and
                // `SwitchListTile` paints its ink/splash on the nearest
                // `Material` ancestor — without one of its own, the
                // framework asserts that the card's own background would
                // hide it. `transparency` keeps the card's own surface as
                // the visible background rather than painting a second one.
                child: Material(
                  type: MaterialType.transparency,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTokens.space4,
                        ),
                        child: Text(
                          l10n.settingsAudioSectionTitle,
                          style: AppTypography.uiTextStyle(
                            Language.english,
                            UiRole.caption,
                            color: tokens.colors.onSurfaceMuted,
                          ),
                        ),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(l10n.soundLabel),
                        value: soundEnabled,
                        onChanged: (_) =>
                            ref.read(soundEnabledProvider.notifier).toggle(),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(l10n.musicLabel),
                        value: musicEnabled,
                        onChanged: (_) =>
                            ref.read(musicEnabledProvider.notifier).toggle(),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(l10n.hapticsLabel),
                        value: hapticsEnabled,
                        onChanged: (_) =>
                            ref.read(hapticsEnabledProvider.notifier).toggle(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppTokens.space16),
              const MetaCard(
                child: Material(
                  type: MaterialType.transparency,
                  child: _ThemeSection(),
                ),
              ),
              const SizedBox(height: AppTokens.space16),
              const MetaCard(
                child: Material(
                  type: MaterialType.transparency,
                  child: _BackgroundSection(),
                ),
              ),
              const SizedBox(height: AppTokens.space16),
              MetaCard(
                child: Material(
                  type: MaterialType.transparency,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTokens.space4,
                        ),
                        child: Text(
                          l10n.settingsNotificationsSectionTitle,
                          style: AppTypography.uiTextStyle(
                            Language.english,
                            UiRole.caption,
                            color: tokens.colors.onSurfaceMuted,
                          ),
                        ),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(l10n.streakReminderLabel),
                        value: streakRemindersEnabled,
                        onChanged: (_) => ref
                            .read(streakRemindersEnabledProvider.notifier)
                            .toggle(),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The eight palettes, plus AUTO.
///
/// Every chip carries a SWATCH of the palette it names, drawn from that
/// palette's own tokens rather than from anything written here. A row of nine
/// identical chips differing only in a word would make the player tap through
/// all of them to find out what they do — and the names are the half of this
/// screen a native speaker has not reviewed yet.
class _ThemeSection extends ConsumerWidget {
  const _ThemeSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final selection = ref.watch(appThemeSettingProvider);
    // What AUTO currently resolves to, so the caption can name it. Watched
    // rather than recomputed here: this is the same value `app.dart` is
    // painting with, and deriving a second answer from a second clock read is
    // how the caption ends up disagreeing with the screen it sits on.
    final resolved = ref.watch(resolvedThemeVariantProvider);

    void select(AppThemeSelection value) =>
        ref.read(appThemeSettingProvider.notifier).set(value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l10n.themeLabel),
        const SizedBox(height: AppTokens.space8),
        Wrap(
          spacing: AppTokens.space8,
          runSpacing: AppTokens.space8,
          children: [
            ChoiceChip(
              // AUTO's swatch is whatever it resolves to right now, which is
              // the honest preview: picking it gives you that, for now.
              avatar: _ThemeSwatch(variant: resolved),
              label: Text(l10n.themeAuto),
              selected: selection.isAuto,
              onSelected: (_) => select(const AppThemeSelection.auto()),
            ),
            for (final variant in AppThemeVariant.values)
              ChoiceChip(
                avatar: _ThemeSwatch(variant: variant),
                label: Text(_themeName(l10n, variant)),
                selected: selection.variant == variant,
                onSelected: (_) => select(AppThemeSelection.fixed(variant)),
              ),
          ],
        ),
        if (selection.isAuto) ...[
          const SizedBox(height: AppTokens.space8),
          Text(
            l10n.themeAutoNote(_themeName(l10n, resolved)),
            style: AppTypography.uiTextStyle(
              Language.english,
              UiRole.caption,
              color: AppTokens.of(context).colors.onSurfaceMuted,
            ),
          ),
        ],
      ],
    );
  }
}

/// A palette in miniature: its own ground, ringed by its own outline, with a
/// dot of its own accent. Reads the tokens for [variant] directly rather than
/// the ambient theme — the whole point is to show a palette that is NOT the
/// one currently on screen.
class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({required this.variant});

  final AppThemeVariant variant;

  static const double _size = 18;
  static const double _dot = 8;

  @override
  Widget build(BuildContext context) {
    final colors = AppTokens.colorsFor(variant);
    return SizedBox(
      width: _size,
      height: _size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceHigh,
          shape: BoxShape.circle,
          border: Border.all(color: colors.outline),
        ),
        child: Center(
          child: SizedBox(
            width: _dot,
            height: _dot,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.primary,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A switch rather than a `Map` so a variant added to the enum without a case
/// here is a compile error, not a runtime fallback string nobody notices.
String _themeName(AppLocalizations l10n, AppThemeVariant variant) =>
    switch (variant) {
      AppThemeVariant.midnight => l10n.themeMidnight,
      AppThemeVariant.deepSea => l10n.themeDeepSea,
      AppThemeVariant.twilight => l10n.themeTwilight,
      AppThemeVariant.forest => l10n.themeForest,
      AppThemeVariant.slate => l10n.themeSlate,
      AppThemeVariant.daylight => l10n.themeDaylight,
      AppThemeVariant.morningMint => l10n.themeMorningMint,
      AppThemeVariant.desertSand => l10n.themeDesertSand,
    };

/// The board background: three swatches plus the player's own photo.
///
/// Its own widget rather than more rows inside the sound card, because the
/// photo half is genuinely different in kind — it is asynchronous (a picker
/// takes over the screen), it can fail, and it needs the "remove" affordance
/// a swatch never does.
class _BackgroundSection extends ConsumerWidget {
  const _BackgroundSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final style = ref.watch(backgroundStyleSettingProvider);
    final photoPath = ref.watch(backgroundPhotoPathProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l10n.backgroundLabel),
        const SizedBox(height: AppTokens.space8),
        Wrap(
          spacing: AppTokens.space8,
          runSpacing: AppTokens.space8,
          children: [
            for (final option in BackgroundStyle.gradients)
              ChoiceChip(
                label: Text(_backgroundName(l10n, option)),
                selected: style == option,
                // Picking a gradient DELETES the photo copy rather than just
                // looking away from it: a picture the player has stopped using
                // has no business still sitting in the cache, and this is the
                // only moment the app can know they are done with it.
                onSelected: (_) {
                  ref.read(backgroundStyleSettingProvider.notifier).set(option);
                  unawaited(
                    ref.read(backgroundPhotoPathProvider.notifier).clear(),
                  );
                },
              ),
            ActionChip(
              avatar: const Icon(Icons.image_outlined),
              label: Text(
                photoPath == null
                    ? l10n.backgroundChoosePhoto
                    : l10n.backgroundChangePhoto,
              ),
              onPressed: () => unawaited(
                ref.read(backgroundPhotoPathProvider.notifier).pick(),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppTokens.space8),
        Text(
          l10n.backgroundPhotoNote,
          style: AppTypography.uiTextStyle(
            Language.english,
            UiRole.caption,
            color: AppTokens.of(context).colors.onSurfaceMuted,
          ),
        ),
      ],
    );
  }
}

String _backgroundName(AppLocalizations l10n, BackgroundStyle style) =>
    switch (style) {
      BackgroundStyle.calm => l10n.backgroundCalm,
      BackgroundStyle.ember => l10n.backgroundEmber,
      BackgroundStyle.lagoon => l10n.backgroundLagoon,
      // Never rendered: `BackgroundStyle.gradients` excludes it, and the photo
      // is offered as its own action rather than as a swatch. Kept so adding a
      // future style is a compile error here rather than a silent gap.
      BackgroundStyle.photo => l10n.backgroundChoosePhoto,
    };
