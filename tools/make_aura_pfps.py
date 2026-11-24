"""Cut the ten webhook pictures: nine from Sol's RNG art, Moontide from a photo of the moon.

    python tools/make_aura_pfps.py <folder with the downloads> [names...]   (run from the repo root)

With names (e.g. `moontide`), only those pictures are made. Then run
tools/make_webhook_pfps.py to rebuild the round preview.

Sources (Sol's RNG Wiki, static.wikia.nocookie.net, downloaded 2026-11-22; save each as
<name>.gif in the folder): equinox = EquinoxNewCollection.gif, boss = NeferkhafCollection.gif
(Neferkhaf), galaxy = Galaxy_Aura.gif, illusionary = Illusionary_collection.gif,
overdrive = MatrixOverdriveCollect1on.gif (Matrix : Overdrive), contrast = Eclispe_collection.gif
(Eclipse), matrix = MatrixCollectionEon1.gif (the teal Matrix aura, used for Matrix Green).
The orange Matrix and Radiant pictures come from the theme art in assets/themes/src.
moontide = a plain photo of the full moon, tinted yellow: save as moon.jpg in the same folder,
from https://commons.wikimedia.org/wiki/File:Moon_nearside_LRO.jpg (NASA/GSFC/Arizona State
University, public domain; the 1280px version was used).
Each picture is one frame, cropped square around the aura and saved as 512x512 PNG
(webhook avatars don't animate). Needs Python 3 + Pillow. Not used at runtime.
"""
import os
import sys
from PIL import Image, ImageDraw, ImageEnhance, ImageOps

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "webhook_pfps")
SRC = os.path.join(ROOT, "assets", "themes", "src")

# name: (source file, frame, centre x, centre y, side) -- centre as fractions, side as a fraction of the height
SPEC = {
    "overdrive":    ("{dl}/overdrive.gif", 44, 0.50, 0.42, 0.90),
    "galaxy":       ("{dl}/galaxy.gif", 8, 0.55, 0.40, 0.85),
    "boss":         ("{dl}/boss.gif", 48, 0.50, 0.50, 0.95),
    "equinox":      ("{dl}/equinox.gif", 30, 0.50, 0.42, 0.80),
    "matrix":       ("{src}/matrix.webp", 0, 0.50, 0.36, 0.70),
    "radiant":      ("{src}/radiant.webp", 0, 0.56, 0.62, 0.74),
    "illusionary":  ("{dl}/illusionary.gif", 40, 0.50, 0.45, 0.85),
    "contrast":     ("{dl}/contrast.gif", 60, 0.50, 0.30, 0.55),
    "matrix_green": ("{dl}/matrix.gif", 59, 0.50, 0.42, 0.80),
}


def moon(path):
    """The moon photo cropped to its disc (a little space around it) and tinted yellow."""
    gray = Image.open(path).convert("L")
    box = gray.point(lambda v: 255 if v > 24 else 0).getbbox() or (0, 0, *gray.size)
    cx, cy = (box[0] + box[2]) / 2, (box[1] + box[3]) / 2
    s = max(box[2] - box[0], box[3] - box[1]) * 1.06
    gray = gray.crop((int(cx - s / 2), int(cy - s / 2), int(cx + s / 2), int(cy + s / 2)))
    gray = ImageOps.autocontrast(gray.resize((512, 512), Image.LANCZOS), cutoff=0.5)
    # Plain black around the disc (the photo has a credit line in one corner).
    r = 512 / 1.06 / 2 + 3
    disc = Image.new("L", (512, 512), 0)
    ImageDraw.Draw(disc).ellipse((256 - r, 256 - r, 256 + r, 256 + r), fill=255)
    gray = Image.composite(gray, Image.new("L", (512, 512), 0), disc)
    return ImageOps.colorize(gray, black="#050400", mid="#d2a12a", white="#fff4c8", midpoint=110)


def main():
    dl, only = sys.argv[1], set(sys.argv[2:])
    if not only or "moontide" in only:
        moon(os.path.join(dl, "moon.jpg")).save(os.path.join(OUT, "moontide_moontide.png"), optimize=True)
        print("moontide")
    for name, (src, frame, cx, cy, side) in SPEC.items():
        if only and name not in only:
            continue
        im = Image.open(src.format(dl=dl, src=SRC))
        if getattr(im, "n_frames", 1) > 1:
            im.seek(min(frame, im.n_frames - 1))
        im = im.convert("RGB")
        w, h = im.size
        s = int(min(h * side, w))
        x0 = int(max(0, min(w - s, cx * w - s / 2)))
        y0 = int(max(0, min(h - s, cy * h - s / 2)))
        sq = im.crop((x0, y0, x0 + s, y0 + s)).resize((512, 512), Image.LANCZOS)
        ImageEnhance.Contrast(sq).enhance(1.08).save(os.path.join(OUT, "moontide_%s.png" % name), optimize=True)
        print(name)


if __name__ == "__main__":
    main()
