/// Reading another device's account out of Firestore (P13).
///
/// ---------------------------------------------------------------------------
/// SCOPE: THE READ SIDE ONLY, AND ONLY FOR THE MERGE
///
/// P14 owns cloud sync properly — the outbox drain, the Cloud Function that
/// replays a score submission and writes the authoritative number (Ch08), and
/// the Firestore rules around all of it. This file exists because P13's merge
/// needs SOMETHING to merge: `linkWithCredential` coming back with
/// `credential-already-in-use` means the Google account already has cloud
/// progress, and without a way to read it, "merge" degrades to "keep local",
/// which preserves the guest's data but silently abandons the account they
/// just signed into.
///
/// So the contract here is deliberately narrow: given a uid, return that
/// account's snapshot. No writes, no listeners, no schema opinions beyond the
/// one document shape below — those are P14's to design.
///
/// The document shape is `users/{uid}` with three arrays and two scalars,
/// chosen so ONE read serves a merge. A per-level subcollection would be the
/// natural Firestore modelling, and is what P14 will likely want for
/// incremental sync — but it would make this a fan-out of hundreds of reads
/// on the one screen where the player is already waiting on a sign-in sheet.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/progression/account_merge.dart';
import '../../domain/progression/day_key.dart';
import '../../domain/progression/streak.dart';
import '../../domain/text/language.dart';

part 'cloud_account_repository.g.dart';

/// Overridden in `bootstrap.dart` with the Firestore-backed implementation
/// once Firebase is up. Defaults to Noop so every widget test and every
/// unconfigured checkout reads an empty cloud rather than needing a project.
@Riverpod(keepAlive: true)
CloudAccountRepository cloudAccountRepository(Ref ref) =>
    const NoopCloudAccountRepository();

/// Reads a cloud account.
abstract interface class CloudAccountRepository {
  /// The account stored under [uid], or [AccountSnapshot.empty] when there is
  /// nothing there or it could not be read.
  ///
  /// NEVER throws, and empty-on-failure is load-bearing: `AccountMerge.merge`
  /// against an empty remote is exactly a no-op, so a failed read degrades to
  /// "keep everything local" — the safe direction. A throw here would
  /// propagate into the sign-in flow and turn a network blip into a visible
  /// error on a screen the player just tapped through.
  Future<AccountSnapshot> readSnapshot(String uid);
}

/// There is no cloud. Always empty.
///
/// The binding whenever Firebase is unavailable — which, per
/// `app/config/firebase_options.dart`, includes every unconfigured checkout.
final class NoopCloudAccountRepository implements CloudAccountRepository {
  const NoopCloudAccountRepository();

  @override
  Future<AccountSnapshot> readSnapshot(String uid) async =>
      AccountSnapshot.empty;
}

/// Parses the `users/{uid}` document shape into a snapshot.
///
/// Split out from the Firestore client so the parsing — which is where the
/// bugs live — is testable without a Firestore instance. Every field is
/// defensive: a document written by a NEWER build, or half-written by an
/// interrupted sync, must degrade to "that part is missing" rather than
/// throwing and losing the whole merge.
abstract final class CloudAccountCodec {
  static AccountSnapshot decode(Map<String, Object?>? document) {
    if (document == null) return AccountSnapshot.empty;

    return AccountSnapshot(
      levels: _decodeLevels(document['levels']),
      dailies: _decodeDailies(document['dailies']),
      achievements: _decodeAchievements(document['achievements']),
      coinBalance: _asInt(document['coinBalance']) ?? 0,
      streak: _decodeStreak(document['streak']),
    );
  }

  static Map<String, LevelSnapshot> _decodeLevels(Object? raw) {
    final result = <String, LevelSnapshot>{};
    for (final entry in _asMapList(raw)) {
      final language = _language(entry['lang']);
      final level = _asInt(entry['level']);
      if (language == null || level == null) continue;
      final snapshot = LevelSnapshot(
        language: language,
        level: level,
        stars: _asInt(entry['stars']) ?? 0,
        bestScore: _asInt(entry['bestScore']) ?? 0,
        hintsUsed: _asInt(entry['hintsUsed']) ?? 0,
        completedAt: _asInt(entry['completedAt']) ?? 0,
      );
      result[snapshot.key] = snapshot;
    }
    return result;
  }

  static Map<String, DailySnapshot> _decodeDailies(Object? raw) {
    final result = <String, DailySnapshot>{};
    for (final entry in _asMapList(raw)) {
      final language = _language(entry['lang']);
      final date = entry['date'];
      if (language == null || date is! String) continue;
      final DayKey day;
      try {
        day = DayKey.parse(date);
      } on FormatException {
        continue;
      }
      final snapshot = DailySnapshot(
        day: day,
        language: language,
        score: _asInt(entry['score']) ?? 0,
        stars: _asInt(entry['stars']) ?? 0,
        completedAt: _asInt(entry['completedAt']) ?? 0,
      );
      result[snapshot.key] = snapshot;
    }
    return result;
  }

  static Map<String, AchievementSnapshot> _decodeAchievements(Object? raw) {
    final result = <String, AchievementSnapshot>{};
    for (final entry in _asMapList(raw)) {
      final id = entry['id'];
      if (id is! String || id.isEmpty) continue;
      result[id] = AchievementSnapshot(
        id: id,
        progress: _asInt(entry['progress']) ?? 0,
        unlockedAt: _asInt(entry['unlockedAt']),
      );
    }
    return result;
  }

  static StreakState _decodeStreak(Object? raw) {
    if (raw is! Map) return StreakState.empty;
    final map = raw.cast<String, Object?>();
    return StreakState(
      current: _asInt(map['current']) ?? 0,
      longest: _asInt(map['longest']) ?? 0,
      lastActiveDay: _day(map['lastActiveDay']),
      lastPlayedDay: _day(map['lastPlayedDay']),
      freezes: _asInt(map['freezes']) ?? 0,
    );
  }

  static List<Map<String, Object?>> _asMapList(Object? raw) => raw is List
      ? [
          for (final entry in raw)
            if (entry is Map) entry.cast<String, Object?>(),
        ]
      : const [];

  /// Firestore hands back numbers as `int` or `double` depending on how they
  /// were written; a JS-written value can arrive as either.
  static int? _asInt(Object? raw) => switch (raw) {
    final int value => value,
    final double value => value.round(),
    _ => null,
  };

  static Language? _language(Object? raw) {
    if (raw is! String) return null;
    for (final language in Language.values) {
      if (language.code == raw) return language;
    }
    return null;
  }

  static DayKey? _day(Object? raw) {
    if (raw is! String) return null;
    try {
      return DayKey.parse(raw);
    } on FormatException {
      return null;
    }
  }
}
