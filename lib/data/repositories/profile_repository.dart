import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../services/diagnostics/error_reporter.dart';
import '../local/app_database.dart';
import '../local/integrity_tags.dart';
import '../local/outbox_kind.dart';
import '../local/tables.dart';
import 'local_repository.dart';

part 'profile_repository.g.dart';

/// The player's own record. One row, created on first open.
final class ProfileRepository extends LocalRepository {
  ProfileRepository({
    required super.database,
    required super.integrity,
    required super.reporter,
    super.clock,
  });

  /// The profile, or null while it fails its integrity check.
  ///
  /// Null rather than a thrown error, and null rather than a half-trusted row:
  /// the caller renders the same empty state it would for a brand-new player,
  /// which is exactly the "reset to default" behaviour Ch10 asks for and is
  /// invisible to the person holding the phone.
  Stream<ProfileRow?> watchProfile() {
    final query = database.select(database.profile)
      ..where((row) => row.id.equals(AppDatabase.profileId));

    return query.watchSingleOrNull().map(
      (row) => row != null && _isIntact(row) ? row : null,
    );
  }

  Future<void> updateDisplayName(String? displayName) =>
      _update(displayName: Value(displayName), enqueueSync: true);

  /// Links the local guest to a Firebase uid once auth lands (P13).
  Future<void> linkCloudUser(String cloudUserId) =>
      _update(cloudUserId: Value(cloudUserId), enqueueSync: true);

  /// Bumps `lastSeenAt`.
  ///
  /// Deliberately does NOT queue an outbox row: this fires on every cold
  /// start, and a sync queue that grows by one row per launch spends a
  /// player's data allowance telling the server something it can infer from
  /// any other request.
  Future<void> touchLastSeen() => _update(enqueueSync: false);

  Future<void> _update({
    Value<String?> displayName = const Value.absent(),
    Value<String?> cloudUserId = const Value.absent(),
    required bool enqueueSync,
  }) {
    final now = nowMillis;

    return database.transaction(() async {
      final existing =
          await (database.select(database.profile)
                ..where((row) => row.id.equals(AppDatabase.profileId)))
              .getSingleOrNull();

      // A profile that fails its check is rebuilt from defaults rather than
      // edited, so a tampered field cannot survive by being left untouched.
      final trusted = existing != null && _isIntact(existing) ? existing : null;

      final nextDisplayName = displayName.present
          ? displayName.value
          : trusted?.displayName;
      final nextCloudUserId = cloudUserId.present
          ? cloudUserId.value
          : trusted?.cloudUserId;
      final createdAt = trusted?.createdAt ?? now;

      await database
          .into(database.profile)
          .insertOnConflictUpdate(
            ProfileCompanion.insert(
              id: const Value(AppDatabase.profileId),
              displayName: Value(nextDisplayName),
              cloudUserId: Value(nextCloudUserId),
              createdAt: createdAt,
              lastSeenAt: now,
              integrityTag: RowTags.profile(
                integrity,
                id: AppDatabase.profileId,
                displayName: nextDisplayName,
                cloudUserId: nextCloudUserId,
                createdAt: createdAt,
                lastSeenAt: now,
              ),
            ),
          );

      if (enqueueSync) {
        await enqueue(
          kind: OutboxKind.profileUpdate,
          createdAt: now,
          payload: {
            'displayName': nextDisplayName,
            'cloudUserId': nextCloudUserId,
          },
        );
      }
    });
  }

  bool _isIntact(ProfileRow row) => guard.accepts(
    table: LocalTables.profile,
    rowKey: '${row.id}',
    expected: RowTags.profile(
      integrity,
      id: row.id,
      displayName: row.displayName,
      cloudUserId: row.cloudUserId,
      createdAt: row.createdAt,
      lastSeenAt: row.lastSeenAt,
    ),
    stored: row.integrityTag,
  );
}

@Riverpod(keepAlive: true)
Future<ProfileRepository> profileRepository(Ref ref) async => ProfileRepository(
  database: ref.watch(appDatabaseProvider),
  integrity: await ref.watch(rowIntegrityProvider.future),
  reporter: ref.watch(errorReporterProvider),
);
