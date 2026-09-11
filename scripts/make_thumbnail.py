#!/usr/bin/env python3
"""Compose the YouTube thumbnail for the Icos promo video.

1280x720, the size YouTube wants. Brand colours and the real Inter typeface the
app ships, with a real grid lifted out of a real screenshot rather than a mockup.

Usage:
    python3 scripts/make_thumbnail.py [output.png]
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
FONTS = Path('/tmp/fonts')
W, H = 1280, 720

NAVY = (10, 22, 40)
AMBER = (255, 145, 0)
WHITE = (255, 255, 255)
MUTED = (148, 163, 184)


def radial_glow(size, colour, strength=0.55):
    """Soft circular glow, drawn small and blurred up so the falloff is smooth."""
    small = 160
    g = Image.new('L', (small, small), 0)
    d = ImageDraw.Draw(g)
    steps = 44
    for i in range(steps):
        t = i / steps
        r = int(small / 2 * (1 - t))
        v = int(255 * strength * (t ** 2.1))
        d.ellipse([small / 2 - r, small / 2 - r, small / 2 + r, small / 2 + r], fill=v)
    g = g.resize((size, size), Image.LANCZOS).filter(ImageFilter.GaussianBlur(size // 18))
    layer = Image.new('RGBA', (size, size), colour + (0,))
    layer.putalpha(g)
    return layer


def rounded(img, radius):
    mask = Image.new('L', img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, img.width - 1, img.height - 1],
                                           radius=radius, fill=255)
    out = Image.new('RGBA', img.size, (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)
    return out


def tracked(draw, xy, text, font, fill, tracking):
    """drawtext with letter spacing, which PIL has no option for."""
    x, y = xy
    for ch in text:
        draw.text((x, y), ch, font=font, fill=fill)
        x += draw.textlength(ch, font=font) + tracking
    return x


def main() -> int:
    out_path = Path(sys.argv[1]) if len(sys.argv) > 1 else \
        ROOT / 'release' / 'youtube' / 'icos-thumbnail-1280x720.png'

    canvas = Image.new('RGB', (W, H), NAVY)

    grid = Image.open('/tmp/grid_crop.png').convert('RGBA')
    side = 560
    grid = grid.resize((side, side), Image.LANCZOS)
    grid = rounded(grid, 26)

    # Nudged up and in: YouTube stamps the video duration over the bottom-right
    # corner, and it should not land on the board.
    gx, gy = W - side - 92, (H - side) // 2 - 26

    # Amber bloom behind the board so it lifts off the navy.
    glow = radial_glow(int(side * 2.05), AMBER, 0.52)
    canvas.paste(glow, (gx + side // 2 - glow.width // 2,
                        gy + side // 2 - glow.height // 2), glow)
    # A cool counter-glow on the text side keeps the left half from going flat.
    cool = radial_glow(760, (123, 31, 162), 0.34)
    canvas.paste(cool, (-190, H - 430), cool)

    canvas.paste(grid, (gx, gy), grid)

    d = ImageDraw.Draw(canvas)
    eyebrow = ImageFont.truetype(str(FONTS / 'Inter-Bold.ttf'), 30)
    title = ImageFont.truetype(str(FONTS / 'Inter-Bold.ttf'), 170)
    tag = ImageFont.truetype(str(FONTS / 'Inter-Medium.ttf'), 46)
    foot = ImageFont.truetype(str(FONTS / 'Inter-Medium.ttf'), 30)

    left = 82
    tracked(d, (left, 168), 'DAILY PUZZLE', eyebrow, AMBER, 6)
    d.text((left - 8, 214), 'ICOS', font=title, fill=WHITE)
    d.text((left, 410), 'One line.', font=tag, fill=MUTED)
    d.text((left, 466), 'Every cell.', font=tag, fill=MUTED)

    d.rounded_rectangle([left, 546, left + 96, 552], radius=3, fill=AMBER)
    d.text((left, 586), 'Free  ·  No ads  ·  New puzzle daily', font=foot, fill=MUTED)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out_path, 'PNG', optimize=True)
    kb = out_path.stat().st_size // 1024
    print(f'wrote {out_path} ({W}x{H}, {kb} KB)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
