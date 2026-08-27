import 'dart:convert';

import '../../domain/progression/day_key.dart';
import '../../domain/progression/streak.dart';

/// JSON for the `kv_settings` streak row (P11).
///
/// Same shape and same reasoning as `score_event_codec.dart`: the encoding is
/// its own file so both directions sit side by side and a round-trip test can
/// pin them, rather than being spread across a repository method and whatever
/// reads it back.
///
/// DECODING IS TOTAL. Anything unparseable — a truncated write, a row written
/// by a newer build, a hand-edited value that still happens to verify —
/// resolves to [StreakState.empty] rather than throwing. A player whose streak
/// resets to zero has lost something small and visible; one whose app throws
/// on the home screen has lost the app.
abstract final class StreakCodec {
  static const String _current = 'current';
  static const String _longest = 'longest';
  static const String _lastActive = 'lastActiveDay';
  static const String _lastPlayed = 'lastPlayedDay';
  static const String _freezes = 'freezes';

  static String encode(StreakState state) => jsonEncode({
    _current: state.current,
    _longest: state.longest,
    _lastActive: state.lastActiveDay?.toString(),
    _lastPlayed: state.lastPlayedDay?.toString(),
    _freezes: state.freezes,
  });

  static StreakState decode(String? raw) {
    if (raw == null || raw.isEmpty) return StreakState.empty;

    try {
      final json = jsonDecode(raw);
      if (json is! Map) return StreakState.empty;

      return StreakState(
        current: _readInt(json[_current]),
        longest: _readInt(json[_longest]),
        lastActiveDay: _readDay(json[_lastActive]),
        lastPlayedDay: _readDay(json[_lastPlayed]),
        // Clamped rather than trusted: the value went through JSON on a device
        // the player controls, and an unbounded freeze count would make the
        // streak unbreakable. `StreakRules` caps grants, so this caps reads.
        freezes: _readInt(json[_freezes]).clamp(0, StreakRules.maxFreezes),
      );
    } catch (_) {
      return StreakState.empty;
    }
  }

  static int _readInt(Object? value) {
    if (value is int) return value < 0 ? 0 : value;
    return 0;
  }

  static DayKey? _readDay(Object? value) {
    if (value is! String || value.isEmpty) return null;
    try {
      return DayKey.parse(value);
    } catch (_) {
      return null;
    }
  }
}
