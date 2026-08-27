import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/progression/day_key.dart';
import '../../domain/progression/streak.dart';
import '../../services/diagnostics/error_reporter.dart';
import '../../services/time/trusted_clock.dart';
import '../local/app_database.dart';
import '../local/integrity_tags.dart';
import '../local/streak_codec.dart';
import '../local/tables.dart';
import 'local_repository.dart';

part 'streak_repository.g.dart';

/// The daily streak, stored as one integrity-tagged `kv_settings` row.
///
/// EVERY READ IS SETTLED. `StreakRules.settle` is pure and idempotent (see its
/// library header), so the repository ages the stored state forward to the
/// caller's "today" on the way out. That is what makes a freeze consume itself
/// the moment the player opens the app after missing a day, rather than
/// waiting for them to finish a level to discover the streak they thought they
/// had is gone.
///
/// The settle result is NOT written back on a read. Two reasons: a read path
/// that writes turns a Drift stream into a feedback loop (the write dirties
/// the table, the stream re-emits, it settles again), and the stored state is
/// already sufficient — settling is deterministic in `(state, today)`, so the
/// number shown and the number that will be persisted on the next completion
/// agree by construction. [registerPlay] is the one writer.
final class StreakRepository extends LocalRepository {
  StreakRepository({
    required super.database,
    required super.integrity,
    required super.reporter,
    super.clock,
  });

  /// The stored state, un-settled. Prefer [streakAsOf] unless you specifically
  /// want what is on disk.
  Future<StreakState> readRaw() async =>
      StreakCodec.decode(await readKv(KvKeys.streakState));

  /// The stored state aged forward to [today].
  Future<StreakTransition> streakAsOf(DayKey today) async =>
      StreakRules.settle(await readRaw(), today);

  /// A live stream of the streak as of [today], re-emitting on every write.
  ///
  /// Watches only the one KV row. Drift re-emits a `watch` on any write to the
  /// table, and `kv_settings` also carries the install id and the sync cursor,
  /// so filtering here keeps a sync tick from rebuilding the home screen's
  /// streak counter.
  Stream<StreakTransition> watchStreakAsOf(DayKey today) {
    final query = database.select(database.kvSettings)
      ..where((row) => row.key.equals(KvKeys.streakState));

    return query.watchSingleOrNull().map((row) {
      if (row == null) return StreakRules.settle(StreakState.empty, today);

      final intact = guard.accepts(
        table: LocalTables.kvSettings,
        rowKey: KvKeys.streakState,
        expected: RowTags.kvSetting(
          integrity,
          key: KvKeys.streakState,
          value: row.value,
        ),
        stored: row.integrityTag,
      );

      return StreakRules.settle(
        intact ? StreakCodec.decode(row.value) : StreakState.empty,
        today,
      );
    });
  }

  /// Records that a level was completed on [today] and persists the result.
  ///
  /// Returns the transition so the caller can tell the player what happened —
  /// a freeze firing silently is the one outcome that reads as a bug.
  ///
  /// Idempotent within a day by construction: `StreakRules.registerPlay`
  /// returns the state unchanged when it has already counted [today], so
  /// finishing five levels in one sitting writes the same row five times
  /// rather than counting five days.
  Future<StreakTransition> registerPlay(DayKey today) async {
    return database.transaction(() async {
      final stored = StreakCodec.decode(await readKv(KvKeys.streakState));
      final transition = StreakRules.registerPlay(stored, today);

      await writeKv(KvKeys.streakState, StreakCodec.encode(transition.state));
      return transition;
    });
  }

  /// Settles the stored state against [today] and PERSISTS it.
  ///
  /// The one place a settle is written back, called on app resume so a freeze
  /// spent while the app was closed is durable even if the player never
  /// finishes a level that session. Writes nothing when settling changed
  /// nothing, so it cannot churn the row on every resume.
  Future<StreakTransition> settleAndPersist(DayKey today) async {
    return database.transaction(() async {
      final stored = StreakCodec.decode(await readKv(KvKeys.streakState));
      final transition = StreakRules.settle(stored, today);
      if (transition.state == stored) return transition;

      await writeKv(KvKeys.streakState, StreakCodec.encode(transition.state));
      return transition;
    });
  }
}

/// The rollback floor for [TrustedClock], backed by `kv_settings`.
///
/// Lives in the data layer rather than in `services/time/` because it is a
/// database concern; `TrustedClock` only knows the port.
final class DriftDayHighWaterMarkStore extends LocalRepository
    implements DayHighWaterMarkStore {
  DriftDayHighWaterMarkStore({
    required super.database,
    required super.integrity,
    required super.reporter,
  });

  @override
  Future<DayKey?> read() async {
    final raw = await readKv(KvKeys.dayHighWaterMark);
    if (raw == null) return null;
    try {
      return DayKey.parse(raw);
    } catch (_) {
      // A mark that will not parse is a mark that is not there. The clock
      // still answers; only the guard is lost.
      return null;
    }
  }

  @override
  Future<void> write(DayKey day) =>
      writeKv(KvKeys.dayHighWaterMark, day.toString());
}

@Riverpod(keepAlive: true)
Future<StreakRepository> streakRepository(Ref ref) async => StreakRepository(
  database: ref.watch(appDatabaseProvider),
  integrity: await ref.watch(rowIntegrityProvider.future),
  reporter: ref.watch(errorReporterProvider),
);
