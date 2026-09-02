import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../services/audio/sound_settings.dart';

/// What the player chose before [PauseSheet] closed. `null` (the sheet
/// dismissed by tapping the scrim, with no button pressed) means the same
/// thing as [resume] — tapping outside a pause sheet returns to the game.
enum PauseAction { resume, restart, home }

/// Ch09: resume, restart, sound toggle, home. Shown with `showModalBottomSheet`;
/// the caller acts on the returned [PauseAction] rather than this widget
/// reaching into [GameController] itself, so it stays a dumb, testable sheet.
class PauseSheet extends ConsumerWidget {
  const PauseSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final soundEnabled = ref.watch(soundEnabledProvider);
    final musicEnabled = ref.watch(musicEnabledProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTokens.space24,
          AppTokens.space24,
          AppTokens.space24,
          AppTokens.space16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(PauseAction.resume),
              child: Text(l10n.resumeButton),
            ),
            const SizedBox(height: AppTokens.space12),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(PauseAction.restart),
              child: Text(l10n.restartButton),
            ),
            const SizedBox(height: AppTokens.space8),
            SwitchListTile(
              title: Text(l10n.soundLabel),
              value: soundEnabled,
              onChanged: (_) =>
                  ref.read(soundEnabledProvider.notifier).toggle(),
            ),
            // Its own switch, not a sub-setting of sound: the two are wanted
            // independently — see `UiSettingsStore.musicEnabled`.
            SwitchListTile(
              title: Text(l10n.musicLabel),
              value: musicEnabled,
              onChanged: (_) =>
                  ref.read(musicEnabledProvider.notifier).toggle(),
            ),
            const SizedBox(height: AppTokens.space8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(PauseAction.home),
              child: Text(l10n.navHome),
            ),
          ],
        ),
      ),
    );
  }
}
