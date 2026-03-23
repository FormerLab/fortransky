#!/usr/bin/env python3
"""
pixels_to_png.py — convert dither.f90 output to PNG
Reads  /tmp/bsky_pixels_out.dat
Writes /tmp/bsky_dither_preview.png

No auth, no posting — just pixel data to PNG.
Called by dither_flow in tui.f90 before upload.
"""
import sys
import io
import argparse
from pathlib import Path
from PIL import Image

PIXELS_OUT   = '/tmp/bsky_pixels_out.dat'
PREVIEW_FILE = '/tmp/bsky_dither_preview.png'


def read_pixels(path: str):
    with open(path) as f:
        lines = f.readlines()
    header = lines[0]
    width  = int(header[0:5])
    height = int(header[5:10])
    pixels = []
    for line in lines[1:height + 1]:
        values = line.strip().split()
        pixels.extend(int(v) for v in values)
    return width, height, pixels


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--pixels',  default=PIXELS_OUT)
    parser.add_argument('--out',     default=PREVIEW_FILE)
    args = parser.parse_args()

    width, height, pixels = read_pixels(args.pixels)
    img = Image.new('L', (width, height))
    img.putdata(pixels)
    img.save(args.out, format='PNG', optimize=True)
    print(f'[pixels_to_png] {width}×{height} → {args.out}', file=sys.stderr)


if __name__ == '__main__':
    main()
