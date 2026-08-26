import '../text/language.dart';

/// One row of a `words_{lang}.json` content pack (Ch07/P10).
///
/// Plain final class, not `@freezed`, matching `LevelCompletionSummary`'s
/// precedent (`application/game_controller.dart`) rather than `GameState`'s:
/// this is a small, read-only value parsed once from a bundled asset and
/// never `copyWith`-mutated, which is exactly the shape that precedent
/// reaches for over freezed's heavier machinery. It never needs `toJson` —
/// content flows one way, asset into the app — so [fromJson] is the only
/// direction implemented.
final class WordEntry {
  const WordEntry({
    required this.id,
    required this.lang,
    required this.word,
    required this.display,
    required this.roman,
    required this.en,
    required this.category,
    required this.graphemes,
    required this.difficulty,
    required this.hint,
  });

  /// Stable, human-readable: `{lang}_{category}_{index}`.
  final String id;

  final Language lang;

  /// The NORMALIZED form (`ScriptNormalizer.normalize` already applied) —
  /// this is what `GridGenerator.generate` receives directly. Validated by
  /// `tool/validate_content.dart`, which re-normalizes and compares.
  final String word;

  /// Human-facing rendering for the word-list chip. Equal to [word] for
  /// Urdu/Hindi (there is no cased/natural-form distinction once normalized);
  /// Title Case for English.
  final String display;

  /// Romanized transliteration, uppercase. Equal to [word] for English.
  final String roman;

  /// The English gloss/meaning, uppercase. Equal to [word] for English.
  final String en;

  /// One of the twelve Ch07 categories — see `CLAUDE.md` § Content pipeline.
  final String category;

  /// `ScriptNormalizer.graphemeCount(word, lang)`, precomputed so content can
  /// be filtered by grid size without re-normalizing at runtime. The
  /// validator checks this stays in sync with the live computation.
  final int graphemes;

  /// 1–5, derived from [graphemes] (2–3→1 … 9→5). Presentation-only; never
  /// fed into `Scoring` (CLAUDE.md → scoring is a normative contract with its
  /// own, deliberately separate, integer table).
  final int difficulty;

  /// Shown to the player when they use a hint, in the word's OWN language.
  final String hint;

  factory WordEntry.fromJson(Map<String, Object?> json) => WordEntry(
    id: json['id']! as String,
    lang: Language.fromCode(json['lang']! as String),
    word: json['word']! as String,
    display: json['display']! as String,
    roman: json['roman']! as String,
    en: json['en']! as String,
    category: json['category']! as String,
    graphemes: json['graphemes']! as int,
    difficulty: json['difficulty']! as int,
    hint: json['hint']! as String,
  );

  @override
  bool operator ==(Object other) =>
      other is WordEntry &&
      other.id == id &&
      other.lang == lang &&
      other.word == word &&
      other.display == display &&
      other.roman == roman &&
      other.en == en &&
      other.category == category &&
      other.graphemes == graphemes &&
      other.difficulty == difficulty &&
      other.hint == hint;

  @override
  int get hashCode => Object.hash(
    id,
    lang,
    word,
    display,
    roman,
    en,
    category,
    graphemes,
    difficulty,
    hint,
  );

  @override
  String toString() => 'WordEntry($id: $word, category: $category)';
}
