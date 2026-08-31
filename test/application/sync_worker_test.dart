import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/application/sync_controller.dart';
import 'package:word_search_master/data/local/app_database.dart';
import 'package:word_search_master/data/local/outbox_kind.dart';
import 'package:word_search_master/data/local/tables.dart';
import 'package:word_search_master/data/remote/sync_api.dart';
import 'package:word_search_master/data/repositories/daily_repository.dart';
import 'package:word_search_master/data/repositories/outbox_repository.dart';
import 'package:word_search_master/data/repositories/progress_repository.dart';
import 'package:word_search_master/domain/progression/day_key.dart';
import 'package:word_search_master/domain/scoring/score_event.dart';
import 'package:word_search_master/domain/sync/backoff.dart';
import 'package:word_search_master/domain/sync/conflict_resolver.dart';
import 'package:word_search_master/domain/sync/outbox_status.dart';
import 'package:word_search_master/domain/text/language.dart';
import 'package:word_search_master/services/connectivity/connectivity_service.dart';
import 'package:word_search_master/services/diagnostics/error_reporter.dart';

import '../support/local_db.dart';

/// P16's FIRST acceptance criterion, driven end to end:
///
///   "3 din offline khel kar internet on karne par sab kuch sync hota hai."
///
/// Three days of real play against a real Drift database with the network
/// refusing every call, then the network comes back and the queue empties.
/// Nothing is mocked below the `SyncApi` seam — the outbox rows, their
/// integrity tags, their attempt counts and their backoff schedule are all the
/// production code paths.

/// A scriptable network. Records every submission so the test can assert on
/// order as well as on outcome.
final class FakeSyncApi implements SyncApi {
  FakeSyncApi({this.outcome});

  /// Answers every call. Defaults to accepting with no reconciliation.
  SyncOutcome Function(OutboxKind kind, Map<String, Object?> payload)? outcome;

  final List<(OutboxKind, Map<String, Object?>)> calls = [];

  /// Rows in flight at this instant, and the high-water mark of that count.
  int _inFlight = 0;
  int peakConcurrency = 0;

  /// When set, each call parks on this until the test releases it — which is
  /// how the concurrency assertions observe overlap at all.
  Completer<void>? gate;

  /// When set, groups calls by conflict key so same-key overlap is observable
  /// directly rather than inferred from the order of the call log.
  String Function(Map<String, Object?> payload)? keyOf;

  final Set<String> _liveKeys = {};

  /// True if two calls sharing a conflict key were ever in flight together.
  bool sawSameKeyOverlap = false;

  @override
  Future<SyncOutcome> submit({
    required OutboxKind kind,
    required Map<String, Object?> payload,
  }) async {
    calls.add((kind, payload));
    _inFlight++;
    peakConcurrency = peakConcurrency > _inFlight ? peakConcurrency : _inFlight;
    final key = keyOf?.call(payload);
    if (key != null && !_liveKeys.add(key)) sawSameKeyOverlap = true;
    try {
      if (gate != null) await gate!.future;
      // Always yield, so two calls started in the same turn genuinely overlap
      // rather than running to completion one after the other.
      await Future<void>.delayed(Duration.zero);
      return outcome?.call(kind, payload) ?? const SyncAccepted();
    } finally {
      _inFlight--;
      if (key != null) _liveKeys.remove(key);
    }
  }
}

final class FakeConnectivityService implements ConnectivityService {
  FakeConnectivityService({this.online = true});

  bool online;
  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  void setOnline(bool value) {
    online = value;
    _controller.add(value);
  }

  @override
  Future<bool> isOnline() async => online;

  @override
  Stream<bool> get changes => _controller.stream;

  void dispose() => _controller.close();
}

