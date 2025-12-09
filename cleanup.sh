#!/usr/bin/env bash
set -euo pipefail

###########################################
# LENSTRACE CLEANUP
###########################################

NO_COLOR=0
FULL=0

for arg in "$@"; do
  case "$arg" in
    --no-color) NO_COLOR=1 ;;
    --full) FULL=1 ;;
    -h|--help)
      cat <<EOF
LENSTRACE Cleanup Utility

Usage: ./cleanup.sh [options]

Options:
  --full      Also remove cloudflared binary (fresh reinstall next run)
  --no-color  Disable ANSI colors
  -h, --help  Show this help
EOF
      exit 0
      ;;
  esac
done

if [ "$NO_COLOR" -eq 1 ] || ! command -v tput >/dev/null 2>&1; then
  RED=""; GRN=""; YLW=""; CYA=""; RST=""; BOLD=""
else
  RED=$(tput setaf 1)
  GRN=$(tput setaf 2)
  YLW=$(tput setaf 3)
  CYA=$(tput setaf 6)
  RST=$(tput sgr0)
  BOLD=$(tput bold)
fi

OK="${GRN}[✓]${RST}"
INFO="${CYA}[*]${RST}"
WARN="${YLW}[!]${RST}"

ROOT="$(cd "$(dirname "$0")" && pwd)"
CAPTURE_DIR="$ROOT/capture"
SNAP_DIR="$CAPTURE_DIR/snapshots"

PHP_SILENT="$ROOT/php_silent.log"
TUNNEL_SILENT="$ROOT/tunnel_silent.log"
PHP_OLD="$ROOT/php_server.log"
TUNNEL_OLD="$ROOT/tunnel.log"
LENSTRACE_LOG="$CAPTURE_DIR/lenstrace.log"
CLOUDFLARED_BIN="$ROOT/cloudflared"

PORT="8080"

clear
echo -e "${CYA}${BOLD}LENSTRACE CLEANUP${RST}"
echo -e "${YLW}This will:${RST}
  - stop PHP server & Cloudflare tunnel
  - delete log files (php/tunnel/lenstrace.log)
  - delete stored snapshots in capture/snapshots/
  - NOT touch core project files (index.html, lensbeacon.php, serve.sh)"

if [ "$FULL" -eq 1 ]; then
  echo -e "  - ${RED}ALSO delete cloudflared binary (fresh download next run)${RST}"
fi
echo

read -rp "⚠️  Permanently erase all camera snapshots & logs? (y/N): " ANSW
case "$ANSW" in
  y|Y) ;;
  *)
    echo -e "${OK} Cleanup aborted. Data preserved."
    exit 0
    ;;
esac

echo -e "${INFO} Stopping PHP server on port ${PORT}..."
PIDS=""
if command -v ss >/dev/null 2>&1; then
  PIDS=$(ss -ltnp 2>/dev/null | grep ":${PORT}" | awk '{print $6}' | sed 's/pid=//;s/,.*//' | sort -u || true)
fi
if [ -z "$PIDS" ]; then
  PIDS=$(pgrep -f "php -S 127.0.0.1:${PORT}" 2>/dev/null || true)
fi
if [ -z "$PIDS" ]; then
  echo -e "${WARN} No PHP processes found on port ${PORT}."
else
  for pid in $PIDS; do
    [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
  done
  echo -e "${OK} PHP processes stopped."
fi

echo -e "${INFO} Stopping cloudflared (if running)..."
pkill -f cloudflared 2>/dev/null || true
echo -e "${OK} cloudflared stop signal sent."

echo -e "${INFO} Removing logs and snapshots..."
mkdir -p "$CAPTURE_DIR"
rm -f "$PHP_SILENT" "$TUNNEL_SILENT" "$PHP_OLD" "$TUNNEL_OLD" "$LENSTRACE_LOG" 2>/dev/null || true

if [ -d "$SNAP_DIR" ]; then
  rm -f "$SNAP_DIR"/* 2>/dev/null || true
else
  mkdir -p "$SNAP_DIR"
fi

echo -e "${OK} Logs and snapshots removed."

if [ "$FULL" -eq 1 ]; then
  if [ -f "$CLOUDFLARED_BIN" ]; then
    echo -e "${INFO} Removing cloudflared binary..."
    rm -f "$CLOUDFLARED_BIN" 2>/dev/null || true
    echo -e "${OK} cloudflared binary removed."
  else
    echo -e "${WARN} cloudflared binary not found — nothing to remove."
  fi
fi

echo -e "${INFO} Creating fresh empty files..."
touch "$PHP_SILENT" "$TUNNEL_SILENT" "$LENSTRACE_LOG" 2>/dev/null || true
echo -e "${OK} Fresh files ready."

sleep 0.4
clear
echo -e "${GRN}${BOLD}🔒 LENSTRACE SNAPSHOT RESET${RST}"
echo -e "${GRN}All previous snapshots and logs have been wiped.${RST}"
if [ "$FULL" -eq 1 ]; then
  echo -e "${YLW}Note: cloudflared will be downloaded again next time you run ./serve.sh${RST}"
fi
echo -e "${CYA}You can now run ./serve.sh for a clean new LENSTRACE session.${RST}"