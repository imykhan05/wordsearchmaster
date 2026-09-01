import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/data/local/outbox_kind.dart';
import 'package:word_search_master/data/remote/sync_api.dart';

/// Ch10's "4xx means permanent" rule, and the two codes it must NOT apply to.
///
/// Pure — no Firebase, no network. The mapping is a function precisely so it
/// can be checked this way rather than by reasoning about it at a call site.
void main() {
  group('codes that mean the payload will never be accepted', () {
    for (final code in const [
      'invalid-argument',
      'failed-precondition',
      'out-of-range',
      'permission-denied',
      'not-found',
      'already-exists',
      'unimplemented',
    ]) {
      test('$code is permanent', () {
        expect(
          FunctionsSyncApi.outcomeForCode(code),
          isA<SyncPermanentFailure>(),
        );
      });
    }
  });

  group('the two 4xx codes that mean LATER, not never', () {
    test('resource-exhausted is transient, because it says "retry later"', () {
      // P14's rate limit. Treating it as permanent would discard real levels
      // from exactly the player whose backlog is largest — the offline player
      // this whole subsystem exists for.
      expect(
        FunctionsSyncApi.outcomeForCode('resource-exhausted'),
        isA<SyncTransientFailure>(),
      );
    });

    test('unauthenticated is transient, because the next token works', () {
      // An expired ID token or an App Check token that has not minted yet.
      // Marking it permanent would strand every row queued during a refresh.
      expect(
        FunctionsSyncApi.outcomeForCode('unauthenticated'),
        isA<SyncTransientFailure>(),
      );
    });
  });

  group('5xx, timeouts and cancellations', () {
    for (final code in const [
      'unavailable',
      'deadline-exceeded',
      'internal',
      'aborted',
      'cancelled',
      'data-loss',
      'unknown',
    ]) {
      test('$code is transient', () {
        expect(
          FunctionsSyncApi.outcomeForCode(code),
          isA<SyncTransientFailure>(),
        );
      });
    }
  });

  test('an unrecognised code retries rather than gives up', () {
    // The cheap mistake: retrying something unretryable costs a request and a
    // backoff step; giving up on something retryable costs a player their
    // progress.
    expect(
      FunctionsSyncApi.outcomeForCode('some-code-from-a-future-sdk'),
      isA<SyncTransientFailure>(),
    );
  });

  test('the failure reason carries the code, for the Crashlytics grouping', () {
    final outcome = FunctionsSyncApi.outcomeForCode(
      'invalid-argument',
      'level 9999',
    );
    expect(
      (outcome as SyncPermanentFailure).reason,
      contains('invalid-argument'),
    );
    expect(outcome.reason, contains('level 9999'));
  });

  group('which kinds this build can deliver', () {
    test('levels, dailies and category-claim achievements have callables', () {
      expect(
        FunctionsSyncApi.callableFor(OutboxKind.levelComplete),
        'submitScore',
      );
      expect(
        FunctionsSyncApi.callableFor(OutboxKind.dailyResult),
        'submitDaily',
      );
      // P17: the one achievement the server cannot derive on its own.
      expect(
        FunctionsSyncApi.callableFor(OutboxKind.achievementUnlocked),
        'submitAchievement',
      );
    });

    test('the rest have none yet, and are deferred rather than failed', () {
      // Marking them permanently failed would throw away a record the player
      // earned; marking them transient would burn the ladder up to six hours
      // on a call that was never going to be made.
      for (final kind in const [
        OutboxKind.coinsDelta,
        OutboxKind.profileUpdate,
      ]) {
        expect(FunctionsSyncApi.callableFor(kind), isNull);
      }
    });
  });

  group('reading the server response', () {
    test('parses P14s SubmitResponse', () {
      final ack = FunctionsSyncApi.parseAck({
        'score': 156,
        'stars': 3,
        'bestScore': 200,
        'bestStars': 3,
        'specVersion': 1,
        'alreadyRecorded': false,
      });
      expect(ack!.score, 156);
      expect(ack.bestScore, 200);
      expect(ack.alreadyRecorded, isFalse);
    });

    test('returns null rather than a zeroed ack when fields are missing', () {
      // Reconciling a player's level DOWN TO ZERO because a response shape
      // changed would be far worse than not reconciling at all.
      expect(FunctionsSyncApi.parseAck({'score': 156}), isNull);
      expect(FunctionsSyncApi.parseAck({'score': 'lots'}), isNull);
      expect(FunctionsSyncApi.parseAck(null), isNull);
      expect(FunctionsSyncApi.parseAck('not a map'), isNull);
    });

    test('reads an idempotent replay flag', () {
      final ack = FunctionsSyncApi.parseAck({
        'score': 10,
        'stars': 1,
        'bestScore': 10,
        'bestStars': 1,
        'alreadyRecorded': true,
      });
      expect(ack!.alreadyRecorded, isTrue);
    });
  });

  test('the Noop binding HOLDS the queue rather than emptying it', () async {
    // An unconfigured checkout and airplane mode are the same code path (P13).
    // A Noop that answered "accepted" would silently delete every queued level
    // on a developer's machine.
    final outcome = await const NoopSyncApi().submit(
      kind: OutboxKind.levelComplete,
      payload: const {},
    );
    expect(outcome, isA<SyncTransientFailure>());
  });
}
