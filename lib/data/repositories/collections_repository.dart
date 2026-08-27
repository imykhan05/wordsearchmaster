import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/progression/collections.dart';
import '../../services/diagnostics/error_reporter.dart';
import '../local/app_database.dart';
import '../local/integrity_tags.dart';
import '../local/outbox_kind.dart';
import '../local/tables.dart';
import 'local_repository.dart';

part 'collections_repository.g.dart';

/// Collection badges, recorded in the `achievements` table (Ch12).
///
/// ---------------------------------------------------------------------------
/// THE TABLE IS A CACHE, NOT THE TRUTH
///
/// `Collections.forLanguage` DERIVES a badge from `level_progress` rows, and
/// that derivation is what the collections grid renders. So why store
/// anything?
///
/// For the two things a derivation cannot do: remember WHEN the badge was
/// earned (`unlockedAt`, which the profile screen shows and analytics wants),
/// and give the outbox a row to sync so the badge exists on the player's other
/// devices before those devices have re-earned the levels underneath it.
///
/// Keeping the derivation authoritative is what makes the badge unforgeable —
/// editing an `achievements` row buys a timestamp and nothing else, because the
/// grid still asks `level_progress` whether the category is actually complete.
final class CollectionsRepository extends LocalRepository {
  CollectionsRepository({
    required super.database,
    required super.integrity,
    required super.reporter,
    super.clock,
  });

  /// Verified achievement rows, keyed by `achievements.id`.
  Stream<Map<String, AchievementRow>> watchUnlocked() {
    final query = database.select(database.achievements);

    return query.watch().map(
      (rows) => {
        for (final row in rows)
          if (_isIntact(row) && row.unlockedAt != null) row.id: row,
      },
    );
  }

  /// A ONE-SHOT read of the verified unlocked rows, keyed by id.
  ///
  /// Not `watchUnlocked().first` — see
  /// `ProgressRepository.completedLevels` for why taking the first event of a
  /// live query is the wrong way to ask for a snapshot.
  Future<Map<String, AchievementRow>> unlockedRows() async {
    final rows = await database.select(database.achievements).get();
    return {
      for (final row in rows)
        if (_isIntact(row) && row.unlockedAt != null) row.id: row,
    };
  }

  /// When [badge] was recorded as earned, or null if it has not been.
  Future<int?> unlockedAt(CategoryBadge badge) async {
    final row = await (database.select(
      database.achievements,
    )..where((row) => row.id.equals(badge.achievementId))).getSingleOrNull();
    if (row == null || !_isIntact(row)) return null;
    return row.unlockedAt;
  }

  /// Records [badge] as earned and queues it, ATOMICALLY.
  ///
  /// Returns false when it was already recorded — the earn timestamp is the
  /// FIRST time, and replaying a level in a completed category must not reset
  /// it. `progress` stores the level count the badge was completed at, which is
  /// what makes a support ticket ("my ANIMALS badge vanished") answerable.
  Future<bool> recordEarned(CategoryBadge badge) {
    final unlockedAt = nowMillis;
    final id = badge.achievementId;
    final progress = badge.levelsCompleted;

    return database.transaction(() async {
      final existing = await (database.select(
        database.achievements,
      )..where((row) => row.id.equals(id))).getSingleOrNull();
      if (existing != null &&
          _isIntact(existing) &&
          existing.unlockedAt != null) {
        return false;
      }

      await database
          .into(database.achievements)
          .insertOnConflictUpdate(
            AchievementsCompanion.insert(
              id: id,
              progress: Value(progress),
              unlockedAt: Value(unlockedAt),
              integrityTag: RowTags.achievement(
                integrity,
                id: id,
                progress: progress,
                unlockedAt: unlockedAt,
              ),
            ),
          );

      await enqueue(
        kind: OutboxKind.achievementUnlocked,
        createdAt: unlockedAt,
        payload: {
          'id': id,
          'category': badge.category,
          'language': badge.language.code,
          'progress': progress,
          'unlockedAt': unlockedAt,
        },
      );
      return true;
    });
  }

  bool _isIntact(AchievementRow row) => guard.accepts(
    table: LocalTables.achievements,
    rowKey: row.id,
    expected: RowTags.achievement(
      integrity,
      id: row.id,
      progress: row.progress,
      unlockedAt: row.unlockedAt,
    ),
    stored: row.integrityTag,
  );
}

@Riverpod(keepAlive: true)
Future<CollectionsRepository> collectionsRepository(Ref ref) async =>
    CollectionsRepository(
      database: ref.watch(appDatabaseProvider),
      integrity: await ref.watch(rowIntegrityProvider.future),
      reporter: ref.watch(errorReporterProvider),
    );
