import 'package:drift/drift.dart';

/// The Ch10 local schema. Drift is the SOURCE OF TRUTH — the network is
/// background sync only (CLAUDE.md → Architecture), so every read path in the
/// app resolves here and the game stays fully playable offline.
///
/// ---------------------------------------------------------------------------
/// TABLE NAMES ARE PINNED, NOT INFERRED
///
/// Drift would derive `level_progress` from `LevelProgress` on its own, but
/// the table name is part of the HMAC input (see `integrity.dart` — it binds a
/// row's tag to its address so rows cannot be copied between tables). A rename
/// would therefore invalidate every tag on every device and read as "everyone
/// tampered".
///
/// Drift requires each `tableName` override to be a literal, so these cannot
/// be the single source both sides read. `local_schema_test.dart` closes that
/// gap by asserting every generated `actualTableName` against the constant
/// below — a class rename that shifts a table name fails there rather than in
/// the field, six months later, as a wave of integrity violations.
abstract final class LocalTables {
  static const String profile = 'profile';
  static const String levelProgress = 'level_progress';
  static const String dailyResults = 'daily_results';
  static const String coinsLedger = 'coins_ledger';
  static const String achievements = 'achievements';
  static const String outbox = 'outbox';
  static const String kvSettings = 'kv_settings';
}

/// The player. Exactly one row, `id = 1`.
///
/// A singleton table rather than loose keys in [KvSettings] so the fields are
/// typed and so the whole profile carries ONE integrity tag — a display name
/// and the cloud user id it is paired with cannot be separated by editing one
/// of them.
@DataClassName('ProfileRow')
class Profile extends Table {
  @override
  String get tableName => 'profile';

  IntColumn get id => integer()();

  TextColumn get displayName => text().nullable()();

  /// Firebase uid once anonymous auth lands (P13). Null while the player is
  /// still a pure local guest.
  TextColumn get cloudUserId => text().nullable()();

  IntColumn get createdAt => integer()();
  IntColumn get lastSeenAt => integer()();

  TextColumn get integrityTag => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// One row per level the player has finished.
///
/// KEYED BY (language, level), not by level alone: level 47 in Urdu and level
/// 47 in Hindi are different puzzles built from different content packs
/// (P10), so they earn stars independently. Collapsing them onto one key
/// would let finishing an English level silently unlock the Urdu one.
@DataClassName('LevelProgressRow')
class LevelProgress extends Table {
  @override
  String get tableName => 'level_progress';

  TextColumn get languageCode => text()();
  IntColumn get level => integer()();

  IntColumn get stars => integer()();
  IntColumn get bestScore => integer()();
  IntColumn get hintsUsed => integer()();
  IntColumn get completedAt => integer()();

  TextColumn get integrityTag => text()();

  @override
  Set<Column<Object>> get primaryKey => {languageCode, level};

  /// Cheap guards that also make a hand-edited database fail at the SQLite
  /// layer before it ever reaches the integrity check. Defence in depth: a
  /// tamper that gets the tag right but the value absurd still bounces.
  @override
  List<String> get customConstraints => const [
    'CHECK (stars BETWEEN 0 AND 3)',
    'CHECK (best_score >= 0)',
    'CHECK (hints_used >= 0)',
  ];
}

/// The once-a-day puzzle result — the same puzzle for every player (Ch12).
@DataClassName('DailyResultRow')
class DailyResults extends Table {
  @override
  String get tableName => 'daily_results';

  /// `yyyy-MM-dd`, always UTC. A local-date key would let a player in
  /// Karachi and one in Delhi disagree about which day it is and replay the
  /// same daily twice.
  TextColumn get date => text()();
  TextColumn get languageCode => text()();

  IntColumn get score => integer()();
  IntColumn get stars => integer()();
  IntColumn get completedAt => integer()();

  TextColumn get integrityTag => text()();

  @override
  Set<Column<Object>> get primaryKey => {date, languageCode};
}

/// APPEND-ONLY coin movements. The balance is the SUM of these, never a
/// stored number (Ch10).
///
/// Why a ledger and not a `coins` column:
///
///   * a wrong balance is debuggable — the row that caused it is still there,
///     with the reason string that wrote it;
///   * a lost or double-applied reward shows up as a missing or duplicated
///     row rather than as a number nobody can explain;
///   * cheating is VISIBLE. Editing a stored balance leaves no trace; here a
///     forged row fails its tag and is excluded from the sum while staying on
///     disk as evidence.
///
/// "Append-only" is enforced by SQLite triggers (see `AppDatabase`), not by
/// convention — the repository has no update or delete path, and neither does
/// anyone with a SQLite editor.
@DataClassName('CoinsLedgerRow')
class CoinsLedger extends Table {
  @override
  String get tableName => 'coins_ledger';

  IntColumn get id => integer().autoIncrement()();

  /// Signed. Positive earns, negative spends.
  IntColumn get delta => integer()();

  /// Why this movement happened, e.g. `level_complete:en:47`. Free text on
  /// purpose: it is read by a human debugging a support ticket, not parsed.
  TextColumn get reason => text()();

  IntColumn get createdAt => integer()();

  TextColumn get integrityTag => text()();

  @override
  List<String> get customConstraints => const [
    // A zero-delta row is always a bug: it moves nothing and only pads the
    // ledger a human has to read.
    'CHECK (delta != 0)',
    'CHECK (length(reason) > 0)',
  ];
}

/// Unlockables (Ch12). `unlockedAt` null means "in progress".
@DataClassName('AchievementRow')
class Achievements extends Table {
  @override
  String get tableName => 'achievements';

