import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'analytics_service.g.dart';

/// The event taxonomy's transport, not its schema (Ch11).
///
/// Behind an interface for the same reason `ErrorReporter`/`AdGateway` are
/// (CLAUDE.md → Architecture): nothing outside `services/` may import a
/// vendor SDK, and a screen that fires an event needs something it can assert
/// on in a widget test without a platform channel. [NoopAnalyticsService] is
/// the binding on every flavor until a real one lands — Firebase Analytics
/// itself is still a `bootstrap.dart` stub (step 2, `TODO(P13)`), so a
/// reporter that pretended to send events would be worse than one that
/// visibly does nothing, the same call `error_reporter.dart` already makes.
///
/// ONE METHOD, deliberately untyped past `name`/`params`: P12 needs exactly
/// one event (`dda_applied`, via the [DdaAnalytics] extension below), and
/// inventing a typed `AnalyticsEvent` hierarchy for a taxonomy of one entry
/// is exactly the premature abstraction CLAUDE.md's "Never do" section warns
/// against. A future prompt that needs a second event widens this — or adds
/// its own extension alongside [DdaAnalytics] — rather than this file
/// guessing today at a shape nothing calls yet.
abstract interface class AnalyticsService {
  void logEvent(String name, [Map<String, Object?> params]);
}

/// Drops every call on the floor.
final class NoopAnalyticsService implements AnalyticsService {
  const NoopAnalyticsService();

  @override
  void logEvent(String name, [Map<String, Object?> params = const {}]) {}
}

/// The app-wide reporter.
///
/// TODO(P19/P20): override this with the Firebase Analytics-backed
/// implementation once `bootstrap.dart`'s Firebase step is real.
@Riverpod(keepAlive: true)
AnalyticsService analyticsService(Ref ref) => const NoopAnalyticsService();

/// P12's one event: "every DDA intervention fires `dda_applied`" (Ch02).
///
/// [type] names WHICH intervention fired — `pulse`, `hint_offer` or
/// `downshift` — so a live dashboard can tell them apart; it is an analytics
/// key, never player-visible copy, so it carries none of the "never imply the
/// game was made easier" wording risk a UI string would.
extension DdaAnalytics on AnalyticsService {
  void ddaApplied({
    required String type,
    required String language,
    required int level,
  }) => logEvent('dda_applied', {
    'type': type,
    'language': language,
    'level': level,
  });
}
