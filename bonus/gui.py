#!/usr/bin/env python3
"""
Live FFT Edge Detection GUI
WebSocket-based streaming — no MJPEG reconnect flashing
"""

import cv2
import numpy as np
import struct
import os
import time
import threading
import subprocess
import signal
import sys
import base64
from flask import Flask, render_template_string
from flask_sock import Sock

# ── Config ───────────────────────────────────────────────────
FFT_SIZE       = 256
DISPLAY_W      = 640
DISPLAY_H      = 480
FRAME_IN       = "/dev/shm/fft_frame.bin"
EDGES_OUT      = "/dev/shm/fft_edges.bin"
READY_FLAG     = "/dev/shm/fft_ready.tmp"
QEMU_BIN       = "qemu-riscv64"
FFT_BIN        = "./fft_live"

# ── Global state ─────────────────────────────────────────────
latest_raw_jpg   = None
latest_edge_jpg  = None
frame_lock       = threading.Lock()
stats_lock       = threading.Lock()

frames_processed = 0
total_time_s     = 0.0
processing_times = []  # Rolling window for full pipeline
fft_times        = []  # Rolling window for RISC-V FFT processing only
qemu_process     = None

app  = Flask(__name__)
sock = Sock(app)

# ── HTML ─────────────────────────────────────────────────────
HTML = """
<!DOCTYPE html>
<html>
<head>
  <title>Live FFT Edge Detection — RISC-V Assembly</title>
  <style>
    *{margin:0;padding:0;box-sizing:border-box}
    body{background:#0d1117;color:#e6edf3;font-family:'Segoe UI',monospace;min-height:100vh}
    header{background:#161b22;border-bottom:1px solid #30363d;padding:12px 24px;
           display:flex;align-items:center;gap:16px}
    header h1{font-size:18px;color:#58a6ff;font-weight:600}
    .badge{background:#1f6feb;color:white;padding:2px 8px;border-radius:12px;
           font-size:11px;font-weight:600}
    header span{font-size:12px;color:#8b949e}
    .feeds{display:flex;gap:2px;padding:16px;justify-content:center}
    .panel{background:#161b22;border:1px solid #30363d;border-radius:8px;overflow:hidden}
    .panel-title{padding:8px 16px;font-size:12px;font-weight:600;color:#8b949e;
                 text-transform:uppercase;letter-spacing:.05em;
                 border-bottom:1px solid #21262d;background:#0d1117}
    .panel canvas{display:block;width:640px;height:480px}
    .stats{background:#161b22;border:1px solid #30363d;border-radius:8px;
           margin:0 16px 16px;padding:16px 24px}
    .stats h2{font-size:13px;font-weight:600;color:#58a6ff;margin-bottom:12px;
              text-transform:uppercase;letter-spacing:.05em}
    .stats-grid{display:grid;grid-template-columns:repeat(auto-fit, minmax(180px, 1fr));gap:16px;row-gap:24px;}
    .stat{display:flex;flex-direction:column;gap:4px}
    .stat-label{font-size:10px;color:#8b949e;text-transform:uppercase;letter-spacing:.08em}
    .stat-value{font-size:20px;font-weight:700;color:#e6edf3;font-variant-numeric:tabular-nums}
    .stat-unit{font-size:11px;color:#8b949e}
    .info-bar{display:flex;gap:24px;padding:8px 16px;background:#0d1117;
              border-top:1px solid #21262d;font-size:11px;color:#8b949e}
    .info-bar span{color:#58a6ff}
  </style>
</head>
<body>
<header>
  <h1>Live FFT Edge Detection</h1>
  <span class="badge">RISC-V RVV Assembly</span>
  <span>QEMU emulated &bull; 2D FFT Pipeline &bull; Butterworth High-Pass &bull; Real-time</span>
</header>
<div class="feeds">
  <div class="panel">
    <div class="panel-title">&#127909; Raw Camera Feed</div>
    <canvas id="rawCanvas" width="640" height="480"></canvas>
  </div>
  <div style="width:2px"></div>
  <div class="panel">
    <div class="panel-title">&#9654; Processed Feed (RISC-V FFT Edges)</div>
    <canvas id="edgeCanvas" width="640" height="480"></canvas>
  </div>
</div>
<div class="stats">
  <h2>Performance Stats</h2>
  <div class="stats-grid">
    <div class="stat">
      <div class="stat-label">Frames Processed</div>
      <div class="stat-value" id="frames">0</div>
    </div>
    <div class="stat">
      <div class="stat-label">Total Uptime</div>
      <div class="stat-value" id="total_s">0.0</div>
      <div class="stat-unit">seconds</div>
    </div>
    <div class="stat">
      <div class="stat-label">Current Full Pipeline</div>
      <div class="stat-value" id="curr_full">0.0</div>
      <div class="stat-unit">ms</div>
    </div>
    <div class="stat">
      <div class="stat-label">Avg Full Pipeline</div>
      <div class="stat-value" id="avg_full">0.0</div>
      <div class="stat-unit">ms / frame</div>
    </div>
    <div class="stat">
      <div class="stat-label">Current RISC-V FFT</div>
      <div class="stat-value" id="curr_fft">0.0</div>
      <div class="stat-unit">ms</div>
    </div>
    <div class="stat">
      <div class="stat-label">Avg RISC-V FFT</div>
      <div class="stat-value" id="avg_fft">0.0</div>
      <div class="stat-unit">ms / frame</div>
    </div>
  </div>
</div>
<div class="info-bar">
  <div>FFT Size: <span>256x256</span></div>
  <div>Display: <span>640x480</span></div>
  <div>Filter: <span>Butterworth High-Pass (D&#8320;=N/6)</span></div>
  <div>IFFT: <span>Spatial Edge Reconstruction</span></div>
  <div>IPC: <span>/dev/shm (RAM disk)</span></div>
</div>

<script>
const rawCtx  = document.getElementById('rawCanvas').getContext('2d');
const edgeCtx = document.getElementById('edgeCanvas').getContext('2d');

function drawFrame(ctx, b64) {
  const img = new Image();
  img.onload = () => ctx.drawImage(img, 0, 0, 640, 480);
  img.src = 'data:image/jpeg;base64,' + b64;
}

const ws = new WebSocket('ws://' + location.host + '/ws');
ws.onmessage = function(event) {
  const data = JSON.parse(event.data);
  if (data.raw)  drawFrame(rawCtx,  data.raw);
  if (data.edge) drawFrame(edgeCtx, data.edge);
  if (data.stats) {
    document.getElementById('frames').textContent    = data.stats.frames;
    document.getElementById('total_s').textContent   = data.stats.total_s.toFixed(1);
    document.getElementById('curr_full').textContent = data.stats.curr_full.toFixed(1);
    document.getElementById('avg_full').textContent  = data.stats.avg_full.toFixed(1);
    document.getElementById('curr_fft').textContent  = data.stats.curr_fft.toFixed(1);
    document.getElementById('avg_fft').textContent   = data.stats.avg_fft.toFixed(1);
  }
};
ws.onclose = () => setTimeout(() => location.reload(), 1000);
</script>
</body>
</html>
"""

