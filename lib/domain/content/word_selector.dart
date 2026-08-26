import 'dart:math';

import '../models/level_definition.dart';
import '../models/word_entry.dart';
import '../text/script_normalizer.dart';

/// Draws a level's actual word list out of a language's full content pack.
///
/// THE REAL FIX CLAUDE.md FLAGS FOR HINDI: a crossing needs two words to
/// share an identical grapheme, and picking words uniformly at random rarely
/// produces that in Devanagari, where a "letter" is an akshara drawn from a
/// far larger set than the Latin alphabet — only 17–38% of randomly-picked
/// Hindi words share a grapheme with anything already chosen, against
/// 91–97% in English (Ch07). [selectForLevel] instead grows the set
/// preferring words that share a grapheme with what is already chosen, so
/// Hindi levels get a real chance at the same intersection density as
/// English and Urdu ones at the same level number. This is the production
/// version of `test/domain/grid/word_fixtures.dart`'s `pickCohesive`, which
/// proved the shape of the fix before real content existed to run it on.
abstract final class WordSelector {
  /// The [level.wordCount] words for [level], deterministic in [level.seed]
  /// — the same [LevelDefinition] always resolves to the same word list, so
  /// nothing about a level needs to be stored beyond its definition.
  ///
  /// [pool] is every [WordEntry] for the level's language; this filters it
  /// to [LevelDefinition.categoryPool] and to words that fit the level's own
  /// [LevelDefinition.gridSize] before selecting. Returns fewer than
  /// [LevelDefinition.wordCount] rather than throwing if the filtered pool
  /// is too small — `validate_content.dart` is where that shortfall is a
  /// build-breaking error, not a runtime one (CLAUDE.md → never crash a
  /// player's session over a content problem).
  static List<WordEntry> selectForLevel({
    required LevelDefinition level,
    required List<WordEntry> pool,
  }) {
    final eligible = [
      for (final entry in pool)
        if (level.categoryPool.contains(entry.category) &&
            entry.graphemes <= level.gridSize)
          entry,
    ]..shuffle(Random(level.seed));

    if (eligible.isEmpty) return const [];

    final chosen = <WordEntry>[eligible.removeAt(0)];
    final graphemePool = <String>{
      ...ScriptNormalizer.graphemes(chosen.first.word, chosen.first.lang),
    };

    while (chosen.length < level.wordCount && eligible.isNotEmpty) {
      var pickedIndex = 0;
      for (var i = 0; i < eligible.length; i++) {
        final graphemes = ScriptNormalizer.graphemes(
          eligible[i].word,
          eligible[i].lang,
        );
        if (graphemes.any(graphemePool.contains)) {
          pickedIndex = i;
          break;
        }
      }

      final entry = eligible.removeAt(pickedIndex);
      chosen.add(entry);
      graphemePool.addAll(ScriptNormalizer.graphemes(entry.word, entry.lang));
    }

    return chosen;
  }
}
