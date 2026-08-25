import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/domain/scoring/score_event.dart';
import 'package:word_search_master/domain/scoring/scoring.dart';

void main() {
  group('base points', () {
    test('a word is worth 10 points per grapheme at combo 1', () {
      expect(Scoring.wordScore(graphemeCount: 5, consecutiveCorrect: 1), 50);
      expect(Scoring.wordScore(graphemeCount: 2, consecutiveCorrect: 1), 20);
    });

    test('graphemes are the unit, so a Hindi word scores by aksharas', () {
      // "पानी" is 2 graphemes and 4 code points. Scoring the code points would
      // pay double for every matra.
      expect(Scoring.wordScore(graphemeCount: 2, consecutiveCorrect: 1), 20);
    });

    test('a degenerate grapheme count scores nothing rather than negative', () {
      expect(Scoring.wordScore(graphemeCount: 0, consecutiveCorrect: 3), 0);
      expect(Scoring.wordScore(graphemeCount: -4, consecutiveCorrect: 3), 0);
    });
  });

  group('the combo ladder', () {
    test('runs x1.0, x1.2, x1.4, x1.6, x1.8, x2.0', () {
      const expected = [1.0, 1.2, 1.4, 1.6, 1.8, 2.0];
      for (var step = 1; step <= 6; step++) {
        expect(
          Scoring.comboMultiplier(step),
          closeTo(expected[step - 1], 1e-9),
          reason: 'combo $step',
        );
      }
    });

    test('caps at the sixth consecutive word', () {
      for (final step in [6, 7, 12, 500]) {
        expect(Scoring.comboMultiplier(step), 2.0, reason: 'combo $step');
        expect(
          Scoring.wordScore(graphemeCount: 5, consecutiveCorrect: step),
          100,
        );
      }
    });

    test('the integer ladder is exactly 10x the displayed multiplier', () {
      // Scoring multiplies by these integers rather than by the doubles, so
      // Dart and the TypeScript port cannot drift apart on float rounding —
      // and one point of drift means a rejected submission.
      for (var step = 1; step <= 6; step++) {
        expect(
          Scoring.comboPointsPerGrapheme[step - 1],
          (Scoring.comboMultiplier(step) * Scoring.basePointsPerGrapheme)
              .round(),
        );
      }
      expect(Scoring.comboPointsPerGrapheme, [10, 12, 14, 16, 18, 20]);
    });

    test('the full ladder scores as specified, word by word', () {
      const word = 5;
      const expectedPerWord = [50, 60, 70, 80, 90, 100, 100];

      var running = 0;
      for (var i = 0; i < expectedPerWord.length; i++) {
        running += expectedPerWord[i];
        final events = [
          for (var w = 0; w <= i; w++) const WordFound(graphemeCount: word),
        ];
        expect(
          Scoring.computeScore(events),
          running,
          reason: '${i + 1} consecutive words',
        );
      }
    });

    test('a wrong selection resets the combo to zero', () {
      // Five in a row, then a miss, then one more: the sixth word scores at
      // x1.0 again, not x2.0.
      final events = <ScoreEvent>[
        for (var i = 0; i < 5; i++) const WordFound(graphemeCount: 5),
        const WrongSelection(),
        const WordFound(graphemeCount: 5),
      ];

      // 50 + 60 + 70 + 80 + 90 = 350, then 50 at the reset combo.
      expect(Scoring.computeScore(events), 400);
    });

    test('a wrong selection costs no points itself', () {
      const found = [WordFound(graphemeCount: 4)];
      const withMiss = [WordFound(graphemeCount: 4), WrongSelection()];

      expect(Scoring.computeScore(withMiss), Scoring.computeScore(found));
    });

    test('a hint does NOT reset the combo', () {
      final withHint = <ScoreEvent>[
        const WordFound(graphemeCount: 5),
        const HintUsed(),
        const WordFound(graphemeCount: 5),
      ];
      // Second word still scores at combo 2 (60), minus the 25 penalty.
      expect(Scoring.computeScore(withHint), 50 + 60 - 25);
    });

    test('maxComboIn reports the longest run', () {
      final events = <ScoreEvent>[
        const WordFound(graphemeCount: 3),
        const WordFound(graphemeCount: 3),
        const WrongSelection(),
        const WordFound(graphemeCount: 3),
        const WordFound(graphemeCount: 3),
        const WordFound(graphemeCount: 3),
      ];

      expect(Scoring.maxComboIn(events), 3);
    });
  });

  group('hints', () {
    test('each hint costs a flat 25 points', () {
      final one = <ScoreEvent>[
        const WordFound(graphemeCount: 10),
        const HintUsed(),
      ];
      final two = <ScoreEvent>[
        const WordFound(graphemeCount: 10),
        const HintUsed(),
        const HintUsed(),
      ];

      expect(Scoring.computeScore(one), 100 - 25);
      expect(Scoring.computeScore(two), 100 - 50);
    });

    test('the penalty is not scaled by the combo', () {
      final early = <ScoreEvent>[
        const HintUsed(),
        for (var i = 0; i < 6; i++) const WordFound(graphemeCount: 5),
      ];
      final late = <ScoreEvent>[
        for (var i = 0; i < 6; i++) const WordFound(graphemeCount: 5),
        const HintUsed(),
      ];

      expect(Scoring.computeScore(early), Scoring.computeScore(late));
    });

    test('the score floors at zero — hints never push a player negative', () {
      final events = <ScoreEvent>[
        const WordFound(graphemeCount: 2),
        for (var i = 0; i < 10; i++) const HintUsed(),
      ];

      expect(Scoring.computeScore(events), 0);
    });

    test('hintsIn counts only paid hints', () {
      final events = <ScoreEvent>[
        const HintUsed(),
        const WordFound(graphemeCount: 3),
        const HintUsed(),
        const WrongSelection(),
      ];

      expect(Scoring.hintsIn(events), 2);
    });
  });

  group('stars — relaxed mode', () {
    test('3 for no hints, 2 for one, 1 for two or more', () {
      expect(Scoring.computeStars(hintsUsed: 0), 3);
      expect(Scoring.computeStars(hintsUsed: 1), 2);
      expect(Scoring.computeStars(hintsUsed: 2), 1);
      expect(Scoring.computeStars(hintsUsed: 9), 1);
    });

    test('never returns 0 — a completed level always earns something', () {
      for (var hints = 0; hints < 50; hints++) {
        expect(Scoring.computeStars(hintsUsed: hints), inInclusiveRange(1, 3));
      }
    });

    test('a negative hint count is treated as none', () {
      expect(Scoring.computeStars(hintsUsed: -3), 3);
    });

    test('stars cannot depend on time — there is no time to depend on', () {
      // Enforced by the signature rather than by convention: relaxed mode is
      // the product default and timing pressure is what drives this game's
      // audience away (Ch01/Ch02). Blitz (v1.2) gets its own function.
      //
      // Two levels with identical hints but wildly different amounts of play
      // are indistinguishable to this function.
      expect(
        Scoring.computeStars(hintsUsed: 1),
        Scoring.computeStars(hintsUsed: 1),
      );
    });
  });

  group('purity', () {
    test('computeScore is deterministic over repeated calls', () {
      final events = <ScoreEvent>[
        const WordFound(graphemeCount: 5),
        const WordFound(graphemeCount: 4),
        const WrongSelection(),
        const WordFound(graphemeCount: 3),
        const HintUsed(),
      ];

      final first = Scoring.computeScore(events);
      for (var i = 0; i < 100; i++) {
        expect(Scoring.computeScore(events), first);
      }
    });

    test('computeScore does not mutate its input', () {
      final events = <ScoreEvent>[
        const WordFound(graphemeCount: 5),
        const WrongSelection(),
      ];
      final snapshot = List<ScoreEvent>.from(events);

      Scoring.computeScore(events);

      expect(events, snapshot);
    });

    test('an empty level scores zero', () {
      expect(Scoring.computeScore(const []), 0);
      expect(Scoring.maxComboIn(const []), 0);
      expect(Scoring.hintsIn(const []), 0);
    });
  });

  group('the spec header worked example', () {
    test('scores 103 with 2 stars, exactly as documented', () {
      // This case is quoted verbatim in the scoring.dart spec header and is
      // the cross-language parity fixture for the TypeScript port in P14. If
      // this number changes, the port and the spec must change with it.
      final events = <ScoreEvent>[
        const WordFound(graphemeCount: 5),
        const WordFound(graphemeCount: 4),
        const WrongSelection(),
        const WordFound(graphemeCount: 3),
        const HintUsed(),
      ];

      expect(Scoring.computeScore(events), 103);
      expect(Scoring.computeStars(hintsUsed: Scoring.hintsIn(events)), 2);
      expect(Scoring.maxComboIn(events), 2);
    });

    test('the spec version is pinned so a stale client is detectable', () {
      expect(Scoring.specVersion, 1);
    });
  });
}