  TextColumn get id => text()();
  IntColumn get progress => integer().withDefault(const Constant(0))();
  IntColumn get unlockedAt => integer().nullable()();

  TextColumn get integrityTag => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// The sync queue. Ch10's outbox pattern.
///
/// Every mutation that must eventually reach the cloud writes its game-state
/// row AND its outbox row in ONE transaction (CLAUDE.md → Never do: never
/// block gameplay on a network call). Either both land or neither does, so
/// the queue can never drift out of step with the state it describes.
///
/// WHAT THE TAG COVERS, AND WHAT IT DELIBERATELY DOES NOT:
///
/// The tag signs [kind], [payload] and [createdAt] — the submission itself,
/// which is immutable once queued. It does NOT sign [attempts] or
/// [lastAttemptAt], because the sync worker bumps those on every retry; if
/// they were signed, either every retry would need a re-tag (turning a
/// harmless counter into a write amplification problem) or a perfectly normal
/// second attempt would look like tampering. A player who edits their own
/// retry counter gains nothing; one who edits the payload is caught.
@DataClassName('OutboxRow')
class Outbox extends Table {
  @override
  String get tableName => 'outbox';

  IntColumn get id => integer().autoIncrement()();

  /// An `OutboxKind` name.
  ///
  /// Validated on READ rather than by a SQL `CHECK (kind IN (...))`: the
  /// allowed set grows every time a new mutation learns to sync, and a check
  /// constraint would turn each of those into a schema migration. The sync
  /// worker parses this back to the enum and reports+skips anything it does
  /// not recognise, which is also the right behaviour for a row written by a
  /// NEWER build after a downgrade.
  TextColumn get kind => text()();

  /// JSON. For a level completion this carries the ordered `ScoreEvent` list,
  /// because Ch08's Cloud Function recomputes the score by replaying it and
  /// writes ITS answer, never the client's number (P14).
  TextColumn get payload => text()();

  IntColumn get createdAt => integer()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  IntColumn get lastAttemptAt => integer().nullable()();

  /// An `OutboxStatus` name (P16). Parsed back on read, like [kind].
  ///
  /// Defaulted rather than required so the v2→v3 migration can add the column
  /// without touching a single existing row: every queued submission written
  /// before P16 existed is `pending`, which is exactly what it was.
  TextColumn get status => text().withDefault(const Constant('pending'))();

  /// When this row becomes eligible again, in millis (P16).
  ///
  /// NULL means "now" — a fresh row, or one whose backoff has been cleared by
  /// a force-drain. Stored as an absolute instant rather than a delay because
  /// the queue is rescanned on every connectivity change, and a delay would
  /// have to be re-derived against a clock on each of those scans.
  IntColumn get nextRetryAt => integer().nullable()();

  TextColumn get integrityTag => text()();

  @override
  List<String> get customConstraints => const [
    'CHECK (length(payload) > 0)',
    'CHECK (attempts >= 0)',
  ];
}

/// Small typed values that are NOT UI preferences.
///
/// The line, from CLAUDE.md → Never do: `shared_preferences` is for
/// non-sensitive UI toggles (sound, haptics, selected language) and nothing
/// else. Anything that affects game state or sync — the install id, sync
/// cursors, FTUE completion — lives here, in the integrity-tagged database.
@DataClassName('KvSettingRow')
class KvSettings extends Table {
  @override
  String get tableName => 'kv_settings';

  TextColumn get key => text()();
  TextColumn get value => text()();

  /// Empty for the exempt install-id row — see `KvKeys.installId`.
  TextColumn get integrityTag => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

/// Reserved [KvSettings] keys.
abstract final class KvKeys {
  /// The per-install salt half of the integrity key.
  ///
  /// EXEMPT FROM INTEGRITY CHECKING, and it has to be: it is an input to the
  /// key that every other tag is computed with, so it cannot sign itself.
  ///
  /// That exemption is safe because the failure mode is closed rather than
  /// open. Editing this value does not forge anything — it changes the
  /// derived key, so EVERY other row in the database stops verifying at once
  /// and is discarded. An attacker gains nothing; a player who somehow does
  /// it loses local progress and re-syncs from the cloud. The value is an
  /// identifier, never a secret (see the `integrity.dart` header).
  static const String installId = 'install_id';

  /// Last time a full cloud sync completed, millis since epoch.
  static const String lastSyncAt = 'last_sync_at';

  /// Prefix for one cached leaderboard per board id (P16).
  ///
  /// A PREFIX rather than a single key, because the board list is open-ended
  /// — `weekly_*` and `daily_*` grow forever (P14) — and one blob holding all
  /// of them would be rewritten in full every time any one board refreshed.
  static const String leaderboardCachePrefix = 'leaderboard_cache:';

  /// The streak and its freezes (P11), as the JSON `StreakState` encodes to.
  ///
  /// A KV row rather than an eighth table, and deliberately: it is a SINGLE
  /// value with no key space to query, so a table would buy nothing and cost a
  /// schema migration. It carries an integrity tag like any other row — a
  /// streak is game state and Ch02 makes it prominent enough to be worth
  /// forging, which is exactly why CLAUDE.md forbids `shared_preferences`
  /// here.
  static const String streakState = 'streak_state';

  /// The highest day the app has ever resolved, `yyyy-MM-dd`.
  ///
  /// The monotonic floor `services/time/trusted_clock.dart` uses to refuse a
  /// clock that has been wound backwards. Tagged, because an untagged
  /// high-water mark is one string edit away from being no defence at all.
  static const String dayHighWaterMark = 'day_high_water_mark';
}
