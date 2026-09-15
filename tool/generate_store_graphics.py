"""Generates the Play Store graphics that are pure branding art.

Screenshots are NOT here and must not be: Play requires those to show the
real app, so they come off a device (`tool/capture_store_screenshots.ps1`).
What this makes is the feature graphic and the promo-video frames, both of
which are artwork about the app rather than depictions of it.

Every colour below is read from the app's own shipped palette
(`lib/app/theme/app_tokens.dart` -> daylight/midnight) rather than invented,
so the store page and the app are recognisably the same product.

    python3 tool/generate_store_graphics.py
"""

from __future__ import annotations

import math
import os
import random
import subprocess
import sys
from PIL import Image, ImageDraw, ImageFont

OUT = "docs/store-listing/assets"
VIDEO_FRAMES = os.path.join(OUT, "promo_frames")

# Sampled from the app's own tokens so the listing matches the product.
INK = (20, 26, 23)
PARCHMENT = (247, 238, 224)
MARIGOLD = (232, 163, 61)
DEEP = (16, 22, 20)
MUTED = (120, 132, 124)

FONT_BOLD = "assets/fonts/NotoSans-Bold.ttf"
FONT_REG = "assets/fonts/NotoSans-Regular.ttf"
FONT_URDU = "assets/fonts/NotoNaskhArabic-Bold.ttf"
FONT_HINDI = "assets/fonts/NotoSansDevanagari-Bold.ttf"


