/// The replay guard carried on every outbox row that submits a score (P14).
///
/// DERIVED, NOT RANDOM, and that is the whole design. A random nonce would be
/// generated once per attempt and then have to survive in the queued row — and
/// it would still be a fresh value on any path that rebuilt the payload,
/// turning one retried submission into two accepted ones. Deriving it from the
/// attempt's own identity fields makes the property automatic instead:
///
///  * IDENTICAL across every retry of one attempt, because `completedAt` is
///    written once, inside the same transaction as the progress row, and never
///    recomputed. That is what makes `submitScore` idempotent — Ch10's outbox
///    is at-least-once, so a row whose response was lost to a dropped
///    connection WILL be sent again, and refusing it would strand a level the
///    player really finished.
///  * DIFFERENT for a genuine replay of the same level, because a second
///    attempt has its own completion timestamp.
///
/// The server derives the same string when a row queued by a pre-P14 build
/// arrives without one (`validation.ts`'s `parseNonce`), so upgrading a device
/// with a full queue does not strand it either. Both sides therefore have to
/// agree on this format exactly — change it here and in
/// `functions/src/validation.ts` together.
library;

import '../../domain/text/language.dart';

abstract final class SubmissionNonce {
  /// `level:{lang}:{level}:{completedAt}`.
  static String forLevel({
    required Language language,
    required int level,
    required int completedAt,
  }) => 'level:${language.code}:$level:$completedAt';

  /// `daily:{lang}:{date}:{completedAt}`, where `date` is `DayKey.toString()`.
  static String forDaily({
    required Language language,
    required String date,
    required int completedAt,
  }) => 'daily:${language.code}:$date:$completedAt';
}
