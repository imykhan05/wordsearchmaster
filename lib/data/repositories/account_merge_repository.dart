import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/progression/account_merge.dart';
import '../../domain/progression/day_key.dart';
import '../../domain/progression/streak.dart';
import '../../domain/text/language.dart';
import '../../services/diagnostics/error_reporter.dart';
import '../local/app_database.dart';
import '../local/integrity_tags.dart';
import '../local/streak_codec.dart';
import '../local/tables.dart';
import 'local_repository.dart';

part 'account_merge_repository.g.dart';

/// Reads the local account as a snapshot, and writes a merged one back
/// (Ch02 / P13).
///
/// ---------------------------------------------------------------------------
/// THE WRITE IS ONE TRANSACTION, AND THAT IS THE WHOLE SAFETY STORY
///
/// Ch02: "if merging fails, keep local data and retry, never wipe." A merge
/// touches four tables. Applying them one at a time means a failure halfway
/// through leaves an account that is neither the guest's nor the cloud's —
/// levels from one, coins from the other, and no way to tell afterwards which
/// rows are which. [applyMerge] therefore does everything inside a single
/// Drift transaction: it either all lands or none of it does, and "none of it"
/// is exactly the pre-merge local state the player already had.
///
/// There is no delete path in this file at all. Not by convention — there is
/// simply no statement here that removes a row, so "never wipe" is a property
/// of the code rather than a promise about it. Merging is strictly additive:
/// `AccountMerge` keeps every key present on either side, and this writes that
/// union with `insertOnConflictUpdate`.
///
/// ---------------------------------------------------------------------------
/// COINS ARE THE ONE NON-IDEMPOTENT PART, AND THE GUARD LIVES HERE
///
/// `MergedAccount.coinsToCredit` is a DELTA (see its own doc): the ledger is
/// append-only, so a merge cannot set a balance, only add to it. Running the
/// same merge twice would therefore pay the remote balance twice — and a
/// player who signs out and back in would mint coins every time.
///
/// The guard is a reason string naming the remote uid: `merge:<uid>`. Before
/// appending, [applyMerge] looks for a ledger row that already carries it and
/// skips the credit if one exists. That check has to be here rather than in
/// `AccountMerge` because it needs to READ the ledger, which the pure domain
/// layer has no way to do.
final class AccountMergeRepository extends LocalRepository {
  AccountMergeRepository({
    required super.database,
    required super.integrity,
    required super.reporter,
    super.clock,
  });

  /// The ledger reason that marks a merge credit for [remoteUid].
  static String mergeReasonFor(String remoteUid) => 'merge:$remoteUid';

  /// Everything this device holds, as one value.
  ///
  /// Rows that fail their integrity check are DROPPED, exactly as every other
  /// read path drops them (Ch10) — a forged level must not be laundered into
  /// the cloud by a merge, which would make tampering permanent and
  /// cross-device.
  Future<AccountSnapshot> readLocalSnapshot() async {
    final levelRows = await database.select(database.levelProgress).get();
    final dailyRows = await database.select(database.dailyResults).get();
    final achievementRows = await database.select(database.achievements).get();
    final ledgerRows = await database.select(database.coinsLedger).get();

    final levels = <String, LevelSnapshot>{};
    for (final row in levelRows) {
      if (!_levelIntact(row)) continue;
      final language = _languageOrNull(row.languageCode);
      if (language == null) continue;
      final snapshot = LevelSnapshot(
        language: language,
        level: row.level,
        stars: row.stars,
        bestScore: row.bestScore,
        hintsUsed: row.hintsUsed,
        completedAt: row.completedAt,
      );
      levels[snapshot.key] = snapshot;
    }

    final dailies = <String, DailySnapshot>{};
    for (final row in dailyRows) {
      if (!_dailyIntact(row)) continue;
      final language = _languageOrNull(row.languageCode);
      if (language == null) continue;
      final DayKey day;
      try {
        day = DayKey.parse(row.date);
      } on FormatException {
        // A malformed date is a tampered or corrupt row; skip it rather than
        // letting a parse error abort the whole snapshot read.
        continue;
      }
      final snapshot = DailySnapshot(
        day: day,
        language: language,
        score: row.score,
        stars: row.stars,
        completedAt: row.completedAt,
      );
      dailies[snapshot.key] = snapshot;
    }

    final achievements = <String, AchievementSnapshot>{};
    for (final row in achievementRows) {
      if (!_achievementIntact(row)) continue;
      achievements[row.id] = AchievementSnapshot(
        id: row.id,
        progress: row.progress,
        unlockedAt: row.unlockedAt,
      );
    }

    var balance = 0;
    for (final row in ledgerRows) {
      if (_ledgerIntact(row)) balance += row.delta;
    }

    return AccountSnapshot(
      levels: levels,
      dailies: dailies,
      achievements: achievements,
      coinBalance: balance,
      streak: StreakCodec.decode(await readKv(KvKeys.streakState)),
    );
  }

