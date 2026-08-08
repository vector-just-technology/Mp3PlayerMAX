#!/bin/bash
# ============================================================
# Audio Output Switcher — jack or bluetooth
# Usage: bash audio_switch.sh jack|bluetooth [BT_MAC]
# ============================================================

MODE="$1"
BT_MAC="$2"

case "$MODE" in
    jack)
        echo "[*] Switching audio output to 3.5mm jack..."
        # Set ALSA to use onboard audio card
        sudo bash -c 'cat > /etc/asound.conf <<EOF
pcm.!default {
    type hw
    card 0
}
ctl.!default {
    type hw
    card 0
}
EOF'
        # Force PulseAudio sink to analog
        pactl set-default-sink alsa_output.platform-bcm2835_audio.analog-stereo 2>/dev/null || \
        pactl set-default-sink $(pactl list sinks short | grep analog | awk '{print $2}' | head -1)
        amixer cset numid=3 1   # 1 = 3.5mm jack, 2 = HDMI
        echo "[OK] Audio output: 3.5mm jack"
        ;;

    bluetooth)
        if [ -z "$BT_MAC" ]; then
            echo "[ERROR] Bluetooth MAC address required."
            echo "Usage: bash audio_switch.sh bluetooth AA:BB:CC:DD:EE:FF"
            echo ""
            echo "Paired devices:"
            bluetoothctl paired-devices
            exit 1
        fi
        echo "[*] Connecting to Bluetooth device $BT_MAC..."
        bluetoothctl connect "$BT_MAC"
        sleep 2
        BT_SINK=$(pactl list sinks short | grep bluez | awk '{print $2}' | head -1)
        if [ -z "$BT_SINK" ]; then
            echo "[ERROR] Bluetooth sink not found. Is the device connected?"
            exit 1
        fi
        pactl set-default-sink "$BT_SINK"
        echo "[OK] Audio output: Bluetooth ($BT_MAC)"
        ;;

    *)
        echo "Usage: bash audio_switch.sh jack|bluetooth [BT_MAC_ADDRESS]"
        exit 1
        ;;
esac
