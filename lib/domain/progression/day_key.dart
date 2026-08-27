/// One UTC calendar day, `yyyy-MM-dd`.
///
/// PURE DART. The unit both retention systems that care about "days" are
/// counted in: the streak (Ch02) and the Daily Challenge (Ch12).
///
/// ---------------------------------------------------------------------------
/// WHY UTC, NOT THE DEVICE'S LOCAL CALENDAR
///
/// The same reason `ContentRepository.getDailySeed` reads `.toUtc()` first
/// (P10): "the same puzzle for every player" only holds if every player agrees
/// on what day it is. Local calendar days disagree by up to a day across
/// timezones, so a player in Karachi and one in Toronto would see different
/// dailies at the same instant, and a player who flies could replay one. The
/// UTC day is the one boundary every device computes identically with no
/// server involved — which is also what keeps the Daily playable offline.
///
/// The cost is honest and small: near UTC midnight the "new day" arrives at a
/// local wall-clock time that is not local midnight. Ch12 accepts that; a
/// per-timezone daily would need a server to arbitrate and would stop working
/// on a plane.
///
/// The corresponding NON-goal: this type is not a defence against a player
/// changing their device clock. It is a calendar, not a trusted clock — see
/// `services/time/trusted_clock.dart`, which decides WHICH day to hand this.
final class DayKey implements Comparable<DayKey> {
  const DayKey._(this.year, this.month, this.day);

  /// The UTC calendar day containing [instant], whatever timezone it carries.
  factory DayKey.fromDateTime(DateTime instant) {
    final utc = instant.toUtc();
    return DayKey._(utc.year, utc.month, utc.day);
  }

  /// Parses `yyyy-MM-dd`. Throws [FormatException] on anything else — this
  /// only ever reads values [toString] wrote, so a malformed one is a bug in
  /// the caller (or a tampered row), not a user input to be lenient about.
  factory DayKey.parse(String value) {
    final match = _pattern.firstMatch(value);
    if (match == null) {
      throw FormatException('Not a yyyy-MM-dd day key', value);
    }
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);

    // Round-trips through DateTime so 2026-02-30 is rejected rather than
    // silently normalised to March 2nd — a normalising parse would make two
    // different strings compare equal after a round trip.
    final resolved = DateTime.utc(year, month, day);
    if (resolved.year != year ||
        resolved.month != month ||
        resolved.day != day) {
      throw FormatException('Not a real calendar day', value);
    }
    return DayKey._(year, month, day);
  }

  static final RegExp _pattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  final int year;
  final int month;
  final int day;

  /// Midnight UTC on this day.
  DateTime get utcMidnight => DateTime.utc(year, month, day);

  DayKey get next =>
      DayKey.fromDateTime(utcMidnight.add(const Duration(days: 1)));

  DayKey get previous =>
      DayKey.fromDateTime(utcMidnight.subtract(const Duration(days: 1)));

  /// Whole days from [earlier] to this day: positive when this is later.
  ///
  /// Computed from UTC midnights, so it is never off by one over a DST
  /// change — local midnights are 23 or 25 hours apart twice a year, and a
  /// naive local subtraction would drop or double a streak day for half the
  /// world.
  int daysSince(DayKey earlier) =>
      utcMidnight.difference(earlier.utcMidnight).inDays;

  DayKey addDays(int days) =>
      DayKey.fromDateTime(utcMidnight.add(Duration(days: days)));

  @override
  int compareTo(DayKey other) => utcMidnight.compareTo(other.utcMidnight);

  bool operator <(DayKey other) => compareTo(other) < 0;
  bool operator >(DayKey other) => compareTo(other) > 0;
  bool operator <=(DayKey other) => compareTo(other) <= 0;
  bool operator >=(DayKey other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      other is DayKey &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  /// `yyyy-MM-dd` — the exact shape `daily_results.date` stores.
  @override
  String toString() =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';
}
