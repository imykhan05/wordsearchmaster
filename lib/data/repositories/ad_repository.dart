import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/progression/ad_policy.dart';
import '../../services/diagnostics/error_reporter.dart';
import '../local/app_database.dart';
import 'local_repository.dart';

part 'ad_repository.g.dart';

/// Persists the two counters [AdFrequencyPolicy] needs (pre-P18).
///
/// Two `kv_settings` rows, not an eighth table — the same call
/// `DdaRepository`/`KvKeys.streakState` already make: this is a small,
/// GLOBAL pair of counters with no need to be queried as a set, so a table
/// would buy nothing and cost a migration. Global, not per-(language,
/// level) like `DdaRepository`'s counters: ad pacing is about how many
/// puzzles THIS PLAYER has just finished, not which language track — a
/// player who switches languages has not earned a second, independent ad
/// budget. Carries an integrity tag like every other row here (via
/// [LocalRepository.readKv]/[writeKv]) — forging either counter only ever
/// buys the forger FEWER ads, which is self-harm rather than the kind of
/// tamper Ch10 is built to catch, but one code path for every kv row is
/// simpler than special-casing this one as the exception.
///
/// Scoped to JOURNEY completions only — `ProgressionController.recordCompletion`
/// calls [recordLevelCompleted] only from its `JourneySession` branch. The
/// Daily is a once-a-day, once-only puzzle with its own economics; folding
/// it into the same pacing counter would let a player's ad cadence depend on
/// whether they happened to also play today's Daily, which answers a
/// question nobody asked.
final class AdRepository extends LocalRepository {
  AdRepository({
    required super.database,
    required super.integrity,
    required super.reporter,
    super.clock,
  });

  static const _totalLevelsCompletedKey = 'ad_total_levels_completed';
  static const _sinceLastInterstitialKey = 'ad_levels_since_interstitial';

  Future<int> _readCounter(String key) async =>
      int.tryParse(await readKv(key) ?? '') ?? 0;

  /// Journey levels completed, ever — a tampered or missing row reads as 0,
  /// the Ch10 rule for any failed check, which only ever makes an ad show
  /// LATER than it should.
  Future<int> totalLevelsCompleted() => _readCounter(_totalLevelsCompletedKey);

  /// Journey levels completed since an interstitial last actually showed, or
  /// since install if none ever has.
  Future<int> levelsSinceLastInterstitial() =>
      _readCounter(_sinceLastInterstitialKey);

  /// Called once per genuine journey-level completion. Advances BOTH
  /// counters — the second one is what a shown interstitial later resets,
  /// but until then it moves in lockstep with the first.
  Future<void> recordLevelCompleted() async {
    final total = await totalLevelsCompleted();
    final sinceLast = await levelsSinceLastInterstitial();
    await writeKv(_totalLevelsCompletedKey, '${total + 1}');
    await writeKv(_sinceLastInterstitialKey, '${sinceLast + 1}');
  }

  /// Called the moment an interstitial actually shows — never on a mere
  /// eligibility check, and never for one that failed to load or was
  /// skipped as ineligible. Resets the GAP counter only; the lifetime total
  /// never goes backwards.
  Future<void> recordInterstitialShown() =>
      writeKv(_sinceLastInterstitialKey, '0');

  /// Whether [policy] currently allows an interstitial, given this
  /// player's own recorded history.
  Future<bool> canShowInterstitial(AdFrequencyPolicy policy) async {
    final total = await totalLevelsCompleted();
    final sinceLast = await levelsSinceLastInterstitial();
    return policy.canShowInterstitial(
      totalLevelsCompleted: total,
      levelsSinceLastInterstitial: sinceLast,
    );
  }
}

@Riverpod(keepAlive: true)
Future<AdRepository> adRepository(Ref ref) async => AdRepository(
  database: ref.watch(appDatabaseProvider),
  integrity: await ref.watch(rowIntegrityProvider.future),
  reporter: ref.watch(errorReporterProvider),
);
