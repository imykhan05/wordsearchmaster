import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../services/audio/audio_service.dart';
import '../services/haptics/haptics_service.dart';
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

    // Ch03: master mute/haptics toggles must reach the audio and haptics
    // services instantly. Watched once, here, rather than per-screen — both
    // providers are `ref.listen`-based side-effect syncs (see their doc
    // comments), so this just has to keep them alive for the app's life.
    ref.watch(audioMuteSyncProvider);
    ref.watch(hapticsEnabledSyncProvider);

    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,

      locale: language.locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,

      // Dark is the product default; light is offered for players who prefer
      // it and doubles as the high-contrast option (Ch03). The theme takes the
      // language so its default font family follows the script.
      theme: AppTheme.light(language: language),
      darkTheme: AppTheme.dark(language: language),
      themeMode: ThemeMode.dark,

      routerConfig: router,

      // The locale delegates would already give Urdu an RTL Directionality.
      // Wrapping explicitly anyway is deliberate: the grid's gesture maths
      // and the generator's direction vectors are both keyed off
      // Language.isRtl, and this guarantees the rendered direction can never
      // disagree with them — not even if a delegate's locale table changes
      // under a Flutter upgrade.
      builder: (context, child) => Directionality(
        textDirection: language.textDirection,
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
