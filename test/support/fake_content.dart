import 'dart:convert';

import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:word_search_master/data/content/content_repository.dart';
import 'package:word_search_master/domain/grid/grid_directions.dart';
import 'package:word_search_master/domain/text/language.dart';

/// A bundle that serves canned strings — the same shape
/// `content_repository_test.dart`'s own `_FakeBundle` uses.
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

/// Every language's 8-word list, one nature-category concept each — the
/// EXACT set `GameController`'s pre-P10 `_demoWords` constant used to hold
/// inline. English is what every widget test below actually exercises;
/// Hindi/Urdu exist only because `ContentRepository.load` requires all three
/// language packs to be present.
const Map<Language, List<String>> _words = {
  Language.english: [
    'WATER',
    'STONE',
    'RIVER',
    'FOREST',
    'LIGHT',
    'EARTH',
    'STORM',
    'SEED',
  ],
  Language.urdu: ['پانی', 'بادل', 'ہوا', 'زمین', 'درخت', 'دریا', 'سورج', 'برف'],
  Language.hindi: ['पानी', 'बादल', 'हवा', 'धरती', 'नदी', 'सूरज', 'रात', 'तारा'],
};

Map<String, Object?> _wordJson(String id, Language language, String word) => {
  'id': id,
  'lang': language.code,
  'word': word,
  'display': word,
  'roman': word,
  'en': word,
  'category': 'nature',
  'graphemes': word.characters.length,
  'difficulty': 1,
  'hint': 'a hint',
};

Map<String, Object?> _levelJson(int id, Language language) => {
  'id': id,
  'lang': language.code,
  // Byte-identical to the formula `GameController._generateGrid` used
  // before P10/P11 wired real content — `id * 7919` — so a test asserting
  // anything about the resulting grid's exact shape is exercising the same
  // grid it always was.
  'seed': id * 7919,
  'gridSize': id <= 5
      ? 6
      : id <= 20
      ? 8
      : id <= 60
      ? 10
      : 12,
  // Fixed at 8, matching every word in _words being placed — the old
  // hardcoded-content behavior several of these tests assert against
  // directly (e.g. "level 1 must place at least 6 of its 8 demo words").
  'wordCount': 8,
  'categoryPool': ['nature'],
  'directionTier': DirectionTier.forLevel(id).name,
  'theme': 'Nature',
};

/// Builds a [ContentRepository] over the fixture above, entirely in memory —
/// no `rootBundle`, no real asset I/O. Widget tests exercising `GameScreen`
/// only care that SOME valid content resolves and behaves deterministically;
/// the real shipped content pack has its own dedicated coverage
/// (`content_repository_test.dart`, `validate_content_test.dart`).
///
/// [levelCount] must cover every level a test plays up to — 30 is enough
/// headroom for "20 levels back to back" plus one Zeigarnik swap past it.
Future<ContentRepository> buildTestContentRepository({int levelCount = 30}) {
  final files = <String, String>{
    for (final language in Language.values)
      'assets/content/words_${language.code}.json': jsonEncode({
        'words': [
          for (var i = 0; i < _words[language]!.length; i++)
            _wordJson(
              '${language.code}_nature_${i.toString().padLeft(3, '0')}',
              language,
              _words[language]![i],
            ),
        ],
      }),
    'assets/content/levels.json': jsonEncode({
      'levels': [
        for (var id = 1; id <= levelCount; id++)
          for (final language in Language.values) _levelJson(id, language),
      ],
    }),
  };

  return ContentRepository.load(bundle: _FakeBundle(files));
}
