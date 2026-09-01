import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/theme.dart';
import '../../application/achievements_controller.dart';
import '../../domain/progression/achievements.dart';
import '../../domain/text/language.dart';
import '../../l10n/app_localizations.dart';

/// The unlock popup (P17), shown for exactly one [AchievementUnlock] at a
/// time by [AchievementPopupOverlay].
///
/// ONE `TweenAnimationBuilder`, no ticker — the same shape `ChestOpenCard`
/// (P11) and `LevelCompleteCard` (P09) already use, because this is the
/// identical class of celebration: a small, occasional, screen-covering
/// moment that does not need a second animation system of its own.
class AchievementUnlockCard extends StatelessWidget {
  const AchievementUnlockCard({
    required this.unlock,
    required this.onDismiss,
    super.key,
  });

  final AchievementUnlock unlock;
  final VoidCallback onDismiss;

  static const Duration _duration = Duration(milliseconds: 420);

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final (title, description) = _textFor(unlock, l10n);

    return ColoredBox(
      color: tokens.colors.background.withValues(alpha: 0.96),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: Motion.reduced(context, _duration),
        curve: Motion.settle,
        builder: (context, t, child) => Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.scale(scale: 0.85 + t * 0.15, child: child),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppTokens.space24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.emoji_events_rounded,
                  size: 72,
                  color: tokens.colors.primary,
                ),
                const SizedBox(height: AppTokens.space16),
                Text(
                  l10n.achievementUnlockedHeader,
                  style: AppTypography.uiTextStyle(
                    Language.english,
                    UiRole.caption,
                    color: tokens.colors.onSurfaceMuted,
                  ),
                ),
                const SizedBox(height: AppTokens.space8),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: AppTypography.uiTextStyle(
                    Language.english,
                    UiRole.display,
                    color: tokens.colors.onSurface,
                  ),
                ),
                const SizedBox(height: AppTokens.space8),
                Text(
                  description,
                  textAlign: TextAlign.center,
                  style: AppTypography.uiTextStyle(
                    Language.english,
                    UiRole.body,
                    color: tokens.colors.onSurfaceMuted,
                  ),
                ),
                const SizedBox(height: AppTokens.space32),
                FilledButton(
                  onPressed: onDismiss,
                  child: Text(l10n.continueButton),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Collector's category name is deliberately the RAW content key
  /// ("animals"), not a localized string — the same TODO(P17/P21) the
  /// collections grid already carries (CLAUDE.md/P11): localizing all 12
  /// category names is native-speaker review work this prompt does not own.
  static (String, String) _textFor(
    AchievementUnlock unlock,
    AppLocalizations l10n,
  ) => switch (unlock) {
    NamedAchievementUnlock(:final id) => switch (id) {
      AchievementId.firstWord => (
        l10n.achievementFirstWordTitle,
        l10n.achievementFirstWordDescription,
      ),
      AchievementId.wordMaster => (
        l10n.achievementWordMasterTitle,
        l10n.achievementWordMasterDescription,
      ),
      AchievementId.trilingual => (
        l10n.achievementTrilingualTitle,
        l10n.achievementTrilingualDescription,
      ),
      AchievementId.onFire => (
        l10n.achievementOnFireTitle,
        l10n.achievementOnFireDescription,
      ),
      AchievementId.streakKeeper => (
        l10n.achievementStreakKeeperTitle,
        l10n.achievementStreakKeeperDescription,
      ),
      AchievementId.dailyDevotee => (
        l10n.achievementDailyDevoteeTitle,
        l10n.achievementDailyDevoteeDescription,
      ),
      // Never enqueued — see AchievementId.isReachable — but a switch over a
      // sealed/enum type must stay exhaustive rather than assume it.
      AchievementId.speedRunner => (
        l10n.achievementCollectorTitle,
        l10n.achievementCollectorDescription,
      ),
    },
    CollectorAchievementUnlock(:final category) => (
      l10n.achievementCollectorTitle,
      '${l10n.achievementCollectorDescription}: $category',
    ),
  };
}

/// Watches [achievementPopupQueueProvider] and shows [AchievementUnlockCard]
/// for whatever is at the front of it, one at a time.
///
/// Placed in `app.dart`'s `MaterialApp.router.builder`, ABOVE every routed
/// screen — an achievement can unlock while the player is anywhere (a sync
/// landing while they browse the journey map, say), and the queue's own FIFO
/// already guarantees only one card is ever the "front" at once.
class AchievementPopupOverlay extends StatelessWidget {
  const AchievementPopupOverlay({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => Consumer(
    builder: (context, ref, _) {
      final queue = ref.watch(achievementPopupQueueProvider);
      return Stack(
        children: [
          child,
          if (queue.isNotEmpty)
            Positioned.fill(
              child: AchievementUnlockCard(
                key: ValueKey(queue.first.popupId),
                unlock: queue.first,
                onDismiss: () => ref
                    .read(achievementPopupQueueProvider.notifier)
                    .dismissCurrent(),
              ),
            ),
        ],
      );
    },
  );
}
