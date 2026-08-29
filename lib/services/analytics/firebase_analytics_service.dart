import 'package:firebase_analytics/firebase_analytics.dart';

import '../diagnostics/error_reporter.dart';
import 'analytics_service.dart';

/// The real [AnalyticsService], over Firebase Analytics. The only file
/// allowed to import `firebase_analytics`.
///
/// Fills in the binding `analytics_service.dart` has carried a
/// `TODO(P19/P20)` for since P12 — brought forward because P13 is the prompt
/// that actually creates the Firebase projects the events would go to.
///
/// Each flavor points at its own Firebase project (CLAUDE.md → Flavors), so
/// dev events land in DebugView, staging in its own property and prod in
/// production. Nothing here has to branch on flavor to make that true — it
/// falls out of which `FirebaseOptions` bootstrap initialised.
final class FirebaseAnalyticsService implements AnalyticsService {
  const FirebaseAnalyticsService({
    required FirebaseAnalytics analytics,
    required ErrorReporter reporter,
    // The lint wants `this._analytics`, which Dart rejects for a named
    // parameter — same carve-out as `AppDatabase`'s reporter.
    // ignore: prefer_initializing_formals
  }) : _analytics = analytics,
       // ignore: prefer_initializing_formals
       _reporter = reporter;

  final FirebaseAnalytics _analytics;
  final ErrorReporter _reporter;

  @override
  void logEvent(String name, [Map<String, Object?> params = const {}]) {
    // Firebase rejects null values and non-(num|String) types outright, and
    // an event that throws on a malformed param would take a gameplay code
    // path down with it. Filtering here keeps the interface's own signature
    // (`Map<String, Object?>`) honest and permissive for callers.
    final safe = <String, Object>{};
    for (final entry in params.entries) {
      switch (entry.value) {
        case final num value:
          safe[entry.key] = value;
        case final String value:
          safe[entry.key] = value;
        // Anything else (null, a bool, a nested map) is dropped rather than
        // stringified: a silently coerced value is worse than an absent one,
        // because it looks like real data in the dashboard.
      }
    }

    _analytics.logEvent(name: name, parameters: safe).catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      _reporter.nonFatal(
        error,
        stackTrace: stackTrace,
        context: {'stage': 'analytics.logEvent', 'event': name},
      );
    });
  }
}
