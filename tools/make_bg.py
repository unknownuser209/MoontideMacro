"""One-off: build the dashboard art.

    python tools/make_bg.py            (run from the repo root)
    python tools/make_bg.py vesper     (legacy Vesper character-sheet bg)

Default ("moontide") writes
  assets/moontide_bg.png  Sol's RNG title art (assets/moontide_ref.webp, blue
                          geometric lines), centre-cropped to the dashboard
                          aspect, darkened, scaled to CONTENT_W x CONTENT_H
                          and palette-quantised (< 300 KB).
  assets/moontide_bg_dim.png  the same art at 35 % of that brightness: the
                          darker copy the Dashboard shows behind its panels.
  assets/vesper_moon.png  gold crescent for the header (shared by both modes).

Legacy ("vesper") writes
  assets/vesper_bg.png    full-body four-view row over the moonlit ocean,
                          cropped from assets/vesper_ref.webp, darkened ~55 %,
                          scaled to the dashboard content area (CONTENT_W x
                          CONTENT_H, must match Dashboard.ContentW/ContentH)
                          and palette-quantised so it stays small.
  assets/vesper_moon.png  gold crescent on the header colour (#0D1117) for the
                          dashboard header (supersampled, no alpha needed).

Needs Python 3 + Pillow. Not used at runtime.
"""
import os
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "vesper_ref.webp")
OUT_BG = os.path.join(ROOT, "assets", "vesper_bg.png")
SRC_MT = os.path.join(ROOT, "assets", "moontide_ref.webp")
OUT_MT = os.path.join(ROOT, "assets", "moontide_bg.png")
OUT_DIM = os.path.join(ROOT, "assets", "moontide_bg_dim.png")
OUT_MOON = os.path.join(ROOT, "assets", "vesper_moon.png")

CONTENT_W, CONTENT_H = 864, 620          # Dashboard content area (px at 96 dpi)
# Full-body row on the 1439x1074 sheet: the four views sit between the
# "Vesper" title / info column (left, ends ~x 210) and the detail panels
# (right, start ~x 1078); the sheet frame line is y 12-13 and the view labels start at y 619.
CROP_X0, CROP_X1 = 222, 1062
MT_DARKEN = 0.40
DIM = 0.35                                # moontide_bg_dim.png: 35 % of moontide_bg.png's brightness
DARKEN = 0.45                             # keep 45 % brightness (= ~55 % darker)
BG = (0x0D, 0x11, 0x17)
GOLD = (0xF2, 0xA9, 0x3B)


def make_bg():
    im = Image.open(SRC).convert("RGB")
    cw = CROP_X1 - CROP_X0
    ch = round(cw * CONTENT_H / CONTENT_W)
    y0 = 15   # frame line at y 12-13 above, view labels from y 619 below
    im = im.crop((CROP_X0, y0, CROP_X1, y0 + ch))
    im = im.resize((CONTENT_W, CONTENT_H), Image.LANCZOS)
    im = ImageEnhance.Brightness(im).enhance(DARKEN)
    # Soft fade to the window colour along the top and left edges so the art
    # sits under the header / sidebar without a hard seam.
    fade = Image.new("L", (CONTENT_W, CONTENT_H), 0)
    d = ImageDraw.Draw(fade)
    for i in range(40):
        a = int(150 * (1 - i / 40) ** 2)
        d.line([(0, i), (CONTENT_W, i)], fill=a)
        d.line([(i, 0), (i, CONTENT_H)], fill=max(a, 0))
    im = Image.composite(Image.new("RGB", im.size, BG), im, fade)
    q = im.quantize(colors=128, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.FLOYDSTEINBERG)
    q.save(OUT_BG, optimize=True)


def make_moontide(dim=False):
    im = Image.open(SRC_MT).convert("RGB")
    w, h = im.size
    cw = round(h * CONTENT_W / CONTENT_H)             # full height, dashboard aspect
    x0 = 0                                            # full left edge: keeps the whole "Sol's RNG" title legible, not half-cut
    im = im.crop((x0, 0, x0 + cw, h)).resize((CONTENT_W, CONTENT_H), Image.LANCZOS)
    im = ImageEnhance.Brightness(im).enhance(MT_DARKEN * (DIM if dim else 1))
    fade = Image.new("L", (CONTENT_W, CONTENT_H), 0)
    d = ImageDraw.Draw(fade)
    for i in range(40):
        a = int(150 * (1 - i / 40) ** 2)
        d.line([(0, i), (CONTENT_W, i)], fill=a)
        d.line([(i, 0), (i, CONTENT_H)], fill=a)
    im = Image.composite(Image.new("RGB", im.size, BG), im, fade)
    q = im.quantize(colors=128, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.FLOYDSTEINBERG)
    q.save(OUT_DIM if dim else OUT_MT, optimize=True)


def make_moon(size=40, ss=8):
    big = size * ss
    im = Image.new("RGB", (big, big), BG)
    # faint halo
    halo = Image.new("L", (big, big), 0)
    ImageDraw.Draw(halo).ellipse((big * 0.14, big * 0.14, big * 0.86, big * 0.86), fill=60)
    halo = halo.filter(ImageFilter.GaussianBlur(big * 0.08))
    im = Image.composite(Image.new("RGB", im.size, GOLD), im, halo.point(lambda v: v // 3))
    # crescent = disc minus offset disc
    mask = Image.new("L", (big, big), 0)
    md = ImageDraw.Draw(mask)
    r = big * 0.34
    cx, cy = big * 0.5, big * 0.5
    md.ellipse((cx - r, cy - r, cx + r, cy + r), fill=255)
    off_x, off_y, r2 = big * 0.15, -big * 0.09, r * 0.92
    md.ellipse((cx - r2 + off_x, cy - r2 + off_y, cx + r2 + off_x, cy + r2 + off_y), fill=0)
    im = Image.composite(Image.new("RGB", im.size, GOLD), im, mask)
    im = im.resize((size, size), Image.LANCZOS)
    im.save(OUT_MOON, optimize=True)


if __name__ == "__main__":
    import sys
    legacy = len(sys.argv) > 1 and sys.argv[1] == "vesper"
    if legacy:
        make_bg()
    else:
        make_moontide()
        make_moontide(dim=True)
    make_moon()
    for p in ((OUT_BG,) if legacy else (OUT_MT, OUT_DIM)) + (OUT_MOON,):
        print(p, os.path.getsize(p), "bytes")