# ── Normalize ────────────────────────────────────────────────
def normalize_edge(mag_array, N):
    arr = mag_array.reshape(N, N)
    clip_max = np.percentile(arr, 98)
    mn = arr.min()
    if clip_max == mn:
        return np.zeros((N, N), dtype=np.uint8)
    arr = np.clip(arr, mn, clip_max)
    arr = ((arr - mn) / (clip_max - mn) * 255).astype(np.uint8)
    arr[arr < 30] = 0
    return arr

# ── FFT server thread ────────────────────────────────────────
def fft_server_thread():
    global latest_raw_jpg, latest_edge_jpg, frames_processed, total_time_s
    global processing_times, fft_times

    # Try each camera index
    cap = None
    for idx in [0, 1, 2, 3]:
        try:
            test = cv2.VideoCapture(idx, cv2.CAP_V4L2)
            test.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*'MJPG'))
            test.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
            test.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
            test.set(cv2.CAP_PROP_FPS, 30)
            test.set(cv2.CAP_PROP_BUFFERSIZE, 1)
            ret, frame = test.read()
            if ret and frame is not None:
                cap = test
                print(f"Camera on /dev/video{idx}: "
                      f"{int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))}x"
                      f"{int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))}")
                break
            test.release()
        except:
            pass

    if cap is None:
        print("ERROR: No camera found")
        return

    while True:
        ret, frame = cap.read()
        if not ret:
            time.sleep(0.01)
            continue

        t_start = time.time()

        # Store raw JPEG
        raw_disp = cv2.resize(frame, (DISPLAY_W, DISPLAY_H))
        _, raw_buf = cv2.imencode('.jpg', raw_disp,
                                   [cv2.IMWRITE_JPEG_QUALITY, 75])
        with frame_lock:
            latest_raw_jpg = base64.b64encode(raw_buf).decode()

        # Prepare FFT input
        gray  = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        small = cv2.resize(gray, (FFT_SIZE, FFT_SIZE),
                           interpolation=cv2.INTER_AREA)
        pixels = small.astype(np.float32) / 255.0

        # Write to /dev/shm
        with open(FRAME_IN, 'wb') as f:
            f.write(struct.pack('<i', FFT_SIZE))
            f.write(pixels.tobytes())

        # Wait for result and time ONLY the FFT execution
        wait_start = time.time()
        while not os.path.exists(READY_FLAG):
            if time.time() - wait_start > 10.0:
                break
            time.sleep(0.001)
            
        fft_end = time.time()
        fft_proc_ms = (fft_end - wait_start) * 1000.0

        if not os.path.exists(READY_FLAG):
            continue

        try:
            with open(EDGES_OUT, 'rb') as f:
                N_read = struct.unpack('<i', f.read(4))[0]
                edge_data = np.frombuffer(
                    f.read(N_read * N_read * 4), dtype=np.float32)
            try:
                os.unlink(READY_FLAG)
            except:
                pass

            edge_img = normalize_edge(edge_data, N_read)
            edge_disp = cv2.resize(edge_img, (DISPLAY_W, DISPLAY_H),
                                   interpolation=cv2.INTER_CUBIC)
            edge_color = cv2.cvtColor(edge_disp, cv2.COLOR_GRAY2BGR)
            _, edge_buf = cv2.imencode('.jpg', edge_color,
                                       [cv2.IMWRITE_JPEG_QUALITY, 75])
            with frame_lock:
                latest_edge_jpg = base64.b64encode(edge_buf).decode()

            t_end = time.time()
            proc_ms = (t_end - t_start) * 1000.0
            
            with stats_lock:
                processing_times.append(proc_ms)
                fft_times.append(fft_proc_ms)
                
                if len(processing_times) > 60:
                    processing_times.pop(0)
                    fft_times.pop(0)
                    
                frames_processed += 1
                total_time_s += (proc_ms / 1000.0)

        except Exception as e:
            print(f"Error: {e}")
            try:
                os.unlink(READY_FLAG)
            except:
                pass

    cap.release()

