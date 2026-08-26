import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/domain/models/word_entry.dart';
import 'package:word_search_master/domain/text/language.dart';

WordEntry _entry({
  String id = 'en_nature_001',
  Language lang = Language.english,
  String word = 'WATER',
  String display = 'Water',
  String roman = 'WATER',
  String en = 'WATER',
  String category = 'nature',
  int graphemes = 5,
  int difficulty = 2,
  String hint = 'You drink this to stay alive',
}) => WordEntry(
  id: id,
  lang: lang,
  word: word,
  display: display,
  roman: roman,
  en: en,
  category: category,
  graphemes: graphemes,
  difficulty: difficulty,
  hint: hint,
);

void main() {
  group('WordEntry.fromJson', () {
    test('parses every field', () {
      final entry = WordEntry.fromJson(const {
        'id': 'en_nature_001',
        'lang': 'en',
        'word': 'WATER',
        'display': 'Water',
        'roman': 'WATER',
        'en': 'WATER',
        'category': 'nature',
        'graphemes': 5,
        'difficulty': 2,
        'hint': 'You drink this to stay alive',
      });

      expect(entry.id, 'en_nature_001');
      expect(entry.lang, Language.english);
      expect(entry.word, 'WATER');
      expect(entry.display, 'Water');
      expect(entry.roman, 'WATER');
      expect(entry.en, 'WATER');
      expect(entry.category, 'nature');
      expect(entry.graphemes, 5);
      expect(entry.difficulty, 2);
      expect(entry.hint, 'You drink this to stay alive');
    });

    test('throws on a missing required field', () {
      expect(() => WordEntry.fromJson(const {'id': 'x'}), throwsA(anything));
    });

    test('throws on an unknown language code', () {
      expect(
        () => WordEntry.fromJson(const {
          'id': 'x',
          'lang': 'zz',
          'word': 'X',
          'display': 'X',
          'roman': 'X',
          'en': 'X',
          'category': 'nature',
          'graphemes': 2,
          'difficulty': 1,
          'hint': 'x',
        }),
        throwsArgumentError,
      );
    });
  });

  group('equality', () {
    test('two entries with identical fields are equal', () {
      expect(_entry(), _entry());
      expect(_entry().hashCode, _entry().hashCode);
    });

    test('differing on any single field breaks equality', () {
      expect(_entry(), isNot(_entry(word: 'FIRE')));
      expect(_entry(), isNot(_entry(graphemes: 6)));
      expect(_entry(), isNot(_entry(lang: Language.hindi)));
      expect(_entry(), isNot(_entry(id: 'en_nature_002')));
      expect(_entry(), isNot(_entry(difficulty: 3)));
    });
  });

  test('toString is human-readable', () {
    expect(_entry().toString(), contains('WATER'));
    expect(_entry().toString(), contains('nature'));
  });
}
