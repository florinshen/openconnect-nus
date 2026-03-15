# openconnect-nus

Connect to a Cisco AnyConnect VPN on macOS using [openconnect](https://www.infradead.org/openconnect/) with **split tunneling** — only institutional subnets go through the VPN, so your normal internet traffic is unaffected. No AnyConnect client required.

## Why

The official Cisco AnyConnect client forces **all** traffic through the VPN. This project replaces it with `openconnect` + a custom vpnc-script that routes only the subnets you specify.

## Prerequisites

- macOS (Intel or Apple Silicon)
- `sudo` access (required for `openconnect` and route management)

All other dependencies (`openconnect`, `openconnect-sso`) are installed automatically by the install script.

---

## Quick Start

### 1. Clone the repo

```sh
git clone https://github.com/<your-username>/openconnect-nus.git
cd openconnect-nus
```

### 2. Run the installer

```sh
chmod +x install.sh
./install.sh
```

This will:
- Install [Homebrew](https://brew.sh) if it is not already present
- Install `openconnect` and `openconnect-sso` via Homebrew
- Copy the scripts to `~/openconnect-nus/`
- Add shell aliases to `~/.zshrc`

### 3. Configure

**`~/openconnect-nus/nusvpn_up_bg.sh`** — set your VPN portal URL:

```sh
SERVER="https://<your-vpn-host>/<portal-name>"
```

**`~/openconnect-nus/vpnc_nus_split.sh`** — set the subnets to route through the VPN and an optional jump host:

```sh
# Jump/bastion host (leave empty to skip)
HOPPER_HOST="bastion.example.com"

# Subnets routed through the VPN
#   Network          Netmask           Description
#   ─────────────────────────────────────────────────────────
add_routes() {
  add_r 10.0.0.0     255.255.0.0   # internal cluster network
  add_r 10.1.0.0     255.255.0.0   # campus network
  add_r 192.168.0.0  255.255.0.0   # server network
}
```

Add one `add_r` line per subnet. Copy the matching `del_r` lines into `del_routes()`.

### 4. Reload your shell

```sh
source ~/.zshrc
```

---

## Usage

| Command       | Description                            |
|---------------|----------------------------------------|
| `nusvpnup`    | Connect to VPN (opens browser for SSO) |
| `nusvpndown`  | Disconnect VPN                         |
| `nusvpnlog`   | Tail openconnect and vpnc logs         |
| `nusvpnrt`    | Show VPN routes in the routing table   |
| `nustime`     | Show session expiry from the log       |

---

## How It Works

```
nusvpnup
  │
  ├─ openconnect-sso  →  opens a browser for SSO authentication
  │                       outputs HOST / COOKIE / FINGERPRINT
  │
  └─ openconnect (background daemon)
       │
       └─ vpnc_nus_split.sh  (vpnc-script)
            ├─ connect:     configure tunnel interface + add split routes
            └─ disconnect:  remove split routes
```

1. `nusvpn_up_bg.sh` calls `openconnect-sso` to handle browser-based SSO. It captures the session cookie and server fingerprint from the output.
2. `openconnect` is started as a background daemon using that cookie. It calls `vpnc_nus_split.sh` to set up the tunnel.
3. `vpnc_nus_split.sh` adds routes **only for configured subnets** and an optional bastion host — everything else continues over your default interface.
4. `nusvpn_down_bg.sh` sends SIGINT to the `openconnect` daemon (via `~/.nusvpn.pid`), which triggers the disconnect case in the vpnc-script to clean up routes.

---

## Log Files

| Path                          | Contents                            |
|-------------------------------|-------------------------------------|
| `/tmp/nus_auth.log`           | SSO auth output (HOST/COOKIE/FINGERPRINT) |
| `/tmp/nus_openconnect.log`    | openconnect daemon output           |
| `/tmp/nus_vpnc.log`           | vpnc-script execution log           |

---

## Troubleshooting

**VPN did not finish setup**
Run `nusvpnlog` to inspect the logs. Common causes:
- Wrong `SERVER` URL — check with your institution's IT docs
- Server certificate mismatch — the fingerprint is captured automatically; if it fails, check `/tmp/nus_auth.log`

**Routes not removed after disconnect**
Manually clean up with:
```sh
sudo route -n delete -net <network> -netmask <netmask>
```

**`openconnect-sso` browser does not open**
Make sure a graphical session is active. `openconnect-sso` requires a display to show the SSO browser window.

---

## License

MIT