def font(path: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(path, size)


def centre(draw: ImageDraw.ImageDraw, xy, text, fnt, fill):
    """Draws `text` centred on `xy`, which is what every caller wants."""
    left, top, right, bottom = draw.textbbox((0, 0), text, font=fnt)
    draw.text(
        (xy[0] - (right - left) / 2 - left, xy[1] - (bottom - top) / 2 - top),
        text,
        font=fnt,
        fill=fill,
    )


def letter_grid(
    draw: ImageDraw.ImageDraw,
    origin: tuple[int, int],
    cell: int,
    cols: int,
    rows: int,
    seed: int,
    colour,
    highlight: tuple[int, int, int] | None = None,
    highlight_colour=MARIGOLD,
):
    """A decorative word-grid motif — the app's own subject as ornament.

    `highlight` is (row, col_start, length): a horizontal run drawn as the
    selection capsule the game itself draws, which is the single most
    recognisable thing about this app.
    """
    rnd = random.Random(seed)
    alphabet = "ABCDEFGHIJKLMNOPRSTUVWY"
    fnt = font(FONT_BOLD, int(cell * 0.62))

    if highlight:
        hr, hc, hlen = highlight
        x0 = origin[0] + hc * cell
        y0 = origin[1] + hr * cell
        draw.rounded_rectangle(
            [x0 + cell * 0.08, y0 + cell * 0.08,
             x0 + (hlen - 1) * cell + cell * 0.92, y0 + cell * 0.92],
            radius=int(cell * 0.46),
            fill=highlight_colour + (70,) if len(highlight_colour) == 3 else highlight_colour,
            outline=highlight_colour,
            width=max(2, cell // 22),
        )

    for r in range(rows):
        for c in range(cols):
            centre(
                draw,
                (origin[0] + c * cell + cell / 2, origin[1] + r * cell + cell / 2),
                rnd.choice(alphabet),
                fnt,
                colour,
            )


def feature_graphic() -> str:
    """1024x500, Play's required feature graphic.

    No screenshot inside it and no claim of a rating or a download count —
    both are Play policy tripwires, and the second is the commonest reason a
    graphic gets rejected on an app that has neither yet.
    """
    w, h = 1024, 500
    img = Image.new("RGB", (w, h), DEEP)
    draw = ImageDraw.Draw(img, "RGBA")

    # A wash so the right side lifts away from the grid on the left.
    for x in range(w):
        t = x / w
        draw.line(
            [(x, 0), (x, h)],
            fill=(
                int(DEEP[0] + (26 - DEEP[0]) * t),
                int(DEEP[1] + (34 - DEEP[1]) * t),
                int(DEEP[2] + (30 - DEEP[2]) * t),
            ),
        )

    letter_grid(
        draw, (44, 62), 62, 6, 6, seed=7,
        colour=(255, 255, 255, 34),
        highlight=(2, 0, 5),
        highlight_colour=MARIGOLD,
    )

    draw.text((470, 150), "Word Search", font=font(FONT_BOLD, 66), fill=PARCHMENT)
    draw.text((470, 224), "Master", font=font(FONT_BOLD, 66), fill=MARIGOLD)
    draw.text(
        (474, 320),
        "Urdu  ·  Hindi  ·  English",
        font=font(FONT_REG, 30),
        fill=(210, 205, 195),
    )
    draw.text(
        (474, 366),
        "No timer.  Works offline.",
        font=font(FONT_REG, 28),
        fill=MUTED,
    )

    path = os.path.join(OUT, "feature_graphic_1024x500.png")
    img.save(path)
    return path


def promo_frames(seconds: int = 24, fps: int = 30) -> int:
    """Frames for a promo video, 1080x1920.

    Play's "promo video" field takes a YOUTUBE URL, not a file — so this
    exists to be uploaded to YouTube first and linked from the listing. It is
    deliberately typographic rather than a fake gameplay recording: a video
    that mimes gameplay it never actually captured is the same
    misrepresentation the screenshot rule is about.
    """
    os.makedirs(VIDEO_FRAMES, exist_ok=True)
    for old in os.listdir(VIDEO_FRAMES):
        os.remove(os.path.join(VIDEO_FRAMES, old))

    w, h = 1080, 1920
    total = seconds * fps

    cards = [
        ("Word Search", "Master", None),
        ("Three scripts.", "One puzzle.", "اردو · हिंदी · English"),
        ("No timer.", "No pressure.", None),
        ("300 levels.", "Fully offline.", None),
        ("A new puzzle", "every day.", None),
        ("Free on", "Google Play", None),
    ]
    per = total // len(cards)

    for i in range(total):
        card_index = min(i // per, len(cards) - 1)
        local = (i % per) / per
        top, bottom, sub = cards[card_index]

        img = Image.new("RGB", (w, h), DEEP)
        draw = ImageDraw.Draw(img, "RGBA")

        # The grid drifts slowly behind every card, so the video reads as one
        # piece rather than six slides.
        drift = int(math.sin((i / total) * math.pi * 2) * 26)
        letter_grid(
            draw, (60 + drift, 240), 118, 8, 12, seed=11,
            colour=(255, 255, 255, 20),
        )

        # Ease in, hold, ease out — nothing cuts hard.
        if local < 0.18:
            alpha = local / 0.18
        elif local > 0.86:
            alpha = max(0.0, (1 - local) / 0.14)
        else:
            alpha = 1.0
        a = int(255 * alpha)

        centre(draw, (w / 2, h / 2 - 90), top, font(FONT_BOLD, 96), PARCHMENT + (a,))
        centre(draw, (w / 2, h / 2 + 30), bottom, font(FONT_BOLD, 96), MARIGOLD + (a,))
        if sub:
            sub_font = font(FONT_REG, 46)
            centre(draw, (w / 2, h / 2 + 170), sub, sub_font, (205, 200, 190, a))

        img.save(os.path.join(VIDEO_FRAMES, f"f{i:05d}.png"))

    return total


def encode_video(fps: int = 30) -> str:
    out = os.path.join(OUT, "promo_video.mp4")
    subprocess.run(
        [
            "ffmpeg", "-y", "-loglevel", "error",
            "-framerate", str(fps),
            "-i", os.path.join(VIDEO_FRAMES, "f%05d.png"),
            # yuv420p + even dimensions: without both, the file plays
            # everywhere except the places that matter.
            "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "20",
            out,
        ],
        check=True,
    )
    return out


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    print("feature graphic:", feature_graphic())
    frames = promo_frames()
    print("promo frames:", frames)
    print("promo video:", encode_video())
