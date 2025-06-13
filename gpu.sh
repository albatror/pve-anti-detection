#!/bin/bash
# GPU Passthrough Automation Script - version améliorée (Proxmox/KVM/Ubuntu/Debian)
# Basé sur le guide détaillé fourni

set -e

# ---- FONCTIONS UTILES ----
print_ok()   { echo -e "\033[1;32m[OK]\033[0m $1"; }
print_info() { echo -e "\033[1;33m[*]\033[0m $1"; }
print_err()  { echo -e "\033[1;31m[ERR]\033[0m $1"; }

# ---- ETAPE 1 : GRUB ----
print_info "1. Edition des paramètres GRUB pour IOMMU et ACS override..."

GRUB_FILE="/etc/default/grub"
GRUB_TARGET='GRUB_CMDLINE_LINUX_DEFAULT='
GRUB_LINE='GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt pcie_acs_override=downstream,multifunction nofb nomodeset video=vesafb:off,efifb:off"'

if grep -q "$GRUB_LINE" "$GRUB_FILE"; then
    print_ok "Ligne GRUB déjà correcte."
else
    print_info "Modification de la ligne GRUB_CMDLINE_LINUX_DEFAULT..."
    sed -i "/^$GRUB_TARGET/c\\$GRUB_LINE" "$GRUB_FILE"
fi

# ---- ETAPE 2 : update-grub ----
print_info "2. Mise à jour de GRUB..."
update-grub
print_ok "GRUB mis à jour."

# ---- ETAPE 3 : modules VFIO ----
print_info "3. Ajout des modules VFIO au boot..."
MODULES_FILE="/etc/modules"
declare -a MODULES=(vfio vfio_iommu_type1 vfio_pci vfio_virqfd)

for mod in "${MODULES[@]}"; do
    if grep -q "^$mod" "$MODULES_FILE"; then
        print_ok "Module $mod déjà présent."
    else
        echo "$mod" >> "$MODULES_FILE"
        print_ok "Module $mod ajouté."
    fi
done

# ---- ETAPE 4 : IOMMU et MSR ----
print_info "4. Ajout des options IOMMU unsafe interrupts et ignore_msrs..."
IOMMU_FILE="/etc/modprobe.d/iommu_unsafe_interrupts.conf"
KVM_FILE="/etc/modprobe.d/kvm.conf"

if grep -q "options vfio_iommu_type1 allow_unsafe_interrupts=1" "$IOMMU_FILE" 2>/dev/null; then
    print_ok "Option unsafe_interrupts déjà présente."
else
    echo "options vfio_iommu_type1 allow_unsafe_interrupts=1" > "$IOMMU_FILE"
    print_ok "Option unsafe_interrupts ajoutée."
fi

if grep -q "options kvm ignore_msrs=1" "$KVM_FILE" 2>/dev/null; then
    print_ok "Option ignore_msrs déjà présente."
else
    echo "options kvm ignore_msrs=1" > "$KVM_FILE"
    print_ok "Option ignore_msrs ajoutée."
fi

# ---- ETAPE 5 : Blacklist drivers GPU ----
print_info "5. Blacklist des drivers GPU sur l'hôte..."
BLACKLIST_FILE="/etc/modprobe.d/blacklist.conf"
declare -a BLACKLIST=(radeon nouveau nvidia nvidiafb)

for drv in "${BLACKLIST[@]}"; do
    if grep -q "blacklist $drv" "$BLACKLIST_FILE" 2>/dev/null; then
        print_ok "Driver $drv déjà blacklisté."
    else
        echo "blacklist $drv" >> "$BLACKLIST_FILE"
        print_ok "Driver $drv blacklisté."
    fi
done

# ---- ETAPE 6 : Ajout GPU à VFIO ----
print_info "6. Configuration du GPU et audio dans vfio-pci..."

# Si déjà configuré, ne rien faire, sinon demander à l'utilisateur
VFIO_FILE="/etc/modprobe.d/vfio.conf"
if grep -q "options vfio-pci ids=" "$VFIO_FILE" 2>/dev/null; then
    print_ok "VFIO déjà configuré avec des PCI IDs."
else
    echo
    echo "Liste des GPU détectés sur le système :"
    lspci | grep -E "VGA|3D|Audio"
    echo
    read -p "Entrer le PCI ID principal du GPU (exemple: 01:00.0) : " GPU_ID
    read -p "Entrer le PCI ID AUDIO du GPU (exemple: 01:00.1) : " AUDIO_ID
    GPU_HEX=$(lspci -nns $GPU_ID | awk '{print $3}' | cut -d: -f2)
    AUDIO_HEX=$(lspci -nns $AUDIO_ID | awk '{print $3}' | cut -d: -f2)
    echo "options vfio-pci ids=$GPU_HEX,$AUDIO_HEX disable_vga=1" > "$VFIO_FILE"
    print_ok "Ajouté dans $VFIO_FILE : options vfio-pci ids=$GPU_HEX,$AUDIO_HEX disable_vga=1"
fi

# ---- ETAPE 7 : update-initramfs et reboot ----
print_info "7. Regénération de l'initramfs (pour prise en compte du passthrough)..."
update-initramfs -u
print_ok "initramfs régénéré."

echo
print_info "Tout est prêt. Redémarre le serveur pour finaliser le GPU passthrough !"
echo

exit 0
