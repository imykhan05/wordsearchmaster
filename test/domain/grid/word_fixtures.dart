import 'dart:math';

import 'package:word_search_master/domain/text/language.dart';
import 'package:word_search_master/domain/text/script_normalizer.dart';

/// Sample vocabulary for exercising the grid engine.
///
/// TEST FIXTURE ONLY — the shipped word packs are built and native-reviewed in
/// P10. These are nature-category words in each script, enough to stand in for
/// a real level while the content pipeline does not exist yet.
abstract final class WordFixtures {
  static const Map<Language, List<String>> byLanguage = {
    Language.english: [
      'WATER', 'CLOUD', 'FIRE', 'WIND', 'TREE', 'RIVER', //
      'EARTH', 'STONE', 'GRASS', 'LEAF', 'ROOT', 'SAND',
      'RAIN', 'SNOW', 'STORM', 'LIGHT', 'OCEAN', 'FOREST',
      'FLOWER', 'BRANCH', 'VALLEY', 'DESERT', 'ISLAND', 'MEADOW',
      'STREAM', 'SHADOW', 'SUN', 'MOON', 'STAR', 'SKY',
      'HILL', 'LAKE', 'FIELD', 'SEED', 'BIRD', 'MIST',
    ],
    Language.urdu: [
      'پانی', 'آگ', 'ہوا', 'زمین', 'درخت', 'بادل', //
      'دریا', 'پہاڑ', 'پتھر', 'ریت', 'برف', 'بارش',
      'سورج', 'چاند', 'پھول', 'گھاس', 'جنگل', 'سمندر',
      'وادی', 'صحرا', 'طوفان', 'روشنی', 'سایہ', 'آسمان',
      'مٹی', 'شاخ', 'جڑ', 'پتہ', 'کھیت', 'بیج',
      'جھیل', 'دھند', 'موسم', 'رات', 'دن', 'صبح',
    ],
    Language.hindi: [
      'पानी', 'आग', 'हवा', 'धरती', 'पेड़', 'बादल', //
      'नदी', 'पहाड़', 'पत्थर', 'रेत', 'बर्फ', 'सूरज',
      'चाँद', 'तारा', 'फूल', 'घास', 'जंगल', 'समुद्र',
      'घाटी', 'तूफान', 'छाया', 'आसमान', 'मिट्टी', 'शाखा',
      'जड़', 'पत्ता', 'खेत', 'बीज', 'झील', 'मौसम',
      'रात', 'दिन', 'सुबह', 'किरण', 'लहर', 'बूँद',
    ],
  };

  /// [count] distinct words for [language] that fit inside a [maxGraphemes]
  /// grid, drawn deterministically from [random], with no regard for whether
  /// they can intersect.
  static List<String> pick(
    Language language,
    int count,
    int maxGraphemes,
    Random random,
  ) {
    final eligible = [
      for (final word in byLanguage[language]!)
        if (ScriptNormalizer.graphemeCount(word, language) <= maxGraphemes)
          word,
    ]..shuffle(random);

    return eligible.take(count).toList();
  }

  /// Like [pick], but grows the set by preferring words that SHARE a grapheme
  /// with the words already chosen.
  ///
  /// This exists because of a measurement, not a hunch. A crossing requires
  /// two words to contain the identical grapheme, and in Devanagari a
  /// "letter" is an akshara — a consonant-plus-matra cluster drawn from a far
  /// larger set than the Latin alphabet. With words picked at random, only
  /// 17–38% of Hindi words share an akshara with anything already placed,
  /// against 91–97% in English. No generator can cross words that share
  /// nothing, so random Hindi word sets produce grids of isolated words —
  /// which are markedly easier to solve.
  ///
  /// P10 OWNS THE REAL FIX: level word sets must be assembled with this
  /// constraint in mind, especially for Hindi, or Hindi levels will be
  /// measurably easier than English and Urdu ones at the same level number.
  static List<String> pickCohesive(
    Language language,
    int count,
    int maxGraphemes,
    Random random,
  ) {
    final eligible = [
      for (final word in byLanguage[language]!)
        if (ScriptNormalizer.graphemeCount(word, language) <= maxGraphemes)
          word,
    ]..shuffle(random);

    if (eligible.isEmpty) return const [];

    final chosen = <String>[eligible.removeAt(0)];
    final pool = <String>{
      ...ScriptNormalizer.graphemes(chosen.first, language),
    };

    while (chosen.length < count && eligible.isNotEmpty) {
      var pickedIndex = 0;
      for (var i = 0; i < eligible.length; i++) {
        final graphemes = ScriptNormalizer.graphemes(eligible[i], language);
        if (graphemes.any(pool.contains)) {
          pickedIndex = i;
          break;
        }
      }

      final word = eligible.removeAt(pickedIndex);
      chosen.add(word);
      pool.addAll(ScriptNormalizer.graphemes(word, language));
    }

    return chosen;
  }
}

/// One row of the Ch07 difficulty curve.
final class CurveStep {
  const CurveStep({
    required this.levelFrom,
    required this.levelTo,
    required this.gridSize,
    required this.wordCount,
  });

  final int levelFrom;
  final int levelTo;
  final int gridSize;
  final int wordCount;
}

/// The Ch07 difficulty curve, as the fuzz test walks it.
const List<CurveStep> ch07Curve = [
  CurveStep(levelFrom: 1, levelTo: 5, gridSize: 6, wordCount: 4),
  CurveStep(levelFrom: 6, levelTo: 20, gridSize: 8, wordCount: 6),
  CurveStep(levelFrom: 21, levelTo: 60, gridSize: 10, wordCount: 8),
  CurveStep(levelFrom: 61, levelTo: 150, gridSize: 10, wordCount: 10),
  CurveStep(levelFrom: 151, levelTo: 300, gridSize: 12, wordCount: 12),
];
