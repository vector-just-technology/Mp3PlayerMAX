# 🎵 Mp3PlayerMAX

A full-featured Raspberry Pi 3B media station with:
- 🎵 MP3 Player (Bluetooth + 3.5mm jack audio output)
- 📷 USB Webcam viewer & recorder
- 🖥️ Hosyond 3.5" SPI Touchscreen (480×320)
- 🌐 Web UI (accessible from the touchscreen or any browser on your network)

---

## Hardware Required

| Component | Details |
|-----------|---------|
| Raspberry Pi 3B | Main board |
| Hosyond 3.5" Touchscreen | SPI, 480×320, GPIO header mount |
| USB Webcam | Any UVC-compatible webcam |
| Bluetooth Speaker / Headphones | Or use the 3.5mm audio jack |
| MicroSD Card | 16GB+ recommended |
| Power Supply | 5V 2.5A |

---

## Quick Start

### 1. Flash Raspberry Pi OS

Use **Raspberry Pi OS Lite (32-bit)** or **Raspberry Pi OS with Desktop (32-bit)**.

### 2. Clone this repo on your Pi

```bash
git clone https://github.com/vector-just-technology/Mp3PlayerMAX.git
cd Mp3PlayerMAX
```

### 3. Run the installer

```bash
chmod +x scripts/install.sh
sudo bash scripts/install.sh
```

This will:
- Install the Hosyond 3.5" touchscreen driver (safe, non-conflicting)
- Install all Python/system dependencies
- Set up audio (Bluetooth + 3.5mm jack)
- Install and enable the web UI as a systemd service
- Configure autostart on boot

### 4. Reboot

```bash
sudo reboot
```

After reboot, the web UI will be available at:
```
http://<your-pi-ip>:5000
```

The touchscreen will also display the UI automatically via Chromium kiosk mode.

---

## Features

### 🎵 MP3 Player
- Browse and play MP3/FLAC/OGG/WAV files from `/home/pi/Music`
- Playlist support
- Previous / Next / Play / Pause / Stop / Shuffle
- Volume control
- Bluetooth audio output (pair via web UI)
- 3.5mm jack fallback

### 📷 Webcam
- Live MJPEG stream in the browser
- Snapshot capture (saved to `/home/pi/Pictures`)
- Video recording (saved to `/home/pi/Videos`)

### 🖥️ Touchscreen
- Hosyond 3.5" SPI driver installed without overwriting `/boot/config.txt` audio settings
- Touch-calibrated for accurate input
- Chromium kiosk mode auto-starts the web UI on boot

---

## Directory Structure

```
Mp3PlayerMAX/
├── drivers/
│   └── hosyond35_install.sh     # Touchscreen driver installer
├── scripts/
│   ├── install.sh               # Main installer
│   ├── audio_switch.sh          # Switch between BT and jack
│   └── bt_pair.sh               # Bluetooth pairing helper
├── web/
│   ├── app.py                   # Flask web server
│   ├── templates/
│   │   └── index.html           # Web UI
│   └── static/
│       ├── style.css
│       └── app.js
├── config/
│   ├── config.txt.patch         # Safe config.txt additions
│   └── mp3playermax.conf        # App config
├── systemd/
│   ├── mp3playermax.service     # Web server service
│   └── kiosk.service            # Chromium kiosk service
└── README.md
```

---

## Adding Music (SMB Network Share)

After installation, your Pi appears as a network drive on any device on the same WiFi.

**Windows** — open File Explorer and type in the address bar:
```
\\<PI_IP>\Music
```

**Mac** — Finder → Go → Connect to Server:
```
smb://<PI_IP>/Music
```

**Linux:**
```bash
nautilus smb://<PI_IP>/Music
# or mount it:
sudo mount -t cifs //<PI_IP>/Music /mnt/pimusic -o guest
```

Just drag and drop your MP3/FLAC/OGG/WAV files in, then tap **↻ Refresh** in the web UI. The shares are open (no password) and auto-start on boot.

To set up SMB separately (if you skipped it):
```bash
sudo bash scripts/smb_setup.sh
```

---

## Audio Output Switching

Switch between Bluetooth and 3.5mm jack:

```bash
# Use 3.5mm jack
bash scripts/audio_switch.sh jack

# Use Bluetooth (after pairing)
bash scripts/audio_switch.sh bluetooth
```

Or use the toggle in the Web UI.

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| No touchscreen display | Re-run `sudo bash drivers/hosyond35_install.sh` and reboot |
| No audio from jack | Run `sudo raspi-config` → System → Audio → 3.5mm |
| Bluetooth not connecting | Run `bash scripts/bt_pair.sh` |
| Web UI not loading | Check service: `sudo systemctl status mp3playermax` |
| Webcam not detected | Run `ls /dev/video*` — ensure webcam is plugged in |

---

## License

MIT License — free to use, modify, and share.
