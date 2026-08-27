import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/progression/dda.dart';
import '../../domain/text/language.dart';
import '../../services/diagnostics/error_reporter.dart';
import '../local/app_database.dart';
import 'local_repository.dart';

part 'dda_repository.g.dart';

/// Per-(language, level) consecutive-abandon counts (Ch02/P12).
///
/// A `kv_settings` row per level ever abandoned, not an eighth table — the
/// same call `KvKeys.streakState` already makes: this is a small, sparse set
/// of counters with no need to be queried as a set, so a table would buy
/// nothing and cost a migration. It carries an integrity tag like every other
/// row here (via [LocalRepository.readKv]/[writeKv]), because a forged
/// abandon count is exactly the kind of "make the game easier for me" tamper
/// Ch10 exists to make visible rather than silently trust.
///
/// See `domain/progression/dda.dart`'s [DdaAbandonRules] header for what
/// counts as an abandon in this build, and `game_screen.dart` for where one is
/// recorded.
final class DdaRepository extends LocalRepository {
  DdaRepository({
    required super.database,
    required super.integrity,
    required super.reporter,
    super.clock,
  });

  static String _key(Language language, int level) =>
      'dda_abandon:${language.code}:$level';

  /// Consecutive abandons recorded for (language, level) so far, or 0 for a
  /// level never abandoned OR whose row failed its integrity check — the
  /// Ch10 rule: a tampered row reads as empty, never as an error.
  Future<int> abandonCount(Language language, int level) async {
    final raw = await readKv(_key(language, level));
    return int.tryParse(raw ?? '') ?? 0;
  }

  /// One more abandon on (language, level).
  Future<void> recordAbandon(Language language, int level) async {
    final current = await abandonCount(language, level);
    await writeKv(_key(language, level), '${current + 1}');
  }

  /// Resets the streak — called the moment (language, level) is actually
  /// finished (`ProgressionController.recordCompletion`), since the pattern
  /// this counts is specifically "never manages to finish this one".
  Future<void> clearAbandon(Language language, int level) =>
      writeKv(_key(language, level), '0');

  Future<bool> shouldDownshift(Language language, int level) async =>
      DdaAbandonRules.shouldDownshift(await abandonCount(language, level));

  /// Applies the downshift for the attempt about to load and resets the
  /// counter — so it takes two FRESH consecutive abandons before the next one
  /// fires, rather than downshifting every attempt forever after the second.
  Future<void> consumeDownshift(Language language, int level) =>
      clearAbandon(language, level);
}

@Riverpod(keepAlive: true)
Future<DdaRepository> ddaRepository(Ref ref) async => DdaRepository(
  database: ref.watch(appDatabaseProvider),
  integrity: await ref.watch(rowIntegrityProvider.future),
  reporter: ref.watch(errorReporterProvider),
);
