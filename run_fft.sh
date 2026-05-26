#!/bin/bash
# run_fft.sh — 2D FFT Pipeline Controller
# Usage:
#   bash run_fft.sh <image_path>   → process image, generate PNGs
#   bash run_fft.sh                → run hardcoded 8x8/16x16/32x32 benchmarks

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ $# -ge 1 ]; then
    IMAGE=$1
    echo "=== Step 1: Converting image ==="
    python3 "$SCRIPT_DIR/convert_image.py" "$IMAGE"

    echo ""
    echo "=== Step 2: Running FFT on QEMU ==="
    qemu-riscv64 -cpu max "$SCRIPT_DIR/fft_2d"

    echo ""
    echo "=== Step 3: Generating output PNGs ==="
    "$SCRIPT_DIR/visualize"

    echo ""
    echo "=== Done ==="
    echo "Output: fft_output.png and edges_output.png"
else
    echo "=== No image provided — Running hardcoded benchmarks ==="
    rm -f img_input.bin
    qemu-riscv64 -cpu max "$SCRIPT_DIR/fft_2d"
fi
