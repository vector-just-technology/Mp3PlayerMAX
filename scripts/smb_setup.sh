#!/bin/bash
# ============================================================
# Mp3PlayerMAX - Samba (SMB) Share Installer
# Shares ~/Music, ~/Pictures, ~/Videos over the network
# Access from Windows: \\<PI_IP>\Music
# Access from Mac:     smb://<PI_IP>/Music
# ============================================================

set -e

echo "============================================"
echo "  Mp3PlayerMAX - SMB Network Share Setup"
echo "============================================"
echo ""

if [ "$EUID" -ne 0 ]; then
    echo "[ERROR] Please run as root: sudo bash scripts/smb_setup.sh"
    exit 1
fi

echo "[1/4] Installing Samba..."
apt-get update -y
apt-get install -y samba samba-common-bin

echo "[2/4] Creating share directories..."
mkdir -p /home/pi/Music /home/pi/Pictures /home/pi/Videos
chown -R pi:pi /home/pi/Music /home/pi/Pictures /home/pi/Videos
chmod -R 755 /home/pi/Music /home/pi/Pictures /home/pi/Videos

echo "[3/4] Writing Samba config..."

# Backup existing config
cp /etc/samba/smb.conf /etc/samba/smb.conf.bak.mp3playermax 2>/dev/null || true

cat >> /etc/samba/smb.conf << 'EOF'

# ── Mp3PlayerMAX Shares ──────────────────────────────────────

[Music]
   comment = Mp3PlayerMAX Music Library
   path = /home/pi/Music
   browseable = yes
   writable = yes
   guest ok = yes
   create mask = 0644
   directory mask = 0755
   force user = pi

[Pictures]
   comment = Mp3PlayerMAX Snapshots
   path = /home/pi/Pictures
   browseable = yes
   writable = yes
   guest ok = yes
   create mask = 0644
   directory mask = 0755
   force user = pi

[Videos]
   comment = Mp3PlayerMAX Recordings
   path = /home/pi/Videos
   browseable = yes
   writable = yes
   guest ok = yes
   create mask = 0644
   directory mask = 0755
   force user = pi
EOF

echo "[4/4] Enabling and starting Samba..."
systemctl enable smbd nmbd
systemctl restart smbd nmbd

PI_IP=$(hostname -I | awk '{print $1}')

echo ""
echo "============================================"
echo " SMB Shares are LIVE!"
echo ""
echo " From Windows Explorer, type:"
echo "   \\\\$PI_IP\\Music"
echo "   \\\\$PI_IP\\Pictures"
echo "   \\\\$PI_IP\\Videos"
echo ""
echo " From Mac Finder → Go → Connect to Server:"
echo "   smb://$PI_IP/Music"
echo ""
echo " Just drag and drop your MP3s into Music,"
echo " then hit Refresh in the Mp3PlayerMAX web UI."
echo "============================================"
