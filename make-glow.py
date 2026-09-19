#!/usr/bin/env python3
"""Generate glow.png: a white, circular radial-alpha falloff used as the bloom texture.

The QML side tints it with the theme accent at runtime, so the texture itself is
greyscale + alpha and is generated once, not once per theme.

Usage: ./make-glow.py [size]     (default 256)
"""
import math
import sys

from PIL import Image

SIZE = int(sys.argv[1]) if len(sys.argv) > 1 else 256

alpha = Image.new("L", (SIZE, SIZE), 0)
pixels = alpha.load()
centre = (SIZE - 1) / 2.0
for y in range(SIZE):
    for x in range(SIZE):
        r = math.hypot(x - centre, y - centre) / centre  # 0 at the centre, 1 at the edge
        pixels[x, y] = int(round(255 * max(0.0, 1.0 - r) ** 2.2))  # soft falloff, no hard rim

white = Image.new("L", (SIZE, SIZE), 255)
Image.merge("RGBA", (white, white, white, alpha)).save("glow.png")
print("wrote glow.png (%dx%d)" % (SIZE, SIZE))
