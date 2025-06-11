#!/bin/bash
# Automated installation script for PVE anti-detection packages
# Follows the steps from README.en.MD

set -euo pipefail

usage() {
    cat <<EOF
Usage: $0 [<pve-qemu-kvm_deb> <pve-edk2-firmware_deb>]
       $0 --restore

If no package arguments are provided, the script searches the current
directory for the latest \*.deb files matching pve-qemu-kvm_*.deb and
pve-edk2-firmware-ovmf_*.deb.
If not found, downloads latest from https://github.com/lixiaoliu666/pve-anti-detection/releases
EOF
}

GITHUB_REPO="https://github.com/lixiaoliu666/pve-anti-detection"

if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root." >&2
    exit 1
fi

if [ "${1:-}" = "--restore" ]; then
    echo "Restoring official packages..."
    apt reinstall -y pve-qemu-kvm
    apt reinstall -y pve-edk2-firmware-ovmf
    echo "Restore complete. Reboot recommended."
    exit 0
fi

find_or_download_deb() {
    local pattern="$1"
    local filename
    filename=$(ls -t $pattern 2>/dev/null | head -n1 || true)
    if [ -z "$filename" ]; then
        echo "Not found: $pattern. Trying to download from GitHub..."
        # Get latest release download URL for .deb
        url=$(curl -sL "${GITHUB_REPO}/releases/latest" \
            | grep -oP "href=\K\"[^\"]*${pattern/.deb/}[^\"]+\.deb\"" \
            | head -n1 | tr -d '"')
        if [ -z "$url" ]; then
            echo "Cannot find $pattern on GitHub releases." >&2
            exit 1
        fi
        url="https://github.com${url}"
        fname="${url##*/}"
        echo "Downloading $fname from $url..."
        curl -L -o "$fname" "$url"
        filename="$fname"
    fi
    echo "$filename"
}

if [ $# -eq 2 ]; then
    QEMU_DEB="$1"
    OVMF_DEB="$2"
else
    QEMU_DEB=$(find_or_download_deb "pve-qemu-kvm_*.deb")
    OVMF_DEB=$(find_or_download_deb "pve-edk2-firmware-ovmf_*.deb")
    echo "Using packages: $QEMU_DEB and $OVMF_DEB"
fi

# Display currently installed qemu package
echo "Current pve-qemu-kvm version:"
dpkg -l | grep pve-qemu-kvm || true

# Check whether we have version 9.x installed
installed_ver=$(dpkg-query -W -f='${Version}' pve-qemu-kvm 2>/dev/null || true)
if ! echo "$installed_ver" | grep -q '^9\.'; then
    echo "Updating system and installing latest pve-qemu-kvm..."
    apt update
    apt install -y pve-qemu-kvm
fi

# Install the anti-detection packages
echo "Installing $QEMU_DEB and $OVMF_DEB..."
dpkg -i "$QEMU_DEB"
dpkg -i "$OVMF_DEB"
apt-get -f install -y >/dev/null

cat <<MSG
Installation finished. Please reboot the host to apply changes.
MSG
