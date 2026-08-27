import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/services/analytics/analytics_service.dart';

void main() {
  test('NoopAnalyticsService drops every call — the default binding', () {
    const service = NoopAnalyticsService();
    // Nothing to assert beyond "does not throw" — this is the same shape
    // NoopErrorReporter/NoopHapticsService are tested with.
    service.logEvent('dda_applied', {'type': 'pulse'});
  });

  test('analyticsServiceProvider defaults to Noop', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      container.read(analyticsServiceProvider),
      isA<NoopAnalyticsService>(),
    );
  });

  test('ddaApplied logs the dda_applied event with type/language/level', () {
    final recorded = <(String, Map<String, Object?>)>[];
    final service = _RecordingAnalyticsService(recorded);

    service.ddaApplied(type: 'pulse', language: 'ur', level: 5);

    expect(recorded, hasLength(1));
    final (name, params) = recorded.single;
    expect(name, 'dda_applied');
    expect(params, {'type': 'pulse', 'language': 'ur', 'level': 5});
  });
}

final class _RecordingAnalyticsService implements AnalyticsService {
  _RecordingAnalyticsService(this._sink);

  final List<(String, Map<String, Object?>)> _sink;

  @override
  void logEvent(String name, [Map<String, Object?> params = const {}]) =>
      _sink.add((name, params));
}
