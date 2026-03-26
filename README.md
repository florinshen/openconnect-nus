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
- Install `openconnect` via Homebrew
- Install `openconnect-sso` via `pipx` (using Python 3.12, since `openconnect-sso` is a PyPI package and requires Python ≤ 3.12)
- Add a passwordless `sudo` rule for `openconnect` to `/etc/sudoers.d/openconnect-nus`
- Copy the scripts to `~/.openconnect-nus/` (separate from the clone directory)
- Add shell aliases to `~/.zshrc`

### 3. Configure

**`~/.openconnect-nus/nusvpn_up_bg.sh`** — set your VPN portal URL:

```sh
SERVER="https://<your-vpn-host>/<portal-name>"
```

**`~/.openconnect-nus/vpnc_nus_split.sh`** — set the subnets to route through the VPN and an optional jump host:

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

| Path                              | Contents                                  |
|-----------------------------------|-------------------------------------------|
| `/tmp/nus_auth.log`               | SSO auth output (HOST/COOKIE/FINGERPRINT) |
| `/tmp/nus_openconnect.log`        | openconnect daemon output (current session) |
| `/tmp/nus_openconnect.prev.log`   | openconnect daemon output (previous session — survives `nusvpnup`) |
| `/tmp/nus_vpnc.log`               | vpnc-script execution log                 |

When a session dies unexpectedly, check `/tmp/nus_openconnect.prev.log` first — it contains the reconnect failure messages, DPD timeouts, or server reset lines from the connection that just ended.

---

## Avoiding the sudo password prompt

`openconnect` must run as root to create a TUN interface and modify the routing table. By default this means every `nusvpnup` asks for your password.

You can eliminate the prompt by granting passwordless sudo **only for the `openconnect` binary** via a dedicated sudoers file:

```sh
echo "$(whoami) ALL=(ALL) NOPASSWD: $(which openconnect)" | sudo tee /etc/sudoers.d/openconnect-nus
sudo chmod 440 /etc/sudoers.d/openconnect-nus
```

This is a narrow rule — it does not grant blanket passwordless sudo for anything else.

> The `install.sh` script does this automatically during installation.

To remove the rule later:

```sh
sudo rm /etc/sudoers.d/openconnect-nus
```

---

## Known Conflicts: Cisco Secure Client (`vpnagentd`)

If you have the **official Cisco Secure Client** installed alongside this project, its background daemon (`vpnagentd`) can disrupt openconnect sessions.

### Why it interferes

Cisco Secure Client installs a kernel-level packet filter system extension (`com.cisco.anyconnect.macos.acsockext`). When its daemon restarts — for example, during a scheduled cloud-management sync — the extension briefly interrupts DTLS (UDP) packet delivery for all VPN traffic, including openconnect's tunnel. This causes SSH sessions to hang or drop even though the openconnect process is still alive.

### Disable `vpnagentd` when not in use

If you rarely use the official Cisco Secure Client, disable the daemon while using openconnect:

```sh
sudo launchctl bootout system/com.cisco.secureclient.vpn.service.agent
sudo launchctl disable system/com.cisco.secureclient.vpn.service.agent
```

This persists across reboots. Verify it is gone:

```sh
ps aux | grep vpnagent | grep -v grep   # should return nothing
```

### Re-enable when you need Cisco Secure Client

```sh
sudo launchctl enable system/com.cisco.secureclient.vpn.service.agent
sudo launchctl bootstrap system "/opt/cisco/secureclient/bin/Cisco Secure Client - AnyConnect VPN Service.app/Contents/Library/LaunchDaemons/com.cisco.secureclient.vpn.service.agent.plist"
```

Then open the Cisco Secure Client app normally. Once you are done, disable it again:

```sh
sudo launchctl bootout system/com.cisco.secureclient.vpn.service.agent
sudo launchctl disable system/com.cisco.secureclient.vpn.service.agent
```

---

## Session Lifetime and Idle Timeout

The NUS VPN server enforces two independent limits:

| Limit | Duration | What happens |
|---|---|---|
| **Session auth expiry** | 12 hours | openconnect closes the tunnel; reconnect requires fresh browser auth |
| **Idle timeout** | ~8 hours | Server sends `Idle Timeout` disconnect if no user data traffic flows through the tunnel |

The `DPD 30, Keepalive 20` values in the openconnect log are *CSTP protocol* keepalives — they keep the SSL pipe open but are **not counted as user traffic** by the server's idle timer.

To prevent idle disconnects, `nusvpnup` starts a background keepalive process (stored in `~/.nusvpn_keepalive.pid`) that pings the hopper host through the VPN every 4 minutes 30 seconds. `nusvpndown` stops it automatically.

You will still need to run `nusvpnup` again after the 12-hour session auth expires.

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
