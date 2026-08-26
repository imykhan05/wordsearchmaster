import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/content/word_selector.dart';
import '../../domain/models/level_definition.dart';
import '../../domain/models/word_entry.dart';
import '../../domain/text/language.dart';

part 'content_repository.g.dart';

/// Loads and caches the Ch07 content pack — the three `words_{lang}.json`
/// packs and `levels.json` — from `assets/content/` at startup.
///
/// Everything is parsed ONCE, in [load], into plain in-memory maps; every
/// method after that is a synchronous lookup. `bootstrap.dart`'s "7. Content
/// load" step owns calling [load] — see its own doc comment.
final class ContentRepository {
  ContentRepository._({
    required this._wordsByLanguage,
    required this._levelsById,
  });

  final Map<Language, List<WordEntry>> _wordsByLanguage;
  final Map<int, Map<Language, LevelDefinition>> _levelsById;

  /// The Ch07 curve's own range — also what [getLevel] clamps an
  /// out-of-range id into.
  static const int firstLevel = 1;
  static const int lastLevel = 300;

  /// Reads and parses every content asset. [bundle] is injectable so tests
  /// can hand it a fake without touching the real asset bundle.
  static Future<ContentRepository> load({AssetBundle? bundle}) async {
    final assetBundle = bundle ?? rootBundle;

    final wordsByLanguage = <Language, List<WordEntry>>{};
    for (final language in Language.values) {
      final raw = await assetBundle.loadString(
        'assets/content/words_${language.code}.json',
      );
      final json = jsonDecode(raw) as Map<String, Object?>;
      final entries = (json['words']! as List).cast<Map<String, Object?>>();
      wordsByLanguage[language] = [
        for (final entry in entries) WordEntry.fromJson(entry),
      ];
    }

    final levelsRaw = await assetBundle.loadString(
      'assets/content/levels.json',
    );
    final levelsJson = jsonDecode(levelsRaw) as Map<String, Object?>;
    final levelsList = (levelsJson['levels']! as List)
        .cast<Map<String, Object?>>();

    final levelsById = <int, Map<Language, LevelDefinition>>{};
    for (final raw in levelsList) {
      final level = LevelDefinition.fromJson(raw);
      (levelsById[level.id] ??= {})[level.language] = level;
    }

    return ContentRepository._(
      wordsByLanguage: wordsByLanguage,
      levelsById: levelsById,
    );
  }

  /// The definition for level [id] in [language].
  ///
  /// [id] is CLAMPED to [firstLevel]..[lastLevel] rather than throwing — a
  /// corrupt or out-of-range id (bad save data, a future level cap change)
  /// degrades to the nearest real level instead of crashing the player's
  /// session (CLAUDE.md → Never do), the same defensive shape
  /// `DirectionTier.forLevel` already uses.
  LevelDefinition getLevel(int id, Language language) {
    final clamped = id.clamp(firstLevel, lastLevel);
    return _levelsById[clamped]![language]!;
  }

  /// [level]'s actual word list. See [WordSelector] for how the words are
  /// chosen — deterministically, from [level]'s own seed.
  List<WordEntry> getWordsForLevel(LevelDefinition level) {
    return WordSelector.selectForLevel(
      level: level,
      pool: _wordsByLanguage[level.language] ?? const [],
    );
  }

  /// A deterministic seed for the daily challenge: `sha256(dateString +
  /// langCode)`, folded down to a 31-bit non-negative int suitable for
  /// `Random(seed)`/`GridGenerator.generate(seed:)`.
  ///
  /// [date] is always read via `toUtc()` — "the same grid on three devices"
  /// only holds if every device agrees on what DAY it is, and local
  /// calendar days disagree near midnight depending on timezone. The UTC
  /// calendar day is the one thing every device can compute identically
  /// without asking a server.
  int getDailySeed(DateTime date, Language language) {
    final utc = date.toUtc();
    final dateString =
        '${utc.year.toString().padLeft(4, '0')}-'
        '${utc.month.toString().padLeft(2, '0')}-'
        '${utc.day.toString().padLeft(2, '0')}';
    final digest = sha256.convert(utf8.encode('$dateString${language.code}'));
    final bytes = digest.bytes;
    final value =
        (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
    return value & 0x7FFFFFFF;
  }
}

/// The app-wide content pack. `AsyncNotifier`/screens `ref.watch` the
/// `.future` once content is needed — there is no Noop binding, unlike
/// `AudioService`/`HapticsService`: there is no safe "silent" fallback for
/// missing word content, so a load failure surfaces as this provider's
/// error state rather than degrading quietly.
@Riverpod(keepAlive: true)
Future<ContentRepository> contentRepository(Ref ref) =>
    ContentRepository.load();
