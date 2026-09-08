#!/usr/bin/env python3
"""Synthesises the P09/post-P18 audio set as tiny 16-bit mono PCM WAV files,
ONE FOLDER PER SoundTheme (lib/domain/audio/sound_theme.dart) under
assets/audio/{theme_id}/.

No external assets exist for the game's audio, and the prompt explicitly
allows synthesised tones instead — stdlib only (`wave`, `struct`, `math`).

THE COMPETITOR RECIPE (docs/competitor-analysis.md, measured spectrally
across three top word games rather than heard): every one of them converges
on fundamental + octave + fifth partials — the harmonic series' own 1x/2x/3x,
the same ratios a real handbell's partials approximate — on every bell-like
SFX, plus a 5-7kHz shimmer layer on celebration moments. `_tone()` below
takes an explicit HARMONICS dict for exactly this: `{1: 1.0, 2: 0.20, 3: 0.12}`
is "fundamental, quieter octave, quieter-still fifth" as one mix, and each
`ThemeProfile` picks its own version of that mix rather than every clip
repeating magic numbers.

`found.wav` is the one clip runtime-pitched by `ComboPitchLadder`
(services/audio/combo_pitch_ladder.dart): every theme's `found.wav` MUST be
built on the SAME fundamental (C6, 1046.502 Hz) so multiplying its playback
rate by the ladder's ratios lands exactly on D6/E6/G6/A6/C7 regardless of
which theme is active — a theme is free to vary the HARMONICS mixed onto that
fundamental (timbre), never the fundamental itself (pitch).

Run with: python3 tool/generate_audio_assets.py
"""

import math
import os
import struct
import wave
from dataclasses import dataclass, field

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


def _tone(freq, duration_s, amplitude=0.55, attack=0.05, decay_power=2.2, harmonics=None):
    """One note: [freq] plus every partial in [harmonics] (a {multiplier:
    relative_amplitude} dict — {1: 1.0} is a bare sine). All partials share
    the same envelope, so the timbre does not shift shape across the note's
    own decay."""
    if harmonics is None:
        harmonics = {1: 1.0}
    n = int(SAMPLE_RATE * duration_s)
    samples = []
    for i in range(n):
        t = i / SAMPLE_RATE
        env = _envelope(i, n, attack, decay_power)
        value = sum(
            amp * math.sin(2 * math.pi * freq * mult * t)
            for mult, amp in harmonics.items()
        )
        samples.append(value * env * amplitude)
    return samples


def _shimmer(duration_s, amplitude=0.10, attack=0.01, decay_power=3.0):
    """A bright 5-7kHz layer, additively mixed onto a celebration clip's
    final note — the fourth measured element of the competitor recipe,
    alongside the fundamental/octave/fifth mix. Three closely-spaced high
    partials rather than one, so it reads as a sparkle/shimmer texture
    rather than a fourth clean pitch."""
    n = int(SAMPLE_RATE * duration_s)
    partials = (5200.0, 6100.0, 7000.0)
    samples = []
    for i in range(n):
        t = i / SAMPLE_RATE
        env = _envelope(i, n, attack, decay_power)
        value = sum(math.sin(2 * math.pi * f * t) for f in partials) / len(partials)
        samples.append(value * env * amplitude)
    return samples


def _mix(*layers):
    """Sums same-length-or-shorter layers into the first (longest) one,
    padding nothing — a shimmer layer shorter than its host note simply
    stops adding once it runs out."""
    length = max(len(layer) for layer in layers)
    out = [0.0] * length
    for layer in layers:
        for i, value in enumerate(layer):
            out[i] += value
    return out


def _concat(*parts):
    out = []
    for part in parts:
        out.extend(part)
    return out


def _silence(duration_s):
    return [0.0] * int(SAMPLE_RATE * duration_s)


def _write_wav(name, samples, sample_rate=SAMPLE_RATE):
    path = os.path.join(OUT_DIR, name)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(sample_rate)
        frames = b"".join(
            struct.pack("<h", max(-32767, min(32767, int(s * 32767))))
            for s in samples
        )
        f.writeframes(frames)
    return path, os.path.getsize(path)


