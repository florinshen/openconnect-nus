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
KEEPALIVE_PID_FILE="$HOME/.nusvpn_keepalive.pid"
SCRIPT_DIR="${0:A:h}"
SCRIPT="$SCRIPT_DIR/vpnc_nus_split.sh"

# Kill any existing openconnect process BEFORE clearing logs/pid.
# If the old process is not killed here it will eventually die on its own and its
# vpnc disconnect script will delete the split-tunnel routes that the new connection
# just added — breaking the VPN silently while the new tunnel is still alive.
if [[ -f "$PID_FILE" ]]; then
  OLD_PID="$(cat "$PID_FILE" | tr -d '[:space:]')"
  if [[ -n "$OLD_PID" ]] && kill -0 "$OLD_PID" 2>/dev/null; then
    echo "Stopping existing openconnect process (pid $OLD_PID)..."
    sudo kill -INT "$OLD_PID" 2>/dev/null || sudo kill "$OLD_PID" 2>/dev/null || true
    for i in {1..10}; do
      kill -0 "$OLD_PID" 2>/dev/null || break
      sleep 1
    done
  fi
fi

# Also stop the keepalive for the old connection (runs as the current user).
if [[ -f "$KEEPALIVE_PID_FILE" ]]; then
  OLD_KA_PID="$(cat "$KEEPALIVE_PID_FILE" | tr -d '[:space:]')"
  if [[ -n "$OLD_KA_PID" ]] && kill -0 "$OLD_KA_PID" 2>/dev/null; then
    kill "$OLD_KA_PID" 2>/dev/null || true
  fi
  rm -f "$KEEPALIVE_PID_FILE"
fi

# /tmp has the sticky bit: only the file owner can rm a file there.
# Logs are written by root (sudo openconnect / vpnc-script), so sudo rm is needed.
# The sudoers rule installed by install.sh covers this exact call without a password.
# Rotate the previous OC log so it survives the next run — useful for diagnosing
# why the old connection died (reconnect failures, DPD timeouts, server resets, etc.).
sudo mv -f "$OC_LOG" "${OC_LOG%.log}.prev.log" 2>/dev/null || true
sudo rm -f "$AUTH_LOG" "$VPNC_LOG" "$COOKIE_FILE"
rm -f "$PID_FILE" 2>/dev/null || true   # in $HOME — no sticky bit, user can always rm

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

# Keepalive: ping an internal host every 4m30s to prevent the server's idle
# timeout.  The Cisco AnyConnect SSE server sends "Idle Timeout" disconnect
# after ~8h of no user data traffic, independent of the 12h session auth limit.
# CSTP/DPD keepalives (VPN protocol level) do NOT count as user traffic.
# Pinging the hopper (or any routed internal host) sends real ICMP through the
# tunnel, resetting the idle counter on the server.
PING_TARGET="$(head -1 /tmp/nus_hopper_ips 2>/dev/null | tr -d '[:space:]')"
if [[ -n "$PING_TARGET" ]]; then
  (
    OC_PID="$PID"
    while kill -0 "$OC_PID" 2>/dev/null; do
      ping -c 1 -t 5 -q "$PING_TARGET" >/dev/null 2>&1 || true
      sleep 270   # 4 min 30 s — well under any 8h idle threshold
    done
  ) &
  echo $! > "$KEEPALIVE_PID_FILE"
fi

echo "VPN up"
echo "PID file: $PID_FILE"
echo "Auth log: $AUTH_LOG"
echo "OpenConnect log: $OC_LOG"
echo "VPnc log: $VPNC_LOG"
echo "Keepalive pid file: $KEEPALIVE_PID_FILE (target: ${PING_TARGET:-none})"
echo "Route check: netstat -rn -f inet | egrep '10\\.195|10\\.246|137\\.132'"
