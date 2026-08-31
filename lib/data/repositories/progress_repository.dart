import 'dart:math';

import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/scoring/score_event.dart';
import '../../domain/scoring/scoring.dart';
import '../../domain/text/language.dart';
import '../../services/diagnostics/error_reporter.dart';
import '../local/app_database.dart';
import '../local/integrity_tags.dart';
import '../local/outbox_kind.dart';
import '../local/score_event_codec.dart';
import '../local/submission_nonce.dart';
import '../local/tables.dart';
import 'local_repository.dart';

part 'progress_repository.g.dart';

/// Per-level stars, best score and completion, local-first.
final class ProgressRepository extends LocalRepository {
  ProgressRepository({
    required super.database,
    required super.integrity,
    required super.reporter,
    super.clock,
  });

  /// Every completed level in [language], lowest first.
  ///
  /// Rows that fail their integrity check are dropped — see [LocalRepository].
  Stream<List<LevelProgressRow>> watchAll(Language language) {
    final query = database.select(database.levelProgress)
      ..where((row) => row.languageCode.equals(language.code))
      ..orderBy([(row) => OrderingTerm.asc(row.level)]);

    return query.watch().map(
      (rows) => [
        for (final row in rows)
          if (_isIntact(row)) row,
      ],
    );
  }

  Stream<LevelProgressRow?> watchLevel(Language language, int level) {
    final query = database.select(database.levelProgress)
      ..where(
        (row) =>
            row.languageCode.equals(language.code) & row.level.equals(level),
      );

    return query.watchSingleOrNull().map(
      (row) => row != null && _isIntact(row) ? row : null,
    );
  }

  /// The highest level finished in [language], or 0 when none is.
  ///
  /// Deliberately derived from the verified rows rather than from a stored
  /// "highest level" counter: a counter is one number to forge, whereas this
  /// requires forging the level row it claims to summarise.
  Stream<int> watchHighestCompletedLevel(Language language) =>
      watchAll(language)
          .map((rows) => rows.fold(0, (best, row) => max(best, row.level)));

  /// A ONE-SHOT read of the level numbers finished in [language].
  ///
  /// Not `watchAll(...).first`, and the difference is not cosmetic: taking the
  /// first event of a Drift stream OPENS a live query, delivers one row set,
  /// then cancels — and cancelling schedules Drift's own cleanup timer, which
  /// outlives the caller. In a widget test that lands as "a Timer is still
  /// pending after the widget tree was disposed"; in the app it is a
  /// subscription's worth of work for a snapshot nobody is watching. A caller
  /// that wants a value rather than a feed should ask for a value.
  Future<Set<int>> completedLevels(Language language) async {
    final rows = await (database.select(
      database.levelProgress,
    )..where((row) => row.languageCode.equals(language.code))).get();

    return {
      for (final row in rows)
        if (_isIntact(row)) row.level,
    };
  }

  /// Records a finished level and queues its submission, ATOMICALLY.
  ///
  /// [score] is kept only when it beats what is already stored: replaying a
  /// level for fun must never cost a player their best result. Stars follow
  /// the same rule, and both are resolved INSIDE the transaction so a
  /// concurrent write cannot land between the read and the write.
  ///
  /// The queued payload carries the ordered [events], not the computed total —
  /// Ch08's Cloud Function replays them and writes its own number (P14). The
  /// score written locally is the optimistic one the player sees now.
  Future<void> recordLevelComplete({
    required Language language,
    required int level,
    required int stars,
    required int score,
    required int hintsUsed,
    required List<ScoreEvent> events,
  }) {
    final completedAt = nowMillis;

    return database.transaction(() async {
      final existing =
          await (database.select(database.levelProgress)..where(
                (row) =>
                    row.languageCode.equals(language.code) &
                    row.level.equals(level),
              ))
              .getSingleOrNull();

      // A previous row that fails its check is treated as absent rather than
      // as a floor to beat — otherwise a forged best score would be permanent,
      // surviving every honest replay that could not exceed it.
      final previous = existing != null && _isIntact(existing)
          ? existing
          : null;

      final bestScore = max(score, previous?.bestScore ?? 0);
      final bestStars = max(stars, previous?.stars ?? 0);

      await database
          .into(database.levelProgress)
          .insertOnConflictUpdate(
            LevelProgressCompanion.insert(
              languageCode: language.code,
              level: level,
              stars: bestStars,
              bestScore: bestScore,
              hintsUsed: hintsUsed,
              completedAt: completedAt,
              integrityTag: RowTags.levelProgress(
                integrity,
                languageCode: language.code,
                level: level,
                stars: bestStars,
                bestScore: bestScore,
                hintsUsed: hintsUsed,
                completedAt: completedAt,
              ),
            ),
          );

      await enqueue(
        kind: OutboxKind.levelComplete,
        createdAt: completedAt,
        payload: {
          'language': language.code,
          'level': level,
          'stars': stars,
          'hintsUsed': hintsUsed,
          'completedAt': completedAt,
          // Lets the server reject a submission from a client built against
          // older rules instead of silently mis-scoring it.
          'specVersion': Scoring.specVersion,
          // The replay guard. Derived from this attempt's own fields, so a
          // retry of THIS row carries the same value and the server can answer
          // it idempotently instead of recording the level twice (P14).
          'nonce': SubmissionNonce.forLevel(
            language: language,
            level: level,
            completedAt: completedAt,
          ),
          'events': ScoreEventCodec.encode(events),
        },
      );
    });
  }

  bool _isIntact(LevelProgressRow row) => guard.accepts(
    table: LocalTables.levelProgress,
    rowKey: '${row.languageCode}/${row.level}',
    expected: RowTags.levelProgress(
      integrity,
      languageCode: row.languageCode,
      level: row.level,
      stars: row.stars,
      bestScore: row.bestScore,
      hintsUsed: row.hintsUsed,
      completedAt: row.completedAt,
    ),
    stored: row.integrityTag,
  );
}

@Riverpod(keepAlive: true)
Future<ProgressRepository> progressRepository(Ref ref) async =>
    ProgressRepository(
      database: ref.watch(appDatabaseProvider),
      integrity: await ref.watch(rowIntegrityProvider.future),
      reporter: ref.watch(errorReporterProvider),
    );
