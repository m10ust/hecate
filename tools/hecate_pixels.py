#!/usr/bin/env python3
"""Hecate M1 pixel receipts — scan a grim shot for the demo palette.

Usage: hecate_pixels.py <png> <label>
Counts pixels in the top bar strip (and whole frame) near each of the three
hardcoded M1 demo colours. Exit prints one line per colour: label, count.
"""
import sys
from PIL import Image

TARGETS = {
    "green": (0x56, 0xD3, 0x64),
    "amber": (0xD2, 0x99, 0x22),
    "red":   (0xF8, 0x51, 0x49),
}
TOL = 28


def count_near(img, rgb, tol=TOL):
    px = img.load()
    w, h = img.size
    n = 0
    xs, ys = [], []
    for y in range(h):
        for x in range(w):
            p = px[x, y]
            if (abs(p[0] - rgb[0]) <= tol and abs(p[1] - rgb[1]) <= tol
                    and abs(p[2] - rgb[2]) <= tol):
                n += 1
                xs.append(x)
                ys.append(y)
    bbox = (min(xs), min(ys), max(xs), max(ys)) if xs else None
    return n, bbox


def main():
    path, label = sys.argv[1], sys.argv[2]
    img = Image.open(path).convert("RGB")
    w, h = img.size
    bar = img.crop((0, 0, w, min(60, h)))  # the bar strip
    for name, rgb in TARGETS.items():
        n_bar, bbox_bar = count_near(bar, rgb)
        n_all, bbox_all = count_near(img, rgb)
        print(f"{label} {name}: bar={n_bar} bbox={bbox_bar} all={n_all}")


if __name__ == "__main__":
    main()
