import 'dart:math';

import '../text/language.dart';

/// Chooses the letters that fill the cells no word occupies.
///
/// PURE DART. This is the step most word-search generators get lazily wrong,
/// and it decides how hard the puzzle actually is (Ch06).
///
/// Uniform-random fillers make a puzzle far too easy: the answer letters
/// *look* different from the noise, so the eye finds them without reading. Two
/// things fix that here:
///
///  1. fillers follow the letter frequency of the language, so the grid reads
///     like plausible text rather than like keyboard mash;
///  2. [targetBias] of draws come from the graphemes that appear in the target
///     words themselves, which is what actually camouflages the answers.
final class FillerStrategy {
  FillerStrategy({
    required Language language,
    required List<List<String>> words,
    required this.random,
    this.targetBias = 0.6,
  }) : _languagePool = _expand(_frequencies[language]!),
       _targetPool = _targetPoolFor(words);

  final Random random;

  /// Probability that a filler is drawn from the target words' own graphemes
  /// rather than from the language table. Ch06 specifies 60%.
  final double targetBias;

  final List<String> _languagePool;
  final List<String> _targetPool;

  /// One filler grapheme. Always a valid letter of the language — never a
  /// random code point, and for Hindi never a bare matra floating alone.
  String next() {
    final useTarget =
        _targetPool.isNotEmpty && random.nextDouble() < targetBias;
    final pool = useTarget ? _targetPool : _languagePool;
    return pool[random.nextInt(pool.length)];
  }

  static List<String> _targetPoolFor(List<List<String>> words) {
    // Weighted by how often each grapheme appears in the word set, so the
    // camouflage matches the answers' own letter mix.
    final pool = <String>[];
    for (final word in words) {
      pool.addAll(word);
    }
    return pool;
  }

  static List<String> _expand(Map<String, int> weights) {
    final pool = <String>[];
    weights.forEach((grapheme, weight) {
      for (var i = 0; i < weight; i++) {
        pool.add(grapheme);
      }
    });
    return pool;
  }

  /// The curated per-language pools, as grapheme → relative weight.
  ///
  /// CURATED, NOT AUTHORITATIVE. These are hand-set frequencies good enough to
  /// make grids look natural; a native speaker should sanity-check the Urdu
  /// and Hindi tables before release, same rule as the word content (Ch07).
  static final Map<Language, Map<String, int>> _frequencies = {
    Language.english: const {
      'E': 127, 'T': 91, 'A': 82, 'O': 75, 'I': 70, 'N': 67, //
      'S': 63, 'H': 61, 'R': 60, 'D': 43, 'L': 40, 'C': 28,
      'U': 28, 'M': 24, 'W': 24, 'F': 22, 'G': 20, 'Y': 20,
      'P': 19, 'B': 15, 'V': 10, 'K': 8, 'J': 2, 'X': 2,
      'Q': 1, 'Z': 1,
    },
    Language.urdu: const {
      // Weights follow the rough shape of written Urdu: alef, re and noon
      // dominate, and the rarer letters stay rare so the grid does not look
      // like a bag of unusual glyphs.
      'ا': 120, 'ر': 70, 'ن': 68, 'ی': 65, 'و': 55, 'ک': 50, //
      'ل': 45, 'م': 42, 'ت': 40, 'ب': 35, 'س': 32, 'د': 30,
      'ہ': 30, 'ع': 20, 'ج': 18, 'ز': 18, 'پ': 16, 'ش': 15,
      'ف': 14, 'ق': 12, 'ح': 12, 'خ': 11, 'ط': 8, 'گ': 14,
      'چ': 12, 'ص': 8, 'ض': 5, 'ث': 4, 'ذ': 4, 'ظ': 3,
      'غ': 4, 'ٹ': 10, 'ڈ': 8, 'ڑ': 7, 'ں': 12, 'آ': 10,
      'ے': 20, 'ھ': 10,
    },
    Language.hindi: const {
      // Devanagari fillers must be whole aksharas, so this pool mixes bare
      // consonants, independent vowels, and common consonant+matra clusters.
      // A pool of bare consonants alone would make every word containing a
      // matra stand out instantly.
      'क': 55, 'र': 60, 'न': 50, 'त': 45, 'स': 42, 'म': 40, //
      'ह': 35, 'य': 30, 'ल': 30, 'व': 28, 'द': 28, 'प': 26,
      'ब': 22, 'ग': 20, 'ज': 20, 'श': 15, 'ट': 14, 'ठ': 8,
      'ड': 12, 'ढ': 5, 'ण': 6, 'थ': 10, 'ध': 12, 'भ': 12,
      'च': 12, 'छ': 6, 'झ': 4, 'फ': 8, 'ख': 10, 'घ': 6,
      'ष': 5,
      'अ': 18, 'आ': 14, 'इ': 10, 'ई': 8, 'उ': 8, 'ऊ': 5,
      'ए': 10, 'ओ': 7,
      'का': 20, 'कि': 14, 'की': 12, 'के': 14, 'को': 10,
      'ना': 16, 'नी': 12, 'ने': 12, 'नि': 10,
      'रा': 16, 'री': 12, 'रे': 10, 'रि': 8,
      'ता': 14, 'ती': 12, 'ते': 10,
      'मा': 14, 'मी': 10, 'में': 8,
      'सा': 14, 'सी': 10, 'से': 12,
      'ला': 12, 'ली': 10, 'ले': 10,
      'पा': 10, 'पी': 8, 'पे': 6,
      'हा': 10, 'ही': 10, 'है': 12,
      'वा': 10, 'दा': 8, 'दी': 8, 'बा': 8, 'गा': 8, 'जा': 10,
    },
  };

  /// The distinct fillers available for [language]. Exposed for tests and for
  /// P10's content validator, which checks that no filler collides with a
  /// blocklisted grapheme.
  static List<String> poolFor(Language language) =>
      List.unmodifiable(_frequencies[language]!.keys);
}
