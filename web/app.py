"""
Mp3PlayerMAX - Flask Web Server
Raspberry Pi 3B
Controls: MP3 player, webcam, audio output switching
"""

import os
import glob
import subprocess
import threading
import time
import configparser
import json
from pathlib import Path

from flask import Flask, render_template, jsonify, request, Response
from flask_socketio import SocketIO, emit

# ── Config ──────────────────────────────────────────────────
CONFIG_PATH = os.path.join(os.path.dirname(__file__), "../config/mp3playermax.conf")
config = configparser.ConfigParser()
config.read(CONFIG_PATH)

MUSIC_DIR    = config.get("paths", "music_dir",    fallback="/home/pi/Music")
PICTURES_DIR = config.get("paths", "pictures_dir", fallback="/home/pi/Pictures")
VIDEOS_DIR   = config.get("paths", "videos_dir",   fallback="/home/pi/Videos")
HOST         = config.get("web", "host",           fallback="0.0.0.0")
PORT         = config.getint("web", "port",        fallback=5000)
WEBCAM_DEV   = config.get("webcam", "device",      fallback="/dev/video0")
CAM_W        = config.getint("webcam", "width",    fallback=640)
CAM_H        = config.getint("webcam", "height",   fallback=480)
CAM_FPS      = config.getint("webcam", "fps",      fallback=15)

# ── App setup ────────────────────────────────────────────────
app = Flask(__name__)
app.config["SECRET_KEY"] = "mp3playermax-secret"
socketio = SocketIO(app, cors_allowed_origins="*", async_mode="eventlet")

# ── Player State ─────────────────────────────────────────────
player_state = {
    "status": "stopped",      # playing | paused | stopped
    "current_file": None,
    "current_index": -1,
    "playlist": [],
    "volume": 80,
    "shuffle": False,
    "audio_output": "jack",   # jack | bluetooth
    "bt_device": None,
}
player_proc = None
player_lock = threading.Lock()

# ── Webcam State ─────────────────────────────────────────────
cam_lock = threading.Lock()
cam_recording = False
cam_record_proc = None

# ─────────────────────────────────────────────────────────────
# Utility helpers
# ─────────────────────────────────────────────────────────────

def get_music_files():
    exts = ("*.mp3", "*.flac", "*.ogg", "*.wav", "*.aac", "*.m4a")
    files = []
    for ext in exts:
        files.extend(glob.glob(os.path.join(MUSIC_DIR, "**", ext), recursive=True))
    files.sort()
    return files


def run_cmd(cmd, check=False):
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=10)
        return result.stdout.strip(), result.returncode
    except Exception as e:
        return str(e), -1


def broadcast_state():
    socketio.emit("state", player_state)


# ─────────────────────────────────────────────────────────────
# Player control
# ─────────────────────────────────────────────────────────────

def _play_file(filepath):
    global player_proc
    with player_lock:
        if player_proc and player_proc.poll() is None:
            player_proc.terminate()
            player_proc.wait()

        env = os.environ.copy()
        cmd = ["mpg123", "--quiet", "-a", "default", filepath]
        # For FLAC/OGG/WAV use ffplay
        ext = Path(filepath).suffix.lower()
        if ext != ".mp3":
            cmd = ["ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet",
                   "-af", f"volume={player_state['volume']/100}", filepath]

        player_proc = subprocess.Popen(cmd, env=env)

    player_state["status"] = "playing"
    player_state["current_file"] = filepath
    broadcast_state()

    # Watch for process end → auto-next
    def _watch():
        player_proc.wait()
        if player_state["status"] == "playing":
            _auto_next()
    threading.Thread(target=_watch, daemon=True).start()


def _auto_next():
    pl = player_state["playlist"]
    if not pl:
        player_state["status"] = "stopped"
        broadcast_state()
        return
    idx = player_state["current_index"]
    if player_state["shuffle"]:
        import random
        idx = random.randint(0, len(pl) - 1)
    else:
        idx = (idx + 1) % len(pl)
    player_state["current_index"] = idx
    _play_file(pl[idx])