# ---------------------------------------------------------------------------
# Theme profiles
#
# One `ThemeProfile` per `SoundTheme` enum value (Dart), matched by [theme_id]
# — that string doubles as the assets/audio/{theme_id}/ folder name, so a
# mismatch between this file and the Dart enum's `id`s cannot happen silently
# (see `SoundTheme`'s own doc).

@dataclass(frozen=True)
class ThemeProfile:
    theme_id: str

    # The bell/chime mix shared by found/coin/chest_open/level_complete —
    # {1: fundamental, 2: octave, 3: octave+fifth}. found.wav's FUNDAMENTAL
    # frequency is fixed at C6 across every theme (module docstring); only
    # this mix, i.e. the relative harmonic amplitudes, varies.
    bell_harmonics: dict = field(default_factory=lambda: {1: 1.0, 2: 0.20, 3: 0.12})

    found_duration_s: float = 0.11
    found_amplitude: float = 0.6

    tap_duration_s: float = 0.06
    tap_attack: float = 0.10
    tap_decay_power: float = 2.0
    tap_amplitude: float = 0.42
    # A soft second harmonic, unlike the ORIGINAL pre-competitor-analysis tap
    # (a bare single partial) — this is the "every click gets a soft,
    # interactive sound" half of the brief, not just the celebration clips.
    tap_harmonic_amplitude: float = 0.14

    # Celebration clips (chest_open, level_complete) get the shimmer layer;
    # `minimal` turns it off outright rather than shrinking it, matching
    # every other "skip, don't shorten" treatment this codebase uses for a
    # deliberately-absent effect (CLAUDE.md's reduce-motion rule, for one).
    shimmer_enabled: bool = True
    shimmer_amplitude: float = 0.10

    # Music bed. `note_gap_s` is the spacing between the pentatonic figure's
    # own notes (smaller = busier); `figure_amplitude` scales the moving
    # figure alone, separately from the sustained pad underneath it, and
    # `figure_enabled=False` (minimal) drops the figure entirely rather than
    # just quieting it — a bed that is JUST a pad reads as "nothing is
    # happening," which is exactly minimal's brief.
    note_gap_s: float = 1.0
    note_decay_s: float = 1.9
    figure_amplitude: float = 0.115
    figure_enabled: bool = True
    pad_amplitude_scale: float = 1.0


THEMES = [
    # Default. The competitor recipe as measured, applied with no further
    # embellishment: audible-but-quiet octave (0.20) and fifth (0.12) on
    # every bell clip, the original P09 tempo pentatonic figure, shimmer on.
    ThemeProfile(theme_id="soft_bells"),
    # Brighter and busier: a louder fifth partial (more upper-partial energy
    # reads as "livelier" per the competitor notes), shorter note spacing so
    # the bed's figure moves more often, and a stronger shimmer.
    ThemeProfile(
        theme_id="chimes",
        bell_harmonics={1: 1.0, 2: 0.22, 3: 0.20},
        found_duration_s=0.10,
        tap_duration_s=0.05,
        tap_harmonic_amplitude=0.18,
        shimmer_amplitude=0.16,
        note_gap_s=0.65,
        note_decay_s=1.2,
        figure_amplitude=0.13,
    ),
    # The quietest option: fundamental plus a faint octave only (no fifth),
    # shorter clips, no shimmer, and a bed that is JUST the sustained pad —
    # see [figure_enabled]'s own doc for why that is "no figure," not "a
    # quiet figure."
    ThemeProfile(
        theme_id="minimal",
        bell_harmonics={1: 1.0, 2: 0.10},
        found_duration_s=0.09,
        found_amplitude=0.5,
        tap_duration_s=0.045,
        tap_amplitude=0.32,
        tap_harmonic_amplitude=0.0,
        shimmer_enabled=False,
        figure_enabled=False,
        pad_amplitude_scale=0.6,
    ),
]


