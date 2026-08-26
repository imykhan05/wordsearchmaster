import 'dart:math';

/// THE COMBO PITCH LADDER (Ch03) — the signature audio feature.
///
/// One short "found" clip, played back at a rising pentatonic pitch as a
/// combo streak grows: C → D → E → G → A → C, then it holds at the octave
/// for combo 7+. Six correct words in a row must be AUDIBLY a rising musical
/// phrase, not six identical clicks — that is the whole point of this file.
///
/// PURE DART, no `dart:ui`/Flutter and no audio backend: this only computes
/// PLAYBACK-RATE MULTIPLIERS. Changing a sample's playback rate is exactly
/// how "pitch" is implemented here — a plain PCM resample speeds the sample
/// up AND raises its pitch together, which is precisely the chipmunk-style
/// effect a rising musical phrase needs from a single source clip. There is
/// no separate "pitch" API to call; the multiplier IS the instruction.
///
/// SHARES ITS COMBO SHAPE WITH `Scoring` — 1-based, capped at 6 — but is
/// deliberately its own table rather than a reuse of
/// `Scoring.comboPointsPerGrapheme`. Scoring is a normative, cross-language
/// contract (Ch08/P14 ports it to TypeScript byte-for-byte); pitch is a pure
/// presentation concern that will never be replayed server-side, and tying
/// the two together would mean a future scoring-ladder change silently
/// retunes the audio.
abstract final class ComboPitchLadder {
  /// Semitones above the base clip's own pitch, one entry per combo step.
  /// C(0) D(+2) E(+4) G(+7) A(+9) C-octave(+12) — the same five-note scale
  /// (plus its octave) that names the steps in the doc comment above.
  static const List<int> _semitoneSteps = [0, 2, 4, 7, 9, 12];

  /// Longest streak that still climbs the ladder. Combo 7+ holds at the
  /// octave rather than climbing indefinitely — an unbounded pitch ramp
  /// would eventually leave the audible/pleasant range and start sounding
  /// broken rather than exciting.
  static const int maxStep = 6;

  /// The playback-rate multiplier for [combo] (1-based; values below 1 are
  /// clamped up to 1, so a fresh streak's first word is always step 1 — the
  /// unshifted base pitch — even if a caller passes 0).
  static double rateForCombo(int combo) {
    final index = min(max(combo, 1), maxStep) - 1;
    return semitoneRatio(_semitoneSteps[index]);
  }

  /// Equal-tempered frequency ratio for [semitones] above the base pitch:
  /// `2^(semitones/12)`. Exposed on its own because it is the identical
  /// formula a native ear-tuning check would use to verify the asset script
  /// generated `found.wav` at the ladder's own step 1 (C) — see
  /// `tool/generate_audio_assets.py`.
  static double semitoneRatio(int semitones) =>
      pow(2, semitones / 12.0).toDouble();
}
