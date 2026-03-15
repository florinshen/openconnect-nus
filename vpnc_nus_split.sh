#!/bin/sh
PATH="/sbin:/usr/sbin:/bin:/usr/bin"
LOG="/tmp/nus_vpnc.log"

# ============================================================
# CONFIGURATION — edit this section to match your institution
# ============================================================

# Jump/bastion host to also route through the VPN.
# Its IP(s) are resolved at connect time and added as host routes.
# Leave empty to skip: HOPPER_HOST=""
HOPPER_HOST="hopper.example.com"

# Subnets routed through the VPN (split-tunnel rules).
# Edit add_routes / del_routes below to add or remove subnets.
# Format: add_r <network> <netmask>
#
#   Network          Netmask           Description
#   ─────────────────────────────────────────────────────────
add_routes() {
  add_r 10.0.0.0     255.255.0.0   # example: internal cluster network
  add_r 10.1.0.0     255.255.0.0   # example: campus network
  add_r 192.168.0.0  255.255.0.0   # example: server network
}

del_routes() {
  del_r 10.0.0.0     255.255.0.0
  del_r 10.1.0.0     255.255.0.0
  del_r 192.168.0.0  255.255.0.0
}

# ============================================================

HOPPER_IP_FILE="/tmp/nus_hopper_ips"

ts(){ date "+%F %T"; }
log(){ echo "$(ts) $*" >> "$LOG"; }

add_if(){ /sbin/ifconfig "$TUNDEV" inet "$INTERNAL_IP4_ADDRESS" "$INTERNAL_IP4_ADDRESS" netmask 255.255.255.255 up >> "$LOG" 2>&1; }
add_mtu(){ [ -n "$INTERNAL_IP4_MTU" ] && /sbin/ifconfig "$TUNDEV" mtu "$INTERNAL_IP4_MTU" >> "$LOG" 2>&1; }

add_r(){ /sbin/route -n add -net "$1" -netmask "$2" -interface "$TUNDEV" >> "$LOG" 2>&1; }
del_r(){ /sbin/route -n delete -net "$1" -netmask "$2" -interface "$TUNDEV" >> "$LOG" 2>&1; }

add_h(){ /sbin/route -n add -host "$1" -interface "$TUNDEV" >> "$LOG" 2>&1; }
del_h(){ /sbin/route -n delete -host "$1" -interface "$TUNDEV" >> "$LOG" 2>&1; }

resolve_ipv4() {
  if command -v /usr/bin/dig >/dev/null 2>&1; then
    /usr/bin/dig +short "$1" A 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'
    return
  fi
  if command -v /usr/bin/host >/dev/null 2>&1; then
    /usr/bin/host -t A "$1" 2>/dev/null | awk '/has address/ {print $NF}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'
    return
  fi
}

case "$reason" in
  connect|reconnect)
    : > "$LOG"
    chmod 666 "$LOG"
    log "MARKER V3"
    log "script=$0"
    log "reason=$reason"
    log "TUNDEV=$TUNDEV"
    log "INTERNAL_IP4_ADDRESS=$INTERNAL_IP4_ADDRESS"
    log "INTERNAL_IP4_MTU=$INTERNAL_IP4_MTU"

    log "ifconfig before"
    /sbin/ifconfig "$TUNDEV" >> "$LOG" 2>&1 || true

    log "set IPv4 and MTU"
    add_if
    add_mtu

    log "ifconfig after"
    /sbin/ifconfig "$TUNDEV" >> "$LOG" 2>&1 || true

    log "add routes"
    add_routes

    log "add host route for $HOPPER_HOST"
    : > "$HOPPER_IP_FILE"
    for ip in $(resolve_ipv4 "$HOPPER_HOST"); do
      echo "$ip" >> "$HOPPER_IP_FILE"
      add_h "$ip"
      log "hopper ip $ip added"
    done

    log "netstat after"
    /usr/sbin/netstat -rn -f inet >> "$LOG" 2>&1 || true
    ;;

  disconnect)
    log "reason=disconnect TUNDEV=$TUNDEV"
    del_routes

    if [ -f "$HOPPER_IP_FILE" ]; then
      while read -r ip; do
        [ -n "$ip" ] && del_h "$ip"
      done < "$HOPPER_IP_FILE"
      rm -f "$HOPPER_IP_FILE"
    fi
    ;;
esac

exit 0