def generate_sfx(profile: ThemeProfile):
    clips = {}
    h = profile.bell_harmonics

    # found.wav — the base tone the combo pitch ladder plays back at C6, D6,
    # E6, G6, A6, C7. FUNDAMENTAL FIXED AT C6 ACROSS EVERY THEME — see the
    # module docstring.
    clips["found.wav"] = _tone(
        C6,
        profile.found_duration_s,
        amplitude=profile.found_amplitude,
        attack=0.04,
        decay_power=2.5,
        harmonics=h,
    )

    # button_tap.wav — every UI tap, softened relative to the pre-analysis
    # version (CLAUDE.md → "every click/action has a soft interactive
    # sound"): a longer, gentler attack than a dry click, plus a soft second
    # harmonic rather than none.
    clips["button_tap.wav"] = _tone(
        500,
        profile.tap_duration_s,
        amplitude=profile.tap_amplitude,
        attack=profile.tap_attack,
        decay_power=profile.tap_decay_power,
        harmonics={1: 1.0, 2: profile.tap_harmonic_amplitude},
    )

    # coin.wav — a quick two-note "ding-ding" arcade coin pickup, in the same
    # bell mix as found.wav.
    coin = _concat(
        _tone(A5, 0.07, amplitude=0.55, attack=0.03, decay_power=2.0, harmonics=h),
        _tone(E6, 0.12, amplitude=0.55, attack=0.02, decay_power=2.2, harmonics=h),
    )
    clips["coin.wav"] = coin

    # chest_open.wav — a four-note ascending sparkle (C6 D6 G6 C7), the final
    # note carrying the shimmer layer when the theme has one.
    chest_final = _tone(C7, 0.14, amplitude=0.55, attack=0.02, decay_power=1.8, harmonics=h)
    if profile.shimmer_enabled:
        chest_final = _mix(chest_final, _shimmer(0.14, amplitude=profile.shimmer_amplitude))
    clips["chest_open.wav"] = _concat(
        _tone(C6, 0.08, amplitude=0.5, attack=0.02, decay_power=2.0, harmonics=h),
        _tone(D6, 0.08, amplitude=0.5, attack=0.02, decay_power=2.0, harmonics=h),
        _tone(G6, 0.09, amplitude=0.5, attack=0.02, decay_power=2.0, harmonics=h),
        chest_final,
    )

    # level_complete.wav — a five-note fanfare with a tiny gap before the
    # final held note ("...and DONE"), which carries the shimmer.
    lc_final = _tone(E6, 0.22, amplitude=0.6, attack=0.02, decay_power=1.6, harmonics=h)
    if profile.shimmer_enabled:
        lc_final = _mix(lc_final, _shimmer(0.22, amplitude=profile.shimmer_amplitude))
    clips["level_complete.wav"] = _concat(
        _tone(C5, 0.11, amplitude=0.55, attack=0.02, decay_power=2.0, harmonics=h),
        _tone(E5, 0.11, amplitude=0.55, attack=0.02, decay_power=2.0, harmonics=h),
        _tone(G5, 0.11, amplitude=0.55, attack=0.02, decay_power=2.0, harmonics=h),
        _silence(0.03),
        _tone(C6, 0.10, amplitude=0.55, attack=0.02, decay_power=1.8, harmonics=h),
        lc_final,
    )

    total = 0
    for name, samples in clips.items():
        path, size = _write_wav(os.path.join(profile.theme_id, name), samples)
        total += size
        print(f"  {name}: {size / 1024:.1f} KB")
    return total


# ---------------------------------------------------------------------------
# Background music (Ch03's "soft, unobtrusive" bed)
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
# 256KB per theme — which is what keeps three themes' worth of audio inside a
# still-modest total budget (see this file's own final print for the number).

MUSIC_SAMPLE_RATE = 16000
MUSIC_LOOP_SECONDS = 8.0


def _snap(freq):
    """Round to a whole multiple of the loop fundamental — see above."""
    fundamental = 1.0 / MUSIC_LOOP_SECONDS
    return round(freq / fundamental) * fundamental


