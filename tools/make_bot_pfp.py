"""Draw the Macro Creator bot's profile picture.

    python tools/make_bot_pfp.py          (run from the repo root)

Writes assets/bot_pfp/macro_creator.png (1024x1024) and a 512 copy. Same flat,
hand-made style as the webhook pictures (tools/make_webhook_pfps.py): solid
Moontide navy, the gold crescent with one flat shadow band, plus what marks
the bot apart: a big four-point spark being "made" in the crescent's open
side and a flat orbit ring around both (behind the moon at the top, in front
at the bottom). No gradients, glows or blur. Kept inside the middle circle,
since Discord crops avatars round. Needs Python 3 + Pillow. Not used at runtime.
"""
import os
import sys
from PIL import Image, ImageChops, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_webhook_pfps import _star, crescent_mask, mix, rgb  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "bot_pfp")
SIZE = 1024
SS = 2

PANEL, GOLD, CREAM = rgb("0B2A5B"), rgb("F2A93B"), rgb("FFF4DC")
TILT = -16  # degrees the orbit is tilted


def orbit_layer(n, half):
    """Flat orbit ring; half='back' keeps the top half, 'front' the bottom half."""
    c = n / 2
    rx, ry, w = n * 0.41, n * 0.12, n * 0.016
    ring = Image.new("L", (n, n), 0)
    ImageDraw.Draw(ring).ellipse((c - rx, c - ry, c + rx, c + ry), outline=255, width=int(w))
    keep = Image.new("L", (n, n), 0)
    box = (0, 0, n, c) if half == "back" else (0, c, n, n)
    ImageDraw.Draw(keep).rectangle(box, fill=255)
    ring = ImageChops.multiply(ring, keep)
    return ring.rotate(TILT, center=(c, c * 1.04), resample=Image.BICUBIC)


def draw():
    n = SIZE * SS
    c = n / 2
    im = Image.new("RGB", (n, n), PANEL)
    d = ImageDraw.Draw(im)

    # thin flat edge ring + a few plain stars, like the webhook pictures
    rr = n * 0.43
    d.ellipse((c - rr, c - rr, c + rr, c + rr), outline=mix(PANEL, GOLD, 0.35), width=int(n * 0.012))
    for fx, fy in [(0.24, 0.28), (0.78, 0.74), (0.30, 0.80)]:
        s = n * 0.011
        d.ellipse((fx * n - s, fy * n - s, fx * n + s, fy * n + s), fill=mix(PANEL, CREAM, 0.75))

    ring_col = mix(GOLD, CREAM, 0.55)
    im.paste(Image.new("RGB", (n, n), ring_col), (0, 0), orbit_layer(n, "back"))

    # crescent: flat gold with one flat shadow band along the inner edge
    mask = crescent_mask(n, 1.04)
    band = ImageChops.subtract(mask, mask.transform((n, n), Image.AFFINE, (1, 0, n * 0.035, 0, 1, -n * 0.022)))
    im.paste(Image.new("RGB", (n, n), GOLD), (0, 0), mask)
    im.paste(Image.new("RGB", (n, n), mix(GOLD, PANEL, 0.28)), (0, 0), band)

    im.paste(Image.new("RGB", (n, n), ring_col), (0, 0), orbit_layer(n, "front"))

    # the spark being made, plus two small ones
    d = ImageDraw.Draw(im)
    _star(d, n * 0.665, n * 0.375, n * 0.13, CREAM)
    _star(d, n * 0.775, n * 0.505, n * 0.042, CREAM)
    _star(d, n * 0.640, n * 0.575, n * 0.026, CREAM)
    return im.resize((SIZE, SIZE), Image.LANCZOS)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    img = draw()
    p = os.path.join(OUT_DIR, "macro_creator.png")
    img.save(p, optimize=True)
    img.resize((512, 512), Image.LANCZOS).save(os.path.join(OUT_DIR, "macro_creator_512.png"), optimize=True)
    print(p, os.path.getsize(p), "bytes")


if __name__ == "__main__":
    main()