def _stop():
    global player_proc
    with player_lock:
        if player_proc and player_proc.poll() is None:
            player_proc.terminate()
            player_proc.wait()
    player_state["status"] = "stopped"
    broadcast_state()


def _pause_resume():
    global player_proc
    with player_lock:
        if player_proc and player_proc.poll() is None:
            if player_state["status"] == "playing":
                player_proc.send_signal(__import__("signal").SIGSTOP)
                player_state["status"] = "paused"
            elif player_state["status"] == "paused":
                player_proc.send_signal(__import__("signal").SIGCONT)
                player_state["status"] = "playing"
    broadcast_state()


# ─────────────────────────────────────────────────────────────
# Routes — Pages
# ─────────────────────────────────────────────────────────────

@app.route("/")
def index():
    return render_template("index.html")


# ─────────────────────────────────────────────────────────────
# Routes — Player API
# ─────────────────────────────────────────────────────────────

@app.route("/api/library")
def api_library():
    files = get_music_files()
    return jsonify([{"path": f, "name": Path(f).name} for f in files])


@app.route("/api/play", methods=["POST"])
def api_play():
    data = request.json or {}
    files = get_music_files()
    if not files:
        return jsonify({"error": "No music files found in " + MUSIC_DIR}), 404

    if "index" in data:
        idx = int(data["index"])
    elif "path" in data:
        try:
            idx = files.index(data["path"])
        except ValueError:
            return jsonify({"error": "File not in library"}), 404
    else:
        idx = 0

    player_state["playlist"] = files
    player_state["current_index"] = idx
    threading.Thread(target=_play_file, args=(files[idx],), daemon=True).start()
    return jsonify({"ok": True, "playing": files[idx]})


@app.route("/api/pause", methods=["POST"])
def api_pause():
    _pause_resume()
    return jsonify({"status": player_state["status"]})


@app.route("/api/stop", methods=["POST"])
def api_stop():
    _stop()
    return jsonify({"ok": True})


@app.route("/api/next", methods=["POST"])
def api_next():
    _auto_next()
    return jsonify({"ok": True})


@app.route("/api/prev", methods=["POST"])
def api_prev():
    pl = player_state["playlist"]
    if not pl:
        return jsonify({"error": "No playlist"}), 400
    idx = (player_state["current_index"] - 1) % len(pl)
    player_state["current_index"] = idx
    threading.Thread(target=_play_file, args=(pl[idx],), daemon=True).start()
    return jsonify({"ok": True})


@app.route("/api/volume", methods=["POST"])
def api_volume():
    vol = int(request.json.get("volume", 80))
    vol = max(0, min(100, vol))
    player_state["volume"] = vol
    run_cmd(f"amixer set Master {vol}%")
    broadcast_state()
    return jsonify({"volume": vol})


@app.route("/api/shuffle", methods=["POST"])
def api_shuffle():
    player_state["shuffle"] = not player_state["shuffle"]
    broadcast_state()
    return jsonify({"shuffle": player_state["shuffle"]})


@app.route("/api/state")
def api_state():
    return jsonify(player_state)


# ─────────────────────────────────────────────────────────────
# Routes — Audio Output
# ─────────────────────────────────────────────────────────────

@app.route("/api/audio/switch", methods=["POST"])
def api_audio_switch():
    data = request.json or {}
    mode = data.get("mode", "jack")
    bt_mac = data.get("bt_mac", "")

    script = os.path.join(os.path.dirname(__file__), "../scripts/audio_switch.sh")
    if mode == "bluetooth" and bt_mac:
        out, rc = run_cmd(f"bash {script} bluetooth {bt_mac}")
        player_state["audio_output"] = "bluetooth"
        player_state["bt_device"] = bt_mac
    else:
        out, rc = run_cmd(f"bash {script} jack")
        player_state["audio_output"] = "jack"

    broadcast_state()
    return jsonify({"ok": rc == 0, "output": out})


@app.route("/api/bluetooth/scan")
def api_bt_scan():
    run_cmd("bluetoothctl power on")
    run_cmd("bluetoothctl scan on &")
    time.sleep(8)
    run_cmd("bluetoothctl scan off")
    out, _ = run_cmd("bluetoothctl devices")
    devices = []
    for line in out.splitlines():
        parts = line.split(" ", 2)
        if len(parts) == 3:
            devices.append({"mac": parts[1], "name": parts[2]})
    return jsonify(devices)


