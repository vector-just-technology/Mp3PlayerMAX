#!/bin/bash
# ============================================================
# Mp3PlayerMAX - Main Installer
# Raspberry Pi 3B
# ============================================================

set -e

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
USER_HOME="/home/pi"
MUSIC_DIR="$USER_HOME/Music"
PICTURES_DIR="$USER_HOME/Pictures"
VIDEOS_DIR="$USER_HOME/Videos"

echo "============================================"
echo "   Mp3PlayerMAX Installer"
echo "============================================"
echo ""

# --- Check running as root ---
if [ "$EUID" -ne 0 ]; then
    echo "[ERROR] Please run as root: sudo bash scripts/install.sh"
    exit 1
fi

echo "[1/7] Installing system dependencies..."
apt-get update -y
apt-get install -y \
    python3 python3-pip python3-venv \
    mpg123 ffmpeg vlc-nox \
    bluez bluez-tools pulseaudio pulseaudio-module-bluetooth \
    v4l-utils \
    chromium-browser \
    xdotool unclutter \
    git wget curl \
    alsa-utils

echo "[2/7] Installing Hosyond 3.5\" touchscreen driver..."
bash "$REPO_DIR/drivers/hosyond35_install.sh"

echo "[3/7] Setting up Python virtual environment..."
python3 -m venv "$REPO_DIR/venv"
source "$REPO_DIR/venv/bin/activate"
pip install --upgrade pip
pip install flask flask-socketio eventlet mutagen pillow

echo "[4/7] Creating media directories..."
mkdir -p "$MUSIC_DIR" "$PICTURES_DIR" "$VIDEOS_DIR"
chown -R pi:pi "$MUSIC_DIR" "$PICTURES_DIR" "$VIDEOS_DIR"

echo "[5/7] Installing systemd services..."

# Web server service
cp "$REPO_DIR/systemd/mp3playermax.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable mp3playermax.service

# Kiosk service
cp "$REPO_DIR/systemd/kiosk.service" /etc/systemd/system/
systemctl enable kiosk.service

echo "[6/7] Configuring audio..."
# Ensure ALSA defaults to the 3.5mm jack (card 0, device 0)
bash -c 'cat > /etc/asound.conf <<EOF
pcm.!default {
    type hw
    card 0
}
ctl.!default {
    type hw
    card 0
}
EOF'

# Enable PulseAudio Bluetooth module
bash -c 'cat >> /etc/pulse/default.pa <<EOF

### Bluetooth audio support
load-module module-bluetooth-policy
load-module module-bluetooth-discover
EOF'

echo "[7/7] Writing app config..."
cat > "$REPO_DIR/config/mp3playermax.conf" <<EOF
[paths]
music_dir = /home/pi/Music
pictures_dir = /home/pi/Pictures
videos_dir = /home/pi/Videos

[audio]
default_output = jack
volume = 80

[web]
host = 0.0.0.0
port = 5000
debug = false

[webcam]
device = /dev/video0
width = 640
height = 480
fps = 15
EOF

echo ""
echo "============================================"
echo " Installation complete!"
echo ""
echo " Next steps:"
echo "  1. sudo reboot"
echo "  2. After reboot, open: http://$(hostname -I | awk '{print $1}'):5000"
echo "  3. Touchscreen kiosk will start automatically"
echo "============================================"
