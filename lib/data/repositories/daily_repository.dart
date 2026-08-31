import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/progression/day_key.dart';
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

part 'daily_repository.g.dart';

/// The Daily Challenge's one-attempt-per-day record (Ch12).
///
/// ---------------------------------------------------------------------------
/// FULLY PLAYABLE WITH THE RADIO OFF, AND THAT IS A DATA-LAYER PROPERTY
///
/// Nothing here touches the network, and nothing above it needs to: the puzzle
/// is `sha256(utcDate + langCode)` (P10, computed on-device), the attempt is
/// recorded in `daily_results`, and the leaderboard submission is an OUTBOX
/// row that leaves whenever a connection next exists. So the offline path is
/// not a degraded mode with a banner — it is the only path, and being online
/// merely means the queue drains sooner.
///
/// The one-attempt rule is enforced against `daily_results`, a local table, for
/// the same reason: a server check would make the rule unenforceable on a
/// plane, which is precisely where Ch12 promises the Daily works.
///
/// Keyed by `(date, language)` like `level_progress` is by `(language, level)`.
/// Three languages means three different puzzles on the same date — a player
/// who switches script gets that day's Urdu daily as well as its Hindi one,
/// which is deliberate: they are different puzzles from different word packs,
/// not one puzzle rendered twice.
final class DailyRepository extends LocalRepository {
  DailyRepository({
    required super.database,
    required super.integrity,
    required super.reporter,
    super.clock,
  });

  /// The result for [day] in [language], or null if it has not been played.
  Future<DailyResultRow?> result(DayKey day, Language language) async {
    final row =
        await (database.select(database.dailyResults)..where(
              (row) =>
                  row.date.equals(day.toString()) &
                  row.languageCode.equals(language.code),
            ))
            .getSingleOrNull();
    return row != null && _isIntact(row) ? row : null;
  }

  /// Whether today's puzzle has already been attempted.
  ///
  /// A row that fails its integrity check reads as ABSENT, which hands the
  /// player a replay rather than locking them out. That is the right way round
  /// for a failed check: Ch10 says degrade to a default and never show an
  /// error, and the cost of a forged row here is one extra attempt at a puzzle
  /// whose score the server recomputes anyway (P14).
  Future<bool> hasPlayed(DayKey day, Language language) async =>
      await result(day, language) != null;

  /// Live view of [day]'s result, for a screen that must flip from "play" to
  /// "done" the moment the puzzle is finished.
  Stream<DailyResultRow?> watchResult(DayKey day, Language language) {
    final query = database.select(database.dailyResults)
      ..where(
        (row) =>
            row.date.equals(day.toString()) &
            row.languageCode.equals(language.code),
      );

    return query.watchSingleOrNull().map(
      (row) => row != null && _isIntact(row) ? row : null,
    );
  }

  /// Every recorded daily in [language], newest first — the profile screen's
  /// history strip.
  Stream<List<DailyResultRow>> watchAll(Language language) {
    final query = database.select(database.dailyResults)
      ..where((row) => row.languageCode.equals(language.code))
      ..orderBy([(row) => OrderingTerm.desc(row.date)]);

    return query.watch().map(
      (rows) => [
        for (final row in rows)
          if (_isIntact(row)) row,
      ],
    );
  }

