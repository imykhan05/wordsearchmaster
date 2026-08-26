import 'package:flutter/services.dart';

import '../../domain/content/blocklist_parser.dart';
import '../../domain/text/language.dart';

/// Loads the per-language accidental-word blocklists from assets.
///
/// The lists live in `assets/content/` rather than in Dart source so they can
/// be reviewed, corrected and extended by a native speaker without touching
/// code — the generator itself stays pure Dart and simply receives a set
/// (CLAUDE.md → Architecture).
///
/// P10's `ContentRepository` absorbs this alongside the word and level packs;
/// until then this is the one thing that needs the blocklist at runtime.
final class BlocklistLoader {
  BlocklistLoader({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;
  final Map<Language, Set<String>> _cache = {};

  static String assetPathFor(Language language) =>
      'assets/content/blocklist_${language.code}.txt';

  /// The blocklist for [language], cached after the first read.
  ///
  /// A missing or unreadable asset yields an EMPTY set rather than throwing.
  /// The blocklist is a polish pass over the filler; failing to load it must
  /// degrade the grid's tidiness, never break a player's level.
  Future<Set<String>> load(Language language) async {
    final cached = _cache[language];
    if (cached != null) return cached;

    Set<String> entries;
    try {
      entries = parse(await _bundle.loadString(assetPathFor(language)));
    } catch (_) {
      // TODO(P19): Crashlytics non-fatal — silent here, never user-visible.
      entries = const {};
    }

    _cache[language] = entries;
    return entries;
  }

  /// Parses the asset format: one word per line, `#` comments and blank lines
  /// ignored. Delegates to [BlocklistParser], the pure-Dart definition
  /// `tool/validate_content.dart` also imports directly — kept here too so
  /// existing callers of `BlocklistLoader.parse` are unaffected.
  static Set<String> parse(String contents) => BlocklistParser.parse(contents);
}
