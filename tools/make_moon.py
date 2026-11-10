"""One-off: draw the header moon's 8 phase frames.

    python tools/make_moon.py          (run from the repo root)

Writes assets/ui/moon_0.png .. moon_7.png: 40x40, transparent, a gold
(#F2A93B) moon through 8 phases. The phases skip the dark days around new
moon so every frame shows a clear gold crescent: they run evenly from a 55
degree waxing crescent to a 305 degree waning crescent (FIRST..LAST), and
frame 0 is the last of them (the waning crescent, lit on the left like the
brand logo; the still frame when animations are off); frame 1 is the 55
degree waxing crescent, frames 4-5 are nearly full. The
unlit part is a faint gold disc. The Dashboard shows the next frame every
0.4 s (lib/ui/Dashboard.ahk, loop "moon"). Drawn 4x larger and scaled down
for smooth edges.

Needs Python 3 + Pillow. Not used at runtime.
"""
import math
import os
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "ui")
SIZE = 40
SS = 4                      # supersampling factor
RADIUS = 17.0               # px at SIZE
GOLD = (0xF2, 0xA9, 0x3B)
UNLIT_ALPHA = 56            # faint disc for the dark part
FRAMES = 8
FIRST, LAST = 55.0, 305.0   # phase angles (degrees) of the thinnest crescents


def frame(k):
    n = SIZE * SS
    r = RADIUS * SS
    c = (n - 1) / 2.0
    # 0 new .. pi full .. 2 pi new; step i of FRAMES evenly from FIRST to LAST
    i = (k + FRAMES - 1) % FRAMES
    theta = math.radians(FIRST + i * (LAST - FIRST) / (FRAMES - 1))
    cos_t = math.cos(theta)
    waxing = theta < math.pi
    im = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    px = im.load()
    for y in range(n):
        dy = (y - c) / r
        if abs(dy) > 1:
            continue
        half = math.sqrt(1 - dy * dy)
        for x in range(n):
            dx = (x - c) / r
            if abs(dx) > half:
                continue
            # terminator at dx = half * cos(theta): waxing lights the right
            # side of it, waning the left side
            lit = dx > half * cos_t if waxing else dx < -half * cos_t
            px[x, y] = GOLD + ((255,) if lit else (UNLIT_ALPHA,))
    return im.resize((SIZE, SIZE), Image.LANCZOS)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for k in range(FRAMES):
        p = os.path.join(OUT_DIR, "moon_%d.png" % k)
        frame(k).save(p, optimize=True)
        print(p, os.path.getsize(p), "bytes")


if __name__ == "__main__":
    main()
