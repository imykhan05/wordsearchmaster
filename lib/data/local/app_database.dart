import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../services/diagnostics/error_reporter.dart';
import 'integrity.dart';
import 'integrity_tags.dart';
import 'tables.dart';

part 'app_database.g.dart';

/// The local database — THE source of truth (Ch10, CLAUDE.md → Architecture).
///
/// Nothing in the read path ever touches the network. Repositories stream
/// from here; the outbox carries writes cloudward in the background, and the
/// game stays completely playable with the radio off.
@DriftDatabase(
  tables: [
    Profile,
    LevelProgress,
    DailyResults,
    CoinsLedger,
    Achievements,
    Outbox,
    KvSettings,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(
    super.executor, {
    ErrorReporter reporter = const NoopErrorReporter(),
    // The lint below suggests `this._reporter`, which Dart rejects outright:
    // a named parameter may not be private.
    // ignore: prefer_initializing_formals
  }) : _reporter = reporter;

  final ErrorReporter _reporter;

  /// v1 → the first schema draft, which stored coins as a COLUMN on profile.
  /// v2 → the Ch10 schema: that column is gone and `coins_ledger` replaces it.
  ///
  /// v1 never reached a store, but the upgrade path is real code with a real
  /// test (`migration_test.dart`) rather than a comment promising it works.
  /// The migration it performs — turning a stored balance into an opening
  /// ledger entry — is exactly the transformation the append-only rule
  /// implies, so it is worth having proven before a v3 needs the same
  /// machinery under load.
  @override
  int get schemaVersion => 2;

  /// `coins_ledger` is append-only, and that is enforced HERE rather than by
  /// the repository simply declining to write an UPDATE.
  ///
  /// The threat is a player with a SQLite editor, not a careless teammate:
  /// a repository-level convention stops neither. A trigger stops both, and
  /// it keeps the guarantee true for the migration code and for any future
  /// prompt that adds a ledger writer without reading this file first.
  static const List<String> appendOnlyLedgerTriggers = [
    '''
CREATE TRIGGER IF NOT EXISTS coins_ledger_no_update
BEFORE UPDATE ON ${LocalTables.coinsLedger}
BEGIN SELECT RAISE(ABORT, 'coins_ledger is append-only'); END
''',
    '''
CREATE TRIGGER IF NOT EXISTS coins_ledger_no_delete
BEFORE DELETE ON ${LocalTables.coinsLedger}
BEGIN SELECT RAISE(ABORT, 'coins_ledger is append-only'); END
''',
  ];

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
      await _createAppendOnlyTriggers();
    },
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await _migrateV1ToV2(migrator);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      // Resolve the key material LOCALLY here rather than through
      // [integrity]. That getter memoises a Future whose query cannot
      // complete until the database finishes opening — and this callback is
      // part of opening it, so awaiting it here deadlocks the connection
      // outright (no error, no timeout, just a process that never returns).
      final installId = await ensureInstallId();
      await _ensureProfileRow(RowIntegrity.forInstall(installId));
    },
  );

  Future<void> _createAppendOnlyTriggers() async {
    for (final statement in appendOnlyLedgerTriggers) {
      await customStatement(statement);
    }
  }

  // -------------------------------------------------------------------------
  // Integrity key
  // -------------------------------------------------------------------------

  Future<RowIntegrity>? _integrity;

  /// The row-integrity helper for this install, resolved once and reused.
  ///
  /// Memoised as a FUTURE, not as a resolved value: two repositories built in
  /// the same tick would otherwise both miss the cache and race to generate
  /// two different install ids, and the loser's rows would all fail their
  /// checks forever after.
  Future<RowIntegrity> integrity() =>
      _integrity ??= ensureInstallId().then(RowIntegrity.forInstall);

  /// Reads the install id, generating and storing one on first launch.
  ///
  /// This row is the one row in the database with no integrity tag, and it
  /// cannot have one — it is an input to the key every other tag is computed
  /// with. See [KvKeys.installId] for why that exemption is safe.
  Future<String> ensureInstallId() async {
    final existing = await (select(
      kvSettings,
    )..where((row) => row.key.equals(KvKeys.installId))).getSingleOrNull();
    if (existing != null && existing.value.isNotEmpty) return existing.value;

    final generated = _generateInstallId();
    await into(kvSettings).insertOnConflictUpdate(
      KvSettingsCompanion.insert(
        key: KvKeys.installId,
        value: generated,
        integrityTag: '',
      ),
    );
    return generated;
  }

  /// 128 bits from the platform CSPRNG.
  ///
  /// `Random.secure()` rather than `Random()`: a predictable install id makes
  /// the derived key predictable, which is the one thing that would take this
  /// scheme from "tamper evident" (its honest claim) to "trivially forgeable".
  static String _generateInstallId() {
    final random = Random.secure();
    return [
      for (var i = 0; i < 16; i++)
        random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
  }

  // -------------------------------------------------------------------------
  // Row ids
  // -------------------------------------------------------------------------

  /// The next id for an auto-increment table, allocated EXPLICITLY.
  ///
  /// Both tagged auto-increment tables need their id before the tag can be
  /// computed, because the id is the row's address and the tag binds to it
  /// (otherwise a ledger row could simply be duplicated for double the
  /// coins). Letting SQLite assign the id would mean inserting first and
  /// patching the tag afterwards — which `coins_ledger`'s append-only trigger
  /// forbids outright, and which would leave a window where a row exists with
  /// a tag that does not verify.
  ///
  /// Safe because callers run it inside the same transaction as the insert,
  /// and SQLite has exactly one writer at a time.
  Future<int> nextRowId(String table) async {
    // Interpolated rather than bound: SQLite cannot parameterise an
    // identifier. Only ever called with a `LocalTables` constant.
    final row = await customSelect(
      'SELECT COALESCE(MAX(id), 0) + 1 AS next_id FROM $table',
    ).getSingle();
    return row.read<int>('next_id');
  }

  // -------------------------------------------------------------------------
  // Singleton profile
  // -------------------------------------------------------------------------

  /// The one and only profile row id.
  static const int profileId = 1;

  /// Takes [tags] as an argument rather than reading [integrity]: this runs
  /// inside `beforeOpen`, where that memoised getter would deadlock.
  Future<void> _ensureProfileRow(RowIntegrity tags) async {
    final existing = await (select(
      profile,
    )..where((row) => row.id.equals(profileId))).getSingleOrNull();
    if (existing != null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    await into(profile).insert(
      ProfileCompanion.insert(
        id: Value(profileId),
        createdAt: now,
        lastSeenAt: now,
        integrityTag: RowTags.profile(
          tags,
          id: profileId,
          displayName: null,
          cloudUserId: null,
          createdAt: now,
          lastSeenAt: now,
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // v1 → v2
  // -------------------------------------------------------------------------

  /// Replaces v1's `profile.coins` column with an opening `coins_ledger` row.
  ///
  /// THE SUBTLE PART — a migration must not launder a tamper. The v1 balance
  /// is only carried across if the v1 row still verifies under the v1 field
  /// list. Skipping that check would hand a cheater a free amnesty: edit
  /// `coins` on the old schema, upgrade, and the migration would re-tag the
  /// forged number into a perfectly valid ledger entry. A row that fails is
  /// reset to defaults instead — the Ch10 rule for any failed check, and the
  /// reason this reads the OLD tag shape rather than just re-signing whatever
  /// it finds.
  Future<void> _migrateV1ToV2(Migrator migrator) async {
    await migrator.createTable(coinsLedger);

    final tags = RowIntegrity.forInstall(await ensureInstallId());
    final now = DateTime.now().millisecondsSinceEpoch;

    final rows = await customSelect(
      'SELECT id, display_name, cloud_user_id, created_at, last_seen_at, '
      'coins, integrity_tag FROM ${LocalTables.profile}',
    ).get();

    for (final row in rows) {
      final id = row.read<int>('id');
      final displayName = row.readNullable<String>('display_name');
      final cloudUserId = row.readNullable<String>('cloud_user_id');
      final createdAt = row.read<int>('created_at');
      final lastSeenAt = row.read<int>('last_seen_at');
      final coins = row.read<int>('coins');

      final wasIntact = tags.verify(
        table: LocalTables.profile,
        rowKey: '$id',
        // The v1 field list — profile signed its coin balance back then.
        fields: [displayName, cloudUserId, createdAt, lastSeenAt, coins],
        tag: row.read<String>('integrity_tag'),
      );

      if (!wasIntact) {
        _reporter.nonFatal(
          IntegrityViolation(table: LocalTables.profile, rowKey: '$id'),
          context: const {'stage': 'migration.v1_to_v2'},
        );
        await _resetProfileRow(tags, id: id, now: now);
        continue;
      }

      if (coins != 0) {
        final ledgerId = await nextRowId(LocalTables.coinsLedger);
        await into(coinsLedger).insert(
          CoinsLedgerCompanion.insert(
            id: Value(ledgerId),
            delta: coins,
            reason: 'migration:v1_balance',
            createdAt: now,
            integrityTag: RowTags.coinsLedger(
              tags,
              id: ledgerId,
              delta: coins,
              reason: 'migration:v1_balance',
              createdAt: now,
            ),
          ),
        );
      }

      // Re-sign under the v2 field list, which no longer includes coins.
      // Done BEFORE the column drop below so the table rebuild copies the
      // already-correct tag across.
      await customUpdate(
        'UPDATE ${LocalTables.profile} SET integrity_tag = ? WHERE id = ?',
        variables: [
          Variable<String>(
            RowTags.profile(
              tags,
              id: id,
              displayName: displayName,
              cloudUserId: cloudUserId,
              createdAt: createdAt,
              lastSeenAt: lastSeenAt,
            ),
          ),
          Variable<int>(id),
        ],
        updates: {profile},
      );
    }

    // Rebuilds `profile` from its current Dart definition, copying the
    // columns that still exist — which drops `coins`.
    await migrator.alterTable(TableMigration(profile));

    await _createAppendOnlyTriggers();
  }

  Future<void> _resetProfileRow(
    RowIntegrity tags, {
    required int id,
    required int now,
  }) async {
    await customUpdate(
      'UPDATE ${LocalTables.profile} SET display_name = NULL, '
      'cloud_user_id = NULL, created_at = ?, last_seen_at = ?, coins = 0, '
      'integrity_tag = ? WHERE id = ?',
      variables: [
        Variable<int>(now),
        Variable<int>(now),
        Variable<String>(
          RowTags.profile(
            tags,
            id: id,
            displayName: null,
            cloudUserId: null,
            createdAt: now,
            lastSeenAt: now,
          ),
        ),
        Variable<int>(id),
      ],
      updates: {profile},
    );
  }
}

/// The app's database handle. Opened once, closed when the app dies.
@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) {
  final database = AppDatabase(
    driftDatabase(name: 'wsm'),
    reporter: ref.watch(errorReporterProvider),
  );
  ref.onDispose(database.close);
  return database;
}

/// The integrity helper, resolved from the install id.
@Riverpod(keepAlive: true)
Future<RowIntegrity> rowIntegrity(Ref ref) =>
    ref.watch(appDatabaseProvider).integrity();
