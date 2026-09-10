/// The eight looks the app can wear, and the clock rule that picks one.
///
/// PURE DART — no `package:flutter`, so not a `Brightness` in sight. A variant
/// knows only whether it is a DARK look ([isDark]); the actual colours live in
/// `lib/app/theme/app_tokens.dart`, which is the only file in `lib/` allowed
/// to contain a colour literal at all. Same indirection `JourneyRegion` already
/// uses for its accent index and `BackgroundStyle` for its gradient index, and
/// for the same reason: the rule about which look applies is testable without
/// a rendering engine.
library;

/// One named palette.
///
/// [id] doubles as the persisted preference string, so a value stored by one
/// build and read by another cannot drift from the enum — the same one-string
/// discipline `BackgroundStyle.id` keeps between the preference and its
/// folder.
enum AppThemeVariant {
  /// The palette the app shipped with: near-black green ground, marigold
  /// accent. Stays [defaultVariant] so an upgrade that only ADDED the ability
  /// to change the theme does not change anybody's screen.
  midnight('midnight', isDark: true),

  /// Deep navy ground, aqua accent.
  deepSea('deep_sea', isDark: true),

  /// Aubergine ground, rose accent.
  twilight('twilight', isDark: true),

  /// Pine ground, new-leaf accent.
  forest('forest', isDark: true),

  /// Neutral graphite ground, steel-blue accent — the least tinted dark look,
  /// for a player who wants no hue at all behind the grid.
  slate('slate', isDark: true),

  /// The warm cream light palette the app already carried but never showed:
  /// `app.dart` was hard-locked to dark until this enum existed.
  daylight('daylight', isDark: false),

  /// Pale mint ground, deep teal accent.
  morningMint('morning_mint', isDark: false),

  /// Warm sand ground, terracotta accent.
  desertSand('desert_sand', isDark: false);

  const AppThemeVariant(this.id, {required this.isDark});

  /// Persisted preference string — see the enum doc.
  final String id;

  /// Whether this look wants light text on a dark ground. Drives
  /// `Brightness` at the `app/theme` layer, which this file cannot name.
  final bool isDark;

  static const AppThemeVariant defaultVariant = AppThemeVariant.midnight;

  static List<AppThemeVariant> get dark =>
      values.where((variant) => variant.isDark).toList();

  static List<AppThemeVariant> get light =>
      values.where((variant) => !variant.isDark).toList();

  /// Falls back to [defaultVariant] for an unrecognised id — a downgrade, or a
  /// palette retired in a later release. The same degrade-don't-throw shape
  /// `BackgroundStyle.fromId` already uses.
  static AppThemeVariant fromId(String? id) => values.firstWhere(
    (variant) => variant.id == id,
    orElse: () => defaultVariant,
  );
}

/// Six slices of a day, each with the look it hands over to.
///
/// LOCAL time, deliberately — and this is the one place in the codebase that
/// says so. `DayKey`, `getDailySeed` and `TrustedClock` all count days in UTC
/// because a streak and a Daily puzzle have to mean the same thing for every
/// player at once; fairness is the whole point there. A theme is the opposite
/// kind of question: what matters is how much light is in the room the player
/// is actually sitting in, which only their own wall clock knows. There is
/// also nothing to cheat — a player who sets their clock forward gets an
/// evening palette early and has taken nothing from anyone.
enum TimeOfDaySlot {
  morning(startHour: 5, variant: AppThemeVariant.morningMint),
  day(startHour: 8, variant: AppThemeVariant.daylight),
  afternoon(startHour: 12, variant: AppThemeVariant.desertSand),
  evening(startHour: 16, variant: AppThemeVariant.twilight),
  night(startHour: 19, variant: AppThemeVariant.midnight),

  /// 23:00 until the next morning. Named for the hours rather than for
  /// [AppThemeVariant.midnight], which is the NIGHT slot's palette — the two
  /// words genuinely mean different things here.
  lateNight(startHour: 23, variant: AppThemeVariant.deepSea);

  const TimeOfDaySlot({required this.startHour, required this.variant});

  /// Local hour this slot begins, inclusive. It runs until the next slot's
  /// [startHour]; [lateNight] wraps past midnight into [morning].
  final int startHour;

