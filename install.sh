#!/data/data/com.termux/files/usr/bin/bash
# One-liner installer for Roblox Auto-Rejoin Tool

set -e

REPO_RAW="https://raw.githubusercontent.com/USER/REPO/main/rejoin.sh"   # ← PALITAN MO ITO
TARGET="$HOME/bin/rejoin.sh"

echo "[*] Updating packages..."
pkg update -y >/dev/null 2>&1

echo "[*] Installing dependencies..."
pkg install -y curl termux-api tsu coreutils procps >/dev/null 2>&1

echo "[*] Downloading rejoin.sh..."
mkdir -p "$HOME/bin"
curl -sL "$REPO_RAW" -o "$TARGET"
chmod +x "$TARGET"

echo "[*] Setting up alias..."
grep -q "alias rejoin=" ~/.bashrc 2>/dev/null || \
    echo "alias rejoin='$TARGET'" >> ~/.bashrc

echo ""
echo "[✓] Tapos! I-run mo:"
echo "    rejoin"
echo ""
echo "Sa background:"
echo "    nohup rejoin > ~/rejoin.log 2>&1 &"
echo ""
echo "Tingnan log:"
echo "    tail -f ~/rejoin.log"
