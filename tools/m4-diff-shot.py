#!/usr/bin/env python3
"""Diff two grim shots to locate the panel (the only thing that changed)."""
import sys
from PIL import Image, ImageChops

a = Image.open(sys.argv[1]).convert("RGB")
b = Image.open(sys.argv[2]).convert("RGB")
diff = ImageChops.difference(a, b)
bbox = diff.getbbox()
print("diff bbox:", bbox)
if bbox:
    print(f"w={bbox[2]-bbox[0]} h={bbox[3]-bbox[1]}")
