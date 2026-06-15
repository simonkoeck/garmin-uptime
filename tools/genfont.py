#!/usr/bin/env python3
# Generate Connect IQ custom bitmap fonts (BMFont .fnt + PNG) from a TTF.
#
# Produces white, anti-aliased glyphs on a transparent sheet (Connect IQ tints
# them with the drawText colour). Each glyph occupies a full line-height cell so
# baseline alignment is trivial and correct. Digits are tabular (uniform width)
# so the clock doesn't jiggle as numbers change.
import os, sys
from PIL import Image, ImageFont, ImageDraw

OUT = os.path.join(os.path.dirname(__file__), "..", "resources", "fonts")
os.makedirs(OUT, exist_ok=True)


def gen(name, ttf, size, chars, tabular_digits=False, pad=2):
    font = ImageFont.truetype(ttf, size)
    asc, desc = font.getmetrics()
    lineH = asc + desc

    # per-glyph advance width
    def adv(ch):
        return int(round(font.getlength(ch)))

    digitW = max(adv(d) for d in "0123456789") if tabular_digits else 0

    cells = []  # (ch, cellW)
    for ch in chars:
        w = adv(ch)
        if tabular_digits and ch.isdigit():
            w = digitW
        cells.append((ch, max(w, 1)))

    # pack into a grid, wrapping near 512px
    maxW = 512
    x = y = 0
    rowH = lineH + pad
    placed = []  # (ch, cellW, px, py)
    for ch, w in cells:
        if x + w + pad > maxW:
            x = 0
            y += rowH
        placed.append((ch, w, x, y))
        x += w + pad
    sheetW = maxW
    sheetH = y + rowH

    img = Image.new("RGBA", (sheetW, sheetH), (255, 255, 255, 0))
    draw = ImageDraw.Draw(img)
    for ch, w, px, py in placed:
        gw = adv(ch)
        # centre tabular digits within their cell
        offx = (w - gw) // 2 if (tabular_digits and ch.isdigit()) else 0
        draw.text((px + offx, py), ch, font=font, fill=(255, 255, 255, 255))

    png = name + ".png"
    img.save(os.path.join(OUT, png))

    lines = []
    lines.append('info face="%s" size=%d bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=1 aa=1 padding=0,0,0,0 spacing=0,0' % (name, size))
    lines.append('common lineHeight=%d base=%d scaleW=%d scaleH=%d pages=1 packed=0' % (lineH, asc, sheetW, sheetH))
    lines.append('page id=0 file="%s"' % png)
    lines.append('chars count=%d' % len(placed))
    for ch, w, px, py in placed:
        lines.append('char id=%d x=%d y=%d width=%d height=%d xoffset=0 yoffset=0 xadvance=%d page=0 chnl=15'
                     % (ord(ch), px, py, w, lineH, w))
    with open(os.path.join(OUT, name + ".fnt"), "w") as f:
        f.write("\n".join(lines) + "\n")
    print("wrote %s.fnt + %s  (%dx%d, %d glyphs, lineH=%d)" % (name, png, sheetW, sheetH, len(placed), lineH))

# Terminal style: JetBrains Mono. Large for the prompt/time, small for data rows.
JBM = "/nix/store/sm4799k958k08jhhqvx1sw7gpjqhi75k-jetbrains-mono-2.304/share/fonts/truetype"
gen("lumen_mono_lg", JBM + "/JetBrainsMono-Medium.ttf", 56, "0123456789:> ")
gen("lumen_mono", JBM + "/JetBrainsMonoNL-Regular.ttf", 26,
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789:>_%.,-() /█░")