@app.route("/api/bluetooth/connect", methods=["POST"])
def api_bt_connect():
    mac = request.json.get("mac", "")
    if not mac:
        return jsonify({"error": "MAC required"}), 400
    run_cmd(f"bluetoothctl trust {mac}")
    out, rc = run_cmd(f"bluetoothctl connect {mac}")
    if rc == 0:
        player_state["audio_output"] = "bluetooth"
        player_state["bt_device"] = mac
        broadcast_state()
    return jsonify({"ok": rc == 0, "output": out})


# ─────────────────────────────────────────────────────────────
# Routes — Webcam
# ─────────────────────────────────────────────────────────────

def gen_frames():
    import cv2
    cap = cv2.VideoCapture(WEBCAM_DEV)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, CAM_W)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, CAM_H)
    cap.set(cv2.CAP_PROP_FPS, CAM_FPS)
    try:
        while True:
            ok, frame = cap.read()
            if not ok:
                break
            _, buf = cv2.imencode(".jpg", frame)
            yield (b"--frame\r\nContent-Type: image/jpeg\r\n\r\n" +
                   buf.tobytes() + b"\r\n")
    finally:
        cap.release()


@app.route("/api/webcam/stream")
def webcam_stream():
    try:
        import cv2
        return Response(gen_frames(), mimetype="multipart/x-mixed-replace; boundary=frame")
    except ImportError:
        return jsonify({"error": "opencv-python not installed. Run: pip install opencv-python-headless"}), 500


@app.route("/api/webcam/snapshot", methods=["POST"])
def webcam_snapshot():
    try:
        import cv2
        cap = cv2.VideoCapture(WEBCAM_DEV)
        ok, frame = cap.read()
        cap.release()
        if not ok:
            return jsonify({"error": "Could not capture frame"}), 500
        filename = os.path.join(PICTURES_DIR, f"snap_{int(time.time())}.jpg")
        cv2.imwrite(filename, frame)
        return jsonify({"ok": True, "file": filename})
    except ImportError:
        # fallback: use fswebcam
        filename = os.path.join(PICTURES_DIR, f"snap_{int(time.time())}.jpg")
        out, rc = run_cmd(f"fswebcam -r {CAM_W}x{CAM_H} --jpeg 85 {filename}")
        return jsonify({"ok": rc == 0, "file": filename})


@app.route("/api/webcam/record/start", methods=["POST"])
def webcam_record_start():
    global cam_recording, cam_record_proc
    with cam_lock:
        if cam_recording:
            return jsonify({"error": "Already recording"}), 400
        filename = os.path.join(VIDEOS_DIR, f"video_{int(time.time())}.mp4")
        cmd = (f"ffmpeg -f v4l2 -video_size {CAM_W}x{CAM_H} -framerate {CAM_FPS} "
               f"-i {WEBCAM_DEV} -vcodec libx264 -preset ultrafast {filename}")
        cam_record_proc = subprocess.Popen(cmd.split())
        cam_recording = True
    return jsonify({"ok": True, "file": filename})


@app.route("/api/webcam/record/stop", methods=["POST"])
def webcam_record_stop():
    global cam_recording, cam_record_proc
    with cam_lock:
        if cam_record_proc:
            cam_record_proc.terminate()
            cam_record_proc = None
        cam_recording = False
    return jsonify({"ok": True})


# ─────────────────────────────────────────────────────────────
# SocketIO
# ─────────────────────────────────────────────────────────────

@socketio.on("connect")
def on_connect():
    emit("state", player_state)


# ─────────────────────────────────────────────────────────────
# Entry point
# ─────────────────────────────────────────────────────────────

if __name__ == "__main__":
    print(f"[Mp3PlayerMAX] Starting on http://{HOST}:{PORT}")
    print(f"[Mp3PlayerMAX] Music dir: {MUSIC_DIR}")
    socketio.run(app, host=HOST, port=PORT, debug=False)
