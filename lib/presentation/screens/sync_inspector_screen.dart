import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/theme.dart';
import '../../application/sync_controller.dart';
import '../../data/local/app_database.dart';
import '../../data/repositories/outbox_repository.dart';
import '../../domain/sync/backoff.dart';
import '../../domain/sync/outbox_status.dart';
import '../../domain/text/language.dart';
import '../../services/connectivity/connectivity_service.dart';

/// DEV-ONLY. Every queued submission, why it has not gone, and a force-drain.
///
/// ---------------------------------------------------------------------------
/// WHY THIS SCREEN EXISTS
///
/// The sync engine is deliberately silent: no dialogs, no banners, no retry
/// buttons (Ch10). That is right for a player and impossible for a developer —
/// "my level did not count" is otherwise a bug with no observable surface at
/// all. This screen is that surface, and it is the reason the queue can afford
/// to say nothing to anyone else.
///
/// Registered only on the dev flavor, in the route table itself rather than
/// gated inside the widget — the same treatment the Style Gallery gets, so
/// there is no build in which a player can reach it.
///
/// ---------------------------------------------------------------------------
/// EVERY STRING HERE IS A HARDCODED LITERAL, ON PURPOSE
///
/// Dev tooling is allowlisted from `check_localized_strings.dart` for the same
/// reason `GameDebugPanel` is: translating "next retry" into Urdu and Hindi
/// would spend a native speaker's review budget on text that never ships, and
/// the ARB files already carry a backlog of real player-facing copy awaiting
/// exactly that review.
class SyncInspectorScreen extends ConsumerWidget {
  const SyncInspectorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTokens.of(context);
    final syncState = ref.watch(syncControllerProvider);
    final online = ref.watch(isOnlineProvider).value ?? true;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync Inspector'),
        actions: [
          IconButton(
            tooltip: 'Force drain',
            icon: syncState.isDraining
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            // FORCES PAST BOTH GATES: it clears every `next_retry_at` and then
            // drains with `force: true`, which skips the connectivity check.
            // A force button that still respected the backoff would be useless
            // exactly when it is needed — six hours into the ladder.
            onPressed: syncState.isDraining
                ? null
                : () async {
                    final outbox = await ref.read(
                      outboxRepositoryProvider.future,
                    );
                    await outbox.clearBackoff();
                    await ref
                        .read(syncControllerProvider.notifier)
                        .drain(force: true);
                  },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(online: online, state: syncState),
            const Divider(height: 1),
            Expanded(
              child: ref
                  .watch(outboxRowsProvider)
                  .when(
                    data: (rows) => rows.isEmpty
                        ? const Center(child: Text('Queue is empty'))
                        : ListView.separated(
                            itemCount: rows.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) =>
                                _OutboxTile(row: rows[index]),
                          ),
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, _) => Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppTokens.space24),
                        child: Text(
                          'Outbox unavailable: $error',
                          style: AppTypography.uiTextStyle(
                            Language.english,
                            UiRole.caption,
                            color: tokens.colors.onSurfaceMuted,
                          ),
                        ),
                      ),
                    ),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.online, required this.state});

  final bool online;
  final SyncState state;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final summary = state.lastSummary;

    return Padding(
      padding: const EdgeInsets.all(AppTokens.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            online ? 'ONLINE' : 'OFFLINE',
            style: AppTypography.uiTextStyle(
              Language.english,
              UiRole.body,
              color: online
                  ? tokens.colors.primary
                  : tokens.colors.onSurfaceMuted,
            ),
          ),
          const SizedBox(height: AppTokens.space4),
          Text(
            summary == null
                ? 'No drain has run this session'
                : 'Last drain: $summary',
            style: AppTypography.uiTextStyle(
              Language.english,
              UiRole.caption,
              color: tokens.colors.onSurfaceMuted,
            ),
          ),
          const SizedBox(height: AppTokens.space4),
          Text(
            // The backoff ladder itself, so a tester reading a `next retry`
            // below can tell at a glance whether it is on the curve.
            'Ladder: ${BackoffSchedule.steps.map(_short).join(' · ')} '
            '(+/-${(BackoffSchedule.jitterFraction * 100).round()}%)',
            style: AppTypography.uiTextStyle(
              Language.english,
              UiRole.caption,
              color: tokens.colors.onSurfaceFaint,
            ),
          ),
        ],
      ),
    );
  }
}

class _OutboxTile extends ConsumerWidget {
  const _OutboxTile({required this.row});

  final OutboxRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTokens.of(context);
    final status = outboxStatusOf(row);
    final now = DateTime.now().millisecondsSinceEpoch;
    final nextRetryAt = row.nextRetryAt;

    final due =
        status == OutboxStatus.pending &&
        (nextRetryAt == null || nextRetryAt <= now);

    return ListTile(
      dense: true,
      leading: Icon(
        switch (status) {
          OutboxStatus.pending => due ? Icons.upload_outlined : Icons.schedule,
          OutboxStatus.failedPermanent => Icons.report_gmailerrorred_outlined,
          OutboxStatus.succeeded => Icons.check_circle_outline,
        },
        color: status == OutboxStatus.failedPermanent
            ? tokens.colors.onSurfaceMuted
            : tokens.colors.onSurfaceFaint,
      ),
      title: Text('#${row.id}  ${row.kind}'),
      subtitle: Text(
        [
          'attempts: ${row.attempts}',
          if (nextRetryAt != null)
            'next retry: ${_relative(nextRetryAt - now)}'
          else if (status == OutboxStatus.pending)
            'next retry: now',
          if (status == OutboxStatus.failedPermanent) 'PERMANENTLY FAILED',
        ].join('   '),
        style: AppTypography.uiTextStyle(
          Language.english,
          UiRole.caption,
          color: tokens.colors.onSurfaceMuted,
        ),
      ),
      // A permanently failed row can be put back, which is the one action this
      // screen offers beyond looking: it is how a developer confirms a payload
      // fix without clearing the whole database and replaying twenty levels.
      trailing: status == OutboxStatus.failedPermanent
          ? IconButton(
              tooltip: 'Requeue',
              icon: const Icon(Icons.replay),
              onPressed: () async {
                final outbox = await ref.read(outboxRepositoryProvider.future);
                await outbox.retryPermanentFailure(row.id);
              },
            )
          : null,
      onTap: () => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('#${row.id} ${row.kind}'),
          content: SingleChildScrollView(child: SelectableText(row.payload)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  static String _relative(int millis) {
    if (millis <= 0) return 'now';
    return _short(Duration(milliseconds: millis));
  }
}

String _short(Duration duration) {
  if (duration.inMilliseconds == 0) return 'now';
  if (duration.inSeconds < 60) return '${duration.inSeconds}s';
  if (duration.inMinutes < 60) return '${duration.inMinutes}m';
  if (duration.inHours < 24) return '${duration.inHours}h';
  return '${duration.inDays}d';
}

/// Every outbox row, newest first. Dev tooling only.
final outboxRowsProvider = StreamProvider.autoDispose<List<OutboxRow>>((
  ref,
) async* {
  final outbox = await ref.watch(outboxRepositoryProvider.future);
  yield* outbox.watchAll();
});
