import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/domain/text/language.dart';
import 'package:word_search_master/domain/text/script_normalizer.dart';

/// Code points are spelled out rather than pasted as literals wherever the
/// distinction matters, because ي and ی (and ه vs ہ) are visually near-identical
/// in most editors — which is exactly why this class has to exist.
String u(List<int> codePoints) => String.fromCharCodes(codePoints);

// Urdu letters.
const _peh = 0x067E; // پ
const _alef = 0x0627; // ا
const _alefMadda = 0x0622; // آ
const _noon = 0x0646; // ن
const _gaf = 0x06AF; // گ
const _beh = 0x0628; // ب
const _dal = 0x062F; // د
const _lam = 0x0644; // ل

// The variant pairs this class exists to reconcile.
const _arabicYeh = 0x064A; // ي  → should become...
const _farsiYeh = 0x06CC; // ی
const _arabicKaf = 0x0643; // ك  → should become...
const _keheh = 0x06A9; // ک
const _heh = 0x0647; // ه  → should become...
const _hehGoal = 0x06C1; // ہ

// Harakat.
const _tanweenFath = 0x064B;
const _tanweenDamm = 0x064C;
const _tanweenKasr = 0x064D;
const _fatha = 0x064E;
const _damma = 0x064F;
const _kasra = 0x0650;
const _shadda = 0x0651;
const _sukun = 0x0652;

// Invisible formatting.
const _zwnj = 0x200C;
const _zwj = 0x200D;
const _lrm = 0x200E;
const _rlm = 0x200F;

