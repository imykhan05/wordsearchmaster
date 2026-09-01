/// The network half of the outbox drain (Ch10 / P16).
///
/// One interface, three bindings, and a SEALED OUTCOME — because the whole
/// point of this file is that the worker must decide between "count an attempt
/// and try again later" and "stop, this will never work", and a bool or a
/// thrown exception would let a call site forget that the distinction exists.
///
/// ---------------------------------------------------------------------------
/// "4xx MEANS PERMANENT" IS THE RIGHT INSTINCT AND THE WRONG RULE
///
/// Ch10 says a 4xx is an invalid payload: mark it permanently failed and stop
/// retrying. That is correct for the case it describes and wrong for two 4xx
/// codes that this system produces on purpose:
///
///   * `resource-exhausted` (429) is P14's rate limit. It literally means
///     "retry later" — treating it as permanent would discard real levels from
///     exactly the player whose backlog is largest, which is the offline
///     player this whole subsystem exists for.
///   * `unauthenticated` (401) is an expired ID token or an App Check token
///     that has not minted yet. The next attempt carries a fresh one and
///     succeeds. Marking it permanent would strand every row queued during a
///     token refresh.
///
/// So the mapping below is by MEANING, not by status class, and the two
/// exceptions are the reason it is a documented function with its own test
/// rather than an inline `if (code.startsWith('4'))`.
///
/// The default for an unrecognised code is TRANSIENT. Retrying something
/// unretryable costs a request and a backoff step; giving up on something
/// retryable costs a player their progress. The cheap mistake is the one to
/// make.
library;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../app/config/app_config.dart';
import '../../domain/sync/conflict_resolver.dart';
import '../local/outbox_kind.dart';

part 'sync_api.g.dart';

/// What happened to one submission.
sealed class SyncOutcome {
  const SyncOutcome();
}

/// The server took it. The row leaves the queue.
final class SyncAccepted extends SyncOutcome {
  const SyncAccepted({this.ack});

  /// Present for score submissions, so the caller can reconcile
  /// (`ConflictResolver` rule 1). Null for kinds that return nothing to
  /// reconcile, such as a profile edit.
  final ServerScoreAck? ack;

  @override
  String toString() => 'SyncAccepted($ack)';
}

/// Try again later: offline, a timeout, a 5xx, a rate limit, an auth hiccup.
final class SyncTransientFailure extends SyncOutcome {
  const SyncTransientFailure(this.reason);
  final String reason;

  @override
  String toString() => 'SyncTransientFailure($reason)';
}

/// The server refused the payload and will refuse it again.
final class SyncPermanentFailure extends SyncOutcome {
  const SyncPermanentFailure(this.reason);
  final String reason;

  @override
  String toString() => 'SyncPermanentFailure($reason)';
}

/// This build has no endpoint for that kind yet.
///
/// NOT a failure, and deliberately not one: the row is held, no attempt is
/// counted, no backoff is scheduled and nothing is reported. P14 shipped
/// `submitScore` and `submitDaily`; P17 shipped `submitAchievement`. The
/// server half of the coin ledger (`OutboxKind.coinsDelta`) is still owed by
/// a later prompt. Treating those rows as permanently failed would throw away
/// a record the player earned, and treating them as transient would burn the
/// ladder up to six hours on a call that was never going to be made.
final class SyncDeferred extends SyncOutcome {
  const SyncDeferred(this.reason);
  final String reason;

  @override
  String toString() => 'SyncDeferred($reason)';
}

abstract interface class SyncApi {
  /// Sends one queued payload.
  ///
  /// Must never throw — every failure mode is a [SyncOutcome]. A worker that
  /// had to guard each call with a try/catch would eventually have one that
  /// did not, and an uncaught error in a background drain takes the whole
  /// drain down with it.
  Future<SyncOutcome> submit({
    required OutboxKind kind,
    required Map<String, Object?> payload,
  });
}

/// The binding when Firebase is unconfigured — which, per P13, is the SAME
/// code path as airplane mode rather than a second one.
///
/// Answers transient, so the queue holds everything and drains whenever a
/// configured build eventually runs. A Noop that answered "accepted" would
/// silently delete every queued level on a developer's machine.
final class NoopSyncApi implements SyncApi {
  const NoopSyncApi();

  @override
  Future<SyncOutcome> submit({
    required OutboxKind kind,
    required Map<String, Object?> payload,
  }) async => const SyncTransientFailure('no backend configured');
}

/// Calls P14's callables in `asia-south1`.
final class FunctionsSyncApi implements SyncApi {
  FunctionsSyncApi(this._functions);

