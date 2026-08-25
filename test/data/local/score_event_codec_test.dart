import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/data/local/score_event_codec.dart';
import 'package:word_search_master/domain/scoring/score_event.dart';
import 'package:word_search_master/domain/scoring/scoring.dart';

/// The wire format for the events an outbox row carries to P14's Cloud
/// Function. It has to survive a JSON round trip exactly, because the server
/// replays it to compute the score.
void main() {
  const worked = [
    WordFound(graphemeCount: 5),
    WordFound(graphemeCount: 4),
    WrongSelection(),
    WordFound(graphemeCount: 3),
    HintUsed(),
  ];

  test('round-trips through real JSON', () {
    final decoded = ScoreEventCodec.decode(
      jsonDecode(jsonEncode(ScoreEventCodec.encode(worked))) as List<Object?>,
    );

    expect(decoded, worked);
  });

  test('the decoded list scores identically to the original', () {
    // The parity fixture from the scoring spec header: 103 points, 2 stars.
    // If the codec ever reorders or drops an event, the server and the client
    // disagree by exactly the amount that gets a submission rejected.
    final decoded = ScoreEventCodec.decode(
      jsonDecode(jsonEncode(ScoreEventCodec.encode(worked))) as List<Object?>,
    );

    expect(Scoring.computeScore(worked), 103);
    expect(Scoring.computeScore(decoded), Scoring.computeScore(worked));
  });

  test('ORDER is preserved — the combo ladder depends on it', () {
    const reordered = [
      WordFound(graphemeCount: 4),
      WordFound(graphemeCount: 5),
      WrongSelection(),
      WordFound(graphemeCount: 3),
      HintUsed(),
    ];

    final encoded = ScoreEventCodec.encode(worked);
    expect(encoded, isNot(ScoreEventCodec.encode(reordered)));
    expect(ScoreEventCodec.decode(encoded), worked);
  });

  test('the discriminators are the frozen short forms', () {
    // Changing these silently invalidates every queued row on every device
    // that has not synced yet.
    expect(ScoreEventCodec.encode(const [WordFound(graphemeCount: 2)]), [
      {'t': 'w', 'g': 2},
    ]);
    expect(ScoreEventCodec.encode(const [WrongSelection()]), [
      {'t': 'x'},
    ]);
    expect(ScoreEventCodec.encode(const [HintUsed()]), [
      {'t': 'h'},
    ]);
  });

  test('an empty list round-trips to an empty list', () {
    expect(ScoreEventCodec.decode(ScoreEventCodec.encode(const [])), isEmpty);
  });

  group('malformed input is dropped, never thrown', () {
    // A queue row that cannot be parsed must not wedge sync forever.
    test('an unknown discriminator is skipped', () {
      expect(
        ScoreEventCodec.decode([
          {'t': 'w', 'g': 3},
          {'t': 'zzz'},
        ]),
        const [WordFound(graphemeCount: 3)],
      );
    });

    test('a WordFound with no grapheme count is skipped', () {
      expect(
        ScoreEventCodec.decode([
          {'t': 'w'},
          {'t': 'h'},
        ]),
        const [HintUsed()],
      );
    });

    test('a non-map entry is skipped', () {
      expect(ScoreEventCodec.decode(['nonsense', 42, null]), isEmpty);
    });
  });
}
