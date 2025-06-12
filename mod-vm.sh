#!/bin/bash
set -euo pipefail

VMID=100

MAC_ADDR="D8:FC:93:4A:7B:01"
BRIDGE="vmbr0"
GPU_PCI="0000:01:00.0"
GPU_AUDIO="0000:01:00.1"
NVME_PCI="0000:02:00.0"

EFIDISK_PATH="local-lvm:vm-${VMID}-disk-0,efitype=4m,size=4M,pre-enrolled-keys=1"
ISO_PATH="local:iso/Win10_2004_French_x64.iso"

PREVIEW_FILE="vm${VMID}-preview.txt"
VM_CONF_PATH="/etc/pve/qemu-server/${VMID}.conf"

# Get host SMBIOS info
get_smbios_value() {
    local type="$1"
    local label="$2"
    dmidecode -t "$type" | grep "$label:" | head -n1 | cut -d: -f2- | sed 's/^[ \t]*//'
}
EXISTING_UUID=$(grep '^smbios1:' "$VM_CONF_PATH" 2>/dev/null | grep -o 'uuid=[^, ]*' | cut -d= -f2 || true)
if [[ -z "$EXISTING_UUID" ]]; then
    if [[ -r /proc/sys/kernel/random/uuid ]]; then
        SMBIOS_UUID=$(cat /proc/sys/kernel/random/uuid)
    else
        SMBIOS_UUID="$(date +%s)-$$-$RANDOM"
    fi
else
    SMBIOS_UUID="$EXISTING_UUID"
fi

SYS_MANUFACTURER=$(get_smbios_value 1 "Manufacturer")
SYS_PRODUCT=$(get_smbios_value 1 "Product Name")
SYS_VERSION=$(get_smbios_value 1 "Version")
SYS_SERIAL=$(get_smbios_value 1 "Serial Number")
SYS_SKU=$(get_smbios_value 1 "SKU Number")
SYS_FAMILY=$(get_smbios_value 1 "Family")

cat <<EOF | tee "$PREVIEW_FILE"
====== Prévisualisation modification VM $VMID ======

[SMBIOS]
  UUID         : $SMBIOS_UUID
  Constructeur : $SYS_MANUFACTURER
  Produit      : $SYS_PRODUCT
  Version      : $SYS_VERSION
  Numéro série : $SYS_SERIAL
  SKU          : $SYS_SKU
  Famille      : $SYS_FAMILY

[CARTE RÉSEAU]
  net0: e1000=${MAC_ADDR},bridge=${BRIDGE},firewall=1

[QEMU ARGS ANTI-DETECTION]
  -cpu host,hypervisor=off,vmware-cpuid-freq=false,enforce=false,host-phys-bits=true -smbios type=0 -smbios type=9 -smbios type=8 -smbios type=8

[GPU/NVMe PASSTHROUGH]
  GPU      : $GPU_PCI
  GPU Audio: $GPU_AUDIO
  NVMe     : $NVME_PCI

Le détail a été enregistré dans : $PREVIEW_FILE

=====================================================
EOF

read -p "Valider ces valeurs pour la VM $VMID ? (oui/non) : " CONFIRM
if [[ "$CONFIRM" =~ ^[Oo][Uu][Ii]$ ]]; then
    SMBIOS1_ARGS="uuid=${SMBIOS_UUID},manufacturer=${SYS_MANUFACTURER},product=${SYS_PRODUCT},version=${SYS_VERSION},serial=${SYS_SERIAL},sku=${SYS_SKU},family=${SYS_FAMILY}"

    qm set $VMID --smbios1 "$SMBIOS1_ARGS"
    # ... autres qm set comme avant
    echo -e "\n✅ Champs SMBIOS appliqués à la VM $VMID"
else
    echo "Aucune modification appliquée."
fi
