/// The three supported languages.
///
/// PURE DART — no Flutter import (see CLAUDE.md → Architecture). Anything
/// Flutter-typed that belongs to a language (TextDirection, Locale) is mapped
/// in the presentation/theme layer, not stored here.
///
/// P03 extends this with `locale`, `textDirection`, `gridPrimaryDirection`
/// and the normalization hooks. P02 needs only the identity + script facts
/// below to pick fonts, so that is all this carries today.
enum Language {
  urdu(code: 'ur', isRtl: true),
  hindi(code: 'hi', isRtl: false),
  english(code: 'en', isRtl: false);

  const Language({required this.code, required this.isRtl});

  /// ISO 639-1 code, also the key used by the content JSON files (P10).
  final String code;

  /// True for scripts read right-to-left. Urdu only, of the three.
  final bool isRtl;

  static Language fromCode(String code) => Language.values.firstWhere(
    (language) => language.code == code,
    orElse: () =>
        throw ArgumentError.value(code, 'code', 'Unknown language code'),
  );
}
