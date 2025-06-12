#!/bin/bash
set -euo pipefail

VMID=100

MAC_ADDR="D8:FC:93:4A:7B:01"
BRIDGE="vmbr0"

GPU_PCI="0000:01:00.0"
GPU_AUDIO="0000:01:00.1"
NVME_PCI="0000:02:00.0"

PREVIEW_FILE="vm${VMID}-preview.txt"

# Chemins disques à adapter à ton infra !
EFIDISK_PATH="local-lvm:vm-${VMID}-disk-0,efitype=4m,size=528K"
SATA0_PATH="local-lvm:vm-${VMID}-disk-1,size=128G,ssd=1"
ISO_PATH="local:iso/Win10_2004_French_x64.iso"

# Recherche UUID existant dans la config Proxmox
VM_CONF_PATH="/etc/pve/qemu-server/${VMID}.conf"
if [[ -f "$VM_CONF_PATH" ]]; then
    EXISTING_UUID=$(grep '^smbios1:' "$VM_CONF_PATH" | grep -o 'uuid=[^, ]*' | cut -d= -f2)
else
    EXISTING_UUID=""
fi

# Génération UUID POSIX only si besoin
if [[ -z "$EXISTING_UUID" ]]; then
    if [[ -r /proc/sys/kernel/random/uuid ]]; then
        SMBIOS_UUID=$(cat /proc/sys/kernel/random/uuid)
    else
        # fallback très simple (timestamp+PID+RANDOM, pas aussi universel, mais évite toute dépendance)
        SMBIOS_UUID="$(date +%s)-$$-$RANDOM"
    fi
else
    SMBIOS_UUID="$EXISTING_UUID"
fi

SMBIOS1_ARGS="uuid=${SMBIOS_UUID}"

QEMU_ARGS="-cpu host,hypervisor=off,vmware-cpuid-freq=false,enforce=false,host-phys-bits=true -smbios type=0 -smbios type=9 -smbios type=8 -smbios type=8"

cat <<EOF | tee "$PREVIEW_FILE"
====== Prévisualisation modification VM $VMID (style README adapté) ======

[CARTE RÉSEAU]
  net0: e1000=${MAC_ADDR},bridge=${BRIDGE},firewall=1

[QEMU ARGS ANTI-DETECTION]
  args: $QEMU_ARGS

[AUTRES OPTIONS]
  balloon: 0
  bios: ovmf
  boot: order=ide2;sata0;net0
  cores: 24
  cpu: host
  efidisk0: $EFIDISK_PATH
  ide2: $ISO_PATH,media=cdrom
  localtime: 1
  memory: 24576
  numa: 0
  ostype: l26
  sata0: $SATA0_PATH
  scsihw: virtio-scsi-single
  smbios1: $SMBIOS1_ARGS
  sockets: 1

[GPU PASSTHROUGH]
  GPU      : $GPU_PCI
  GPU Audio: $GPU_AUDIO
  NVMe     : $NVME_PCI

Le détail a été enregistré dans : $PREVIEW_FILE

=====================================================
EOF

echo
read -p "Souhaitez-vous appliquer ces modifications à la VM $VMID ? (oui/non) : " CONFIRM
if [[ "$CONFIRM" =~ ^[Oo][Uu][Ii]$ ]]; then
    echo "Application des modifications..."

    qm set $VMID --args "$QEMU_ARGS"
    qm set $VMID --balloon 0
    qm set $VMID --bios ovmf
    qm set $VMID --boot "order=ide2;sata0;net0"
    qm set $VMID --cores 24
    qm set $VMID --cpu host
    qm set $VMID --efidisk0 "$EFIDISK_PATH"
    qm set $VMID --ide2 "$ISO_PATH,media=cdrom"
    qm set $VMID --localtime 1
    qm set $VMID --memory 24576
    qm set $VMID --numa 0
    qm set $VMID --ostype l26
    qm set $VMID --sata0 "$SATA0_PATH"
    qm set $VMID --scsihw virtio-scsi-single
    qm set $VMID --smbios1 "$SMBIOS1_ARGS"
    qm set $VMID --sockets 1
    qm set $VMID --net0 "e1000=${MAC_ADDR},bridge=${BRIDGE},firewall=1"

    qm set $VMID --hostpci0 "$GPU_PCI,pcie=1,rombar=0,multifunction=on"
    qm set $VMID --hostpci1 "$GPU_AUDIO,pcie=1"
    qm set $VMID --hostpci2 "$NVME_PCI,pcie=1"

    echo -e "\n=== VM $VMID CONFIGURATION SUMMARY ==="
    qm config $VMID
    echo -e "\n✅ Modifications appliquées à la VM $VMID"
else
    echo "Aucune modification appliquée."
fi