void main() {
  late TestDatabase db;
  late FakeSyncApi api;
  late FakeConnectivityService connectivity;
  late ProviderContainer container;

  setUp(() async {
    db = await openMemoryDatabase();
    addTearDown(db.database.close);
    api = FakeSyncApi();
    connectivity = FakeConnectivityService();
    addTearDown(connectivity.dispose);

    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db.database),
        syncApiProvider.overrideWithValue(api),
        connectivityServiceProvider.overrideWithValue(connectivity),
        errorReporterProvider.overrideWithValue(db.reporter),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<ProgressRepository> progress() =>
      container.read(progressRepositoryProvider.future);
  Future<DailyRepository> daily() =>
      container.read(dailyRepositoryProvider.future);
  Future<OutboxRepository> outbox() =>
      container.read(outboxRepositoryProvider.future);

  Future<SyncSummary> drain({bool force = false}) =>
      container.read(syncControllerProvider.notifier).drain(force: force);

  Future<List<OutboxRow>> allRows() =>
      db.database.select(db.database.outbox).get();

  /// One finished level, written through the real repository path.
  Future<void> playLevel(
    int level, {
    Language language = Language.english,
  }) async {
    final repo = await progress();
    await repo.recordLevelComplete(
      language: language,
      level: level,
      stars: 3,
      score: 156,
      hintsUsed: 0,
      events: const [
        WordFound(graphemeCount: 3),
        WordFound(graphemeCount: 3),
        WordFound(graphemeCount: 3),
        WordFound(graphemeCount: 3),
      ],
    );
  }

  // =========================================================================
  // THE ACCEPTANCE CRITERION
  // =========================================================================

  group('three days offline, then the radio comes back', () {
    test('every queued submission drains and the queue empties', () async {
      connectivity.setOnline(false);

      // Day 1: five levels. Day 2: five more, plus a daily. Day 3: five more.
      // Between each day the app tries to sync and cannot, which is what
      // builds the attempt counts and the backoff the reconnect has to clear.
      var level = 1;
      for (var day = 0; day < 3; day++) {
        for (var i = 0; i < 5; i++) {
          await playLevel(level++);
        }
        if (day == 1) {
          final dailyRepo = await daily();
          await dailyRepo.recordDailyComplete(
            day: DayKey.parse('2026-09-02'),
            language: Language.english,
            score: 320,
            stars: 3,
            events: const [WordFound(graphemeCount: 4)],
          );
        }
        // The drain that goes nowhere. It must not consume, drop, or corrupt
        // anything — an offline drain is a no-op, not a failed delivery.
        final offline = await drain();
        expect(offline.attempted, 0);
      }

      expect(await allRows(), hasLength(16));
      expect(api.calls, isEmpty, reason: 'nothing may be sent while offline');

      // The radio comes back.
      connectivity.setOnline(true);
      final summary = await drain();

      expect(summary.succeeded, 16);
      expect(summary.transientFailures, 0);
      expect(summary.permanentFailures, 0);
      expect(
        await allRows(),
        isEmpty,
        reason: 'a delivered row leaves the queue',
      );
      expect(api.calls, hasLength(16));
    });

    test(
      'an offline drain never touches attempt counts or the backoff',
      () async {
        // Three days of failed sync attempts must not walk a row up the ladder
        // when the reason is simply that there was no network to try on.
        connectivity.setOnline(false);
        await playLevel(1);

        for (var i = 0; i < 20; i++) {
          await drain();
        }

        final row = (await allRows()).single;
        expect(row.attempts, 0);
        expect(row.nextRetryAt, isNull);
        expect(outboxStatusOf(row), OutboxStatus.pending);
      },
    );

    test('rows are sent oldest first', () async {
      // Load-bearing for `ConflictResolver` rule 1: the server's best-of is
      // only right once every earlier submission for that level has landed.
      for (var level = 1; level <= 6; level++) {
        await playLevel(level);
      }
      await drain();

      expect(api.calls.map((call) => call.$2['level']).toList(), [
        1,
        2,
        3,
        4,
        5,
        6,
      ]);
    });

    test(
      'a level played while the queue drains is picked up next time',
      () async {
        await playLevel(1);
        await drain();
        expect(await allRows(), isEmpty);

        await playLevel(2);
        final second = await drain();
        expect(second.succeeded, 1);
        expect(await allRows(), isEmpty);
      },
    );
  });

  // =========================================================================
  // Failure handling
  // =========================================================================

  group('a 4xx the server will refuse again', () {
    test('marks the row permanently failed and files a non-fatal', () async {
      api.outcome = (_, _) => const SyncPermanentFailure('invalid-argument');
      await playLevel(1);

      final summary = await drain();

      expect(summary.permanentFailures, 1);
      final row = (await allRows()).single;
      expect(outboxStatusOf(row), OutboxStatus.failedPermanent);
      expect(row.nextRetryAt, isNull, reason: 'nothing is scheduled');
      expect(
        db.reporter.errors.whereType<OutboxPermanentFailure>(),
        hasLength(1),
      );
    });

    test('never retries it, and never blocks the rows behind it', () async {
      var call = 0;
      api.outcome = (_, _) => call++ == 0
          ? const SyncPermanentFailure('bad')
          : const SyncAccepted();
      await playLevel(1);
      await playLevel(2);

      await drain();
      expect(await allRows(), hasLength(1), reason: 'the good row went');

      api.calls.clear();
      await drain();
      expect(
        api.calls,
        isEmpty,
        reason: 'a permanently failed row is never sent again',
      );
    });

    test(
      'a payload this build cannot read is refused rather than retried',
      () async {
        await playLevel(1);
        // Corrupt the payload the way a newer build's row would look, keeping
        // the tag valid so it is a PARSE failure, not an integrity one.
        final row = (await allRows()).single;
        await db.database.customStatement(
          'UPDATE ${LocalTables.outbox} SET payload = ?, integrity_tag = ? '
          'WHERE id = ?',
          ['not json at all', _retag(db, row, 'not json at all'), row.id],
        );

        final summary = await drain();
        expect(summary.permanentFailures, 1);
        expect(api.calls, isEmpty, reason: 'it was never sendable');
      },
    );
  });

  group('a 5xx, a timeout, or a dropped socket', () {
    test(
      'counts an attempt and schedules the next one on the ladder',
      () async {
        api.outcome = (_, _) => const SyncTransientFailure('unavailable');
        await playLevel(1);

        final before = DateTime.now().millisecondsSinceEpoch;
        await drain();
        final row = (await allRows()).single;

        expect(row.attempts, 1);
        expect(outboxStatusOf(row), OutboxStatus.pending);
        // Step 1 is 5s +/-20%.
        expect(row.nextRetryAt! - before, inInclusiveRange(3900, 6100));
      },
    );

    test('walks up the ladder, one rung per failure', () async {
      api.outcome = (_, _) => const SyncTransientFailure('unavailable');
      await playLevel(1);
      final repo = await outbox();

      for (var failures = 1; failures <= 5; failures++) {
        final row = (await allRows()).single;
        // Reach past the backoff each time, so the ladder is what is measured
        // rather than the wait.
        await repo.clearBackoff();
        final now = DateTime.now().millisecondsSinceEpoch;
        await repo.markTransientFailure(row, nowMillis: now);

        final after = (await allRows()).single;
        // `markTransientFailure` schedules the step for the count AFTER the
        // increment: one failure means rung 1 (5s), not rung 2.
        final (low, high) = BackoffSchedule.bandFor(after.attempts);
        expect(after.attempts, failures);
        expect(
          after.nextRetryAt! - now,
          inInclusiveRange(low.inMilliseconds - 1, high.inMilliseconds + 1),
        );
      }
    });

    test('a row still inside its backoff is not sent', () async {
      api.outcome = (_, _) => const SyncTransientFailure('unavailable');
      await playLevel(1);
      await drain();

      api.calls.clear();
      api.outcome = (_, _) => const SyncAccepted();
      await drain();
      expect(api.calls, isEmpty, reason: 'the 5s step has not elapsed');

      // The Inspector's force-drain clears it.
      final repo = await outbox();
      await repo.clearBackoff();
      await drain();
      expect(api.calls, hasLength(1));
      expect(await allRows(), isEmpty);
    });

    test('never gives up, however many times it fails', () async {
      api.outcome = (_, _) => const SyncTransientFailure('unavailable');
      await playLevel(1);
      final repo = await outbox();

      for (var i = 0; i < 30; i++) {
        await repo.clearBackoff();
        await drain();
      }

      final row = (await allRows()).single;
      expect(outboxStatusOf(row), OutboxStatus.pending);
      expect(row.attempts, 30);
    });
  });

  group('a kind this build has no endpoint for', () {
    test(
      'is held without consuming an attempt or reporting anything',
      () async {
        api.outcome = (_, _) => const SyncDeferred('no endpoint');
        await playLevel(1);

        final summary = await drain();

        expect(summary.deferred, 1);
        final row = (await allRows()).single;
        expect(row.attempts, 0);
        expect(row.nextRetryAt, isNull);
        expect(outboxStatusOf(row), OutboxStatus.pending);
        expect(db.reporter.errors, isEmpty);
      },
    );
  });

  // =========================================================================
  // Ordering and concurrency
  // =========================================================================

  group('ordering rules', () {
    test('sends at most two submissions at once', () async {
      for (var level = 1; level <= 8; level++) {
        await playLevel(level);
      }
      final gate = Completer<void>();
      api.gate = gate;

      final draining = drain();
      // Let the worker start as many as it is willing to.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      await draining;

      expect(api.peakConcurrency, lessThanOrEqualTo(syncConcurrency));
      expect(
        api.peakConcurrency,
        syncConcurrency,
        reason: 'and it does use both',
      );
    });

    test('one kind at a time', () async {
      await playLevel(1);
      final dailyRepo = await daily();
      await dailyRepo.recordDailyComplete(
        day: DayKey.parse('2026-09-02'),
        language: Language.english,
        score: 320,
        stars: 3,
        events: const [WordFound(graphemeCount: 4)],
      );
      await playLevel(2);

      await drain();

      // All levels, then all dailies — never interleaved.
      final kinds = api.calls.map((call) => call.$1).toList();
      expect(kinds, [
        OutboxKind.levelComplete,
        OutboxKind.levelComplete,
        OutboxKind.dailyResult,
      ]);
    });

    test('never two submissions of the SAME level in flight at once', () async {
      // Rule 3 of the drain: with a concurrency of 2, two rows for one level
      // could otherwise each return a best-of computed before the other
      // landed, and the reply that arrived last would win with a stale number.
      await playLevel(4);
      await playLevel(4); // a replay of the same level
      await playLevel(5);

      api.keyOf = (payload) => 'level:${payload['level']}';

      await drain();

      expect(api.sawSameKeyOverlap, isFalse);
      expect(
        api.calls.where((call) => call.$2['level'] == 4),
        hasLength(2),
        reason: 'both attempts were still sent, just never at the same time',
      );
    });

    test('unrelated rows are NOT serialised against each other', () async {
      // The contrast that makes the test above mean something: if every row
      // serialised, "no same-key overlap" would hold trivially and the
      // concurrency limit would be 1 in practice.
      for (var level = 1; level <= 6; level++) {
        await playLevel(level);
      }
      api.keyOf = (payload) => 'level:${payload['level']}';

      await drain();

      expect(api.peakConcurrency, syncConcurrency);
      expect(api.sawSameKeyOverlap, isFalse);
    });
  });

  // =========================================================================
  // Reconciliation
  // =========================================================================

  group('the server is authoritative', () {
    test('a matching score changes nothing', () async {
      api.outcome = (_, _) => const SyncAccepted(
        ack: ServerScoreAck(score: 156, stars: 3, bestScore: 156, bestStars: 3),
      );
      await playLevel(1);

      final summary = await drain();
      expect(summary.reconciled, 0);

      final repo = await progress();
      final row = await repo.watchLevel(Language.english, 1).first;
      expect(row!.bestScore, 156);
    });

    test('a LOWER server score is written over the local one', () async {
      // The rule that resolves against the player, and the reason it exists.
      api.outcome = (_, _) => const SyncAccepted(
        ack: ServerScoreAck(score: 40, stars: 1, bestScore: 40, bestStars: 1),
      );
      await playLevel(1);

      final summary = await drain();
      expect(summary.reconciled, 1);

      final repo = await progress();
      final row = await repo.watchLevel(Language.english, 1).first;
      expect(row!.bestScore, 40);
      expect(row.stars, 1);
    });

    test('a reconcile does not queue another submission', () async {
      // A reconcile that enqueued its own row would sync in a loop forever.
      api.outcome = (_, _) => const SyncAccepted(
        ack: ServerScoreAck(score: 40, stars: 1, bestScore: 40, bestStars: 1),
      );
      await playLevel(1);
      await drain();

      expect(await allRows(), isEmpty);
    });

    test('the reconciled row still verifies its integrity tag', () async {
      api.outcome = (_, _) => const SyncAccepted(
        ack: ServerScoreAck(score: 40, stars: 1, bestScore: 40, bestStars: 1),
      );
      await playLevel(1);
      await drain();

      final repo = await progress();
      // A row written with a stale tag would read back as missing.
      expect(await repo.completedLevels(Language.english), {1});
      expect(db.reporter.integrityViolations, isEmpty);
    });

    test('a daily reconciles to the attempt the server kept', () async {
      api.outcome = (_, _) => const SyncAccepted(
        ack: ServerScoreAck(score: 99, stars: 2, bestScore: 99, bestStars: 2),
      );
      final dailyRepo = await daily();
      final day = DayKey.parse('2026-09-02');
      await dailyRepo.recordDailyComplete(
        day: day,
        language: Language.english,
        score: 320,
        stars: 3,
        events: const [WordFound(graphemeCount: 4)],
      );

      await drain();

      final row = await dailyRepo.result(day, Language.english);
      expect(row!.score, 99);
      expect(row.stars, 2);
    });
  });

  // =========================================================================
  // Integrity
  // =========================================================================

  test('a tampered payload is never sent', () async {
    await playLevel(1);
    final row = (await allRows()).single;
    await db.database.customStatement(
      'UPDATE ${LocalTables.outbox} SET payload = ? WHERE id = ?',
      ['{"language":"en","level":300,"events":[]}', row.id],
    );

    final summary = await drain();

    expect(api.calls, isEmpty);
    expect(summary.attempted, 0);
    // Excluded, reported, and left on disk as evidence.
    expect(db.reporter.integrityViolations, isNotEmpty);
    expect(await allRows(), hasLength(1));
  });

  test('two drains cannot overlap', () async {
    for (var level = 1; level <= 4; level++) {
      await playLevel(level);
    }
    final gate = Completer<void>();
    api.gate = gate;

    final first = drain();
    await Future<void>.delayed(Duration.zero);
    final second = await drain();
    expect(
      second.attempted,
      0,
      reason: 'the second caller returns immediately',
    );

    gate.complete();
    final summary = await first;
    expect(summary.succeeded, 4);
  });
}

/// Recomputes the outbox tag for a rewritten payload, so a test can simulate a
/// row this build cannot PARSE without also simulating tampering.
String _retag(TestDatabase db, OutboxRow row, String payload) =>
    db.integrity.tagFor(
      table: LocalTables.outbox,
      rowKey: '${row.id}',
      fields: [row.kind, payload, row.createdAt],
    );
