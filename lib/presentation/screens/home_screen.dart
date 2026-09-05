import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_route.dart';
import '../../app/theme/theme.dart';
import '../../application/account_controller.dart';
import '../../domain/progression/streak.dart';
import '../../domain/text/language.dart';
import '../../l10n/app_localizations.dart';
import '../widgets/sync_status.dart';
import '../../services/audio/audio_service.dart';
import '../../services/haptics/haptics_service.dart';
import '../../services/notifications/notification_service.dart';
import '../../services/settings/ui_settings_store.dart';
import '../meta/journey_providers.dart';
import '../meta/meta_tiles.dart';

/// Home (Ch02): the streak counter is the most prominent thing on it, the
/// coin balance sits beside it, and one button drops the player back into the
/// journey exactly where they left off.
///
/// Everything here reads through the P11 providers rather than a repository
/// directly, so the screen renders and decides nothing — the same discipline
/// the journey map keeps.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tokens = AppTokens.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navHome),
        actions: const [
          // Ch10's ONE permitted network surface: a small static icon. Never a
          // dialog, never a banner, never a retry button — see
          // `SyncStatusIndicator`'s own header.
          Padding(
            padding: EdgeInsets.only(right: AppTokens.space16),
            child: Center(child: SyncStatusIndicator()),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppTokens.space24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _StreakBanner(),
              // Invisible — see its own doc for why the streak banner is the
              // trigger rather than first launch or app resume.
              const _NotificationPermissionRequester(),
              const SizedBox(height: AppTokens.space16),
              const CoinBalanceTile(),
              // Renders nothing (and no extra gap) until level 8 is
              // completed and stays dismissible after that — see its own doc.
              const _SaveProgressBanner(),
              const SizedBox(height: AppTokens.space32),
              FilledButton(
                onPressed: () {
                  ref.read(audioServiceProvider).playButtonTap();
                  ref.read(hapticsServiceProvider).buttonTap();
                  context.go(const JourneyRoute().location);
                },
                child: Text(l10n.playButton),
              ),
              const SizedBox(height: AppTokens.space12),
              OutlinedButton(
                onPressed: () {
                  ref.read(audioServiceProvider).playButtonTap();
                  ref.read(hapticsServiceProvider).buttonTap();
                  context.go(const DailyRoute().location);
                },
                child: Text(l10n.navDaily),
              ),
              const SizedBox(height: AppTokens.space12),
              TextButton(
                onPressed: () => context.go(const ProfileRoute().location),
                child: Text(l10n.collectionsTitle),
              ),
              const SizedBox(height: AppTokens.space24),
              Text(
                l10n.appTitle,
                textAlign: TextAlign.center,
                style: AppTypography.uiTextStyle(
                  Language.english,
                  UiRole.caption,
                  color: tokens.colors.onSurfaceFaint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The Ch02 streak counter, and the one place a spent freeze is surfaced.
///
/// A freeze firing is the only streak outcome a player could otherwise
/// mistake for a bug ("I missed Tuesday and my streak is still 12"), so the
/// banner says so explicitly when `StreakEvent.frozen` comes back from the
/// settle — see `StreakRules`' library header.
class _StreakBanner extends ConsumerWidget {
  const _StreakBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tokens = AppTokens.of(context);
    final streakAsync = ref.watch(currentStreakProvider);

    final transition = streakAsync.value;
    final state = transition?.state ?? StreakState.empty;

    return MetaCard(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.local_fire_department_rounded,
                size: 40,
                color: state.current > 0
                    ? tokens.colors.primary
                    : tokens.colors.onSurfaceFaint,
              ),
              const SizedBox(width: AppTokens.space8),
              Text(
                '${state.current}',
                style: AppTypography.uiTextStyle(
                  Language.english,
                  UiRole.display,
                  color: tokens.colors.onSurface,
                ),
              ),
            ],
          ),
          Text(
            l10n.streakLabel,
            style: AppTypography.uiTextStyle(
              Language.english,
              UiRole.caption,
              color: tokens.colors.onSurfaceMuted,
            ),
          ),
          if (state.freezes > 0) ...[
            const SizedBox(height: AppTokens.space8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.ac_unit_rounded,
                  size: 16,
                  color: tokens.colors.info,
                ),
                const SizedBox(width: AppTokens.space4),
                Text(
                  l10n.streakFreezesLabel(state.freezes),
                  style: AppTypography.uiTextStyle(
                    Language.english,
                    UiRole.caption,
                    color: tokens.colors.info,
                  ),
                ),
              ],
            ),
          ],
          if (transition?.event == StreakEvent.frozen) ...[
            const SizedBox(height: AppTokens.space8),
            Text(
              l10n.streakFrozenMessage,
              textAlign: TextAlign.center,
              style: AppTypography.uiTextStyle(
                Language.english,
                UiRole.caption,
                color: tokens.colors.info,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Post-P17: asks for the OS notification permission once a streak exists
/// worth protecting, never on first launch.
///
/// Entirely invisible — [build] always returns [SizedBox.shrink]. The streak
/// banner sitting right above it is what makes the MOMENT defensible rather
/// than arbitrary: Ch02's FTUE (`app_smoke_test.dart` pins "no login, no
/// permission dialog, no ad" on the very first screen) rules out asking
/// before a player has played at all, and asking the instant they reach Home
/// for the first time would be the identical mistake one screen later. A
/// streak of 2 is the earliest point there is something concrete to lose,
/// which is what the permission is actually for.
///
/// [_requested] is a LOCAL, session-only guard, separate from
/// [UiSettingsStore.notificationPermissionAsked]: the store's flag is written
/// asynchronously, and [NotificationService] is not itself observed by
/// Riverpod, so nothing else stops [build] running again — a level completing
/// while the request is still in flight, say — before that write lands. The
/// stored flag is what makes the ask permanent across sessions; this field is
/// what makes it idempotent within one.
class _NotificationPermissionRequester extends ConsumerStatefulWidget {
  const _NotificationPermissionRequester();

  @override
  ConsumerState<_NotificationPermissionRequester> createState() =>
      _NotificationPermissionRequesterState();
}

class _NotificationPermissionRequesterState
    extends ConsumerState<_NotificationPermissionRequester> {
  bool _requested = false;

  Future<void> _ask() async {
    await ref.read(notificationServiceProvider).requestPermission();
    await ref
        .read(uiSettingsStoreProvider)
        .setNotificationPermissionAsked(true);
  }

  @override
  Widget build(BuildContext context) {
    final streak = ref.watch(currentStreakProvider).value?.state.current ?? 0;
    final alreadyAsked = ref
        .read(uiSettingsStoreProvider)
        .notificationPermissionAsked;

    if (!_requested && !alreadyAsked && streak >= 2) {
      _requested = true;
      // Deferred a frame: this runs from inside `build`, and the OS
      // permission sheet is exactly the kind of side effect that must not
      // start before the frame it was triggered from has finished.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_ask());
      });
    }

    return const SizedBox.shrink();
  }
}

/// Ch02/P12: "Login is offered only after level 8, framed as 'save your
/// progress', and is dismissible." No real auth exists yet (P13) — accepting
/// the offer is a stub, the same status as `doubleRewardPlaceholder`/
/// `adPlaceholderLabel`'s P18 ad placeholders, and dismisses the banner
/// exactly as declining it does, rather than leaving a half-finished flow on
/// screen.
///
/// A `ConsumerStatefulWidget` purely to hold [_dismissed] — the persisted
/// flag it is seeded from (`UiSettingsStore.loginPromptDismissed`) is a plain
/// synchronous field, not itself an observable Riverpod stream, so a local
/// `ValueNotifier` is what lets dismissing it repaint just this card. Same
/// shape as `game_screen.dart`'s `_urduIntroDismissed`.
class _SaveProgressBanner extends ConsumerStatefulWidget {
  const _SaveProgressBanner();

  @override
  ConsumerState<_SaveProgressBanner> createState() =>
      _SaveProgressBannerState();
}

class _SaveProgressBannerState extends ConsumerState<_SaveProgressBanner> {
  late final ValueNotifier<bool> _dismissed = ValueNotifier<bool>(
    ref.read(uiSettingsStoreProvider).loginPromptDismissed,
  );

  @override
  void dispose() {
    _dismissed.dispose();
    super.dispose();
  }

  void _dismiss() {
    _dismissed.value = true;
    unawaited(ref.read(uiSettingsStoreProvider).setLoginPromptDismissed(true));
  }

  /// The real guest→Google flow (P13), replacing P12's placeholder.
  ///
  /// Dismisses on SUCCESS only. A player who cancelled the sheet or hit a
  /// network failure has not decided anything, and hiding the offer would
  /// take away the retry they are most likely to want next.
  Future<void> _accept(AppLocalizations l10n) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref
        .read(accountControllerProvider.notifier)
        .linkWithGoogle();
    if (!mounted) return;

    final message = switch (result) {
      AccountLinkResult.linked => l10n.signInSuccessMessage,
      AccountLinkResult.linkedMergePending => l10n.signInMergePendingMessage,
      AccountLinkResult.failed => l10n.signInFailedMessage,
      AccountLinkResult.cancelled => null,
    };
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
    if (result == AccountLinkResult.linked ||
        result == AccountLinkResult.linkedMergePending) {
      _dismiss();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = AppTokens.of(context);
    final highest = ref.watch(highestCompletedLevelProvider).value ?? 0;

    return ValueListenableBuilder<bool>(
      valueListenable: _dismissed,
      builder: (context, dismissed, child) {
        if (dismissed || highest < 8) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(top: AppTokens.space16),
          child: MetaCard(
            child: Row(
              children: [
                Icon(Icons.cloud_outlined, color: tokens.colors.info),
                const SizedBox(width: AppTokens.space12),
                Expanded(
                  child: Text(
                    l10n.saveProgressPromptMessage,
                    style: AppTypography.uiTextStyle(
                      Language.english,
                      UiRole.body,
                      color: tokens.colors.onSurface,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => unawaited(_accept(l10n)),
                  child: Text(l10n.saveProgressPromptAction),
                ),
                IconButton(
                  tooltip: l10n.saveProgressPromptDismiss,
                  onPressed: _dismiss,
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
