#!/usr/bin/env python3
"""Synthesises the five P09 SFX clips as tiny 16-bit mono PCM WAV files.

No external assets exist for Ch03's juice pass, and the prompt explicitly
allows synthesised tones instead. Kept intentionally simple (sine partials +
a short envelope, stdlib only — `wave`, `struct`, `math`) so the whole set
stays well under the 400KB budget while still reading as five distinct,
recognisable game sounds rather than five identical beeps.

`found.wav` is the one clip runtime-pitched by `ComboPitchLadder`
(services/audio/combo_pitch_ladder.dart): it MUST be a single clean tone at
C6 (1046.502 Hz) so multiplying its playback rate by the ladder's ratios
lands exactly on D6/E6/G6/A6/C7, not on some other combination of partials
beating against each other.

Run with: python3 tool/generate_audio_assets.py
"""

import math
import os
import struct
import wave

SAMPLE_RATE = 22050
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")

# Equal-tempered frequencies, A4 = 440Hz.
C5, D5, E5, G5, A5 = 523.251, 587.330, 659.255, 783.991, 880.000
C6, D6, E6, G6, A6 = 1046.502, 1174.659, 1318.510, 1567.982, 1760.000
C7 = 2093.005


def _envelope(i, n, attack, decay_power):
    """Fast linear attack, then a smooth power-curve decay to silence."""
    attack_n = max(1, int(n * attack))
    if i < attack_n:
        return i / attack_n
    t = (i - attack_n) / max(1, (n - attack_n))
    return (1.0 - t) ** decay_power


def _tone(freq, duration_s, amplitude=0.55, attack=0.05, decay_power=2.2, harmonic=0.18):
    """One note: a fundamental sine plus a soft second harmonic for timbre."""
    n = int(SAMPLE_RATE * duration_s)
    samples = []
    for i in range(n):
        t = i / SAMPLE_RATE
        env = _envelope(i, n, attack, decay_power)
        value = math.sin(2 * math.pi * freq * t)
        value += harmonic * math.sin(2 * math.pi * freq * 2 * t)
        samples.append(value * env * amplitude)
    return samples


def _concat(*parts):
    out = []
    for part in parts:
        out.extend(part)
    return out


def _silence(duration_s):
    return [0.0] * int(SAMPLE_RATE * duration_s)


def _write_wav(name, samples):
    path = os.path.join(OUT_DIR, name)
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SAMPLE_RATE)
        frames = b"".join(
            struct.pack("<h", max(-32767, min(32767, int(s * 32767))))
            for s in samples
        )
        f.writeframes(frames)
    return path, os.path.getsize(path)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    clips = {}

    # found.wav — the base tone the combo pitch ladder plays back at C6, D6,
    # E6, G6, A6, C7. A clean plucky "ding": fast attack, quick decay, 110ms.
    clips["found.wav"] = _tone(C6, 0.11, amplitude=0.6, attack=0.04, decay_power=2.5)

    # button_tap.wav — a soft 40ms UI tock. No harmonic; a click reads better
    # with a single clean partial.
    clips["button_tap.wav"] = _tone(
        500, 0.045, amplitude=0.45, attack=0.08, decay_power=1.8, harmonic=0.0
    )

    # coin.wav — a quick two-note "ding-ding" arcade coin pickup.
    clips["coin.wav"] = _concat(
        _tone(A5, 0.07, amplitude=0.55, attack=0.03, decay_power=2.0),
        _tone(E6, 0.12, amplitude=0.55, attack=0.02, decay_power=2.2),
    )

    # chest_open.wav — a four-note ascending sparkle (pentatonic-flavoured,
    # matching the game's musical language): C6 D6 G6 C7.
    clips["chest_open.wav"] = _concat(
        _tone(C6, 0.08, amplitude=0.5, attack=0.02, decay_power=2.0),
        _tone(D6, 0.08, amplitude=0.5, attack=0.02, decay_power=2.0),
        _tone(G6, 0.09, amplitude=0.5, attack=0.02, decay_power=2.0),
        _tone(C7, 0.14, amplitude=0.55, attack=0.02, decay_power=1.8),
    )

    # level_complete.wav — a five-note triumphant fanfare with a tiny gap
    # before the final held note, so it reads as "...and DONE" rather than
    # one continuous run.
    clips["level_complete.wav"] = _concat(
        _tone(C5, 0.11, amplitude=0.55, attack=0.02, decay_power=2.0),
        _tone(E5, 0.11, amplitude=0.55, attack=0.02, decay_power=2.0),
        _tone(G5, 0.11, amplitude=0.55, attack=0.02, decay_power=2.0),
        _silence(0.03),
        _tone(C6, 0.10, amplitude=0.55, attack=0.02, decay_power=1.8),
        _tone(E6, 0.22, amplitude=0.6, attack=0.02, decay_power=1.6),
    )

    total = 0
    for name, samples in clips.items():
        path, size = _write_wav(name, samples)
        total += size
        print(f"{name}: {size / 1024:.1f} KB")
    print(f"TOTAL: {total / 1024:.1f} KB")