  /// The look this slice of the day wears.
  final AppThemeVariant variant;
}

/// The clock half of AUTO mode: which slot a local time falls in, and how long
/// until it stops being true.
///
/// Both answers are pure functions of a [DateTime] handed in, never of
/// `DateTime.now()` read inside — so every boundary in the day is walked in a
/// loop by the tests instead of waiting for one to arrive.
abstract final class AutoTheme {
  /// Boundaries in ascending order. Derived from the enum rather than repeated,
  /// so a slot cannot be added without moving them.
  static final List<int> boundaryHours = [
    for (final slot in TimeOfDaySlot.values) slot.startHour,
  ];

  /// Which slot [local] falls in. Total: an hour before the first boundary
  /// belongs to [TimeOfDaySlot.lateNight], which is the slot that wraps.
  static TimeOfDaySlot slotAt(DateTime local) {
    var current = TimeOfDaySlot.lateNight;
    for (final slot in TimeOfDaySlot.values) {
      if (local.hour >= slot.startHour) current = slot;
    }
    return current;
  }

  /// The look AUTO mode resolves to at [local].
  static AppThemeVariant variantAt(DateTime local) => slotAt(local).variant;

  /// How long until [local] falls in a different slot.
  ///
  /// A HINT FOR A TIMER, NOT A GUARANTEE. Local days are 23 or 25 hours long
  /// twice a year and a phone's clock can move under us, so the caller always
  /// re-reads the clock when the timer fires rather than trusting that this
  /// landed exactly on a boundary. Floored at one minute so a clock that
  /// jumps backwards cannot produce a zero-delay timer that spins.
  static Duration timeUntilNextSlot(DateTime local) {
    final next = _nextBoundaryAfter(local);
    final remaining = next.difference(local);
    return remaining > _minimum ? remaining : _minimum;
  }

  static const Duration _minimum = Duration(minutes: 1);

  static DateTime _nextBoundaryAfter(DateTime local) {
    for (final hour in boundaryHours) {
      if (hour > local.hour) {
        return DateTime(local.year, local.month, local.day, hour);
      }
    }
    // Past the last boundary of the day: the next one is tomorrow's first.
    // `DateTime` normalises an out-of-range day, so month and year roll over
    // on their own.
    return DateTime(
      local.year,
      local.month,
      local.day + 1,
      boundaryHours.first,
    );
  }
}

/// What the player picked in Settings: one fixed [AppThemeVariant], or AUTO.
///
/// A small union rather than a ninth enum value, because "auto" is not a look —
/// it resolves to one of the eight, and every consumer that wants a palette
/// wants that resolved answer instead. Persisted as ONE string ([id]), the
/// same single-key shape as every other preference in `UiSettingsStore`.
final class AppThemeSelection {
  const AppThemeSelection.auto() : variant = null;

  const AppThemeSelection.fixed(AppThemeVariant this.variant);

  /// Null exactly when this is AUTO.
  final AppThemeVariant? variant;

  bool get isAuto => variant == null;

  /// Reserved id for AUTO. No [AppThemeVariant] may use it —
  /// `app_theme_variant_test.dart` asserts that.
  static const String autoId = 'auto';

  static const AppThemeSelection defaultSelection = AppThemeSelection.auto();

  String get id => variant?.id ?? autoId;

  /// Degrades an unrecognised id to [defaultSelection], like every other
  /// `fromId` in this codebase. Null (never set) lands there too, which is
  /// what makes AUTO the out-of-the-box behaviour.
  static AppThemeSelection fromId(String? id) {
    if (id == null || id == autoId) return defaultSelection;
    for (final variant in AppThemeVariant.values) {
      if (variant.id == id) return AppThemeSelection.fixed(variant);
    }
    return defaultSelection;
  }

  /// The look this selection means at [local]. AUTO asks the clock; a fixed
  /// pick ignores it.
  AppThemeVariant resolve(DateTime local) =>
      variant ?? AutoTheme.variantAt(local);

  @override
  bool operator ==(Object other) =>
      other is AppThemeSelection && other.variant == variant;

  @override
  int get hashCode => variant.hashCode;

  @override
  String toString() => 'AppThemeSelection($id)';
}