  /// Records a finished daily and queues its leaderboard submission,
  /// ATOMICALLY — the Ch10 outbox contract, identical to
  /// `ProgressRepository.recordLevelComplete`.
  ///
  /// Returns false and writes NOTHING when the day has already been played.
  /// The check runs inside the transaction so two completions racing (a double
  /// tap, a rebuild) cannot both find the day free and both submit.
  ///
  /// Unlike a level, a daily result is NOT best-of: the first attempt is the
  /// attempt. That is what makes the daily leaderboard comparable at all —
  /// "one attempt per day" with a best-of write would let a player grind.
  Future<bool> recordDailyComplete({
    required DayKey day,
    required Language language,
    required int score,
    required int stars,
    required List<ScoreEvent> events,
  }) {
    final completedAt = nowMillis;
    final date = day.toString();

    return database.transaction(() async {
      final existing =
          await (database.select(database.dailyResults)..where(
                (row) =>
                    row.date.equals(date) &
                    row.languageCode.equals(language.code),
              ))
              .getSingleOrNull();
      if (existing != null && _isIntact(existing)) return false;

      await database
          .into(database.dailyResults)
          .insertOnConflictUpdate(
            DailyResultsCompanion.insert(
              date: date,
              languageCode: language.code,
              score: score,
              stars: stars,
              completedAt: completedAt,
              integrityTag: RowTags.dailyResult(
                integrity,
                date: date,
                languageCode: language.code,
                score: score,
                stars: stars,
                completedAt: completedAt,
              ),
            ),
          );

      await enqueue(
        kind: OutboxKind.dailyResult,
        createdAt: completedAt,
        payload: {
          'date': date,
          'language': language.code,
          'stars': stars,
          'completedAt': completedAt,
          'specVersion': Scoring.specVersion,
          'nonce': SubmissionNonce.forDaily(
            language: language,
            date: date,
            completedAt: completedAt,
          ),
          // The ordered events, never the total: P14's Cloud Function replays
          // them and writes ITS number (CLAUDE.md → Never write scores
          // directly from client to Firestore).
          'events': ScoreEventCodec.encode(events),
        },
      );
      return true;
    });
  }

  /// Applies the server's stored daily result back onto the local row
  /// (Ch10 conflict rule 3 / P16).
  ///
  /// The server keeps the FIRST attempt and answers a later one with what it
  /// already holds (`submitDaily`), so what comes back is not "the better
  /// result" — it is the result that actually counted on the board. Local has
  /// to match it, including downward, for the same reason a level does:
  /// showing a player a daily score that the leaderboard disagrees with is a
  /// bug they can see.
  ///
  /// NEVER ENQUEUES, for the same loop-avoidance reason as
  /// `ProgressRepository.reconcileFromServer`.
  ///
  /// Returns true when the row moved.
  Future<bool> reconcileFromServer({
    required DayKey day,
    required Language language,
    required int score,
    required int stars,
  }) async {
    final date = day.toString();

    return database.transaction(() async {
      final existing =
          await (database.select(database.dailyResults)..where(
                (row) =>
                    row.date.equals(date) &
                    row.languageCode.equals(language.code),
              ))
              .getSingleOrNull();
      final previous = existing != null && _isIntact(existing)
          ? existing
          : null;

      if (previous != null &&
          previous.score == score &&
          previous.stars == stars) {
        return false;
      }

      final completedAt = previous?.completedAt ?? nowMillis;

      await database
          .into(database.dailyResults)
          .insertOnConflictUpdate(
            DailyResultsCompanion.insert(
              date: date,
              languageCode: language.code,
              score: score,
              stars: stars,
              completedAt: completedAt,
              integrityTag: RowTags.dailyResult(
                integrity,
                date: date,
                languageCode: language.code,
                score: score,
                stars: stars,
                completedAt: completedAt,
              ),
            ),
          );
      return true;
    });
  }

  bool _isIntact(DailyResultRow row) => guard.accepts(
    table: LocalTables.dailyResults,
    rowKey: '${row.date}/${row.languageCode}',
    expected: RowTags.dailyResult(
      integrity,
      date: row.date,
      languageCode: row.languageCode,
      score: row.score,
      stars: row.stars,
      completedAt: row.completedAt,
    ),
    stored: row.integrityTag,
  );
}

@Riverpod(keepAlive: true)
Future<DailyRepository> dailyRepository(Ref ref) async => DailyRepository(
  database: ref.watch(appDatabaseProvider),
  integrity: await ref.watch(rowIntegrityProvider.future),
  reporter: ref.watch(errorReporterProvider),
);
