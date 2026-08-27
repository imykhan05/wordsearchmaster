import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/application/game_controller.dart';
import 'package:word_search_master/data/local/app_database.dart';
import 'package:word_search_master/data/repositories/dda_repository.dart';
import 'package:word_search_master/domain/text/language.dart';
import 'package:word_search_master/services/analytics/analytics_service.dart';

import '../support/local_db.dart';

/// `journeyDownshiftProvider` (`game_controller.dart`) — the ONE place
/// `DdaRepository` is read+consumed for the Ch02 downshift rule, resolved by
/// `GameScreen` BEFORE it constructs a `JourneySession`, never inside
/// `GameController.build` itself. See that provider's own doc for why the
/// split exists: `game_controller_test.dart`'s whole suite depends on
/// `GameController` staying database-free, which this file is what actually
/// proves the feature still works despite that split.
final class _RecordingAnalytics implements AnalyticsService {
  final List<(String, Map<String, Object?>)> events = [];

  @override
  void logEvent(String name, [Map<String, Object?> params = const {}]) =>
      events.add((name, params));
}

void main() {
  Future<(ProviderContainer, TestDatabase)> buildContainer() async {
    final db = await openMemoryDatabase();
    addTearDown(db.database.close);
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db.database)],
    );
    addTearDown(container.dispose);
    return (container, db);
  }

  test('a level never abandoned does not downshift', () async {
    final (container, _) = await buildContainer();

    final downshift = await container.read(journeyDownshiftProvider(1).future);

    expect(downshift, isFalse);
  });

  test('two consecutive abandons downshift the NEXT entry', () async {
    final (container, db) = await buildContainer();
    final ddaRepo = await container.read(ddaRepositoryProvider.future);
    await ddaRepo.recordAbandon(Language.english, 4);
    await ddaRepo.recordAbandon(Language.english, 4);

    final downshift = await container.read(journeyDownshiftProvider(4).future);

    expect(downshift, isTrue);
    // Consumed: reading it again (a hypothetical next attempt at the SAME
    // level, in a fresh container over the same database) is no longer
    // downshifted until two more abandons happen.
    final again = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db.database)],
    );
    addTearDown(again.dispose);
    expect(await again.read(journeyDownshiftProvider(4).future), isFalse);
  });

  test('firing the downshift logs dda_applied, type downshift', () async {
    final db = await openMemoryDatabase();
    addTearDown(db.database.close);
    final analytics = _RecordingAnalytics();
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db.database),
        analyticsServiceProvider.overrideWithValue(analytics),
      ],
    );
    addTearDown(container.dispose);
    final ddaRepo = await container.read(ddaRepositoryProvider.future);
    await ddaRepo.recordAbandon(Language.english, 9);
    await ddaRepo.recordAbandon(Language.english, 9);

    await container.read(journeyDownshiftProvider(9).future);

    expect(analytics.events, hasLength(1));
    final (name, params) = analytics.events.single;
    expect(name, 'dda_applied');
    expect(params['type'], 'downshift');
    expect(params['level'], 9);
  });

  test('NOT downshifting fires no analytics event', () async {
    final db = await openMemoryDatabase();
    addTearDown(db.database.close);
    final analytics = _RecordingAnalytics();
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db.database),
        analyticsServiceProvider.overrideWithValue(analytics),
      ],
    );
    addTearDown(container.dispose);

    await container.read(journeyDownshiftProvider(2).future);

    expect(analytics.events, isEmpty);
  });
}
