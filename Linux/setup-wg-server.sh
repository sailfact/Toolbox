#!/bin/bash
# This script sets up a WireGuard server on Ubuntu Server.
# Usage: ./setup-wg-server.sh [IP_ADDRESS] [PORT] [DNS_SERVER]

install_if_missing() {
    local pkg="$1"
    if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
        echo "[OK] $pkg is already installed"
    else
        echo "[--] $pkg not found — installing..."
        apt-get install -y "$pkg"
        echo "[OK] $pkg installed successfully"
    fi
}

set -euo pipefail

ipaddr=${1:-10.0.0.1}
port=${2:-51820}
dnsserver=${3:-1.1.1.1} 

# Packages required for WireGuard setup
PACKAGES=(wireguard qrencode)



# Ensure running as root
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root (use sudo)" >&2
    exit 1
fi

echo "Updating package index..."
apt-get update -qq

for pkg in "${PACKAGES[@]}"; do
    install_if_missing "$pkg"
done

echo ""
echo "All packages ready."