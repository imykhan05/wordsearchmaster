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


if __name__ == "__main__":
    main()
