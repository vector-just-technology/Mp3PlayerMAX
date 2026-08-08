#!/bin/bash
# ============================================================
# Hosyond 3.5" SPI Touchscreen Driver Installer
# Compatible with Raspberry Pi 3B
# Driver: LCD-show (waveshare-compatible, works with Hosyond)
# Non-destructive: preserves audio and existing config.txt settings
# ============================================================

set -e

SCRIPTDIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG=/boot/config.txt
BACKUP=/boot/config.txt.bak.mp3playermax

echo "============================================"
echo " Hosyond 3.5\" Touchscreen Driver Installer"
echo "============================================"

# --- Backup config.txt ---
if [ ! -f "$BACKUP" ]; then
    echo "[*] Backing up $CONFIG to $BACKUP"
    sudo cp "$CONFIG" "$BACKUP"
fi

# --- Install dependencies ---
echo "[*] Installing dependencies..."
sudo apt-get update -y
sudo apt-get install -y git bc fbi xinput x11-xserver-utils xserver-xorg-input-evdev

# --- Clone LCD-show driver (waveshare-compatible, works with Hosyond 3.5 SPI) ---
DRIVERDIR=/opt/LCD-show
if [ ! -d "$DRIVERDIR" ]; then
    echo "[*] Cloning LCD-show driver..."
    sudo git clone https://github.com/goodtft/LCD-show.git "$DRIVERDIR"
else
    echo "[*] LCD-show already present, pulling latest..."
    sudo git -C "$DRIVERDIR" pull
fi
sudo chmod -R 755 "$DRIVERDIR"

# --- Apply ONLY the SPI/touchscreen overlays — do NOT touch audio settings ---
echo "[*] Patching /boot/config.txt (non-destructive)..."

patch_if_missing() {
    local LINE="$1"
    if ! grep -qF "$LINE" "$CONFIG"; then
        echo "$LINE" | sudo tee -a "$CONFIG" > /dev/null
        echo "    Added: $LINE"
    else
        echo "    Already present: $LINE"
    fi
}

# Make sure dtparam=audio=on is preserved (do not remove it)
if ! grep -q "dtparam=audio=on" "$CONFIG"; then
    patch_if_missing "dtparam=audio=on"
fi

# SPI overlay for the display
patch_if_missing "dtparam=spi=on"
patch_if_missing "dtoverlay=ads7846,cs=1,penirq=25,penirq_pull=2,speed=50000,keep_vref_on=0,swapxy=0,pmax=255,xohms=150,xmin=200,xmax=3900,ymin=200,ymax=3900"
patch_if_missing "dtoverlay=waveshare35a:rotate=90"

# Display framebuffer settings
patch_if_missing "hdmi_force_hotplug=1"
patch_if_missing "max_usb_current=1"
patch_if_missing "hdmi_group=2"
patch_if_missing "hdmi_mode=1"
patch_if_missing "hdmi_mode=87"
patch_if_missing "hdmi_cvt 480 320 60 6 0 0 0"
patch_if_missing "hdmi_drive=2"
patch_if_missing "display_rotate=0"

# --- Install evdev rules for touch input ---
echo "[*] Installing touch input rules..."
sudo bash -c 'cat > /etc/udev/rules.d/99-hosyond-touch.rules <<EOF
# Hosyond / ADS7846 touch input
SUBSYSTEM=="input", ATTRS{name}=="ADS7846 Touchscreen", ENV{DEVNAME}=="*event*", SYMLINK+="input/touchscreen"
EOF'

# --- Install 99-calibration.conf for X11 ---
sudo mkdir -p /etc/X11/xorg.conf.d/
sudo bash -c 'cat > /etc/X11/xorg.conf.d/99-calibration.conf <<EOF
Section "InputClass"
    Identifier      "calibration"
    MatchProduct    "ADS7846 Touchscreen"
    Option  "Calibration"   "3936 227 268 3880"
    Option  "SwapAxes"      "1"
    Option  "EmulateThirdButton" "0"
EndSection
EOF'

echo ""
echo "============================================"
echo " Driver installed successfully!"
echo " IMPORTANT: Reboot for changes to take effect"
echo " Run: sudo reboot"
echo "============================================"
