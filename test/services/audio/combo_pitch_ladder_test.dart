import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:word_search_master/services/audio/combo_pitch_ladder.dart';

/// The signature audio feature (Ch03): pins the pentatonic ladder itself,
/// pure Dart and independent of any audio backend. The end-to-end "6 words
/// in a row is audibly a rising phrase" acceptance criterion is proven at
/// the integration level in `game_screen_test.dart`, which asserts THIS
/// table is what actually gets called with a real combo sequence — this
/// file is where the table's own shape is pinned.
void main() {
  group('rateForCombo — the pentatonic ladder C D E G A C', () {
    test('step 1 is the unshifted base pitch', () {
      expect(ComboPitchLadder.rateForCombo(1), 1.0);
    });

    test('steps 2..6 match 2^(semitones/12) for D E G A C — 2,4,7,9,12', () {
      const semitones = [2, 4, 7, 9, 12];
      for (var i = 0; i < semitones.length; i++) {
        final combo = i + 2;
        final expected = pow(2, semitones[i] / 12.0).toDouble();
        expect(
          ComboPitchLadder.rateForCombo(combo),
          closeTo(expected, 1e-9),
          reason: 'combo $combo',
        );
      }
    });

    test('step 6 lands exactly on the octave — rate 2.0', () {
      expect(ComboPitchLadder.rateForCombo(6), closeTo(2.0, 1e-9));
    });

    test('is STRICTLY increasing across 1..6 — the audible "rising" part', () {
      final rates = [
        for (var combo = 1; combo <= 6; combo++)
          ComboPitchLadder.rateForCombo(combo),
      ];
      for (var i = 1; i < rates.length; i++) {
        expect(
          rates[i],
          greaterThan(rates[i - 1]),
          reason: 'combo ${i + 1} must sound higher than combo $i',
        );
      }
    });

    test('combo 7+ holds at the octave rather than climbing further', () {
      final atSix = ComboPitchLadder.rateForCombo(6);
      expect(ComboPitchLadder.rateForCombo(7), atSix);
      expect(ComboPitchLadder.rateForCombo(50), atSix);
    });

    test(
      '0 and negative combos clamp up to step 1, never crash or go silent',
      () {
        expect(
          ComboPitchLadder.rateForCombo(0),
          ComboPitchLadder.rateForCombo(1),
        );
        expect(
          ComboPitchLadder.rateForCombo(-3),
          ComboPitchLadder.rateForCombo(1),
        );
      },
    );
  });

  group('semitoneRatio', () {
    test('0 semitones is unity', () {
      expect(ComboPitchLadder.semitoneRatio(0), 1.0);
    });

    test('12 semitones is exactly one octave — double the frequency', () {
      expect(ComboPitchLadder.semitoneRatio(12), closeTo(2.0, 1e-9));
    });

    test('is the equal-tempered formula, not an approximation', () {
      for (final semitones in [1, 2, 4, 7, 9, 11]) {
        expect(
          ComboPitchLadder.semitoneRatio(semitones),
          closeTo(pow(2, semitones / 12.0).toDouble(), 1e-12),
        );
      }
    });
  });
}
