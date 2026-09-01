import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/app/theme/app_theme.dart';
import 'package:word_search_master/application/achievements_controller.dart';
import 'package:word_search_master/domain/progression/achievements.dart';
import 'package:word_search_master/l10n/app_localizations.dart';
import 'package:word_search_master/presentation/meta/achievement_unlock_card.dart';

/// "Queued so two unlocks never overlap" — P17's own words. Proves the
/// overlay shows exactly one card at a time, in FIFO order, and dismissing
/// reveals the next one rather than both at once.
void main() {
  Widget wrap() => ProviderScope(
    child: MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const AchievementPopupOverlay(
        child: Scaffold(body: Text('game screen')),
      ),
    ),
  );

  testWidgets('no queue: only the wrapped child renders', (tester) async {
    await tester.pumpWidget(wrap());

    expect(find.text('game screen'), findsOneWidget);
    expect(find.byType(AchievementUnlockCard), findsNothing);
  });

  testWidgets('two unlocks queued: only the front one shows', (tester) async {
    await tester.pumpWidget(wrap());
    final element = tester.element(find.byType(AchievementPopupOverlay));
    final container = ProviderScope.containerOf(element);

    container
        .read(achievementPopupQueueProvider.notifier)
        .enqueueIfUnseen(const NamedAchievementUnlock(AchievementId.firstWord));
    container
        .read(achievementPopupQueueProvider.notifier)
        .enqueueIfUnseen(
          const NamedAchievementUnlock(AchievementId.wordMaster),
        );
    await tester.pump();

    expect(find.byType(AchievementUnlockCard), findsOneWidget);
    expect(find.text('First Word'), findsOneWidget);
    expect(find.text('Word Master'), findsNothing);
  });

  testWidgets('dismissing the front card reveals the next one', (tester) async {
    await tester.pumpWidget(wrap());
    final element = tester.element(find.byType(AchievementPopupOverlay));
    final container = ProviderScope.containerOf(element);
    final notifier = container.read(achievementPopupQueueProvider.notifier);
    notifier.enqueueIfUnseen(
      const NamedAchievementUnlock(AchievementId.firstWord),
    );
    notifier.enqueueIfUnseen(
      const NamedAchievementUnlock(AchievementId.wordMaster),
    );
    await tester.pump();

    await tester.tap(find.byType(FilledButton));
    // The card's own `TweenAnimationBuilder` needs a frame to settle after
    // the state change; `pumpAndSettle` is safe here since nothing in this
    // subtree schedules an indeterminate spinner (unlike the Sync
    // Inspector's live Drift stream — see that test's own note on why it
    // avoids `pumpAndSettle`).
    await tester.pumpAndSettle();

    expect(find.text('Word Master'), findsOneWidget);
    expect(find.text('First Word'), findsNothing);
  });
}
