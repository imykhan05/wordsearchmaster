/// The eight named achievements (P17), and the ids the two granting paths
/// agree on.
///
/// PURE DART. This file names the achievements and states which of them are
/// reachable in this build; it grants none of them. Six are computed
/// server-side inside `recordSubmission`'s own transaction
/// (`functions/src/stats.ts`) the moment their counter crosses a threshold —
/// the client only ever LISTENS for them, on `users/{uid}.stats.achievements`.
/// The other two are different:
///
///  * [collector] has no fixed id — it is one of 36 sub-badges
///    (12 categories x 3 languages), already modelled by
///    [CategoryBadge.achievementId] in `collections.dart` since P11. This enum
///    exists for the SIX fixed ones; Collector is represented in the UI by
///    iterating `Collections.forLanguage` directly, the same source P11's
///    collections grid already reads.
///  * [speedRunner] cannot unlock in this build at all — it needs Blitz mode
///    (v1.2), which does not exist. Its slot renders locked and greyed with an
///    honest caption; nothing anywhere grants it.
library;

/// One of the six server-granted achievements. [serverId] MUST match
/// `functions/src/stats.ts`'s `ACHIEVEMENTS` map byte-for-byte — it is the
/// key the unlock arrives under on `users/{uid}.stats.achievements`.
enum AchievementId {
  firstWord('first_word'),
  wordMaster('word_master'),
  trilingual('trilingual'),
  onFire('on_fire'),
  streakKeeper('streak_keeper'),
  dailyDevotee('daily_devotee'),

  /// TODO(v1.2, Blitz mode). Defined so the UI can render a locked slot;
  /// never granted by anything in this build — see the library header.
  speedRunner('speed_runner');

  const AchievementId(this.serverId);

  final String serverId;

  /// [AchievementId] for [serverId], or null for an id this build does not
  /// know — including every Collector sub-badge, which is deliberately NOT
  /// a member of this enum (see the header).
  static AchievementId? tryParse(String serverId) {
    for (final id in AchievementId.values) {
      if (id.serverId == serverId) return id;
    }
    return null;
  }

  /// Whether anything in this build can actually grant this achievement.
  /// Only [speedRunner] is not — used to render its slot as locked rather
  /// than merely unearned.
  bool get isReachable => this != AchievementId.speedRunner;
}
