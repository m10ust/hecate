#!/usr/bin/env python3
"""Find text-colored (bright) pixel rows in a narrow screenshot to locate
the measured-size line, then OCR that band (tesseract misses thin light
rows at default psm)."""
import sys
from PIL import Image

img = Image.open(sys.argv[1]).convert("L")
w, h = img.size
px = img.load()
bands = []
cur = None
for y in range(h):
    bright = sum(1 for x in range(0, w, 3) if px[x, y] > 150)
    if bright > 3:
        if cur is None:
            cur = [y, y]
        else:
            cur[1] = y
    else:
        if cur and cur[1] - cur[0] >= 4:
            bands.append(tuple(cur))
        cur = None
if cur and cur[1] - cur[0] >= 4:
    bands.append(tuple(cur))
print("text bands (y ranges):", bands[:20])
