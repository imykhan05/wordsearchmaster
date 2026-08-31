/// The lifecycle of one queued submission (Ch10 / P16).
///
/// THREE STATES, AND THE ABSENT FOURTH IS THE INTERESTING ONE. There is no
/// `inFlight` here, because an in-flight marker has to be WRITTEN before the
/// request goes out and CLEARED after it comes back — and a process that dies
/// in between leaves the row marked as in flight forever, with nothing to
/// clear it. A stuck row is a level the player finished and will never see
/// credited, which is the exact failure this queue exists to prevent.
///
/// So the claim is held in memory by the worker for the life of one drain, and
/// the guard against a genuine double-send is the SERVER's replay nonce (P14):
/// a repeat is answered idempotently with the stored result. That puts the
/// durable guarantee on the side of the system that can actually keep one.
enum OutboxStatus {
  /// Eligible now, or waiting for `next_retry_at`. The only state a row is
  /// created in.
  pending,

  /// The server refused the payload itself and will refuse it again — a 4xx
  /// that is not a rate limit and not an auth hiccup. Retrying cannot help, so
  /// the row stops consuming attempts, a Crashlytics non-fatal records it, and
  /// the player is told nothing (Ch10: a background sync failure is never a
  /// user-visible error).
  ///
  /// Kept on disk rather than deleted, for the same reason a tampered row is:
  /// it is evidence. The Sync Inspector lists it, and a support case that says
  /// "my level 40 never counted" is then answerable.
  failedPermanent,

  /// Accepted by the server. Rows are deleted on success, so this state
  /// exists for the brief window inside the completing transaction and for
  /// anything that reads a row it has just settled.
  succeeded;

  /// [OutboxStatus] for [name], or null if this build does not know it.
  ///
  /// Null rather than a throw, matching `OutboxKind.tryParse`: a row written
  /// by a NEWER build that the player then downgraded away from must not
  /// crash the sync worker or wedge the queue behind it.
  static OutboxStatus? tryParse(String name) {
    for (final status in OutboxStatus.values) {
      if (status.name == name) return status;
    }
    return null;
  }
}
