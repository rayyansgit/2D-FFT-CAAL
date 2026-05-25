#!/usr/bin/env python3
# convert_image.py
# Converts any image (JPEG, PNG, etc.) to img_input.bin for fft_2d
#
# Usage:
#   python3 convert_image.py <image_path>
#
# Output:
#   img_input.bin — [int32 N][int32 N][N*N float32 pixels]
#   where N is the next power of 2 >= max(width, height), capped at 512

import sys
import struct
from PIL import Image
import numpy as np

MAX_SIZE = 512

def next_power_of_2(n):
    p = 1
    while p < n:
        p <<= 1
    return p

def convert(image_path):
    img = Image.open(image_path).convert('L')  # grayscale
    w, h = img.size
    print(f"Original size: {w}x{h}")

    # force square, round up to next power of 2, cap at 512
    larger = max(w, h)
    N = next_power_of_2(larger)
    if N > MAX_SIZE:
        N = MAX_SIZE
        print(f"Capped to {N}x{N}")
    else:
        print(f"Resizing to {N}x{N}")

    img = img.resize((N, N), Image.LANCZOS)
    pixels = np.array(img, dtype=np.float32) / 255.0  # normalize to [0,1]

    with open('img_input.bin', 'wb') as f:
        f.write(struct.pack('<i', N))           # width
        f.write(struct.pack('<i', N))           # height
        f.write(pixels.astype(np.float32).tobytes())  # row-major floats

    print(f"Written img_input.bin — {N}x{N} image ({N*N} floats, {N*N*4} bytes)")

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python3 convert_image.py <image_path>")
        sys.exit(1)
    convert(sys.argv[1])
