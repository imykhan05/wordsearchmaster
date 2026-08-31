/// The ONLY thing the sync engine is allowed to show a player (Ch10 / P16).
///
/// ---------------------------------------------------------------------------
/// NO "NO INTERNET" DIALOG. EVER.
///
/// CLAUDE.md forbids it outright and Ch10 explains why: the audience in Ch01
/// is offline more often than not, so an app that interrupts to announce it is
/// an app that interrupts constantly — and interrupts to report something the
/// player already knows and cannot fix. The game is fully playable either way
/// (Ch10 makes the local database the source of truth), so being offline is
/// not an error condition at all. It is a normal state, and normal states get
/// a status icon, not a modal.
///
/// The rule is enforced structurally rather than by convention: nothing in the
/// sync subsystem holds a `BuildContext`, so there is no code path from a
/// failed drain to a dialog. `no_network_dialog_test.dart` proves the
/// property from the other end, by driving a full offline session and
/// asserting that no dialog, no bottom sheet and no snackbar is ever built.
///
/// ---------------------------------------------------------------------------
/// WHAT THIS WIDGET IS ALLOWED TO BE
///
/// Small, static, and never load-bearing for layout. It reserves its own space
/// whether or not it has anything to show, so appearing and disappearing can
/// never reflow the row it sits in — the same "disable in place" rule
/// [RewardedActionButton] keeps, for the same reason: a control that moves
/// under a finger already travelling towards it is worse than one that is
/// simply unavailable.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/theme.dart';
import '../../domain/text/language.dart';
import '../../l10n/app_localizations.dart';
import '../../services/connectivity/connectivity_service.dart';

/// A small static offline / pending-sync indicator.
///
/// Renders one of three things in a FIXED footprint:
///
///   * offline, with work queued -> a cloud-off icon;
///   * offline, nothing queued   -> a cloud-off icon (still honest: the player
///     is offline, they just have nothing waiting);
///   * online                    -> nothing visible, same size.
///
/// It is deliberately not a button. Tapping it would imply the player can do
/// something about it, and they cannot.
class SyncStatusIndicator extends ConsumerWidget {
  const SyncStatusIndicator({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tokens = AppTokens.of(context);
    // WATCHES CONNECTIVITY AND NOTHING ELSE, deliberately.
    //
    // An earlier version also watched the queue depth so the label could read
    // "3 items waiting to sync" — which opened a LIVE DRIFT QUERY from a
    // widget that sits in every app bar in the game. That is the exact trap
    // CLAUDE.md already records from P11: a Drift stream schedules a cleanup
    // timer when it is cancelled, and the timer outlives the widget tree, so
    // every widget test that visited any screen died on "a Timer is still
    // pending after the widget tree was disposed".
    //
    // It was also more than Ch10 asks for. The rule is a small static OFFLINE
    // indicator; the queue depth is a developer's question, and the Sync
    // Inspector answers it properly.
    final online = ref.watch(isOnlineProvider).value ?? true;
    final label = online ? l10n.syncUpToDateLabel : l10n.offlineIndicatorLabel;

    return SizedBox(
      // The footprint is constant. An indicator that collapsed when the
      // connection came back would shift whatever sits beside it, which on the
      // home screen is a row of taps.
      width: size,
      height: size,
      child: Semantics(
        label: label,
        // Not a button, not a live region: it must not steal focus or
        // interrupt a screen reader mid-sentence to announce a state change
        // the player cannot act on.
        container: true,
        child: online
            ? const SizedBox.shrink()
            : Tooltip(
                message: label,
                child: Icon(
                  Icons.cloud_off_outlined,
                  size: size,
                  color: tokens.colors.onSurfaceFaint,
                ),
              ),
      ),
    );
  }
}

/// A rewarded-ad action that DISABLES IN PLACE rather than disappearing.
///
/// Ch10 asks for this explicitly, and the reason is a finger already moving.
/// A player reaches for "double your coins" the instant the level-complete
/// card settles; if the button vanishes because the radio dropped in that same
/// moment, everything below it jumps up and the tap lands on whatever took its
/// place. A disabled button in the same rectangle costs the player one wasted
/// tap and nothing else.
///
/// So the widget renders the SAME subtree at the SAME size in both states —
/// only `onPressed` and the colours change. `sync_ux_test.dart` measures the
/// rendered rect online and offline and asserts they are identical, because
/// "looks about the same" is not a property a future refactor preserves.
class RewardedActionButton extends ConsumerWidget {
  const RewardedActionButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
  });

  final String label;

  /// Null means "not available yet" — the P18 ad wiring, or a reward already
  /// taken. Combined with connectivity below; either one disables.
  final VoidCallback? onPressed;

  final IconData? icon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(isOnlineProvider).value ?? true;
    // A rewarded ad genuinely cannot be shown offline, so the button is
    // honestly unavailable — this is not a pessimistic guess like the
    // connectivity check in the sync worker, where trying anyway is free.
    final enabled = online && onPressed != null;

    return OutlinedButton.icon(
      onPressed: enabled ? onPressed : null,
      // `icon` is passed in both states rather than dropped when disabled:
      // an icon that disappears changes the button's intrinsic width.
      icon: Icon(icon ?? Icons.play_circle_outline),
      label: Text(label),
    );
  }
}

/// "Updated 5 minutes ago", from a millis timestamp.
///
/// A RELATIVE label rather than an absolute one, because the number a player
/// needs is "is this stale?", and answering that from a wall-clock time makes
/// them do the subtraction. It also sidesteps a real localisation trap: a
/// formatted date needs a calendar, a numbering system and an ordering that
/// differ across the three scripts this game ships in, while "5 minutes ago"
/// needs one plural rule that the ARB files already express.
class LastUpdatedLabel extends StatelessWidget {
  const LastUpdatedLabel({super.key, required this.timestampMillis, this.now});

  final int timestampMillis;

  /// Injected in tests. Real callers leave it null and get the wall clock.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = AppTokens.of(context);

    return Text(
      l10n.lastUpdatedLabel(
        relativeTime(l10n, timestampMillis, now: now ?? DateTime.now()),
      ),
      style: AppTypography.uiTextStyle(
        // Matching the rest of the meta surfaces, which pass `english` for
        // chrome text and reserve the script-aware styles for content.
        Language.english,
        UiRole.caption,
        color: tokens.colors.onSurfaceMuted,
      ),
    );
  }
}

/// The relative phrase for [timestampMillis], in coarsening buckets.
///
/// Coarse ON PURPOSE. "3 days ago" and "3 days and 4 hours ago" answer the
/// same question, and the second one invites a player to wonder whether the
/// extra precision means something. Anything in the future — a device whose
/// clock ran ahead, which `TrustedClock` already documents as the case it
/// cannot prevent — reads as "just now" rather than as a negative duration.
String relativeTime(
  AppLocalizations l10n,
  int timestampMillis, {
  required DateTime now,
}) {
  final elapsed = now.millisecondsSinceEpoch - timestampMillis;
  if (elapsed < const Duration(minutes: 1).inMilliseconds) {
    return l10n.relativeJustNow;
  }
  final minutes = elapsed ~/ const Duration(minutes: 1).inMilliseconds;
  if (minutes < 60) return l10n.relativeMinutesAgo(minutes);
  final hours = elapsed ~/ const Duration(hours: 1).inMilliseconds;
  if (hours < 24) return l10n.relativeHoursAgo(hours);
  return l10n.relativeDaysAgo(
    elapsed ~/ const Duration(days: 1).inMilliseconds,
  );
}
