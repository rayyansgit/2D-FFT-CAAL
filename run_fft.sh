#!/bin/bash
# run_fft.sh
# Full FFT pipeline: image -> binary -> QEMU -> PNGs
#
# Usage:
#   ./run_fft.sh <image_path>

set -e

if [ $# -lt 1 ]; then
    echo "Usage: ./run_fft.sh <image_path>"
    exit 1
fi

IMAGE=$1
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Step 1: Converting image ==="
python3 "$SCRIPT_DIR/convert_image.py" "$IMAGE"

echo ""
echo "=== Step 2: Running FFT on QEMU ==="
qemu-riscv64 -cpu max "$SCRIPT_DIR/fft_2d" bench

echo ""
echo "=== Step 3: Generating output PNGs ==="
"$SCRIPT_DIR/visualize"

echo ""
echo "=== Done ==="
echo "Output: fft_output.png and edges_output.png"
