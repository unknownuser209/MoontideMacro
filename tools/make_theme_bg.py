"""Build the dashboard backgrounds for the colour themes (Settings > Look).

    python tools/make_theme_bg.py          (run from the repo root)

Writes assets/themes/<theme>.png (864 x 620, the Dashboard content area):
the theme's Sol's RNG art, centre-cropped to that aspect, scaled, softened,
darkened and tinted toward the theme's background colour so panels and text
read on it, then palette-quantised (small file).

Sources (first that exists):
  overdrive  assets/themes/src/matrix_overdrive.(png|jpg|jpeg|webp)
             (the Matrix : Overdrive aura picture; save it there from the
             Sol's RNG wiki), else assets/biomes/HELL.png
  glitch     assets/biomes/GLITCHED.png
  dream      assets/biomes/DREAMSPACE.png
  cyber      assets/biomes/CYBERSPACE.png
The Moontide theme keeps assets/moontide_bg_dim.png (tools/make_bg.py).

Needs Python 3 + Pillow. Not used at runtime.
"""
import os
from PIL import Image, ImageEnhance, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
W, H = 864, 620
OUT = os.path.join(ROOT, "assets", "themes")
SRC = os.path.join(OUT, "src")

# theme -> (source candidates, background colour it is tinted toward)
THEMES = {
    "overdrive": ([os.path.join(SRC, "matrix_overdrive." + e) for e in ("png", "jpg", "jpeg", "webp")]
                  + [os.path.join(ROOT, "assets", "biomes", "HELL.png")], (0x12, 0x0A, 0x0C)),
    "glitch": ([os.path.join(ROOT, "assets", "biomes", "GLITCHED.png")], (0x0A, 0x11, 0x0C)),
    "dream": ([os.path.join(ROOT, "assets", "biomes", "DREAMSPACE.png")], (0x14, 0x0C, 0x14)),
    "cyber": ([os.path.join(ROOT, "assets", "biomes", "CYBERSPACE.png")], (0x0A, 0x10, 0x14)),
}
BRIGHT = 0.42     # keep 42 % brightness
TINT = 0.35       # then 35 % of the way to the theme background


def build(name, sources, bg):
    src = next((p for p in sources if os.path.exists(p)), None)
    if src is None:
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
    im = ImageEnhance.Brightness(im).enhance(BRIGHT)
    im = Image.blend(im, Image.new("RGB", (W, H), bg), TINT)
    os.makedirs(OUT, exist_ok=True)
    out = os.path.join(OUT, name + ".png")
    im.quantize(colors=192, method=Image.Quantize.MEDIANCUT).save(out, optimize=True)
    print(name, "<-", os.path.relpath(src, ROOT), "->", os.path.relpath(out, ROOT), os.path.getsize(out) // 1024, "KB")


if __name__ == "__main__":
    for n, (s, c) in THEMES.items():
        build(n, s, c)