# ── WebSocket route ──────────────────────────────────────────
@sock.route('/ws')
def websocket(ws):
    """Push frames + stats to browser via WebSocket — no reconnect flashing."""
    import json
    while True:
        with frame_lock:
            raw  = latest_raw_jpg
            edge = latest_edge_jpg
        with stats_lock:
            pt = processing_times[:]
            ft = fft_times[:]
            fp = frames_processed
            ts = total_time_s

        msg = {}
        if raw:  msg['raw']  = raw
        if edge: msg['edge'] = edge
        
        msg['stats'] = {
            'frames':    fp,
            'total_s':   ts,
            'curr_full': pt[-1] if pt else 0.0,
            'avg_full':  sum(pt)/len(pt) if pt else 0.0,
            'curr_fft':  ft[-1] if ft else 0.0,
            'avg_fft':   sum(ft)/len(ft) if ft else 0.0,
        }
        
        try:
            ws.send(json.dumps(msg))
        except:
            break
        time.sleep(1/25)   # ~25fps push rate

@app.route('/')
def index():
    return HTML

# ── Startup ──────────────────────────────────────────────────
def start_qemu_server():
    global qemu_process
    for f in [FRAME_IN, EDGES_OUT, READY_FLAG, "/dev/shm/fft_ready"]:
        try: os.unlink(f)
        except: pass
    print(f"Starting RISC-V FFT server: {QEMU_BIN} -cpu max {FFT_BIN}")
    qemu_process = subprocess.Popen(
        [QEMU_BIN, '-cpu', 'max', FFT_BIN],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    line = qemu_process.stdout.readline()
    print(f"Server: {line.decode().strip()}")

def cleanup(sig, frame):
    global qemu_process
    print("\nShutting down...")
    if qemu_process: qemu_process.terminate()
    for f in [FRAME_IN, EDGES_OUT, READY_FLAG, "/dev/shm/fft_ready.tmp"]:
        try: os.unlink(f)
        except: pass
    sys.exit(0)

if __name__ == '__main__':
    signal.signal(signal.SIGINT,  cleanup)
    signal.signal(signal.SIGTERM, cleanup)

    start_qemu_server()
    time.sleep(0.5)

    t = threading.Thread(target=fft_server_thread, daemon=True)
    t.start()

    print(f"\n{'='*50}")
    print(f"GUI running at: http://localhost:5000")
    print(f"FFT size: {FFT_SIZE}x{FFT_SIZE}  Display: {DISPLAY_W}x{DISPLAY_H}")
    print(f"Open your browser to http://localhost:5000")
    print(f"{'='*50}\n")

    app.run(host='0.0.0.0', port=5000, threaded=True, debug=False)