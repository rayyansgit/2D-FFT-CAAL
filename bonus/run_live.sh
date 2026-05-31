#!/bin/bash
# run_live.sh — Start the live FFT edge detection pipeline

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Auto-attach webcam via usbipd
echo "=== Attaching webcam to WSL ==="
/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe \
    -Command "usbipd attach --wsl --busid 2-2" 2>/dev/null
sleep 2

# Fix permissions without sudo prompt
for dev in /dev/video0 /dev/video1 /dev/video2 /dev/video3; do
    [ -e "$dev" ] && sudo chmod 666 "$dev" 2>/dev/null
done

# Verify camera is available
if ! ls /dev/video0 > /dev/null 2>&1; then
    echo "ERROR: Camera not found. Try running in PowerShell (Admin):"
    echo "  usbipd attach --wsl --busid 2-2"
    exit 1
fi
echo "Camera attached: $(ls /dev/video*)"

# Clean up stale IPC files
rm -f /dev/shm/fft_frame.bin /dev/shm/fft_edges.bin \
       /dev/shm/fft_ready /dev/shm/fft_ready.tmp

echo ""
echo "Starting Live FFT Edge Detection..."
echo "Open browser at: http://localhost:5000"
echo "Press Ctrl+C to stop."
echo ""

python3 gui.py
