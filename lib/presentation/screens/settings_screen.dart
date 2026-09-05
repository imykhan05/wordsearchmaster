import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_route.dart';
import '../../app/theme/theme.dart';
import '../../domain/text/language.dart';
import '../../l10n/app_localizations.dart';
import '../../services/audio/sound_settings.dart';
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
