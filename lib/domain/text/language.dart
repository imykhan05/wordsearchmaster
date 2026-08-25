import '../grid/grid_vector.dart';

/// The three supported languages.
///
/// PURE DART — no Flutter import (see CLAUDE.md → Architecture). The
/// Flutter-typed views of a language (`Locale`, `TextDirection`, `Offset`,
/// font families) live in the `LanguageX` extension in `lib/app/language/`,
/// so the grid engine and the normalizer can stay runnable as plain Dart.
enum Language {
  /// Right-to-left, Arabic script. The differentiator for this product, and
  /// the language everything in Ch04 exists for.
  urdu(code: 'ur', isRtl: true),

  /// Left-to-right, Devanagari. Aksharas mean a "letter" is a grapheme
  /// cluster, not a code point.
  hindi(code: 'hi', isRtl: false),

  /// Left-to-right, Latin.
  english(code: 'en', isRtl: false);

  const Language({required this.code, required this.isRtl});

  /// ISO 639-1 code. Also the key used by the content JSON files (P10) and
  /// the suffix on the ARB files.
  final String code;

  /// True for scripts read right-to-left. Urdu only, of the three.
  final bool isRtl;

  /// The direction a horizontally-placed word runs in this script.
  ///
  /// For Urdu this points WEST — a horizontal word makes the column index
  /// DECREASE. This is not a rendering hack to be undone later: reading
  /// direction is a property of the language, so the generator places words
  /// this way and hit-testing agrees with it by construction (Ch04, Masla 5).
  GridVector get primaryDirection => isRtl ? GridVector.west : GridVector.east;

  /// The direction a *reversed* word runs — the hardest tier (Ch06).
  GridVector get reverseDirection => primaryDirection.opposite;

  /// The language's own name in its own script.
  ///
  /// Deliberately NOT localized: the language-select cards must each render
  /// in their own script no matter which locale is currently active, because
  /// the player choosing has not picked a language yet (Ch02 FTUE).
  String get endonym => switch (this) {
    Language.urdu => 'اردو',
    Language.hindi => 'हिन्दी',
    Language.english => 'English',
  };

  static Language fromCode(String code) => Language.values.firstWhere(
    (language) => language.code == code,
    orElse: () =>
        throw ArgumentError.value(code, 'code', 'Unknown language code'),
  );
}
