"""One-off: draw the header moon's 12 phase frames.

    python tools/make_moon.py          (run from the repo root)

Writes assets/ui/moon_0.png .. moon_11.png: 40x40, transparent, a WHITE moon
through a whole cycle in 30 degree steps, new moon included (2026-11-13: the
old 8 frames skipped the dark days, so the cycle jumped from the last
crescent straight to the first). The Dashboard tints every frame to the
theme's Accent when it loads them (Theme.MoonBitmap: Moontide gold, Equinox
white), so only the alpha matters here. Frame 0 is the 300 degree waning
crescent (lit on the left like the brand logo; the still frame when
animations are off), frame 2 the new moon (only the faint disc and its
rim), frame 8 the full moon. The unlit part is a faint disc with a slightly
brighter rim, so the new moon still shows. The Dashboard steps through them
over 3.2 s (lib/ui/Dashboard.ahk, loop "moon"). Drawn 4x larger and scaled
down for smooth edges.

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
WHITE = (255, 255, 255)     # tinted to the theme's Accent at load time
UNLIT_ALPHA = 56            # faint disc for the dark part
RIM_ALPHA = 120             # its edge (the new moon's outline)
RIM = 0.09                  # rim width, fraction of the radius
FRAMES = 12
STILL = 300.0               # frame 0's phase angle (degrees; 0 new, 180 full)


def phase(k):
    return (STILL + k * 360.0 / FRAMES) % 360.0


def frame(k):
    n = SIZE * SS
    r = RADIUS * SS
    c = (n - 1) / 2.0
    theta = math.radians(phase(k))
    cos_t = math.cos(theta)
    waxing = theta < math.pi
    dark = abs(math.sin(theta / 2)) < 1e-9      # new moon: nothing lit
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
            lit = (not dark) and (dx > half * cos_t if waxing else dx < -half * cos_t)
            if lit:
                a = 255
            else:
                a = RIM_ALPHA if math.hypot(dx, dy) > 1 - RIM else UNLIT_ALPHA
            px[x, y] = WHITE + (a,)
    return im.resize((SIZE, SIZE), Image.LANCZOS)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for k in range(FRAMES):
        p = os.path.join(OUT_DIR, "moon_%d.png" % k)
        frame(k).save(p, optimize=True)
        print(p, os.path.getsize(p), "bytes", "phase %.0f" % phase(k))


if __name__ == "__main__":
    main()
