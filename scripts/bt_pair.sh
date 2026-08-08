#!/bin/bash
# ============================================================
# Bluetooth Pairing Helper
# Scans for and pairs a Bluetooth audio device
# ============================================================

echo "============================================"
echo " Bluetooth Pairing Helper"
echo "============================================"
echo ""

# Ensure bluetooth service is running
sudo systemctl start bluetooth

# Enable Bluetooth adapter
bluetoothctl power on
bluetoothctl agent on
bluetoothctl default-agent

echo ""
echo "[*] Scanning for Bluetooth devices for 15 seconds..."
echo "    Turn on your speaker/headphones NOW and put them in pairing mode."
echo ""

bluetoothctl scan on &
SCAN_PID=$!
sleep 15
kill $SCAN_PID 2>/dev/null

echo ""
echo "Available devices:"
bluetoothctl devices

echo ""
read -p "Enter the MAC address of your device (e.g. AA:BB:CC:DD:EE:FF): " BT_MAC

if [ -z "$BT_MAC" ]; then
    echo "[ERROR] No MAC address entered. Exiting."
    exit 1
fi

echo ""
echo "[*] Pairing with $BT_MAC..."
bluetoothctl pair "$BT_MAC"
bluetoothctl trust "$BT_MAC"
bluetoothctl connect "$BT_MAC"

echo ""
echo "[*] Switching audio output to Bluetooth..."
bash "$(dirname "$0")/audio_switch.sh" bluetooth "$BT_MAC"

echo ""
echo "[OK] Bluetooth setup complete!"
echo "     MAC address: $BT_MAC"
echo "     Save this MAC to switch back: bash scripts/audio_switch.sh bluetooth $BT_MAC"
