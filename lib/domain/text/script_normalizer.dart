import 'package:characters/characters.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import 'language.dart';

/// Canonicalises text so that the same word always compares equal, whichever
/// keyboard or source it came from.
///
/// PURE DART — no Flutter import. Roughly forty lines of logic that decide
/// whether the game is correct: without it a player selects the right word in
/// Urdu and the game says "wrong", because the grid holds ی and the word list
/// holds ي (Ch04, Masla 4).
///
/// The rule for the rest of the codebase: normalize BEFORE comparing and
/// BEFORE placing into the grid. Never compare raw strings.
abstract final class ScriptNormalizer {
  /// Urdu letter substitutions. Arabic-keyboard forms map to the Urdu ones.
  static const Map<int, int> _urduLetterMap = {
    0x064A: 0x06CC, // ي ARABIC YEH        → ی FARSI YEH      (most common slip)
    0x0643: 0x06A9, // ك ARABIC KAF        → ک KEHEH          (Urdu uses Keheh)
    0x0647: 0x06C1, // ه ARABIC HEH        → ہ HEH GOAL
  };

  // Harakat / vowel diacritics: zabar, zer, pesh, tanween, shadda, jazm...
  static const int _harakatStart = 0x064B;
  static const int _harakatEnd = 0x0652;

  static const int _zwnj = 0x200C; // ZERO WIDTH NON-JOINER
  static const int _zwj = 0x200D; // ZERO WIDTH JOINER
  static const int _lrm = 0x200E; // LEFT-TO-RIGHT MARK
  static const int _rlm = 0x200F; // RIGHT-TO-LEFT MARK

  /// ALEF WITH MADDA ABOVE. Listed here to be explicit that it is deliberately
  /// left alone: آ is a distinct letter in Urdu, not a decorated ا. Merging it
  /// into ا would make آگ and اگ the same word, which is simply wrong.
  static const int alefMadda = 0x0622;

  /// Returns the canonical form of [input] for [language].
  ///
  /// Always trims surrounding whitespace, in every language — a trailing
  /// space from a content file must never cause a mismatch.
  static String normalize(String input, Language language) =>
      switch (language) {
        Language.urdu => _normalizeUrdu(input),
        Language.hindi => _normalizeHindi(input),
        Language.english => _normalizeEnglish(input),
      };

  /// The normalized form of [input] split into grapheme clusters — one entry
  /// per GRID CELL.
  ///
  /// Normalizes first, deliberately: placement and matching have to agree on
  /// what a "letter" is, so both go through this one function.
  ///
  /// This is why "पानी" is two cells (पा, नी) and not four. A code-point split
  /// would strand the matras ा and ी in cells of their own, which reads as
  /// nonsense to anyone who speaks Hindi (Ch04, Masla 3).
  static List<String> graphemes(String input, Language language) =>
      normalize(input, language).characters.toList();

  /// How many grid cells [input] occupies. Agrees with [graphemes] by
  /// construction — the content validator (P10) checks stored counts against
  /// this.
  static int graphemeCount(String input, Language language) =>
      normalize(input, language).characters.length;

  /// Whether two strings are the same word once normalized. This is the only
  /// correct way to compare user input against a target word.
  static bool matches(String a, String b, Language language) =>
      normalize(a, language) == normalize(b, language);

  static String _normalizeUrdu(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      if (_isStrippedInUrdu(rune)) continue;
      buffer.writeCharCode(_urduLetterMap[rune] ?? rune);
    }
    return buffer.toString().trim();
  }

  static bool _isStrippedInUrdu(int rune) {
    if (rune >= _harakatStart && rune <= _harakatEnd) return true;
    return rune == _zwnj || rune == _zwj || rune == _lrm || rune == _rlm;
  }

  static String _normalizeHindi(String input) {
    // NFC also resolves Devanagari's nukta letters. Those precomposed forms
    // (क़ U+0958 and friends) are Unicode composition exclusions, so NFC
    // DECOMPOSES them to base + nukta — meaning क़ typed as one code point and
    // क़ typed as two end up identical either way.
    final composed = unorm.nfc(input);

    final buffer = StringBuffer();
    for (final rune in composed.runes) {
      if (rune == _zwnj || rune == _zwj) continue;
      buffer.writeCharCode(rune);
    }
    return buffer.toString().trim();
  }

  static String _normalizeEnglish(String input) => input.trim().toUpperCase();
}