void main() {
  group('Urdu — letter variants', () {
    test('1. Arabic Yeh becomes Farsi Yeh', () {
      expect(
        ScriptNormalizer.normalize(u([_arabicYeh]), Language.urdu),
        u([_farsiYeh]),
      );
    });

    test('2. Arabic Kaf becomes Keheh', () {
      expect(
        ScriptNormalizer.normalize(u([_arabicKaf]), Language.urdu),
        u([_keheh]),
      );
    });

    test('3. Heh becomes Heh Goal', () {
      expect(
        ScriptNormalizer.normalize(u([_heh]), Language.urdu),
        u([_hehGoal]),
      );
    });

    test('4. already-canonical letters are left alone', () {
      final canonical = u([_farsiYeh, _keheh, _hehGoal]);
      expect(ScriptNormalizer.normalize(canonical, Language.urdu), canonical);
    });

    test('5. all three substitutions apply in one pass', () {
      expect(
        ScriptNormalizer.normalize(
          u([_arabicKaf, _heh, _arabicYeh]),
          Language.urdu,
        ),
        u([_keheh, _hehGoal, _farsiYeh]),
      );
    });
  });

  group('Urdu — harakat are stripped', () {
    final harakat = {
      '6. tanween fath': _tanweenFath,
      '7. tanween damm': _tanweenDamm,
      '8. tanween kasr': _tanweenKasr,
      '9. fatha (zabar)': _fatha,
      '10. damma (pesh)': _damma,
      '11. kasra (zer)': _kasra,
      '12. shadda': _shadda,
      '13. sukun (jazm)': _sukun,
    };

    harakat.forEach((name, mark) {
      test('$name is removed', () {
        expect(
          ScriptNormalizer.normalize(u([_beh, mark, _dal]), Language.urdu),
          u([_beh, _dal]),
        );
      });
    });
  });

  group('Urdu — invisible formatting is stripped', () {
    final invisibles = {
      '14. ZWNJ': _zwnj,
      '15. ZWJ': _zwj,
      '16. LRM': _lrm,
      '17. RLM': _rlm,
    };

    invisibles.forEach((name, mark) {
      test('$name is removed', () {
        expect(
          ScriptNormalizer.normalize(u([_beh, mark, _dal]), Language.urdu),
          u([_beh, _dal]),
        );
      });
    });
  });

  group('Urdu — Alef Madda is NOT merged', () {
    test('18. Alef Madda survives normalization unchanged', () {
      expect(
        ScriptNormalizer.normalize(u([_alefMadda]), Language.urdu),
        u([_alefMadda]),
      );
    });

    test('19. آگ and اگ stay different words', () {
      // آ is a distinct letter, not a decorated ا. Merging them would make
      // "fire" and a non-word compare equal.
      final aag = ScriptNormalizer.normalize(
        u([_alefMadda, _gaf]),
        Language.urdu,
      );
      final aag2 = ScriptNormalizer.normalize(u([_alef, _gaf]), Language.urdu);
      expect(aag, isNot(aag2));
    });
  });

  group('Urdu — real words', () {
    test(
      '20. پانی typed with an Arabic keyboard matches the Urdu spelling',
      () {
        final arabicKeyboard = u([_peh, _alef, _noon, _arabicYeh]);
        final urduKeyboard = u([_peh, _alef, _noon, _farsiYeh]);

        expect(
          ScriptNormalizer.matches(arabicKeyboard, urduKeyboard, Language.urdu),
          isTrue,
        );
      },
    );

    test('21. a word WITH harakat matches the same word without', () {
      // The acceptance criterion from the prompt.
      final withHarakat = u([
        _beh,
        _fatha,
        _alef,
        _dal,
        _sukun,
        _lam,
      ]); // بادل, vowelled
      final plain = u([_beh, _alef, _dal, _lam]); // بادل

      expect(
        ScriptNormalizer.matches(withHarakat, plain, Language.urdu),
        isTrue,
      );
    });

    test('22. a fully mixed input canonicalises completely', () {
      final messy = u([
        _rlm,
        _arabicKaf,
        _fatha,
        _alef,
        _zwnj,
        _heh,
        _arabicYeh,
      ]);
      expect(
        ScriptNormalizer.normalize(messy, Language.urdu),
        u([_keheh, _alef, _hehGoal, _farsiYeh]),
      );
    });

    test('23. surrounding whitespace is trimmed', () {
      expect(
        ScriptNormalizer.normalize('  ${u([_beh, _dal])}  ', Language.urdu),
        u([_beh, _dal]),
      );
    });

    test('24. normalization is idempotent', () {
      final once = ScriptNormalizer.normalize(
        u([_arabicKaf, _fatha, _arabicYeh]),
        Language.urdu,
      );
      expect(ScriptNormalizer.normalize(once, Language.urdu), once);
    });

    test('25. empty input stays empty', () {
      expect(ScriptNormalizer.normalize('', Language.urdu), '');
    });
  });

  group('Hindi', () {
    test('26. precomposed क़ matches क + nukta after NFC', () {
      // U+0958 is a Unicode composition exclusion, so NFC decomposes it.
      // Either way of typing the word must compare equal.
      final precomposed = u([0x0958]);
      final decomposed = u([0x0915, 0x093C]);

      expect(
        ScriptNormalizer.matches(precomposed, decomposed, Language.hindi),
        isTrue,
      );
    });

    test('27. the same holds for ज़ and ड़', () {
      expect(
        ScriptNormalizer.matches(
          u([0x095B]),
          u([0x091C, 0x093C]),
          Language.hindi,
        ),
        isTrue,
      );
      expect(
        ScriptNormalizer.matches(
          u([0x095C]),
          u([0x0921, 0x093C]),
          Language.hindi,
        ),
        isTrue,
      );
    });

    test('28. ZWNJ is stripped', () {
      expect(
        ScriptNormalizer.normalize(u([0x0915, _zwnj, 0x0928]), Language.hindi),
        u([0x0915, 0x0928]),
      );
    });

    test('29. ZWJ is stripped', () {
      expect(
        ScriptNormalizer.normalize(u([0x0915, _zwj, 0x0928]), Language.hindi),
        u([0x0915, 0x0928]),
      );
    });

    test('30. an ordinary word is left untouched', () {
      expect(ScriptNormalizer.normalize('पानी', Language.hindi), 'पानी');
    });

    test('31. whitespace is trimmed and normalization is idempotent', () {
      final once = ScriptNormalizer.normalize('  पानी  ', Language.hindi);
      expect(once, 'पानी');
      expect(ScriptNormalizer.normalize(once, Language.hindi), once);
    });
  });

  group('English', () {
    test('32. lowercase becomes uppercase', () {
      expect(ScriptNormalizer.normalize('water', Language.english), 'WATER');
    });

    test('33. mixed case becomes uppercase', () {
      expect(ScriptNormalizer.normalize('WaTeR', Language.english), 'WATER');
    });

    test('34. whitespace is trimmed', () {
      expect(
        ScriptNormalizer.normalize('  water  ', Language.english),
        'WATER',
      );
    });

    test('35. normalization is idempotent', () {
      expect(ScriptNormalizer.normalize('WATER', Language.english), 'WATER');
    });
  });

  group('graphemes — one entry per grid cell', () {
    test('36. "पानी" is 2 graphemes, NOT 4 code points', () {
      // The headline acceptance criterion. A code-point split would strand
      // the matras ा and ी in cells of their own (Ch04, Masla 3).
      expect(ScriptNormalizer.graphemes('पानी', Language.hindi), ['पा', 'नी']);
      expect(ScriptNormalizer.graphemeCount('पानी', Language.hindi), 2);
      expect('पानी'.runes.length, 4, reason: 'the naive count this replaces');
    });

    test('37. a Devanagari conjunct stays in one cell', () {
      expect(ScriptNormalizer.graphemes('क्षि', Language.hindi), ['क्षि']);
    });

    test('38. a nukta letter stays with its consonant', () {
      expect(ScriptNormalizer.graphemes('पेड़', Language.hindi), ['पे', 'ड़']);
    });

    test('39. Urdu letters are one cell each, in isolated form', () {
      expect(
        ScriptNormalizer.graphemes(
          u([_peh, _alef, _noon, _arabicYeh]),
          Language.urdu,
        ),
        [
          u([_peh]),
          u([_alef]),
          u([_noon]),
          u([_farsiYeh]),
        ],
      );
    });

    test('40. graphemes are taken AFTER normalization', () {
      // Harakat must not occupy a cell of their own.
      expect(
        ScriptNormalizer.graphemes(u([_beh, _fatha, _dal]), Language.urdu),
        [
          u([_beh]),
          u([_dal]),
        ],
      );
    });

    test('41. English graphemes are uppercased letters', () {
      expect(ScriptNormalizer.graphemes('water', Language.english), [
        'W',
        'A',
        'T',
        'E',
        'R',
      ]);
    });

    test('42. graphemeCount always agrees with graphemes', () {
      const samples = {
        Language.hindi: ['पानी', 'क्षि', 'पेड़'],
        Language.english: ['water', 'Cloud'],
      };
      samples.forEach((language, words) {
        for (final word in words) {
          expect(
            ScriptNormalizer.graphemeCount(word, language),
            ScriptNormalizer.graphemes(word, language).length,
            reason: word,
          );
        }
      });
    });
  });
}
