/// The outbox drain (Ch10 / P16).
///
/// ---------------------------------------------------------------------------
/// WHAT THIS IS FOR
///
/// Ch10 makes the local database the source of truth and the network a
/// background courier. Every mutation already writes its game-state row and
/// its outbox row in ONE transaction (P08), so by the time this class runs,
/// the player's progress is safe whether or not anything here succeeds. That
/// is the whole reason the drain is allowed to be as lazy, as jittered and as
/// silent as it is: nothing is waiting on it.
///
/// ---------------------------------------------------------------------------
/// THE THREE ORDERING RULES, AND WHY EACH ONE EXISTS
///
///  1. OLDEST FIRST. `ConflictResolver` rule 1 reconciles a level against the
///     server's best-of, and that number is only right once every earlier
///     submission for that level has landed. FIFO is what makes "earlier"
///     mean anything.
///  2. ONE KIND AT A TIME. Ch10 asks for it, and it also keeps a burst of
///     level submissions from interleaving with dailies in a way that makes a
///     Sync Inspector log unreadable. Kinds are taken in the order their
///     oldest row was queued, so a kind can never starve behind another.
///  3. AT MOST ONE ROW PER CONFLICT KEY IN FLIGHT. This one is not in the
///     prompt and is load-bearing anyway: with a concurrency limit of 2, two
///     submissions of the SAME level could otherwise be in flight together,
///     each returning a best-of computed before the other landed — and the
///     reply that arrived last would win with the staler number. Serialising
///     by conflict key costs nothing (rows for one level are rare) and closes
///     it completely.
///
/// ---------------------------------------------------------------------------
/// SILENCE IS A FEATURE
///
/// Nothing in this file can produce a dialog, a snackbar or a route change.
/// Ch10 forbids a "no internet" dialog outright, and the reason is the
/// audience: a player on 2G in a village is offline more often than not, and
/// an app that interrupts them to say so is an app that interrupts them
/// constantly. The ONLY thing the player ever sees of this subsystem is a
/// small static indicator, which is a widget that reads state — it is never
/// pushed at them from here.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/local/app_database.dart';
import '../data/local/outbox_kind.dart';
import '../data/remote/sync_api.dart';
import '../data/repositories/daily_repository.dart';
import '../data/local/tables.dart';
import '../data/repositories/outbox_repository.dart';
import '../data/repositories/progress_repository.dart';
import '../domain/progression/day_key.dart';
import '../domain/sync/conflict_resolver.dart';
import '../domain/text/language.dart';
import '../services/connectivity/connectivity_service.dart';
import '../services/diagnostics/error_reporter.dart';

part 'sync_controller.g.dart';

/// How many submissions may be in flight at once (Ch10).
///
/// Two, not more. This runs on a 2GB phone over a link that Ch01 assumes is
/// 2G, where a third concurrent request buys almost no wall-clock time and
/// costs a third socket, a third TLS handshake and a third slice of a very
/// small radio budget. Two is enough to hide one request's latency behind
/// another's, which is the only thing concurrency is here to do.
const int syncConcurrency = 2;

/// What one drain did. Purely informational — nothing gates on it.
final class SyncSummary {
  const SyncSummary({
    this.succeeded = 0,
    this.transientFailures = 0,
    this.permanentFailures = 0,
    this.deferred = 0,
    this.reconciled = 0,
  });

  final int succeeded;
  final int transientFailures;
  final int permanentFailures;
  final int deferred;

  /// How many rows came back with a score that disagreed with the local one.
  /// Expected to be zero forever; a non-zero value here is the signal that
  /// either a client is tampered with or the two scoring ports have drifted.
  final int reconciled;

  int get attempted =>
      succeeded + transientFailures + permanentFailures + deferred;

  SyncSummary operator +(SyncSummary other) => SyncSummary(
    succeeded: succeeded + other.succeeded,
    transientFailures: transientFailures + other.transientFailures,
    permanentFailures: permanentFailures + other.permanentFailures,
    deferred: deferred + other.deferred,
    reconciled: reconciled + other.reconciled,
  );

