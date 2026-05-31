#!/bin/bash
# setup_bonus.sh — Setup script for bonus live FFT edge detection
# Run this from inside ~/fft_bonus directory

set -e
echo "=== Setting up FFT Live Edge Detection ==="

# Install Python dependencies
echo "Installing Python dependencies..."
pip3 install flask opencv-python numpy --break-system-packages 2>/dev/null || \
pip3 install flask opencv-python numpy --break-system-packages --quiet

# Build the RISC-V assembly
echo "Building fft_live.s..."
riscv64-linux-gnu-gcc -march=rv64gcv -O2 -o fft_live fft_live.s -lm -static
echo "Build successful."

echo ""
echo "=== Setup complete ==="
echo "Run: bash run_live.sh"
