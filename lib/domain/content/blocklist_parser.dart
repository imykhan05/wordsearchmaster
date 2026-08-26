/// Parses the accidental-word blocklist asset format: one word per line, `#`
/// comments and blank lines ignored, entries de-duplicated.
///
/// PURE DART, split out of `data/content/blocklist_loader.dart` (which
/// [BlocklistParser.parse] now backs) so that `tool/validate_content.dart` —
/// a plain-Dart CLI run via `dart run`, which cannot resolve anything that
/// transitively imports `package:flutter` (ultimately `dart:ui`, which the
/// standalone Dart SDK does not ship) — can parse the exact same blocklist
/// format the app loads at runtime, from one definition instead of two drifting
/// copies.
abstract final class BlocklistParser {
  static Set<String> parse(String contents) => {
    for (final line in contents.split('\n'))
      if (_isEntry(line.trim())) line.trim(),
  };

  static bool _isEntry(String line) => line.isNotEmpty && !line.startsWith('#');
}