  @override
  String toString() =>
      'SyncSummary(ok: $succeeded, retry: $transientFailures, '
      'dropped: $permanentFailures, deferred: $deferred, '
      'reconciled: $reconciled)';
}

/// Live state for the indicator and the Sync Inspector.
final class SyncState {
  const SyncState({this.isDraining = false, this.lastSyncAt, this.lastSummary});

  final bool isDraining;

  /// Millis of the last drain that sent at least one row successfully.
  final int? lastSyncAt;

  final SyncSummary? lastSummary;

  SyncState copyWith({
    bool? isDraining,
    int? lastSyncAt,
    SyncSummary? lastSummary,
  }) => SyncState(
    isDraining: isDraining ?? this.isDraining,
    lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    lastSummary: lastSummary ?? this.lastSummary,
  );

  @override
  String toString() =>
      'SyncState(draining: $isDraining, lastSyncAt: $lastSyncAt, '
      '$lastSummary)';
}

@Riverpod(keepAlive: true)
class SyncController extends _$SyncController {
  /// Guards against two drains overlapping.
  ///
  /// A plain bool rather than a lock, because the second caller should NOT
  /// queue up behind the first — it should return immediately. Every trigger
  /// (coming online, resuming, a force-drain) wants "make sure a drain is
  /// happening", not "make sure another one happens after this one".
  bool _draining = false;

  @override
  SyncState build() => const SyncState();

  /// Drains everything that is due, if anything is and we are online.
  ///
  /// NEVER THROWS. It is called from a lifecycle callback and from a stream
  /// listener, neither of which has anywhere to put an error, and an
  /// exception escaping here would take down the zone rather than one row.
  Future<SyncSummary> drain({bool force = false}) async {
    if (_draining) return const SyncSummary();

    // EVERY ref READ BEFORE THE FIRST await — the ProgressionController rule
    // (P11), for the same reason: this notifier is reached through
    // `ref.read(...notifier)` and is not watched, so a read placed after an
    // await races its own disposal.
    final connectivity = ref.read(connectivityServiceProvider);
    final api = ref.read(syncApiProvider);
    final outboxFuture = ref.read(outboxRepositoryProvider.future);
    final progressFuture = ref.read(progressRepositoryProvider.future);
    final dailyFuture = ref.read(dailyRepositoryProvider.future);

    _draining = true;
    state = state.copyWith(isDraining: true);
    var summary = const SyncSummary();

    try {
      if (!force && !await connectivity.isOnline()) return summary;

      final outbox = await outboxFuture;
      final progress = await progressFuture;
      final daily = await dailyFuture;

      final due = await outbox.due();
      if (due.isEmpty) return summary;

      for (final batch in _byKindInQueueOrder(due)) {
        summary =
            summary + await _drainKind(batch, outbox, api, progress, daily);
      }

      if (summary.succeeded > 0) {
        final now = DateTime.now().millisecondsSinceEpoch;
        await outbox.writeKv(KvKeys.lastSyncAt, '$now');
        state = state.copyWith(lastSyncAt: now);
      }
    } on Object catch (error, stackTrace) {
      // A drain that died halfway leaves every unsent row exactly where it
      // was — pending, with its attempt count untouched — so the next trigger
      // simply tries again. Reported, never shown.
      ref.read(errorReporterProvider).nonFatal(error, stackTrace: stackTrace);
    } finally {
      _draining = false;
      state = state.copyWith(isDraining: false, lastSummary: summary);
    }

    return summary;
  }

  /// Rows grouped by kind, the groups ordered by their OLDEST row.
  ///
  /// Ordering the groups this way is what stops a kind starving: a player who
  /// queues fifty levels and one daily gets the daily sent in its queued
  /// position rather than after every level, because the group order follows
  /// the same FIFO the rows themselves do.
  static List<List<OutboxRow>> _byKindInQueueOrder(List<OutboxRow> due) {
    final groups = <String, List<OutboxRow>>{};
    for (final row in due) {
      (groups[row.kind] ??= <OutboxRow>[]).add(row);
    }
    // `due` is already oldest-first and Dart maps preserve insertion order, so
    // the groups come out ordered by their first-seen (oldest) row for free.
    return groups.values.toList(growable: false);
  }

