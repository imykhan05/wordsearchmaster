import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_route.dart';
import '../../app/theme/theme.dart';
import '../../domain/audio/sound_theme.dart';
import '../../domain/text/language.dart';
import '../../domain/theme/background_style.dart';
import '../../l10n/app_localizations.dart';
import '../../services/audio/sound_settings.dart';
import '../../services/background/background_settings.dart';
import '../../services/notifications/notification_settings.dart';
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
    final soundTheme = ref.watch(soundThemeSettingProvider);
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
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppTokens.space8,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(l10n.soundThemeLabel),
                            const SizedBox(height: AppTokens.space8),
                            Wrap(
                              spacing: AppTokens.space8,
                              children: [
                                for (final theme in SoundTheme.values)
                                  ChoiceChip(
                                    label: Text(_soundThemeName(l10n, theme)),
                                    selected: soundTheme == theme,
                                    onSelected: (_) => ref
                                        .read(
                                          soundThemeSettingProvider.notifier,
                                        )
                                        .set(theme),
                                  ),
                              ],
                            ),
                          ],
                        ),
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

/// Localizes a [SoundTheme] for display, the same one-call-site-resolves-it
/// shape `categoryLabel()` uses for content-pack categories — a switch
/// rather than a `Map` so a theme added to the enum without a case here is a
/// compile error, not a runtime fallback string nobody notices.
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

String _soundThemeName(AppLocalizations l10n, SoundTheme theme) =>
    switch (theme) {
      SoundTheme.softBells => l10n.soundThemeSoftBells,
      SoundTheme.chimes => l10n.soundThemeChimes,
      SoundTheme.minimal => l10n.soundThemeMinimal,
    };
