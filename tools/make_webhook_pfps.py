"""Draw the webhook profile pictures: one per dashboard theme, each showing its subject.

    python tools/make_webhook_pfps.py          (run from the repo root)

Rebuilds assets/webhook_pfps/_preview_round.png (all ten pictures in Discord's
round crop, in the sign-up dropdown order). The pictures themselves now come
from tools/make_aura_pfps.py; `--all` redraws the old flat designs below.

Each picture shows what its theme stands for (lib/ui/Theme.ahk Presets and
assets/themes/src): Moontide = moon over the tide, Overdrive = the red Matrix :
Overdrive flare, Galaxy = a spiral galaxy, Boss = Neferkhaf (the Potion of the
Dune pharaoh aura), Equinox = the 1 in 2.5B balance aura (衡), Matrix = the
orange HUD rings, Radiant = The Radiant Forest, Illusionary = the blue glitch
heart, Contrast = a bold high-contrast moon, Matrix Green = falling code.
Flat, hand-made look: solid shapes, no glows, gradients or blur. Each non-
Moontide picture carries a small Moontide crescent badge. Everything stays
inside the middle circle, since Discord crops avatars round. Drawn 4x larger
and scaled down for clean edges.

background(), moon_fill(), crescent_mask(), mix(), rgb() and _star() stay for
tools/make_bot_pfp.py. Needs Python 3 + Pillow and Windows' MS Gothic font
(for 衡 and the code-rain glyphs). Not used at runtime.
"""
import math
import os
import random
from PIL import Image, ImageChops, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "webhook_pfps")
SIZE = 512
SS = 4
N = SIZE * SS
C = N / 2
GOTHIC = r"C:\Windows\Fonts\msgothic.ttc"

# dropdown order (moontide_bot/pfps.py CHOICES)
ORDER = ["moontide", "overdrive", "galaxy", "boss", "equinox", "matrix", "radiant",
         "illusionary", "contrast", "matrix_green"]


def rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def mix(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


# ---- kept for tools/make_bot_pfp.py ------------------------------------------
def background(n, bg, panel):
    small = 128
    im = Image.new("RGB", (small, small))
    px = im.load()
    c = (small - 1) / 2
    for y in range(small):
        for x in range(small):
            d = math.hypot(x - c, y - c) / (c * 1.42)
            px[x, y] = mix(panel, bg, min(1.0, d ** 0.9))
    return im.resize((n, n), Image.BICUBIC)


def moon_fill(n, accent, text):
    small = 128
    im = Image.new("RGB", (small, small))
    px = im.load()
    hi, lo = mix(accent, text, 0.25), mix(accent, (0, 0, 0), 0.18)
    for y in range(small):
        for x in range(small):
            px[x, y] = mix(hi, lo, min(1.0, max(0.0, (x + y) / (small * 1.6))))
    return im.resize((n, n), Image.BICUBIC)


def _disc(n, cx, cy, r):
    m = Image.new("L", (n, n), 0)
    ImageDraw.Draw(m).ellipse((cx - r, cy - r, cx + r, cy + r), fill=255)
    return m


def crescent_mask(n, scale=1.0, cx=None, cy=None):
    """White crescent on black: a disc minus an offset disc (opens upper right)."""
    r = n * 0.30 * scale
    cx = n * 0.52 if cx is None else cx
    cy = n * 0.50 if cy is None else cy
    return ImageChops.subtract(_disc(n, cx, cy, r), _disc(n, cx + r * 0.42, cy - r * 0.24, r * 0.86))


def _star(draw, x, y, r, color):
    w = r * 0.22
    draw.polygon([(x, y - r), (x + w, y - w), (x + r, y), (x + w, y + w),
                  (x, y + r), (x - w, y + w), (x - r, y), (x - w, y - w)], fill=color)


# ---- shared bits -------------------------------------------------------------
def fill(im, mask, color):
    im.paste(Image.new("RGB", im.size, color), (0, 0), mask)


def badge(im, panel, accent):
    """Small Moontide crescent in the lower right, on a disc of the panel colour."""
    bx, by, br = N * 0.735, N * 0.735, N * 0.085
    d = ImageDraw.Draw(im)
    d.ellipse((bx - br, by - br, bx + br, by + br), fill=panel, outline=accent, width=int(N * 0.008))
    m = crescent_mask(N, 0.20, bx - N * 0.006, by + N * 0.004)
    fill(im, m, accent)


def ring(im, color, width=0.012, r=0.43):
    d = ImageDraw.Draw(im)
    rr = N * r
    d.ellipse((C - rr, C - rr, C + rr, C + rr), outline=color, width=int(N * width))


def font(size):
    return ImageFont.truetype(GOTHIC, int(size))


# ---- one function per theme --------------------------------------------------
def p_moontide():
    navy, deep, gold, cream = rgb("0B2A5B"), rgb("071C3E"), rgb("F2A93B"), rgb("F7F1E8")
    im = Image.new("RGB", (N, N), navy)
    d = ImageDraw.Draw(im)
    for fx, fy in [(0.25, 0.27), (0.70, 0.22), (0.80, 0.40), (0.32, 0.18)]:
        _star(d, fx * N, fy * N, N * 0.026, cream)
    m = crescent_mask(N, 0.86, N * 0.50, N * 0.42)
    fill(im, m, gold)
    band = ImageChops.subtract(m, m.transform((N, N), Image.AFFINE, (1, 0, N * 0.03, 0, 1, -N * 0.02)))
    fill(im, band, mix(gold, navy, 0.28))
    # the tide: three flat wave bands
    for k, col in enumerate([mix(navy, cream, 0.25), mix(navy, gold, 0.35), deep]):
        y0 = N * (0.64 + k * 0.075)
        pts = [(0, N)]
        for i in range(0, 41):
            x = i / 40 * N
            pts.append((x, y0 + math.sin(i / 40 * math.pi * 4 + k * 1.3) * N * 0.018))
        pts.append((N, N))
        d.polygon(pts, fill=col)
    ring(im, mix(navy, gold, 0.4))
    return im


def p_overdrive():
    bg, red, hot, pale = rgb("1A0508"), rgb("E3202E"), rgb("FF4D57"), rgb("FFD9DC")
    im = Image.new("RGB", (N, N), bg)
    d = ImageDraw.Draw(im)
    # swirling flat arcs behind
    for k, (r, col) in enumerate([(0.36, rgb("5B0B16")), (0.28, rgb("8C1220")), (0.20, rgb("B5162A"))]):
        rr = N * r
        d.arc((C - rr, C - rr * 0.55, C + rr, C + rr * 0.55), 200 + k * 25, 520 + k * 25, fill=col, width=int(N * 0.03))
    # the flare: a big 4-point star, a smaller rotated one, and a white core
    _star(d, C, C, N * 0.33, red)
    star2 = Image.new("L", (N, N), 0)
    _star(ImageDraw.Draw(star2), C, C, N * 0.20, 255)
    fill(im, star2.rotate(45, center=(C, C)), hot)
    d.ellipse((C - N * 0.05, C - N * 0.05, C + N * 0.05, C + N * 0.05), fill=pale)
    for fx, fy, s in [(0.27, 0.70, 0.025), (0.74, 0.30, 0.018), (0.30, 0.30, 0.012)]:
        _star(d, fx * N, fy * N, N * s, hot)
    ring(im, rgb("5B0B16"))
    badge(im, bg, hot)
    return im


def p_galaxy():
    bg, arm1, arm2, core, dot = rgb("100F2E"), rgb("3B36A8"), rgb("8F9BFF"), rgb("F4F5FF"), rgb("C9CEFF")
    im = Image.new("RGB", (N, N), bg)
    d = ImageDraw.Draw(im)
    rnd = random.Random(3)
    for _ in range(60):
        x, y = rnd.uniform(0.12, 0.88) * N, rnd.uniform(0.12, 0.88) * N
        if math.hypot(x - C, y - C) < N * 0.42:
            s = rnd.choice([1, 1, 2]) * N * 0.004
            d.ellipse((x - s, y - s, x + s, y + s), fill=dot)
    # two flat spiral arms made of shrinking dots, tilted into an ellipse
    arms = Image.new("RGB", (N, N), (0, 0, 0))
    am = Image.new("L", (N, N), 0)
    ad = ImageDraw.Draw(arms)
    md = ImageDraw.Draw(am)
    for arm in range(2):
        for i in range(160):
            t = i / 160
            a = arm * math.pi + t * math.pi * 2.6
            r = N * (0.04 + 0.34 * t)
            x, y = C + math.cos(a) * r, C + math.sin(a) * r
            s = N * (0.055 * (1 - t) + 0.008)
            col = arm2 if t < 0.45 else arm1
            ad.ellipse((x - s, y - s, x + s, y + s), fill=col)
            md.ellipse((x - s, y - s, x + s, y + s), fill=255)
    squash = lambda img: img.resize((N, int(N * 0.62))).rotate(0)
    a2, m2 = squash(arms), squash(am)
    canvas, cmask = Image.new("RGB", (N, N)), Image.new("L", (N, N), 0)
    canvas.paste(a2, (0, int(N * 0.19)))
    cmask.paste(m2, (0, int(N * 0.19)))
    canvas, cmask = canvas.rotate(-25, center=(C, C)), cmask.rotate(-25, center=(C, C))
    im.paste(canvas, (0, 0), cmask)
    d = ImageDraw.Draw(im)
    d.ellipse((C - N * 0.07, C - N * 0.07, C + N * 0.07, C + N * 0.07), fill=core)
    ring(im, mix(bg, arm2, 0.35))
    badge(im, bg, arm2)
    return im


def p_boss():
    # Neferkhaf: a pharaoh with a striped nemes headdress, in dune gold and green
    bg, sun, gold, green, dark, face = rgb("1F2A0C"), rgb("3F4A12"), rgb("E8C547"), rgb("4E7A1E"), rgb("141A07"), rgb("C8E04A")
    im = Image.new("RGB", (N, N), bg)
    d = ImageDraw.Draw(im)
    d.ellipse((C - N * 0.34, C - N * 0.40, C + N * 0.34, C + N * 0.28), fill=sun)  # sun disc
    # nemes: a wide trapezoid with lappets, striped gold and green
    nemes = Image.new("L", (N, N), 0)
    nd = ImageDraw.Draw(nemes)
    nd.polygon([(C - N * 0.17, N * 0.22), (C + N * 0.17, N * 0.22), (C + N * 0.30, N * 0.50),
                (C + N * 0.24, N * 0.80), (C + N * 0.11, N * 0.80), (C + N * 0.12, N * 0.52),
                (C - N * 0.12, N * 0.52), (C - N * 0.11, N * 0.80), (C - N * 0.24, N * 0.80),
                (C - N * 0.30, N * 0.50)], fill=255)
    nd.ellipse((C - N * 0.17, N * 0.13, C + N * 0.17, N * 0.33), fill=255)
    stripes = Image.new("RGB", (N, N), gold)
    sd = ImageDraw.Draw(stripes)
    for k in range(-20, 21):
        y = N * 0.16 + k * N * 0.045
        sd.polygon([(0, y), (N, y - N * 0.05), (N, y - N * 0.05 + N * 0.022), (0, y + N * 0.022)], fill=green)
    im.paste(stripes, (0, 0), nemes)
    # broad collar under the face: gold and green arcs
    for k, col in enumerate([green, gold, green, gold]):
        rr = N * (0.24 - k * 0.035)
        d.pieslice((C - rr, N * 0.52 - rr, C + rr, N * 0.52 + rr), 20, 160, fill=col)
    # face (warm gold), kohl eyes with the long liner, nose, braided beard
    skin = rgb("D9A93A")
    d.rounded_rectangle((C - N * 0.10, N * 0.29, C + N * 0.10, N * 0.57), radius=int(N * 0.08), fill=skin)
    d.rectangle((C - N * 0.105, N * 0.29, C + N * 0.105, N * 0.33), fill=gold)  # headband
    for sx in (-1, 1):
        ex = C + sx * N * 0.046
        d.ellipse((ex - N * 0.028, N * 0.395, ex + N * 0.028, N * 0.425), fill=rgb("F4EBD0"))
        d.ellipse((ex - N * 0.012, N * 0.398, ex + N * 0.012, N * 0.422), fill=dark)
        d.line((ex + sx * N * 0.026, N * 0.41, ex + sx * N * 0.06, N * 0.40), fill=dark, width=int(N * 0.008))
        d.line((ex - N * 0.03, N * 0.388, ex + N * 0.03, N * 0.388), fill=dark, width=int(N * 0.008))
    d.polygon([(C, N * 0.43), (C - N * 0.014, N * 0.485), (C + N * 0.014, N * 0.485)], fill=mix(skin, dark, 0.3))
    d.line((C - N * 0.03, N * 0.515, C + N * 0.03, N * 0.515), fill=mix(skin, dark, 0.5), width=int(N * 0.007))
    d.rectangle((C - N * 0.022, N * 0.57, C + N * 0.022, N * 0.70), fill=gold)
    for j in range(5):
        y = N * (0.585 + j * 0.024)
        d.line((C - N * 0.022, y, C + N * 0.022, y), fill=green, width=int(N * 0.006))
    # uraeus: a small rearing cobra on the brow
    d.polygon([(C - N * 0.03, N * 0.30), (C + N * 0.03, N * 0.30), (C, N * 0.19)], fill=gold)
    d.ellipse((C - N * 0.022, N * 0.175, C + N * 0.022, N * 0.215), fill=gold, outline=dark, width=int(N * 0.004))
    d.ellipse((C - N * 0.006, N * 0.19, C + N * 0.006, N * 0.202), fill=dark)
    ring(im, mix(bg, gold, 0.4))
    badge(im, bg, gold)
    return im


def p_equinox():
    black, white, grey = rgb("0E0E0E"), rgb("F4F4F4"), rgb("3A3A3A")
    im = Image.new("RGB", (N, N), grey)
    d = ImageDraw.Draw(im)
    R = N * 0.30
    # balance disc: white half, black half, S curve
    d.ellipse((C - R, C - R, C + R, C + R), fill=white)
    d.pieslice((C - R, C - R, C + R, C + R), 90, 270, fill=black)
    d.ellipse((C - R / 2, C - R, C + R / 2, C), fill=black)
    d.ellipse((C - R / 2, C, C + R / 2, C + R), fill=white)
    d.ellipse((C - R * 0.13, C - R * 0.63, C + R * 0.13, C - R * 0.37), fill=white)
    d.ellipse((C - R * 0.13, C + R * 0.37, C + R * 0.13, C + R * 0.63), fill=black)
    d.ellipse((C - R, C - R, C + R, C + R), outline=white, width=int(N * 0.01))
    # three 衡 orbs, like the aura's
    f = font(N * 0.07)
    for k, ang in enumerate([-140, -90, -40]):
        a = math.radians(ang)
        ox, oy, orr = C + math.cos(a) * N * 0.36, C + math.sin(a) * N * 0.36, N * 0.06
        bgc, fg = (white, black) if k % 2 == 0 else (black, white)
        d.ellipse((ox - orr, oy - orr, ox + orr, oy + orr), fill=bgc, outline=white, width=int(N * 0.006))
        d.text((ox, oy), "衡", font=f, fill=fg, anchor="mm")
    ring(im, mix(grey, white, 0.45))
    badge(im, black, white)
    return im


def p_matrix():
    bg, dim, orange, hot = rgb("1A0D05"), rgb("5B2A0B"), rgb("FF8A2B"), rgb("FFD2A6")
    im = Image.new("RGB", (N, N), bg)
    d = ImageDraw.Draw(im)
    # HUD: ticked rings, broken arcs, crosshair
    for r, w, col in [(0.38, 0.010, dim), (0.30, 0.018, orange), (0.20, 0.010, dim)]:
        rr = N * r
        d.ellipse((C - rr, C - rr, C + rr, C + rr), outline=col, width=int(N * w))
    for i in range(48):
        a = math.radians(i * 7.5)
        r1, r2 = N * 0.34, N * (0.37 if i % 4 else 0.385)
        d.line((C + math.cos(a) * r1, C + math.sin(a) * r1, C + math.cos(a) * r2, C + math.sin(a) * r2),
               fill=orange, width=int(N * 0.006))
    rr = N * 0.25
    for start in (20, 140, 260):
        d.arc((C - rr, C - rr, C + rr, C + rr), start, start + 70, fill=hot, width=int(N * 0.022))
    d.line((C - N * 0.15, C, C + N * 0.15, C), fill=orange, width=int(N * 0.008))
    d.line((C, C - N * 0.15, C, C + N * 0.15), fill=orange, width=int(N * 0.008))
    d.ellipse((C - N * 0.06, C - N * 0.06, C + N * 0.06, C + N * 0.06), fill=orange)
    d.ellipse((C - N * 0.025, C - N * 0.025, C + N * 0.025, C + N * 0.025), fill=hot)
    badge(im, bg, orange)
    return im


def p_radiant():
    # The Radiant Forest: purple sky, a light beam, floating cubes, blocky trees
    sky, sky2, beam, beam2, cube, tree, glow = (rgb("2E1660"), rgb("3D2290"), rgb("E8F4FF"), rgb("9FD3FF"),
                                                 rgb("1B0E3A"), rgb("120A26"), rgb("A97BFF"))
    im = Image.new("RGB", (N, N), sky)
    d = ImageDraw.Draw(im)
    d.rectangle((0, N * 0.45, N, N), fill=sky2)
    d.polygon([(C - N * 0.10, 0), (C + N * 0.10, 0), (C + N * 0.05, N), (C - N * 0.05, N)], fill=beam2)
    d.polygon([(C - N * 0.04, 0), (C + N * 0.04, 0), (C + N * 0.02, N), (C - N * 0.02, N)], fill=beam)
    d.ellipse((C - N * 0.07, N * 0.36 - N * 0.07, C + N * 0.07, N * 0.36 + N * 0.07), fill=beam)
    for fx, fy, s, rot in [(0.28, 0.30, 0.07, 15), (0.72, 0.24, 0.05, 35), (0.66, 0.46, 0.04, 60), (0.33, 0.50, 0.035, 5)]:
        m = Image.new("L", (N, N), 0)
        x, y, h = fx * N, fy * N, s * N
        ImageDraw.Draw(m).rectangle((x - h, y - h, x + h, y + h), fill=255)
        fill(im, m.rotate(rot, center=(x, y)), cube)
    # pine silhouettes: stacked triangles on a trunk, tall at the sides
    for fx, w, h in [(0.14, 0.16, 0.42), (0.27, 0.12, 0.30), (0.74, 0.12, 0.33), (0.87, 0.17, 0.46)]:
        x, base = fx * N, N * 0.90
        d.rectangle((x - N * 0.012, base - h * N * 0.2, x + N * 0.012, N), fill=tree)
        for t in range(3):
            top = base - h * N + t * h * N * 0.22
            half = w * N / 2 * (0.6 + t * 0.2)
            d.polygon([(x, top), (x + half, top + h * N * 0.38), (x - half, top + h * N * 0.38)], fill=tree)
    d.rectangle((0, N * 0.88, N, N), fill=tree)
    ring(im, mix(sky, glow, 0.5))
    badge(im, tree, glow)
    return im


def p_illusionary():
    bg, line, blue, white = rgb("0A1A6E"), rgb("2E55D6"), rgb("4D7CFF"), rgb("F2F5FF")
    im = Image.new("RGB", (N, N), bg)
    d = ImageDraw.Draw(im)
    # perspective grid floor + vertical lines
    hy = N * 0.55
    for i in range(-10, 11):
        d.line((C + i * N * 0.03, hy, C + i * N * 0.16, N), fill=line, width=int(N * 0.004))
    y = hy
    step = N * 0.02
    while y < N:
        d.line((0, y, N, y), fill=line, width=int(N * 0.004))
        step *= 1.35
        y += step
    # the heart, sliced into glitch bands that shift sideways
    heart = Image.new("L", (N, N), 0)
    hd = ImageDraw.Draw(heart)
    r = N * 0.12
    hd.ellipse((C - 2 * r, C - r * 1.6, C, C + r * 0.4), fill=255)
    hd.ellipse((C, C - r * 1.6, C + 2 * r, C + r * 0.4), fill=255)
    hd.polygon([(C - 1.93 * r, C - r * 0.35), (C + 1.93 * r, C - r * 0.35), (C, C + r * 2.3)], fill=255)
    out = Image.new("L", (N, N), 0)
    shifts = [0, 0.03, -0.02, 0, 0.045, -0.035, 0, 0.02]
    band_h = N * 0.06
    for k, s in enumerate(shifts):
        y0 = int(C - r * 1.6 + k * band_h)
        strip = heart.crop((0, y0, N, int(y0 + band_h)))
        out.paste(strip, (int(s * N), y0), strip)
    fill(im, out.transform((N, N), Image.AFFINE, (1, 0, -N * 0.02, 0, 1, 0)), blue)  # blue echo
    fill(im, out, white)
    ring(im, mix(bg, blue, 0.6))
    badge(im, bg, blue)
    return im


def p_contrast():
    black, yellow, white = rgb("000000"), rgb("FFD400"), rgb("FFFFFF")
    im = Image.new("RGB", (N, N), black)
    d = ImageDraw.Draw(im)
    for k in range(-12, 13):  # hazard stripes in the bottom band
        x = C + k * N * 0.08
        d.polygon([(x, N * 0.80), (x + N * 0.04, N * 0.80), (x - N * 0.04, N), (x - N * 0.08, N)], fill=yellow)
    d.rectangle((0, N * 0.78, N, N * 0.80), fill=white)
    m = crescent_mask(N, 0.92, N * 0.50, N * 0.43)
    outline = m.resize((N, N)).filter(__import__("PIL.ImageFilter", fromlist=["MaxFilter"]).MaxFilter(int(N * 0.025) | 1))
    fill(im, outline, white)
    fill(im, m, yellow)
    ring(im, white, width=0.02, r=0.44)
    return im


def p_matrix_green():
    bg, dim, mid, head = rgb("020A04"), rgb("0B3D17"), rgb("1FA845"), rgb("D8FFE0")
    im = Image.new("RGB", (N, N), bg)
    d = ImageDraw.Draw(im)
    glyphs = "ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉ0123456789"
    rnd = random.Random(11)
    f = font(N * 0.05)
    cols = 13
    for k in range(cols):
        x = (k + 0.5) * N / cols
        y = rnd.uniform(-0.3, 0.2) * N
        length = rnd.randint(7, 16)
        for j in range(length):
            g = rnd.choice(glyphs)
            col = head if j == length - 1 else (mid if j > length - 5 else dim)
            d.text((x, y), g, font=f, fill=col, anchor="mm")
            y += N * 0.06
    # a flat moon cut out of the rain
    m = crescent_mask(N, 0.62, N * 0.50, N * 0.47)
    fill(im, m, rgb("39FF6A"))
    ring(im, dim)
    return im


DRAW = {
    "moontide": p_moontide, "overdrive": p_overdrive, "galaxy": p_galaxy, "boss": p_boss,
    "equinox": p_equinox, "matrix": p_matrix, "radiant": p_radiant, "illusionary": p_illusionary,
    "contrast": p_contrast, "matrix_green": p_matrix_green,
}


def preview(paths):
    cell, pad = 240, 20
    sheet = Image.new("RGB", (5 * (cell + pad) + pad, 2 * (cell + pad) + pad), (49, 51, 56))
    m = Image.new("L", (cell, cell), 0)
    ImageDraw.Draw(m).ellipse((0, 0, cell - 1, cell - 1), fill=255)
    for i, p in enumerate(paths):
        im = Image.open(p).resize((cell, cell), Image.LANCZOS)
        sheet.paste(im, (pad + (i % 5) * (cell + pad), pad + (i // 5) * (cell + pad)), m)
    return sheet


def main():
    """Rebuilds the round preview from the ten pictures (all ten are now made by
    tools/make_aura_pfps.py). `--all` redraws the ten old flat designs first."""
    import sys
    os.makedirs(OUT_DIR, exist_ok=True)
    names = ORDER if "--all" in sys.argv else []
    for name in names:
        p = os.path.join(OUT_DIR, "moontide_%s.png" % name)
        DRAW[name]().resize((SIZE, SIZE), Image.LANCZOS).save(p, optimize=True)
        print(p, os.path.getsize(p), "bytes")
    paths = [os.path.join(OUT_DIR, "moontide_%s.png" % n) for n in ORDER]
    preview(paths).save(os.path.join(OUT_DIR, "_preview_round.png"), optimize=True)


if __name__ == "__main__":
    main()