  Future<SyncSummary> _drainKind(
    List<OutboxRow> rows,
    OutboxRepository outbox,
    SyncApi api,
    ProgressRepository progress,
    DailyRepository daily,
  ) async {
    var summary = const SyncSummary();

    /// Keyed by conflict key, so rule 3 is a map lookup rather than a scan.
    final inFlight = <String, Future<void>>{};

    /// Runs one row and REMOVES ITSELF BEFORE COMPLETING.
    ///
    /// The removal has to happen inside the body, not in a `whenComplete`
    /// attached outside: the loop below waits on `Future.any`, which fires the
    /// moment a future completes, and a removal registered as a separate
    /// callback would not have run yet — leaving the loop to see a full map
    /// and spin.
    Future<void> run(OutboxRow row, String key) async {
      try {
        final result = await _send(row, outbox, api, progress, daily);
        // Read-then-write in ONE synchronous step. `summary = summary + await
        // ...` looks equivalent and is not: Dart evaluates the left operand
        // BEFORE awaiting the right, so with two rows in flight both would
        // capture the same `summary` and the second write would discard the
        // first row's result. Dart is single-threaded, so there being no
        // `await` between this read and this write is what makes it safe.
        summary = summary + result;
      } on Object catch (error, stackTrace) {
        // Contained per row rather than per drain. An unhandled error inside
        // one of these futures would surface through `Future.any` and abandon
        // every sibling still in flight as an unawaited error.
        ref.read(errorReporterProvider).nonFatal(error, stackTrace: stackTrace);
      } finally {
        inFlight.remove(key);
      }
    }

    for (final row in rows) {
      final key = _conflictKeyOf(row, outbox);

      // Rule 3: at most one row per conflict key in flight.
      final blocking = inFlight[key];
      if (blocking != null) await blocking;

      // Rule: at most `syncConcurrency` in flight.
      while (inFlight.length >= syncConcurrency) {
        await Future.any(inFlight.values.toList(growable: false));
      }

      inFlight[key] = run(row, key);
    }

    await Future.wait(inFlight.values.toList(growable: false));
    return summary;
  }

  /// Sends one row and records what happened.
  Future<SyncSummary> _send(
    OutboxRow row,
    OutboxRepository outbox,
    SyncApi api,
    ProgressRepository progress,
    DailyRepository daily,
  ) async {
    final kind = outboxKindOf(row);
    final payload = outbox.payloadOf(row);

    if (kind == null || payload == null) {
      // Written by a newer build this one cannot parse. Permanently failed is
      // the honest answer: THIS build genuinely cannot send it. The row stays
      // on disk, so a re-upgrade can pick it up by clearing the status.
      await outbox.markFailedPermanent(
        row,
        reason: kind == null
            ? 'unknown kind ${row.kind}'
            : 'unreadable payload',
      );
      return const SyncSummary(permanentFailures: 1);
    }

    final outcome = await api.submit(kind: kind, payload: payload);

    switch (outcome) {
      case SyncAccepted(:final ack):
        final reconciled = ack == null
            ? false
            : await _reconcile(kind, payload, ack, progress, daily);
        await outbox.markSucceeded(row.id);
        return SyncSummary(succeeded: 1, reconciled: reconciled ? 1 : 0);

      case SyncTransientFailure():
        await outbox.markTransientFailure(row);
        return const SyncSummary(transientFailures: 1);

      case SyncPermanentFailure(:final reason):
        await outbox.markFailedPermanent(row, reason: reason);
        return const SyncSummary(permanentFailures: 1);

      case SyncDeferred():
        // Held: no attempt counted, no backoff scheduled, nothing reported.
        // See `SyncDeferred`'s own doc for why this is not a failure.
        return const SyncSummary(deferred: 1);
    }
  }

