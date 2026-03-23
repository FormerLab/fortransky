#!/usr/bin/env python3
"""
dither_prep.py — Cobolsky image preprocessor
==============================================
Loads any image, converts to greyscale, resizes to 576×720
(authentic MacPaint canvas), and writes a flat pixel file
for dither.cob to process.

Flat file format:
  Line 1 (header, 20 bytes + \n):
    cols 0-4  : width  (5 chars right-justified, e.g. "  576")
    cols 5-9  : height (5 chars right-justified, e.g. "  720")
    cols 10-19: reserved spaces

  Lines 2..H+1 (one per row, W bytes + \n):
    Each byte is a greyscale value 0-255, written as raw byte.
    LINE SEQUENTIAL in COBOL reads up to \n so each row is one record.
    We write bytes as 3-digit decimal strings space-separated for
    COBOL compatibility (COBOL can't easily read raw binary bytes
    via LINE SEQUENTIAL). Each pixel = 4 chars (3 digits + space).
    Row record length = W * 4 bytes.

Usage:
    python3 dither_prep.py input.png
    python3 dither_prep.py input.jpg --width 576 --height 720
    python3 dither_prep.py input.png --out /tmp/bsky_pixels_in.dat
"""

import sys
import argparse
from pathlib import Path
from PIL import Image, ImageEnhance

PIXELS_FILE = "/tmp/bsky_pixels_in.dat"

def prepare(input_path: str, width: int, height: int, out_path: str,
            brightness: float = 1.0, contrast: float = 1.0):
    img = Image.open(input_path)

    # Flatten transparency to white background
    if img.mode in ("RGBA", "LA") or \
       (img.mode == "P" and "transparency" in img.info):
        bg = Image.new("RGB", img.size, (255, 255, 255))
        if img.mode == "P":
            img = img.convert("RGBA")
        bg.paste(img, mask=img.split()[-1] if img.mode == "RGBA" else None)
        img = bg

    # Convert to greyscale
    img = img.convert("L")

    # Adjust brightness and contrast before dithering
    if brightness != 1.0:
        img = ImageEnhance.Brightness(img).enhance(brightness)
    if contrast != 1.0:
        img = ImageEnhance.Contrast(img).enhance(contrast)

    # Resize to target canvas — use LANCZOS for quality
    img = img.resize((width, height), Image.LANCZOS)

    pixels = list(img.getdata())

    with open(out_path, "w") as f:
        # Header
        header = str(width).rjust(5) + str(height).rjust(5) + " " * 10
        f.write(header + "\n")

        # Pixel rows — each pixel as 3-digit decimal + space
        for row in range(height):
            row_pixels = pixels[row * width : (row + 1) * width]
            # Write as space-separated 3-digit values
            line = "".join(f"{p:03d} " for p in row_pixels)
            f.write(line + "\n")

    print(f"[prep] {width}×{height} greyscale → {out_path}")
    print(f"[prep] {height + 1} records written")

def main():
    parser = argparse.ArgumentParser(description="Cobolsky image preprocessor")
    parser.add_argument("input",   help="Input image (PNG, JPG, etc.)")
    parser.add_argument("--width",      type=int,   default=576)
    parser.add_argument("--height",     type=int,   default=720)
    parser.add_argument("--out",                    default=PIXELS_FILE)
    parser.add_argument("--brightness", type=float, default=1.0,
                        help="Brightness multiplier (1.0=unchanged, 1.4=brighter)")
    parser.add_argument("--contrast",   type=float, default=1.0,
                        help="Contrast multiplier (1.0=unchanged, 1.3=more contrast)")
    args = parser.parse_args()

    prepare(args.input, args.width, args.height, args.out,
            args.brightness, args.contrast)

if __name__ == "__main__":
    main()
