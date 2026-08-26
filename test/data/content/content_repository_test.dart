import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/data/content/content_repository.dart';
import 'package:word_search_master/domain/text/language.dart';

/// A bundle that serves canned strings, mirroring
/// `test/data/content/blocklist_loader_test.dart`'s `_FakeBundle` — content
/// tests should not depend on the shipped (large, native-review-pending)
/// asset contents for their day-to-day assertions.
class _FakeBundle extends CachingAssetBundle {
  _FakeBundle(this.files);

  final Map<String, String> files;

  @override
  Future<ByteData> load(String key) async {
    final contents = files[key];
    if (contents == null) throw FlutterError('missing asset: $key');
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(contents)));
  }
}

Map<String, Object?> _word({
  required String id,
  required String lang,
  required String word,
  String category = 'nature',
  int graphemes = 5,
  int difficulty = 2,
}) => {
  'id': id,
  'lang': lang,
  'word': word,
  'display': word,
  'roman': word,
  'en': word,
  'category': category,
  'graphemes': graphemes,
  'difficulty': difficulty,
  'hint': 'a hint',
};

Map<String, Object?> _levelJson({
  required int id,
  required String lang,
  required int seed,
  int gridSize = 6,
  int wordCount = 2,
  List<String> categoryPool = const ['nature'],
  String directionTier = 'starter',
  String theme = 'Nature',
}) => {
  'id': id,
  'lang': lang,
  'seed': seed,
  'gridSize': gridSize,
  'wordCount': wordCount,
  'categoryPool': categoryPool,
  'directionTier': directionTier,
  'theme': theme,
};

/// A fresh bundle every call — three separately-constructed bundles reading
/// the same canned bytes is the cheapest honest stand-in for "three
/// independent devices loading the same shipped assets".
_FakeBundle _bundle() => _FakeBundle({
  'assets/content/words_en.json': jsonEncode({
    'words': [
      _word(id: 'en_nature_001', lang: 'en', word: 'WATER'),
      _word(id: 'en_nature_002', lang: 'en', word: 'FIRE', graphemes: 4),
    ],
  }),
  'assets/content/words_hi.json': jsonEncode({
    'words': [
      _word(
        id: 'hi_nature_001',
        lang: 'hi',
        word: 'पानी',
        graphemes: 2,
        difficulty: 1,
      ),
    ],
  }),
  'assets/content/words_ur.json': jsonEncode({
    'words': [
      _word(
        id: 'ur_nature_001',
        lang: 'ur',
        word: 'پانی',
        graphemes: 2,
        difficulty: 1,
      ),
    ],
  }),
  'assets/content/levels.json': jsonEncode({
    'levels': [
      _levelJson(id: 1, lang: 'en', seed: 111),
      _levelJson(id: 1, lang: 'hi', seed: 111, wordCount: 1),
      _levelJson(id: 1, lang: 'ur', seed: 111, wordCount: 1),
      _levelJson(
        id: 300,
        lang: 'en',
        seed: 999,
        gridSize: 12,
        wordCount: 2,
        directionTier: 'all',
      ),
    ],
  }),
});

