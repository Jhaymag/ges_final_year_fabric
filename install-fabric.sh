#!/bin/bash

# ──────────────────────────────────────────────────────────────────────────
# GES Network — Prerequisites + Fabric Installer
# Installs: Go, jq, Fabric binaries, Fabric Docker images
# Tested on Ubuntu / WSL2 (Ubuntu)
# ──────────────────────────────────────────────────────────────────────────

set -e

FABRIC_VERSION=${1:-2.5.15}
CA_VERSION=${2:-1.5.17}
GO_VERSION="1.21.13"   # minimum recommended for Fabric 2.5

# ── Resolve script location ───────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "======================================================"
echo " GES Network Prerequisites + Fabric Installer"
echo "======================================================"
echo ""

# ── 1. Install Go ─────────────────────────────────────────────────────────
if command -v go &>/dev/null; then
  INSTALLED_GO=$(go version | awk '{print $3}' | sed 's/go//')
  echo "✓ Go already installed: v${INSTALLED_GO}"
else
  echo "==> Installing Go ${GO_VERSION}..."
  ARCH=$(dpkg --print-architecture)  # amd64 or arm64

  curl -sSLO https://go.dev/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz
  sudo rm -rf /usr/local/go
  sudo tar -C /usr/local -xzf go${GO_VERSION}.linux-${ARCH}.tar.gz
  rm go${GO_VERSION}.linux-${ARCH}.tar.gz

  # Add Go to PATH for this session
  export PATH=$PATH:/usr/local/go/bin

  # Add permanently to ~/.bashrc if not already there
  if ! grep -q '/usr/local/go/bin' ~/.bashrc; then
    echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
    echo 'export GOPATH=$HOME/go' >> ~/.bashrc
  fi

  echo "✓ Go ${GO_VERSION} installed"
fi

# ── 2. Install jq ─────────────────────────────────────────────────────────
if command -v jq &>/dev/null; then
  echo "✓ jq already installed"
else
  echo "==> Installing jq..."
  sudo apt-get update -qq && sudo apt-get install -y -qq jq
  echo "✓ jq installed"
fi

# ── 3. Check Docker ───────────────────────────────────────────────────────
if command -v docker &>/dev/null; then
  echo "✓ Docker already installed: $(docker --version)"
else
  echo ""
  echo "✗ Docker is not installed."
  echo "  Install it from: https://docs.docker.com/engine/install/ubuntu/"
  echo "  Then re-run this script."
  exit 1
fi

# ── 4. Install Fabric binaries + Docker images ────────────────────────────
echo ""
echo "==> Downloading Fabric install script..."
curl -sSLO https://raw.githubusercontent.com/hyperledger/fabric/main/scripts/install-fabric.sh
chmod +x install-fabric.sh

echo "==> Installing Fabric ${FABRIC_VERSION} binaries and Docker images..."
./install-fabric.sh --fabric-version $FABRIC_VERSION --ca-version $CA_VERSION docker binary
rm install-fabric.sh

# ── 5. Add Fabric binaries to PATH ───────────────────────────────────────
FABRIC_BIN="$SCRIPT_DIR/fabric-samples/bin"

export PATH=$PATH:$FABRIC_BIN

if ! grep -q 'fabric-samples/bin' ~/.bashrc; then
  echo "export PATH=\$PATH:$FABRIC_BIN" >> ~/.bashrc
fi

echo ""
echo "======================================================"
echo " ✅ All prerequisites installed!"
echo "======================================================"
echo ""
echo "  Go       : $(go version)"
echo "  peer     : $(peer version 2>/dev/null | head -1 || echo 'in PATH after reload')"
echo "  Docker   : $(docker --version)"
echo ""
echo "⚠️  PATH was updated. Run this to apply in your current terminal:"
echo "   source ~/.bashrc"
echo ""
echo "Then start the network:"
echo "   ./setup-ges-network.sh"
