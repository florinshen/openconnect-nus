#!/bin/zsh
set -euo pipefail

# ============================================================
# CONFIGURATION — edit this section to match your institution
# ============================================================

# VPN portal URL (Cisco AnyConnect / OpenConnect compatible)
# Example: https://<vpn-host>/<portal-name>
SERVER="https://<your-vpn-host>/<portal-name>"

# ============================================================

AUTH_LOG="/tmp/nus_auth.log"
VPNC_LOG="/tmp/nus_vpnc.log"
OC_LOG="/tmp/nus_openconnect.log"
COOKIE_FILE="/tmp/nus_cookie.txt"

PID_FILE="$HOME/.nusvpn.pid"
SCRIPT_DIR="${0:A:h}"
SCRIPT="$SCRIPT_DIR/vpnc_nus_split.sh"

rm -f "$AUTH_LOG" "$VPNC_LOG" "$OC_LOG" "$COOKIE_FILE" "$PID_FILE"

openconnect-sso -s "$SERVER" --browser-display-mode shown --authenticate shell 2>&1 | tee "$AUTH_LOG" >/dev/null

HOST="$(grep '^HOST=' "$AUTH_LOG" | tail -1 | cut -d= -f2- | tr -d '\r')"
COOKIE="$(grep '^COOKIE=' "$AUTH_LOG" | tail -1 | cut -d= -f2- | tr -d '\r')"
FINGERPRINT="$(grep '^FINGERPRINT=' "$AUTH_LOG" | tail -1 | cut -d= -f2- | tr -d '\r')"

if [[ -z "$HOST" || -z "$COOKIE" || -z "$FINGERPRINT" ]]; then
  echo "Parse failed. Check $AUTH_LOG"
  exit 1
fi

print -r -- "$COOKIE" > "$COOKIE_FILE"
chmod 600 "$COOKIE_FILE"

sudo openconnect \
  --protocol=anyconnect \
  --os=mac-intel \
  --cookie-on-stdin \
  --servercert "$FINGERPRINT" \
  --script "$SCRIPT" \
  --timestamp \
  --background \
  --pid-file "$PID_FILE" \
  "$HOST" < "$COOKIE_FILE" >> "$OC_LOG" 2>&1

rm -f "$COOKIE_FILE" || true

if [[ ! -f "$PID_FILE" ]]; then
  echo "PID file not created. Check $OC_LOG"
  tail -n 80 "$OC_LOG" || true
  exit 1
fi

PID="$(cat "$PID_FILE" | tr -d '[:space:]')"
if [[ -z "$PID" ]]; then
  echo "Empty PID. Check $OC_LOG"
  tail -n 80 "$OC_LOG" || true
  exit 1
fi

ok=0
for i in {1..25}; do
  if kill -0 "$PID" 2>/dev/null; then
    if [[ -f "$VPNC_LOG" ]] && grep -q 'MARKER V3' "$VPNC_LOG"; then
      ok=1
      break
    fi
  else
    break
  fi
  sleep 1
done

if [[ "$ok" != "1" ]]; then
  echo "VPN did not finish setup. Showing logs."
  echo
  echo "OpenConnect log tail"
  tail -n 120 "$OC_LOG" || true
  echo
  # echo "VPnc log tail"
  # tail -n 120 "$VPNC_LOG" || true
  exit 1
fi

echo "VPN up"
echo "PID file: $PID_FILE"
echo "Auth log: $AUTH_LOG"
echo "OpenConnect log: $OC_LOG"
echo "VPnc log: $VPNC_LOG"
echo "Route check: netstat -rn -f inet | egrep '10\\.195|10\\.246|137\\.132'"