  final FirebaseFunctions _functions;

  /// The callable for [kind], or null when this build has none.
  static String? callableFor(OutboxKind kind) => switch (kind) {
    OutboxKind.levelComplete => 'submitScore',
    OutboxKind.dailyResult => 'submitDaily',
    // Profile edits are the one thing the client is allowed to write directly
    // (`firestore.rules` permits exactly `displayName` and `photoUrl` on the
    // player's own document), so they need no callable — and giving them one
    // would mean a function whose only job is to copy two fields the rules
    // already let through.
    OutboxKind.profileUpdate => null,
    OutboxKind.coinsDelta => null,
    // The Collector claim (P17) — the one achievement the server cannot
    // derive on its own, so the client submits it as a claim rather than
    // having the server compute it. `submitAchievement` reads only
    // `category`/`language` off the payload; the extra fields
    // `CollectionsRepository.recordEarned` already queues (`id`, `progress`,
    // `unlockedAt`) are simply ignored, so no payload reshaping is needed
    // here — the same outbox row P11 was always going to write is now
    // deliverable as-is.
    OutboxKind.achievementUnlocked => 'submitAchievement',
  };

  @override
  Future<SyncOutcome> submit({
    required OutboxKind kind,
    required Map<String, Object?> payload,
  }) async {
    final callable = callableFor(kind);
    if (callable == null) {
      return SyncDeferred('no endpoint for ${kind.name} in this build');
    }

    try {
      final result = await _functions
          .httpsCallable(callable)
          .call<Map<Object?, Object?>>(payload);
      return SyncAccepted(ack: parseAck(result.data));
    } on FirebaseFunctionsException catch (error) {
      return outcomeForCode(error.code, error.message);
    } on Object catch (error) {
      // A socket that closed, a DNS failure, a platform-channel error. None of
      // those say anything about the payload.
      return SyncTransientFailure('$error');
    }
  }

  /// The Ch10 mapping, as a pure function so it is testable without Firebase.
  ///
  /// See the library header for why `resource-exhausted` and `unauthenticated`
  /// are transient despite being 4xx.
  static SyncOutcome outcomeForCode(String code, [String? message]) {
    final detail = message == null ? code : '$code: $message';
    return switch (code) {
      // The payload itself is wrong, or this caller may never send it.
      'invalid-argument' ||
      'failed-precondition' ||
      'out-of-range' ||
      'permission-denied' ||
      'not-found' ||
      'already-exists' ||
      'unimplemented' => SyncPermanentFailure(detail),

      // 4xx that mean "later", not "never".
      'resource-exhausted' || 'unauthenticated' => SyncTransientFailure(detail),

      // 5xx, timeouts, cancellations.
      'unavailable' ||
      'deadline-exceeded' ||
      'internal' ||
      'aborted' ||
      'cancelled' ||
      'data-loss' ||
      'unknown' => SyncTransientFailure(detail),

      // Unrecognised: retry. See the header.
      _ => SyncTransientFailure(detail),
    };
  }

  /// Reads P14's `SubmitResponse`.
  ///
  /// Every field degrades rather than throwing, and a response missing the
  /// best-of fields yields NULL rather than a zeroed ack — reconciling a
  /// player's level down to zero because a response shape changed would be a
  /// far worse bug than not reconciling at all.
  static ServerScoreAck? parseAck(Object? data) {
    if (data is! Map) return null;
    final score = data['score'];
    final stars = data['stars'];
    final bestScore = data['bestScore'];
    final bestStars = data['bestStars'];
    if (score is! num ||
        stars is! num ||
        bestScore is! num ||
        bestStars is! num) {
      return null;
    }
    return ServerScoreAck(
      score: score.toInt(),
      stars: stars.toInt(),
      bestScore: bestScore.toInt(),
      bestStars: bestStars.toInt(),
      alreadyRecorded: data['alreadyRecorded'] == true,
    );
  }
}

/// Defaults to [NoopSyncApi]; `bootstrap.dart` upgrades it once Firebase
/// initialises, the same way it upgrades `ErrorReporter`.
@Riverpod(keepAlive: true)
SyncApi syncApi(Ref ref) => const NoopSyncApi();

/// The functions region is pinned in one place on the client, matching
/// `REGION` in `functions/src/config.ts`. A mismatch fails every call with an
/// error that names neither side.
FirebaseFunctions functionsForRegion() =>
    FirebaseFunctions.instanceFor(region: AppConfig.functionsRegion);
