#!/bin/zsh
set -euo pipefail

# One-key installer for openconnect-nus on macOS
# Installs Homebrew (if missing), openconnect, openconnect-sso, and sets up scripts.

INSTALL_DIR="$HOME/.openconnect-nus"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==> openconnect-nus installer"
echo

# ── 1. Homebrew ────────────────────────────────────────────────────────────────
if ! command -v brew >/dev/null 2>&1; then
  echo "==> Homebrew not found. Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/homebrew/install/HEAD/install.sh)"

  # Add brew to PATH for Apple Silicon
  if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
else
  echo "==> Homebrew already installed. Skipping."
fi

# ── 2. openconnect ─────────────────────────────────────────────────────────────
if ! command -v openconnect >/dev/null 2>&1; then
  echo "==> Installing openconnect..."
  brew install openconnect
else
  echo "==> openconnect already installed. Skipping."
fi

# ── 2b. sudoers rule for openconnect (no password prompt) ──────────────────────
OC_BIN="$(command -v openconnect)"
SUDOERS_FILE="/etc/sudoers.d/openconnect-nus"
SUDOERS_LINE="$(whoami) ALL=(ALL) NOPASSWD: $OC_BIN"
if sudo grep -qF "$OC_BIN" "$SUDOERS_FILE" 2>/dev/null; then
  echo "==> sudoers rule already present. Skipping."
else
  echo "==> Adding passwordless sudo rule for openconnect (requires your password once)..."
  echo "$SUDOERS_LINE" | sudo tee "$SUDOERS_FILE" > /dev/null
  sudo chmod 440 "$SUDOERS_FILE"
  echo "==> sudoers rule added: $SUDOERS_FILE"
fi

# ── 3. openconnect-sso ─────────────────────────────────────────────────────────
# openconnect-sso is a PyPI package (not Homebrew). It requires Python <=3.12
# because lxml (a dependency) does not yet support Python 3.14+.
# We use pipx to install it in an isolated virtualenv.
if ! command -v openconnect-sso >/dev/null 2>&1; then
  echo "==> Installing openconnect-sso via pipx (Python 3.12)..."

  if ! command -v pipx >/dev/null 2>&1; then
    brew install pipx
    pipx ensurepath
  fi

  if ! brew list python@3.12 &>/dev/null; then
    brew install python@3.12
  fi

  pipx install openconnect-sso --python /opt/homebrew/bin/python3.12

  # setuptools >=71 dropped pkg_resources which openconnect-sso requires
  "$HOME/.local/pipx/venvs/openconnect-sso/bin/python3.12" \
    -m pip install "setuptools<71" --force-reinstall -q
else
  echo "==> openconnect-sso already installed. Skipping."
fi

# ── 4. Copy scripts ────────────────────────────────────────────────────────────
echo "==> Installing scripts to $INSTALL_DIR ..."
mkdir -p "$INSTALL_DIR"
cp "$REPO_DIR/nusvpn_up_bg.sh"   "$INSTALL_DIR/"
cp "$REPO_DIR/nusvpn_down_bg.sh" "$INSTALL_DIR/"
cp "$REPO_DIR/vpnc_nus_split.sh" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/nusvpn_up_bg.sh" \
         "$INSTALL_DIR/nusvpn_down_bg.sh" \
         "$INSTALL_DIR/vpnc_nus_split.sh"

# ── 5. zsh aliases ─────────────────────────────────────────────────────────────
ZSHRC="$HOME/.zshrc"
ALIAS_MARKER="# openconnect-nus aliases"

if grep -q "$ALIAS_MARKER" "$ZSHRC" 2>/dev/null; then
  echo "==> Aliases already present in $ZSHRC. Skipping."
else
  echo "==> Adding aliases to $ZSHRC ..."
  cat >> "$ZSHRC" <<EOF

$ALIAS_MARKER
alias nusvpnup="$INSTALL_DIR/nusvpn_up_bg.sh"
alias nusvpndown="$INSTALL_DIR/nusvpn_down_bg.sh"
alias nusvpnlog='tail -n 200 /tmp/nus_openconnect.log; echo; tail -n 200 /tmp/nus_vpnc.log'
alias nusvpnrt="netstat -rn -f inet | egrep '10\\.195|10\\.246|137\\.132'"
alias nustime="cat /tmp/nus_openconnect.log | grep -i expire"
EOF
fi

# ── Done ───────────────────────────────────────────────────────────────────────
echo
echo "==> Installation complete!"
echo
echo "Next steps:"
echo "  1. Edit $INSTALL_DIR/nusvpn_up_bg.sh"
echo "     → Set SERVER to your VPN portal URL"
echo "  2. Edit $INSTALL_DIR/vpnc_nus_split.sh"
echo "     → Set HOPPER_HOST (or leave empty)"
echo "     → Update add_routes / del_routes with your subnets"
echo "  3. Reload your shell:  source ~/.zshrc"
echo "  4. Connect:            nusvpnup"
echo "  5. Disconnect:         nusvpndown"
