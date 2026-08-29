import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import 'error_reporter.dart';

/// The real [ErrorReporter], over Crashlytics. The only file allowed to
/// import `firebase_crashlytics`.
///
/// Fills in the binding `error_reporter.dart` has been carrying a
/// `TODO(P19)` for since P08 — brought forward to P13 because bootstrap now
/// has real Firebase calls whose failures are exactly what this exists to
/// record, and shipping them into a Noop would mean the first two weeks of
/// crash data are silence.
///
/// THE RULE, unchanged from the interface's own header: a background failure
/// is reported here and NEVER surfaced to the player. Every method is
/// non-throwing and non-blocking — callers invoke this from read paths and
/// from inside Drift stream maps.
final class CrashlyticsErrorReporter implements ErrorReporter {
  const CrashlyticsErrorReporter(this._crashlytics);

  final FirebaseCrashlytics _crashlytics;

  @override
  void nonFatal(
    Object error, {
    StackTrace? stackTrace,
    Map<String, Object?> context = const {},
  }) {
    // `unawaited` in spirit: recordError returns a Future, and awaiting it
    // would make every integrity check on a Drift read path asynchronous.
    // Crashlytics buffers to disk and uploads on its own schedule, so
    // dropping the Future loses nothing but the ability to block on it.
    _crashlytics
        .recordError(
          error,
          stackTrace,
          reason: context.isEmpty ? null : context.toString(),
          // Non-fatal by definition — the app carried on. A `true` here would
          // put integrity violations and offline sync failures in the same
          // bucket as real crashes and make the crash-free-users metric
          // meaningless.
          fatal: false,
        )
        .catchError((Object _) {
          // A reporter that throws while reporting would turn a swallowed
          // failure into a crash — the exact inversion this class exists to
          // prevent. There is nowhere left to escalate to, so this is the one
          // place in the codebase where dropping an error entirely is right.
        });
  }
}
