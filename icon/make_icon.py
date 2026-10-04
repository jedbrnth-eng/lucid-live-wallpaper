"""Compose Lucid's macOS app icon from icon/source.png.

Fits the art into Apple's icon grid (824pt body on a 1024 canvas, continuous-corner squircle),
adds a soft drop shadow and a subtle top edge highlight, then writes AppIcon.png and AppIcon.icns.
Usage: python3 icon/make_icon.py   (needs Pillow)
"""
import os, sys
from PIL import Image, ImageDraw, ImageFilter, ImageChops

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.join(HERE, "source.png")
S, BODY = 1024, 824
OFF = (S - BODY) // 2
SS = 4  # supersampling for clean mask edges

def squircle_mask(size, n=5.0):
    big = size * SS
    m = Image.new("L", (big, big), 0)
    px = m.load()
    r = big / 2.0
    # superellipse |x|^n + |y|^n <= r^n, scan by rows with solved x-extent
    d = ImageDraw.Draw(m)
    for y in range(big):
        t = abs((y + 0.5 - r) / r)
        if t >= 1: continue
        w = r * (1 - t ** n) ** (1.0 / n)
        d.line([(r - w, y), (r + w, y)], fill=255)
    return m.resize((size, size), Image.LANCZOS)

art = Image.open(SRC).convert("RGB").resize((BODY, BODY), Image.LANCZOS)
mask = squircle_mask(BODY)

canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
# drop shadow
shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
sh_mask = Image.new("L", (S, S), 0); sh_mask.paste(mask, (OFF, OFF + 14))
sh_mask = sh_mask.filter(ImageFilter.GaussianBlur(22)).point(lambda v: int(v * 0.55))
shadow.putalpha(sh_mask)
canvas = Image.alpha_composite(canvas, shadow)
# body
body = art.convert("RGBA"); body.putalpha(mask)
canvas.paste(body, (OFF, OFF), body)
# subtle top edge highlight (1.5px inner stroke fading downward)
edge = Image.new("L", (BODY, BODY), 0)
inner = mask.filter(ImageFilter.GaussianBlur(1.2))
ring = ImageChops.subtract(mask, inner.resize((BODY, BODY)).transform((BODY, BODY), Image.AFFINE, (1, 0, 0, 0, 1, -3)))
grad = Image.linear_gradient("L").resize((BODY, BODY)).transpose(Image.FLIP_TOP_BOTTOM)  # white at top
hl = ImageChops.multiply(ring, grad).point(lambda v: int(v * 0.5))
hl_img = Image.new("RGBA", (BODY, BODY), (255, 255, 255, 0)); hl_img.putalpha(hl)
canvas.alpha_composite(hl_img, (OFF, OFF))

out_png = os.path.join(HERE, "AppIcon.png")
canvas.save(out_png)
sizes = [(16, 16), (32, 32), (64, 64), (128, 128), (256, 256), (512, 512), (1024, 1024)]
canvas.save(os.path.join(ROOT, "AppIcon.icns"), format="ICNS", sizes=sizes)
print("wrote", out_png, "and AppIcon.icns")
