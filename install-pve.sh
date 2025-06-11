#!/bin/bash
set -euo pipefail

GITHUB_REPO="https://github.com/lixiaoliu666/pve-anti-detection"
GITHUB_API="https://api.github.com/repos/lixiaoliu666/pve-anti-detection/releases/latest"

usage() {
    cat <<EOF
Usage: $0 [<pve-qemu-kvm_deb> <pve-edk2-firmware_deb>]
       $0 --restore

Auto: Télécharge la version la plus récente ou recommandée du dépôt GitHub si les paquets ne sont pas trouvés localement.
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

get_latest_urls() {
    # Récupère la liste des assets de la dernière release depuis l'API GitHub
    curl -s "$GITHUB_API" | grep "browser_download_url" | cut -d '"' -f 4
}

if [ $# -eq 2 ]; then
    QEMU_DEB="$1"
    OVMF_DEB="$2"
else
    # Recherche locale
    QEMU_DEB=$(ls -t pve-qemu-kvm_*.deb 2>/dev/null | head -n1 || true)
    OVMF_DEB=$(ls -t pve-edk2-firmware-ovmf_*.deb 2>/dev/null | sort -Vr | head -n1 || true)

    # Si absent, télécharge la dernière version
    if [ -z "$QEMU_DEB" ] || [ -z "$OVMF_DEB" ]; then
        echo "Paquets non trouvés localement. Téléchargement depuis GitHub..."
        # Liste toutes les URLs
        URLS=$(get_latest_urls)

        # QEMU
        QEMU_URL=$(echo "$URLS" | grep -E "pve-qemu-kvm_.*\.deb" | head -n1)
        QEMU_DEB="${QEMU_URL##*/}"
        [ -f "$QEMU_DEB" ] || curl -L -o "$QEMU_DEB" "$QEMU_URL"

        # OVMF - Prend la version avec le numéro -x le plus élevé
        OVMF_URL=$(echo "$URLS" | grep -E "pve-edk2-firmware-ovmf_4.*\.deb" | sort -Vr | head -n1)
        OVMF_DEB="${OVMF_URL##*/}"
        [ -f "$OVMF_DEB" ] || curl -L -o "$OVMF_DEB" "$OVMF_URL"

        echo "Utilisation de : $QEMU_DEB et $OVMF_DEB"
    fi
fi

echo "Version courante pve-qemu-kvm :"
dpkg -l | grep pve-qemu-kvm || true

# Vérifie la version installée, upgrade si nécessaire
installed_ver=$(dpkg-query -W -f='${Version}' pve-qemu-kvm 2>/dev/null || true)
if ! echo "$installed_ver" | grep -q '^9\.'; then
    echo "Mise à jour du système et installation de pve-qemu-kvm si besoin..."
    apt update
    apt install -y pve-qemu-kvm
fi

# Installation
echo "Installation de $QEMU_DEB et $OVMF_DEB..."
dpkg -i "$QEMU_DEB"
dpkg -i "$OVMF_DEB"
apt-get -f install -y

cat <<MSG
✅ Installation terminée. Redémarrez l’hôte Proxmox pour appliquer les modifications.
MSG