void main() {
  group('load + getLevel', () {
    test('parses every content asset and looks up a level', () async {
      final repo = await ContentRepository.load(bundle: _bundle());
      final level = repo.getLevel(1, Language.english);
      expect(level.id, 1);
      expect(level.language, Language.english);
      expect(level.seed, 111);
      expect(level.theme, 'Nature');
    });

    test('clamps an out-of-range id to the nearest real level', () async {
      final repo = await ContentRepository.load(bundle: _bundle());

      final tooHigh = repo.getLevel(9999, Language.english);
      expect(tooHigh.id, 300);
      expect(tooHigh.seed, 999);

      final tooLow = repo.getLevel(-5, Language.english);
      expect(tooLow.id, 1);
      expect(tooLow.seed, 111);
    });
  });

  group('getWordsForLevel', () {
    test('delegates to WordSelector against the right language pool', () async {
      final repo = await ContentRepository.load(bundle: _bundle());
      final level = repo.getLevel(1, Language.english);
      final words = repo.getWordsForLevel(level);

      expect(words, hasLength(level.wordCount));
      for (final entry in words) {
        expect(entry.lang, Language.english);
        expect(level.categoryPool, contains(entry.category));
      }
    });
  });

  group('getDailySeed — "same grid on three devices"', () {
    test('three independently-loaded repositories agree for the same date+language', () async {
      final repoA = await ContentRepository.load(bundle: _bundle());
      final repoB = await ContentRepository.load(bundle: _bundle());
      final repoC = await ContentRepository.load(bundle: _bundle());

      final date = DateTime.utc(2026, 8, 26, 14, 30);
      final seedA = repoA.getDailySeed(date, Language.urdu);
      final seedB = repoB.getDailySeed(date, Language.urdu);
      final seedC = repoC.getDailySeed(date, Language.urdu);

      expect(seedA, seedB);
      expect(seedB, seedC);
    });

    test(
      'is stable across every wall-clock hour of the same UTC day — what makes '
      'the "three devices, three timezones" guarantee hold',
      () async {
        final repo = await ContentRepository.load(bundle: _bundle());
        final seeds = {
          for (var hour = 0; hour < 24; hour++)
            repo.getDailySeed(
              DateTime.utc(2026, 8, 26, hour, 0),
              Language.english,
            ),
        };
        expect(seeds, hasLength(1));
      },
    );

    test('changes the moment the UTC calendar day rolls over', () async {
      final repo = await ContentRepository.load(bundle: _bundle());
      final lastSecondOfDay = repo.getDailySeed(
        DateTime.utc(2026, 8, 26, 23, 59, 59),
        Language.english,
      );
      final firstSecondOfNextDay = repo.getDailySeed(
        DateTime.utc(2026, 8, 27, 0, 0, 1),
        Language.english,
      );
      expect(lastSecondOfDay, isNot(firstSecondOfNextDay));
    });

    test('differs by language for the same date', () async {
      final repo = await ContentRepository.load(bundle: _bundle());
      final date = DateTime.utc(2026, 8, 26);
      final seeds = {
        for (final language in Language.values)
          repo.getDailySeed(date, language),
      };
      expect(seeds, hasLength(Language.values.length));
    });

    test('a local (non-UTC) DateTime for the same instant agrees with its UTC form', () async {
      final repo = await ContentRepository.load(bundle: _bundle());
      final utcInstant = DateTime.utc(2026, 8, 26, 14, 30);
      final localInstant = utcInstant.toLocal();
      expect(
        repo.getDailySeed(localInstant, Language.english),
        repo.getDailySeed(utcInstant, Language.english),
      );
    });

    test(
      'returns a non-negative value that fits Random(seed)\'s 31-bit range',
      () async {
        final repo = await ContentRepository.load(bundle: _bundle());
        final seed = repo.getDailySeed(
          DateTime.utc(2026, 8, 26),
          Language.english,
        );
        expect(seed, greaterThanOrEqualTo(0));
        expect(seed, lessThanOrEqualTo(0x7FFFFFFF));
      },
    );
  });

  test('the real shipped content loads end-to-end and daily seeds agree across '
      'three simulated "devices"', () async {
    TestWidgetsFlutterBinding.ensureInitialized();

    final repoA = await ContentRepository.load();
    final repoB = await ContentRepository.load();
    final repoC = await ContentRepository.load();

    final date = DateTime.utc(2026, 8, 26, 9);
    final a = repoA.getDailySeed(date, Language.hindi);
    final b = repoB.getDailySeed(date, Language.hindi);
    final c = repoC.getDailySeed(date, Language.hindi);
    expect(a, b);
    expect(b, c);

    final level1 = repoA.getLevel(1, Language.english);
    expect(repoA.getWordsForLevel(level1), hasLength(level1.wordCount));
  });
}
