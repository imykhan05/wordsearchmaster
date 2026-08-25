/// ============================================================================
/// ROW INTEGRITY — HMAC-SHA256 tagging for locally persisted game state (Ch10)
///
/// WHAT THIS IS FOR, STATED HONESTLY:
///
/// This is tamper EVIDENCE, not tamper PROOF. The key is derived from a
/// constant compiled into the app plus the install id, and both of those live
/// on the player's device — anyone willing to decompile the APK can forge a
/// tag. That is not the threat this defends against.
///
/// What it does buy, and why Ch10 asks for it:
///
///   * a player who opens the .db file in a SQLite editor and types a bigger
///     number into `bestScore` or `delta` is caught on the very next read;
///   * corruption from a half-written page or a bad restore is caught by the
///     same check, with no extra code;
///   * every rejection is a Crashlytics signal, so a cheat that DOES get
///     written shows up in aggregate rather than silently poisoning the
///     leaderboard.
///
/// The real anti-cheat is server-side: Ch08's Cloud Function replays the
/// submitted `ScoreEvent` list and writes ITS number, never the client's
/// (P14). This layer keeps the local database honest between those
/// submissions; it is not a substitute for them.
///
/// ---------------------------------------------------------------------------
/// PURE DART. No Flutter, no Drift, no I/O — so the whole scheme is testable
/// without a database, and so the encoding below can be ported if the tag ever
/// has to be recomputed server-side.
/// ============================================================================
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Computes and verifies the integrity tag on one persisted row.
///
/// Build one per install via [RowIntegrity.forInstall] and hand it to the
/// repositories; the HMAC is keyed once and reused, so tagging a row costs a
/// hash and nothing else.
final class RowIntegrity {
  RowIntegrity.withKey(List<int> key) : _hmac = Hmac(sha256, key);

  /// Derives the row key from an app constant plus [installId].
  ///
  /// The install id is per-device, so a database lifted off one phone and
  /// dropped onto another fails every row — which is the point. It is NOT a
  /// secret (see the header); it is a salt that makes one stolen tag useless
  /// anywhere else.
  factory RowIntegrity.forInstall(String installId) {
    final material = utf8.encode('$_appPepper::$installId');
    return RowIntegrity.withKey(sha256.convert(material).bytes);
  }

  /// Compiled-in half of the key material.
  ///
  /// Rotating this invalidates every tag on every device, which reads as
  /// "everyone tampered" — so it must never change after release without a
  /// migration that re-tags rows under the new key first.
  static const String _appPepper =
      'wsm.row-integrity.v1//com.educativz.word_search_master';

  final Hmac _hmac;

  /// The tag for one row.
  ///
  /// [table] and [rowKey] are part of the signed input on purpose: without
  /// them a row could be COPIED rather than edited — paste level 1's row over
  /// level 50's and the tag would still verify, handing over three stars for
  /// a level never played. Binding the tag to its address makes a valid row
  /// valid in exactly one place.
  String tagFor({
    required String table,
    required String rowKey,
    required List<Object?> fields,
  }) {
    final canonical = _canonical(table: table, rowKey: rowKey, fields: fields);
    return _hmac.convert(utf8.encode(canonical)).toString();
  }

  /// Whether [tag] is the tag this install would produce for these contents.
  bool verify({
    required String table,
    required String rowKey,
    required List<Object?> fields,
    required String tag,
  }) {
    final expected = tagFor(table: table, rowKey: rowKey, fields: fields);
    return tagsMatch(expected, tag);
  }

  /// Compares two already-computed tags.
  ///
  /// Exists so callers holding a `RowTags` result — the single definition of
  /// which columns a table signs — can compare without restating the field
  /// list a second time and risking the two copies drifting apart.
  static bool tagsMatch(String a, String b) => _constantTimeEquals(a, b);

  /// Length-prefixed, type-tagged serialisation of a row.
  ///
  /// Both properties matter, and both defend against a real forgery:
  ///
  ///   * LENGTH PREFIXES stop field boundaries from sliding. A plain
  ///     `fields.join('|')` gives `['a|b', 'c']` and `['a', 'b|c']` the same
  ///     bytes and therefore the same tag, so a tag captured for one row
  ///     validates a different one.
  ///   * TYPE TAGS stop `1` and `'1'` colliding, which otherwise lets an
  ///     integer field be swapped for a string one carrying different
  ///     meaning.
  ///
  /// Deliberately hand-rolled rather than `jsonEncode`: JSON map ordering is
  /// not guaranteed stable across implementations, and a tag that depends on
  /// key order is a tag that breaks on a Dart upgrade.
  static String _canonical({
    required String table,
    required String rowKey,
    required List<Object?> fields,
  }) {
    final buffer = StringBuffer();

    void writePart(String part) {
      buffer
        ..write(utf8.encode(part).length)
        ..write(':')
        ..write(part);
    }

    writePart(table);
    writePart(rowKey);
    for (final field in fields) {
      writePart(_encodeField(field));
    }
    return buffer.toString();
  }

  /// One field, prefixed by a type marker.
  ///
  /// `double` is deliberately rejected rather than encoded: no column in the
  /// Ch10 schema is a float, and IEEE-754 formatting differs just enough
  /// between platforms to make a float tag unreproducible. Failing loudly at
  /// the call site beats a tag that only mismatches on some devices.
  static String _encodeField(Object? field) => switch (field) {
    null => 'n',
    final int value => 'i$value',
    final bool value => 'b${value ? 1 : 0}',
    final String value => 's$value',
    _ => throw ArgumentError.value(
      field,
      'field',
      'Integrity fields must be int, bool, String or null — '
          '${field.runtimeType} has no stable canonical encoding',
    ),
  };

  /// Compares without returning early on the first differing byte.
  ///
  /// Timing barely matters for a local file an attacker already owns; this is
  /// here so the habit is right in the one place tags are compared, and so a
  /// future server-side port of this file starts from a safe comparison.
  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return difference == 0;
  }
}
