import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/data/remote/cloud_account_repository.dart';
import 'package:word_search_master/domain/progression/account_merge.dart';
import 'package:word_search_master/domain/progression/day_key.dart';
import 'package:word_search_master/domain/text/language.dart';

/// Parsing the `users/{uid}` document.
///
/// Every case here is a MALFORMED document, because that is where the risk
/// is: this parses data written by another device, possibly by a newer build,
/// possibly half-written by an interrupted sync. A parse that threw would
/// abort the merge and — since the merge is what carries the guest's progress
/// forward — is exactly how a player loses everything to one bad field.
void main() {
  test('a full document round-trips into a snapshot', () {
    final snapshot = CloudAccountCodec.decode({
      'coinBalance': 250,
      'levels': [
        {
          'lang': 'en',
          'level': 3,
          'stars': 2,
          'bestScore': 400,
          'hintsUsed': 1,
          'completedAt': 111,
        },
      ],
      'dailies': [
        {
          'lang': 'ur',
          'date': '2026-03-04',
          'score': 90,
          'stars': 3,
          'completedAt': 222,
        },
      ],
      'achievements': [
        {'id': 'collection:en:animals', 'progress': 25, 'unlockedAt': 333},
      ],
      'streak': {
        'current': 5,
        'longest': 9,
        'lastActiveDay': '2026-03-04',
        'lastPlayedDay': '2026-03-04',
        'freezes': 1,
      },
    });

    expect(snapshot.coinBalance, 250);
    expect(snapshot.levels['en/3']!.stars, 2);
    expect(snapshot.dailies['2026-03-04/ur']!.score, 90);
    expect(snapshot.achievements['collection:en:animals']!.unlockedAt, 333);
    expect(snapshot.streak.current, 5);
    expect(snapshot.streak.lastActiveDay, DayKey.parse('2026-03-04'));
  });

  test('a null document is empty, not an error', () {
    expect(CloudAccountCodec.decode(null).isEmpty, isTrue);
  });

  test('an empty document is empty', () {
    expect(CloudAccountCodec.decode(const {}).isEmpty, isTrue);
  });

  test('doubles are accepted — Firestore may return either', () {
    // A value written by a JS Cloud Function arrives as a double even when it
    // is conceptually an int.
    final snapshot = CloudAccountCodec.decode({
      'coinBalance': 250.0,
      'levels': [
        {'lang': 'en', 'level': 3.0, 'stars': 2.0, 'bestScore': 400.0},
      ],
    });

    expect(snapshot.coinBalance, 250);
    expect(snapshot.levels['en/3']!.stars, 2);
  });

  test('a level with an unknown language is skipped, not fatal', () {
    final snapshot = CloudAccountCodec.decode({
      'levels': [
        {'lang': 'fr', 'level': 1, 'stars': 3},
        {'lang': 'en', 'level': 2, 'stars': 1},
      ],
    });

    expect(snapshot.levels.keys, ['en/2']);
  });

  test('a malformed date is skipped, not fatal', () {
    final snapshot = CloudAccountCodec.decode({
      'dailies': [
        {'lang': 'en', 'date': 'not-a-date', 'score': 1},
        {'lang': 'en', 'date': '2026-03-04', 'score': 2},
      ],
    });

    expect(snapshot.dailies.keys, ['2026-03-04/en']);
  });

  test('missing numeric fields default to zero rather than throwing', () {
    final snapshot = CloudAccountCodec.decode({
      'levels': [
        {'lang': 'en', 'level': 1},
      ],
    });

    final level = snapshot.levels['en/1']!;
    expect(level.stars, 0);
    expect(level.bestScore, 0);
    expect(level.language, Language.english);
  });

  test('wrong-typed containers degrade to empty', () {
    // A document where `levels` is a string, not a list — the shape a
    // half-written or newer-schema document could arrive in.
    final snapshot = CloudAccountCodec.decode({
      'levels': 'unexpected',
      'streak': 'unexpected',
      'coinBalance': 'unexpected',
    });

    expect(snapshot.levels, isEmpty);
    expect(snapshot.coinBalance, 0);
    expect(snapshot.streak.current, 0);
  });

  test('an achievement with no id is skipped', () {
    final snapshot = CloudAccountCodec.decode({
      'achievements': [
        {'progress': 5},
        {'id': '', 'progress': 5},
        {'id': 'real', 'progress': 5},
      ],
    });

    expect(snapshot.achievements.keys, ['real']);
  });

  test('NoopCloudAccountRepository always reads empty', () async {
    const repo = NoopCloudAccountRepository();

    expect((await repo.readSnapshot('any-uid')).isEmpty, isTrue);
  });

  test('a decoded snapshot merges as a no-op when empty', () {
    // The property that makes "empty on failure" safe: an empty remote
    // preserves the local side exactly.
    final local = AccountSnapshot(
      levels: {
        'en/1': LevelSnapshot(
          language: Language.english,
          level: 1,
          stars: 3,
          bestScore: 500,
          hintsUsed: 0,
          completedAt: 1,
        ),
      },
      coinBalance: 100,
    );

    final merged = AccountMerge.merge(
      local: local,
      remote: CloudAccountCodec.decode(null),
    );

    expect(merged.levels, local.levels);
    expect(merged.coinsToCredit, 0);
  });
}