  /// Merges [remote] into what this device holds and writes the union back.
  ///
  /// Returns the merged snapshot on success, or null when the write failed —
  /// in which case NOTHING was written and the local account is byte-for-byte
  /// what it was before the call. The caller retries; it must not react by
  /// clearing anything.
  Future<AccountSnapshot?> applyMerge({
    required AccountSnapshot remote,
    required String remoteUid,
  }) async {
    try {
      final local = await readLocalSnapshot();
      final merged = AccountMerge.merge(local: local, remote: remote);
      final now = nowMillis;

      await database.transaction(() async {
        for (final level in merged.levels.values) {
          await _writeLevel(level);
        }
        for (final daily in merged.dailies.values) {
          await _writeDaily(daily);
        }
        for (final achievement in merged.achievements.values) {
          await _writeAchievement(achievement);
        }
        await _writeStreak(merged.streak);
        await _creditCoinsOnce(
          amount: merged.coinsToCredit,
          remoteUid: remoteUid,
          now: now,
        );
      });

      return merged.snapshot;
    } catch (error, stackTrace) {
      // Ch02's rule, enforced: a failed merge keeps local data. The
      // transaction above has already rolled back by the time we get here, so
      // there is nothing to undo — only something NOT to do, namely react to
      // the failure by touching the player's rows.
      guard.reporter.nonFatal(
        error,
        stackTrace: stackTrace,
        context: {'stage': 'accountMerge.applyMerge', 'remoteUid': remoteUid},
      );
      return null;
    }
  }

  Future<void> _writeLevel(LevelSnapshot level) => database
      .into(database.levelProgress)
      .insertOnConflictUpdate(
        LevelProgressCompanion.insert(
          languageCode: level.language.code,
          level: level.level,
          stars: level.stars,
          bestScore: level.bestScore,
          hintsUsed: level.hintsUsed,
          completedAt: level.completedAt,
          // Re-signed for THIS install: a tag is bound to the install id, so
          // a row arriving from another device can never carry a tag this
          // device would accept. Re-signing on write is what makes the merged
          // row readable here at all.
          integrityTag: RowTags.levelProgress(
            integrity,
            languageCode: level.language.code,
            level: level.level,
            stars: level.stars,
            bestScore: level.bestScore,
            hintsUsed: level.hintsUsed,
            completedAt: level.completedAt,
          ),
        ),
      );

  Future<void> _writeDaily(DailySnapshot daily) {
    final date = daily.day.toString();
    return database
        .into(database.dailyResults)
        .insertOnConflictUpdate(
          DailyResultsCompanion.insert(
            date: date,
            languageCode: daily.language.code,
            score: daily.score,
            stars: daily.stars,
            completedAt: daily.completedAt,
            integrityTag: RowTags.dailyResult(
              integrity,
              date: date,
              languageCode: daily.language.code,
              score: daily.score,
              stars: daily.stars,
              completedAt: daily.completedAt,
            ),
          ),
        );
  }

  Future<void> _writeAchievement(AchievementSnapshot achievement) => database
      .into(database.achievements)
      .insertOnConflictUpdate(
        AchievementsCompanion.insert(
          id: achievement.id,
          progress: Value(achievement.progress),
          unlockedAt: Value(achievement.unlockedAt),
          integrityTag: RowTags.achievement(
            integrity,
            id: achievement.id,
            progress: achievement.progress,
            unlockedAt: achievement.unlockedAt,
          ),
        ),
      );

  Future<void> _writeStreak(StreakState streak) =>
      writeKv(KvKeys.streakState, StreakCodec.encode(streak));

  /// Appends the merge credit, unless this remote account's credit is already
  /// in the ledger. See the class header for why the guard is here.
  Future<void> _creditCoinsOnce({
    required int amount,
    required String remoteUid,
    required int now,
  }) async {
    // A zero credit would violate the ledger's own `delta != 0` constraint,
    // and means there is nothing to carry across anyway.
    if (amount == 0) return;

    final reason = mergeReasonFor(remoteUid);
    final existing =
        await (database.select(database.coinsLedger)
              ..where((row) => row.reason.equals(reason))
              ..limit(1))
            .getSingleOrNull();
    if (existing != null) return;

    final id = await database.nextRowId(LocalTables.coinsLedger);
    await database
        .into(database.coinsLedger)
        .insert(
          CoinsLedgerCompanion.insert(
            id: Value(id),
            delta: amount,
            reason: reason,
            createdAt: now,
            integrityTag: RowTags.coinsLedger(
              integrity,
              id: id,
              delta: amount,
              reason: reason,
              createdAt: now,
            ),
          ),
        );
  }

  /// The language for [code], or null if this build does not know it.
  ///
  /// Null rather than a throw for the same reason `OutboxKind.tryParse`
  /// returns null: a row written by a newer build that shipped a fourth
  /// language must not crash a merge on an older one.
  static Language? _languageOrNull(String code) {
    for (final language in Language.values) {
      if (language.code == code) return language;
    }
    return null;
  }

  bool _levelIntact(LevelProgressRow row) => guard.accepts(
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

  bool _dailyIntact(DailyResultRow row) => guard.accepts(
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

  bool _achievementIntact(AchievementRow row) => guard.accepts(
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

  bool _ledgerIntact(CoinsLedgerRow row) => guard.accepts(
    table: LocalTables.coinsLedger,
    rowKey: '${row.id}',
    expected: RowTags.coinsLedger(
      integrity,
      id: row.id,
      delta: row.delta,
      reason: row.reason,
      createdAt: row.createdAt,
    ),
    stored: row.integrityTag,
  );
}

@Riverpod(keepAlive: true)
Future<AccountMergeRepository> accountMergeRepository(Ref ref) async =>
    AccountMergeRepository(
      database: ref.watch(appDatabaseProvider),
      integrity: await ref.watch(rowIntegrityProvider.future),
      reporter: ref.watch(errorReporterProvider),
    );