  /// Writes the server's number back over the local one (conflict rule 1).
  ///
  /// Returns whether anything actually moved, which should be `false` on every
  /// honest submission — the client and the server run the same scoring rules
  /// over the same events. A `true` here is worth noticing.
  Future<bool> _reconcile(
    OutboxKind kind,
    Map<String, Object?> payload,
    ServerScoreAck ack,
    ProgressRepository progress,
    DailyRepository daily,
  ) async {
    final languageCode = payload['language'];
    if (languageCode is! String) return false;
    final language = Language.values
        .where((it) => it.code == languageCode)
        .firstOrNull;
    if (language == null) return false;

    switch (kind) {
      case OutboxKind.levelComplete:
        final level = payload['level'];
        if (level is! int) return false;
        return progress.reconcileFromServer(
          language: language,
          level: level,
          stars: ack.bestStars,
          bestScore: ack.bestScore,
        );

      case OutboxKind.dailyResult:
        final date = payload['date'];
        if (date is! String) return false;
        final DayKey day;
        try {
          day = DayKey.parse(date);
        } on FormatException {
          // A malformed date in a payload this build did not write. Nothing to
          // reconcile against, and refusing the whole submission over it would
          // be worse than leaving the local row alone.
          return false;
        }
        return daily.reconcileFromServer(
          day: day,
          language: language,
          score: ack.bestScore,
          stars: ack.bestStars,
        );

      case OutboxKind.coinsDelta:
      case OutboxKind.achievementUnlocked:
      case OutboxKind.profileUpdate:
        return false;
    }
  }

  /// What must not be in flight twice at once.
  ///
  /// A level and a daily are identified by the puzzle they describe; anything
  /// else falls back to the row id, which is unique, so unrelated rows never
  /// serialise against each other by accident.
  static String _conflictKeyOf(OutboxRow row, OutboxRepository outbox) {
    final payload = outbox.payloadOf(row);
    if (payload == null) return 'row:${row.id}';
    return switch (OutboxKind.tryParse(row.kind)) {
      OutboxKind.levelComplete =>
        'level:${payload['language']}:${payload['level']}',
      OutboxKind.dailyResult =>
        'daily:${payload['language']}:${payload['date']}',
      _ => 'row:${row.id}',
    };
  }
}

/// Installs the two triggers that start a drain, and nothing else.
///
/// A SEPARATE PROVIDER FROM THE CONTROLLER, watched once at the app root —
/// the same shape `audioMuteSyncProvider` uses (P09), and for the same two
/// reasons. A notifier's `build` is supposed to be free of side effects, and
/// more practically: every bare-`ProviderContainer` test that touches
/// `SyncController` would otherwise install an `AppLifecycleListener` and
/// subscribe to connectivity, which needs a `WidgetsBinding` those tests do
/// not have.
@riverpod
void syncTriggers(Ref ref) {
  // 1. Coming back online. `ref.listen` rather than `watch`, because a drain
  //    is an action to take on a transition, not a value to recompute.
  ref.listen<AsyncValue<bool>>(isOnlineProvider, (previous, next) {
    final wasOnline = previous?.value ?? false;
    if (next.value == true && !wasOnline) {
      unawaited(ref.read(syncControllerProvider.notifier).drain());
    }
  });

  // 2. Returning to the foreground. Connectivity can change while the app is
  //    backgrounded without the stream ever being listened to, so resuming is
  //    the other moment worth a scan — and it is the one that covers "the
  //    player was offline for three days, then opened the app on wifi".
  final lifecycle = AppLifecycleListener(
    onResume: () =>
        unawaited(ref.read(syncControllerProvider.notifier).drain()),
  );
  ref.onDispose(lifecycle.dispose);
}

/// When the last successful drain finished, or null if there has never been
/// one. Feeds the leaderboard's "last updated" label.
@riverpod
Future<int?> lastSyncAtMillis(Ref ref) async {
  // Watched so it refreshes when a drain lands.
  final state = ref.watch(syncControllerProvider);
  if (state.lastSyncAt != null) return state.lastSyncAt;

  final outbox = await ref.watch(outboxRepositoryProvider.future);
  final stored = await outbox.readKv(KvKeys.lastSyncAt);
  return stored == null ? null : int.tryParse(stored);
}
