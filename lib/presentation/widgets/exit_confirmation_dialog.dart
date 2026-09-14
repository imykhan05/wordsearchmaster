import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/language/selected_language.dart';
import '../../app/theme/theme.dart';
import '../../application/progression_controller.dart';
import '../../l10n/app_localizations.dart';
import 'tap_feedback.dart';

/// The "Exit game?" confirmation shown when the player presses system back
/// on [HomeScreen] — the one screen `SystemBackHandler` has nowhere further
/// to send them, because Home is the root of the app's `.go()` hub (see that
/// widget's own header).
///
/// Styled off [SplashInkPalette] — the fixed parchment-and-ink look of
/// `SplashScreen` — rather than the in-game Slate & Marigold theme. This is
/// the player's LAST frame before the OS takes over, the same branding beat
/// as their first, so it deliberately borrows that screen's look instead of
/// whichever in-game theme happens to be selected.
abstract final class ExitConfirmationDialog {
  /// Shows the confirmation and, if the player confirms, closes the app.
  ///
  /// Returns after the app-close request has been sent, so a caller has
  /// nothing further to do — [SystemBackHandler.onBack] can call this
  /// directly.
  static Future<void> show(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      // Same ink tone as the rest of this dialog rather than a bare
      // `Colors.black54` — `check_no_raw_colors` rejects the latter, and
      // 0.54 alpha is the same visual weight `black54` would have given.
      barrierColor: SplashInkPalette.fill.withValues(alpha: 0.54),
      builder: (_) => const _ExitConfirmationDialogContent(),
    );
    if (confirmed != true) return;
    // Belt and braces alongside `game_screen.dart`'s `_leaveGame` — by the
    // time a player reaches Home, any level save should already have landed,
    // but this costs nothing and closes the same gap if it somehow has not.
    // See `ProgressionController.awaitPendingCompletion` for the mechanism.
    await ref
        .read(progressionControllerProvider.notifier)
        .awaitPendingCompletion();
    // Android: drops the task and returns to the home screen/launcher, the
    // same place system back would have gone with no `SystemBackHandler` in
    // the way. iOS ignores this per Apple's own guidance (apps are expected
    // to suspend, not quit), so this is a no-op there.
    await SystemNavigator.pop();
  }
}

class _ExitConfirmationDialogContent extends ConsumerWidget {
  const _ExitConfirmationDialogContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final language = ref.watch(selectedLanguageProvider);

    final titleStyle = AppTypography.uiTextStyle(
      language,
      UiRole.heading,
      color: SplashInkPalette.fill,
    );
    final messageStyle = AppTypography.uiTextStyle(
      language,
      UiRole.body,
      color: SplashInkPalette.fill,
    );
    final actionStyle = AppTypography.uiTextStyle(
      language,
      UiRole.label,
      color: SplashInkPalette.fill,
    );

    void respond(bool value) {
      ref.tapFeedback();
      Navigator.of(context).pop(value);
    }

    return Dialog(
      // True transparency so the Container below paints its own card — a
      // token at zero alpha rather than `Colors.transparent`, the same
      // substitution `game_screen.dart`'s and `home_screen.dart`'s own
      // Scaffolds already make, for the identical reason.
      backgroundColor: SplashInkPalette.fill.withValues(alpha: 0),
      insetPadding: const EdgeInsets.symmetric(horizontal: AppTokens.space24),
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          AppTokens.space24,
          AppTokens.space32,
          AppTokens.space24,
          AppTokens.space24,
        ),
        decoration: BoxDecoration(
          color: SplashInkPalette.track,
          borderRadius: AppTokens.borderRadius16,
          border: Border.all(color: SplashInkPalette.border, width: 2),
          boxShadow: [
            BoxShadow(
              color: SplashInkPalette.fill.withValues(alpha: 0.35),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(AppTokens.space12),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: SplashInkPalette.fill.withValues(alpha: 0.1),
                border: Border.all(color: SplashInkPalette.border),
              ),
              child: const Icon(
                Icons.exit_to_app_rounded,
                size: 32,
                color: SplashInkPalette.fill,
              ),
            ),
            const SizedBox(height: AppTokens.space16),
            Text(
              l10n.exitAppTitle,
              textAlign: TextAlign.center,
              style: titleStyle,
            ),
            const SizedBox(height: AppTokens.space8),
            Text(
              l10n.exitAppMessage,
              textAlign: TextAlign.center,
              style: messageStyle,
            ),
            const SizedBox(height: AppTokens.space24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: SplashInkPalette.fill,
                      side: const BorderSide(color: SplashInkPalette.fill),
                      shape: const RoundedRectangleBorder(
                        borderRadius: AppTokens.borderRadius8,
                      ),
                      padding: const EdgeInsets.symmetric(
                        vertical: AppTokens.space12,
                      ),
                      textStyle: actionStyle,
                      minimumSize: const Size(0, AppTokens.minTouchTarget),
                    ),
                    onPressed: () => respond(false),
                    child: Text(l10n.exitAppCancelAction),
                  ),
                ),
                const SizedBox(width: AppTokens.space12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: SplashInkPalette.fill,
                      foregroundColor: SplashInkPalette.track,
                      shape: const RoundedRectangleBorder(
                        borderRadius: AppTokens.borderRadius8,
                      ),
                      padding: const EdgeInsets.symmetric(
                        vertical: AppTokens.space12,
                      ),
                      textStyle: actionStyle.copyWith(
                        color: SplashInkPalette.track,
                      ),
                      minimumSize: const Size(0, AppTokens.minTouchTarget),
                    ),
                    onPressed: () => respond(true),
                    child: Text(l10n.exitAppConfirmAction),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
