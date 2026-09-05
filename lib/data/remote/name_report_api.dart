/// Reporting a leaderboard display name (AR-4 / T12, post-P17).
///
/// ---------------------------------------------------------------------------
/// A CREATE, NOT A CALLABLE
///
/// Every other client-initiated write in this codebase that touches
/// server-owned state is a callable (`submitScore`, `submitAchievement`,
/// `redeemInviteCode`), because each needs a computed response. A report
/// needs none — see `functions/src/nameReports.ts`'s header for why the
/// reporter gets no feedback beyond "thanks". So this interface has exactly
/// one method, and it never reads anything back.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'name_report_api.g.dart';

abstract interface class NameReportApi {
  /// Reports [reportedUid]'s current display name, on behalf of [reporterUid].
  ///
  /// Never throws — a failed report degrades to silently not having happened,
  /// the same "never block on a network call" posture every other write in
  /// this app takes. The caller decides what, if anything, to tell the player
  /// from the returned success flag.
  Future<bool> reportDisplayName({
    required String reporterUid,
    required String reportedUid,
  });
}

/// No reports, ever. The binding whenever Firebase is unavailable.
final class NoopNameReportApi implements NameReportApi {
  const NoopNameReportApi();

  @override
  Future<bool> reportDisplayName({
    required String reporterUid,
    required String reportedUid,
  }) async => false;
}

/// Defaults to Noop; `bootstrap.dart` upgrades it once Firebase initialises.
@Riverpod(keepAlive: true)
NameReportApi nameReportApi(Ref ref) => const NoopNameReportApi();
