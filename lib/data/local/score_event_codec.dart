import '../../domain/scoring/score_event.dart';

/// Wire format for the `ScoreEvent` list carried in a `levelComplete` outbox
/// payload.
///
/// This is the ANTI-CHEAT SHAPE from Ch08, not a convenience: the client
/// submits the ordered work it did, and P14's `submitScore.ts` replays that
/// list through its own TypeScript port of the scoring rules and writes the
/// number IT computes. The client's own total is never trusted, so it is not
/// even sent.
///
/// KEYS ARE SHORT AND POSITIONAL-FREE (`{"t":"w","g":5}`) because a level can
/// run to a few dozen events and this payload sits in an outbox row that may
/// be retried over a 2G connection in a Pakistani village — the audience in
/// Ch01. Verbose JSON here is bytes the player pays for.
///
/// The `t` discriminator values are FROZEN. Changing one silently invalidates
/// every queued row on every device that has not synced yet; add a new value
/// instead, and teach the server both.
abstract final class ScoreEventCodec {
  static const String _wordFound = 'w';
  static const String _wrongSelection = 'x';
  static const String _hintUsed = 'h';

  static List<Map<String, Object?>> encode(List<ScoreEvent> events) => [
    for (final event in events)
      switch (event) {
        WordFound(:final graphemeCount) => {
          't': _wordFound,
          'g': graphemeCount,
        },
        WrongSelection() => {'t': _wrongSelection},
        HintUsed() => {'t': _hintUsed},
      },
  ];

  /// Rebuilds the list. Unknown or malformed entries are DROPPED rather than
  /// throwing — a queue row that cannot be parsed must not wedge sync forever,
  /// and the server recomputes from whatever it receives anyway.
  static List<ScoreEvent> decode(List<Object?> raw) => [
    for (final entry in raw)
      if (entry is Map<String, Object?>)
        if (_decodeOne(entry) case final ScoreEvent event) event,
  ];

  static ScoreEvent? _decodeOne(Map<String, Object?> entry) =>
      switch (entry['t']) {
        _wordFound when entry['g'] is int => WordFound(
          graphemeCount: entry['g']! as int,
        ),
        _wrongSelection => const WrongSelection(),
        _hintUsed => const HintUsed(),
        _ => null,
      };
}