# ---------------------------------------------------------------------------
# Background music (Ch03's "soft, unobtrusive" bed, added after P09)
#
# A LOOP, not a clip, which changes the synthesis rules completely: the last
# sample has to flow into the first with no discontinuity, or every pass round
# the loop fires an audible click.
#
# The trick that makes that exact rather than approximate: every partial is
# snapped to a whole multiple of the loop's own fundamental (1 / LOOP_SECONDS).
# A sine whose frequency is k/L completes exactly k cycles in L seconds, so
# sin(2*pi*f*(t+L)) == sin(2*pi*f*t) — the waveform is periodic in the loop by
# construction, and note tails can be wrapped modulo the buffer instead of
# being cut off. The detune this costs is at most half of 1/L (0.0625 Hz at
# L=8), far below anything audible.
#
# 16kHz rather than the SFX 22.05kHz: this is a low, mellow pad with almost no
# energy above 4kHz, and the rate drops 8 seconds of audio from 353KB to
# 256KB — which is what keeps the whole audio set inside its 400KB budget.

MUSIC_SAMPLE_RATE = 16000
MUSIC_LOOP_SECONDS = 8.0


def _snap(freq):
    """Round to a whole multiple of the loop fundamental — see above."""
    fundamental = 1.0 / MUSIC_LOOP_SECONDS
    return round(freq / fundamental) * fundamental


def _music_loop():
    n = int(MUSIC_SAMPLE_RATE * MUSIC_LOOP_SECONDS)
    out = [0.0] * n

    # A sustained, barely-there chord. Continuous across the wrap because
    # each frequency is snapped; no envelope at all, so nothing to line up.
    for freq, amp in ((130.813, 0.055), (195.998, 0.040), (261.626, 0.030)):
        f = _snap(freq)
        for i in range(n):
            out[i] += amp * math.sin(2 * math.pi * f * i / MUSIC_SAMPLE_RATE)

    # A slow pentatonic figure over the top (C D E G A — the same scale
    # ComboPitchLadder walks, so the found-word chimes sit in key with the
    # bed rather than against it). Each note is written with its index taken
    # modulo n, so a tail running past the end reappears at the start where
    # the next pass will continue it seamlessly.
    pattern = [
        (0.0, 523.251),
        (1.0, 783.991),
        (2.0, 659.255),
        (3.0, 880.000),
        (4.0, 783.991),
        (5.0, 587.330),
        (6.0, 659.255),
        (7.0, 392.000),
    ]
    decay_seconds = 1.9
    attack_seconds = 0.035
    for start_s, freq in pattern:
        f = _snap(freq)
        f2 = _snap(freq * 2)
        start = int(start_s * MUSIC_SAMPLE_RATE)
        length = int(decay_seconds * MUSIC_SAMPLE_RATE)
        attack_n = max(1, int(attack_seconds * MUSIC_SAMPLE_RATE))
        for j in range(length):
            if j < attack_n:
                env = j / attack_n
            else:
                env = (1.0 - (j - attack_n) / (length - attack_n)) ** 2.6
            i = (start + j) % n
            t = i / MUSIC_SAMPLE_RATE
            value = math.sin(2 * math.pi * f * t)
            value += 0.12 * math.sin(2 * math.pi * f2 * t)
            out[i] += 0.115 * env * value

    return out


def _write_music(name, samples):
    path = os.path.join(OUT_DIR, name)
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(MUSIC_SAMPLE_RATE)
        f.writeframes(
            b"".join(
                struct.pack("<h", max(-32767, min(32767, int(s * 32767))))
                for s in samples
            )
        )
    return path, os.path.getsize(path)


def generate_music():
    samples = _music_loop()
    peak = max(abs(s) for s in samples)
    print(f"music peak before headroom: {peak:.3f}")
    # Leave real headroom: this plays UNDER the SFX for the whole session,
    # and a bed that competes with the found-word chime is a bed players
    # switch off.
    target_peak = 0.30
    samples = [s * (target_peak / peak) for s in samples]

    # The seam is the whole point, so measure it rather than trusting it: the
    # step from the last sample back to the first must be no larger than a
    # step anywhere inside the buffer.
    seam = abs(samples[0] - samples[-1])
    biggest_internal = max(
        abs(samples[i + 1] - samples[i]) for i in range(0, len(samples) - 1, 7)
    )
    print(f"seam step {seam:.5f} vs largest internal step {biggest_internal:.5f}")
    assert seam <= biggest_internal, "loop seam would click"

    name, size = _write_music("music_loop.wav", samples)
    print(f"music_loop.wav: {size / 1024:.1f} KB")


if __name__ == "__main__":
    main()
    generate_music()
