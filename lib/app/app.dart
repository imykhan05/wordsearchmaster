import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../application/achievements_controller.dart';
import '../application/notification_sync.dart';
import '../application/sync_controller.dart';
import '../presentation/meta/achievement_unlock_card.dart';
import '../services/audio/audio_service.dart';
import '../services/haptics/haptics_service.dart';
import '../services/theme/theme_settings.dart';
import 'language/language_x.dart';
import 'language/selected_language.dart';
import 'router.dart';
import 'theme/theme.dart';

/// The app root. Everything flavor-specific is already resolved into
/// [appConfigProvider] by the time this builds — this widget itself must
/// stay flavor-agnostic.
class WordSearchMasterApp extends ConsumerWidget {
  const WordSearchMasterApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final language = ref.watch(selectedLanguageProvider);
    // The look on screen: the player's pinned palette, or — under AUTO — the
    // one the local time of day resolves to. `ResolvedThemeVariant` owns the
    // boundary timer and the lifecycle re-check, so this is a plain watch.
    final themeVariant = ref.watch(resolvedThemeVariantProvider);

    // Ch03: master mute/haptics toggles must reach the audio and haptics
    // services instantly. Watched once, here, rather than per-screen — both
    // providers are `ref.listen`-based side-effect syncs (see their doc
    // comments), so this just has to keep them alive for the app's life.
    ref.watch(audioMuteSyncProvider);
    ref.watch(musicSyncProvider);
    ref.watch(soundThemeSyncProvider);
    ref.watch(hapticsEnabledSyncProvider);
    // Ch10's outbox drain triggers: coming online, and returning to the
    // foreground. Watched HERE, once, for the same reason the two above are —
    // a provider that installs listeners must be kept alive by something with
    // the app's lifetime, and the app root is the only widget that has one.
    ref.watch(syncTriggersProvider);
    // P17: diffs the live server achievement stream into the popup queue.
    // Same shape and same reason as the two triggers above.
    ref.watch(achievementPopupSyncProvider);
    // Post-P17: keeps this device's push-notification registration current.
    // Same shape and same reason as the sync providers above.
    ref.watch(notificationRegistrationSyncProvider);

    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,

      locale: language.locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,

      // BOTH SLOTS GET THE SAME THEME, and `themeMode` is deliberately gone.
      // Material's light/dark pair exists to follow the OS setting, and that
      // is exactly what must not happen here: the player picked this palette
      // (or picked AUTO, which follows the time of day rather than the system
      // switch), and a phone flipping to dark mode at sunset has no business
      // overriding either answer. Filling both slots identically makes
      // `themeMode` unable to change anything, whatever it is set to.
      //
      // This is also where `themeMode: ThemeMode.dark` — which had made
      // `AppTheme.light()` unreachable since P02 — finally comes out. The
      // theme takes the language so its default font family follows the
      // script.
      theme: AppTheme.forVariant(themeVariant, language: language),
      darkTheme: AppTheme.forVariant(themeVariant, language: language),

      routerConfig: router,

      // The locale delegates would already give Urdu an RTL Directionality.
      // Wrapping explicitly anyway is deliberate: the grid's gesture maths
      // and the generator's direction vectors are both keyed off
      // Language.isRtl, and this guarantees the rendered direction can never
      // disagree with them — not even if a delegate's locale table changes
      // under a Flutter upgrade.
      builder: (context, child) => Directionality(
        textDirection: language.textDirection,
        // Above every routed screen: an achievement can unlock while the
        // player is anywhere, and the overlay's own queue already guarantees
        // only one card shows at once.
        child: AchievementPopupOverlay(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}