def _music_loop(profile: ThemeProfile):
    n = int(MUSIC_SAMPLE_RATE * MUSIC_LOOP_SECONDS)
    out = [0.0] * n

    # A sustained, barely-there chord, re-voiced onto the SAME
    # fundamental/octave/fifth idea as the SFX (rather than the original
    # fundamental-plus-bare-second-harmonic pad) so the bed and the SFX read
    # as one instrument. Continuous across the wrap because each frequency
    # is snapped; no envelope at all, so nothing to line up.
    pad_scale = profile.pad_amplitude_scale
    for freq, amp in (
        (130.813, 0.055 * pad_scale),
        (195.998, 0.040 * pad_scale),
        (261.626, 0.030 * pad_scale),
    ):
        f = _snap(freq)
        for i in range(n):
            out[i] += amp * math.sin(2 * math.pi * f * i / MUSIC_SAMPLE_RATE)

    if not profile.figure_enabled:
        return out

    # A slow pentatonic figure over the top (C D E G A — the same scale
    # ComboPitchLadder walks, so the found-word chimes sit in key with the
    # bed rather than against it). [note_gap_s] scales how far apart the
    # figure's own notes fall; the PATTERN (which note follows which) is
    # unchanged across themes, only its tempo. Each note is written with its
    # index taken modulo n, so a tail running past the end reappears at the
    # start where the next pass will continue it seamlessly.
    pattern = [
        (0.0, C5),
        (1.0, G5),
        (2.0, E5),
        (3.0, A5),
        (4.0, G5),
        (5.0, D5),
        (6.0, E5),
        (7.0, 392.000),  # G4
    ]
    attack_seconds = 0.035
    length = int(profile.note_decay_s * MUSIC_SAMPLE_RATE)
    attack_n = max(1, int(attack_seconds * MUSIC_SAMPLE_RATE))
    for beat, freq in pattern:
        start_s = beat * profile.note_gap_s
        # A loop this dense (chimes' 0.65s gap) can start past the buffer's
        # own end before wrapping — take it modulo the loop length up front
        # so `start` below is always a valid in-buffer index.
        start = int(start_s * MUSIC_SAMPLE_RATE) % n
        f = _snap(freq)
        f2 = _snap(freq * 2)
        for j in range(length):
            if j < attack_n:
                env = j / attack_n
            else:
                env = (1.0 - (j - attack_n) / (length - attack_n)) ** 2.6
            i = (start + j) % n
            t = i / MUSIC_SAMPLE_RATE
            value = math.sin(2 * math.pi * f * t)
            value += 0.12 * math.sin(2 * math.pi * f2 * t)
            out[i] += profile.figure_amplitude * env * value

    return out


def generate_music(profile: ThemeProfile):
    samples = _music_loop(profile)
    peak = max(abs(s) for s in samples)

    # Leave real headroom: this plays UNDER the SFX for the whole session,
    # and a bed that competes with the found-word chime is a bed players
    # switch off. `minimal`'s pad has no figure and a lower peak already
    # (pad_amplitude_scale), so it normalises to the SAME target rather than
    # ending up louder relative to its own quiet character — the explicit
    # target, not "whatever this theme's own peak happens to be," is what
    # keeps every theme's bed at a comparable loudness under the SFX.
    target_peak = 0.30
    samples = [s * (target_peak / peak) for s in samples]

    # The seam is the whole point, so measure it rather than trusting it: the
    # step from the last sample back to the first must be no larger than a
    # step anywhere inside the buffer.
    seam = abs(samples[0] - samples[-1])
    biggest_internal = max(
        abs(samples[i + 1] - samples[i]) for i in range(0, len(samples) - 1, 7)
    )
    # A THEME WITH NO MOVING FIGURE (`minimal`) needs an epsilon here that a
    # busy bed does not: with nothing but the smooth sustained pad, the
    # seam step and the largest internal step are the SAME mathematical
    # quantity by the snapping construction above, and the only way they can
    # differ at all is float rounding in `sin(2*pi*f*t)` at t=0 versus
    # t=MUSIC_LOOP_SECONDS — not a real discontinuity, which would be many
    # orders of magnitude larger than this. A busy figure's own attack ramps
    # dwarf that noise, which is why this only ever bites the pad-only case.
    assert seam <= biggest_internal + 1e-9, f"{profile.theme_id}: loop seam would click"

    name, size = _write_wav(
        os.path.join(profile.theme_id, "music_loop.wav"),
        samples,
        sample_rate=MUSIC_SAMPLE_RATE,
    )
    print(f"  music_loop.wav: {size / 1024:.1f} KB (peak before headroom {peak:.3f})")
    return size


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    grand_total = 0
    for profile in THEMES:
        print(f"{profile.theme_id}/")
        grand_total += generate_sfx(profile)
        grand_total += generate_music(profile)
    print(f"TOTAL across {len(THEMES)} themes: {grand_total / 1024:.1f} KB")


if __name__ == "__main__":
    main()
