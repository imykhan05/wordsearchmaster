import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'error_reporter.g.dart';

/// Where a swallowed failure goes.
///
/// Behind an interface for the same reason `AdGateway` is (CLAUDE.md →
/// Architecture): nothing outside `services/` may import a vendor SDK, and
/// tests need a reporter they can assert on. [NoopErrorReporter] is the
/// binding used until P19 wires the Crashlytics one.
///
/// THE RULE THIS EXISTS TO ENFORCE: a background failure — a sync that did
/// not go out, a row that failed its integrity check, a Firebase call that
/// threw — is reported here and NEVER surfaced to the player. Ch10 is
/// explicit that a tampered or corrupt row resets to a default silently; a
/// dialog telling a 45-year-old on a 2GB phone that their "integrity tag
/// mismatched" is worse than the bug.
abstract interface class ErrorReporter {
  /// Records a non-fatal. Must never throw, and must never block: callers
  /// invoke this from read paths.
  void nonFatal(
    Object error, {
    StackTrace? stackTrace,
    Map<String, Object?> context,
  });
}

/// Drops everything on the floor.
///
/// The binding on every flavor until P19, because Crashlytics itself is still
/// a stub in `bootstrap.dart` — a reporter that pretends to file reports
/// would be worse than one that visibly does nothing.
final class NoopErrorReporter implements ErrorReporter {
  const NoopErrorReporter();

  @override
  void nonFatal(
    Object error, {
    StackTrace? stackTrace,
    Map<String, Object?> context = const {},
  }) {}
}

/// The app-wide reporter.
///
/// TODO(P19): override this with the Crashlytics-backed implementation in
/// `bootstrap.dart`, once step 1 of the init sequence is real.
@Riverpod(keepAlive: true)
ErrorReporter errorReporter(Ref ref) => const NoopErrorReporter();

/// Raised when a persisted row's HMAC tag does not match its contents.
///
/// Carries no row VALUES, only its address: this object reaches Crashlytics,
/// and a player's display name or score has no business in a crash report.
final class IntegrityViolation implements Exception {
  const IntegrityViolation({required this.table, required this.rowKey});

  final String table;
  final String rowKey;

  @override
  String toString() => 'IntegrityViolation($table, rowKey: $rowKey)';
}
