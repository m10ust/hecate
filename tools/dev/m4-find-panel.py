#!/usr/bin/env python3
"""Locate the hecate panel in a full grim shot by finding its dark solid
surface against the wallpaper, then report the bbox."""
import sys
from PIL import Image

png = sys.argv[1]
img = Image.open(png).convert("RGB")
w, h = img.size
px = img.load()

# panel surface is near-black; wallpaper is not. Scan columns/rows.
# Collect pixels darker than 30 in all channels.
minx, miny, maxx, maxy, n = w, h, 0, 0, 0
step = 4
for y in range(0, h, step):
    for x in range(0, w, step):
        r, g, b = px[x, y]
        if r < 28 and g < 28 and b < 30:
            n += 1
            if x < minx: minx = x
            if x > maxx: maxx = x
            if y < miny: miny = y
            if y > maxy: maxy = y
print(f"dark pixels (sampled): {n}, bbox: x {minx}..{maxx}  y {miny}..{maxy}")
print(f"width {maxx-minx} height {maxy-miny}")
