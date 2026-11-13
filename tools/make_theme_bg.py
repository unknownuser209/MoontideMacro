"""Build the dashboard backgrounds for the colour themes (Settings > Look).

    python tools/make_theme_bg.py          (run from the repo root)

Writes assets/themes/<theme>.png (864 x 620, the Dashboard content area):
the theme's Sol's RNG art, centre-cropped to that aspect, scaled, softened,
darkened and tinted toward the theme's background colour so panels and text
read on it, then palette-quantised (small file).

Sources: assets/themes/src/<theme>.webp, the Sol's RNG thumbnails the
user picked (2026-11-12): overdrive (Matrix : Overdrive, red), galaxy
(blue-violet), boss (Boss Preview, green-gold), equinox (1 in 2,500,000,000,
black and white), matrix (orange), radiant (The Radiant Forest, purple),
illusionary (Illusionary, electric blue).
The Moontide theme keeps assets/moontide_bg_dim.png (tools/make_bg.py).

Needs Python 3 + Pillow. Not used at runtime.
"""
import os
from PIL import Image, ImageEnhance, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
W, H = 864, 620
OUT = os.path.join(ROOT, "assets", "themes")
SRC = os.path.join(OUT, "src")

# theme -> (brightness kept, background colour it is tinted toward)
THEMES = {
    "overdrive": (0.42, (0x12, 0x0A, 0x0C)),
    "galaxy": (0.34, (0x0B, 0x0B, 0x1A)),
    "boss": (0.38, (0x11, 0x12, 0x0A)),
    "equinox": (0.30, (0x0E, 0x0E, 0x0E)),
    "matrix": (0.40, (0x14, 0x0C, 0x07)),
    "radiant": (0.34, (0x0D, 0x0A, 0x18)),
    "illusionary": (0.30, (0x06, 0x0A, 0x1C)),
}
TINT = 0.35       # then 35 % of the way to the theme background


def build(name, bright, bg):
    src = os.path.join(SRC, name + ".webp")
    if not os.path.exists(src):
        print(name, ": no source")
        return
    im = Image.open(src).convert("RGB")
    sw, sh = im.size
    if sw / sh > W / H:                     # too wide: crop the sides
        cw = round(sh * W / H)
        im = im.crop(((sw - cw) // 2, 0, (sw - cw) // 2 + cw, sh))
    else:                                    # too tall: crop top and bottom
        ch = round(sw * H / W)
        im = im.crop((0, (sh - ch) // 2, sw, (sh - ch) // 2 + ch))
    small = im.width < W
    im = im.resize((W, H), Image.LANCZOS)
    if small:                                # upscaled art: soften the pixels
        im = im.filter(ImageFilter.GaussianBlur(2.2))
    im = ImageEnhance.Brightness(im).enhance(bright)
    im = Image.blend(im, Image.new("RGB", (W, H), bg), TINT)
    os.makedirs(OUT, exist_ok=True)
    out = os.path.join(OUT, name + ".png")
    im.quantize(colors=192, method=Image.Quantize.MEDIANCUT).save(out, optimize=True)
    print(name, "<-", os.path.relpath(src, ROOT), "->", os.path.relpath(out, ROOT), os.path.getsize(out) // 1024, "KB")


if __name__ == "__main__":
    for n, (b, c) in THEMES.items():
        build(n, b, c)
