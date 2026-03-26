#!/bin/zsh
set -euo pipefail

PID_FILE="$HOME/.nusvpn.pid"
KEEPALIVE_PID_FILE="$HOME/.nusvpn_keepalive.pid"
OC_LOG="/tmp/nus_openconnect.log"
VPNC_LOG="/tmp/nus_vpnc.log"

if [[ ! -f "$PID_FILE" ]]; then
  echo "No PID file. Nothing to stop."
  exit 0
fi

PID="$(cat "$PID_FILE" | tr -d '[:space:]')"
if [[ -z "$PID" ]]; then
  rm -f "$PID_FILE"
  echo "Empty PID file removed."
  exit 0
fi

sudo kill -INT "$PID" 2>/dev/null || sudo kill "$PID" 2>/dev/null || true

for i in {1..10}; do
  if kill -0 "$PID" 2>/dev/null; then
    sleep 1
  else
    break
  fi
done

rm -f "$PID_FILE"

# Stop the keepalive background process.
if [[ -f "$KEEPALIVE_PID_FILE" ]]; then
  KA_PID="$(cat "$KEEPALIVE_PID_FILE" | tr -d '[:space:]')"
  if [[ -n "$KA_PID" ]] && kill -0 "$KA_PID" 2>/dev/null; then
    kill "$KA_PID" 2>/dev/null || true
  fi
  rm -f "$KEEPALIVE_PID_FILE"
fi

echo "VPN down"
echo "OpenConnect log: $OC_LOG"
echo "VPnc log: $VPNC_LOG"
