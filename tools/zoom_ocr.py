#!/usr/bin/env python3
"""Zoom + threshold a screenshot region for tesseract OCR (grim shots are
3440px wide; panel text is small). Usage: zoom_ocr.py <png> <x> <y> <w> <h> <out> [scale]
"""
import sys
from PIL import Image

png, x, y, w, h, out = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5]), sys.argv[6]
scale = int(sys.argv[7]) if len(sys.argv) > 7 else 3
img = Image.open(png).convert("L")
crop = img.crop((x, y, x + w, y + h))
big = crop.resize((crop.width * scale, crop.height * scale), Image.LANCZOS)
big = big.point(lambda p: 255 if p > 110 else 0)
big.save(out)
print("saved", out, big.size)
