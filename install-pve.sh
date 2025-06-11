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
EOF
}

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

if [ $# -eq 2 ]; then
    QEMU_DEB="$1"
    OVMF_DEB="$2"
else
    # Try to locate packages in the current directory
    QEMU_DEB=$(ls -t pve-qemu-kvm_*.deb 2>/dev/null | head -n1 || true)
    OVMF_DEB=$(ls -t pve-edk2-firmware-ovmf_*.deb 2>/dev/null | head -n1 || true)
    if [ -z "$QEMU_DEB" ] || [ -z "$OVMF_DEB" ]; then
        echo "Error: package arguments missing and no matching files found." >&2
        usage
        exit 1
    fi
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
