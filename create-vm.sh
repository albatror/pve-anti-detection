#!/bin/bash
set -euo pipefail

# === CONFIGURATION À PERSONNALISER ===
VMID=200
VMNAME="win11-anti-detect"
STORAGE="local-lvm"
ISO_STORAGE="local"
ISO_NAME="Win11_23H2_French_x64.iso"
CORES=8
SOCKETS=1
RAM_MB=8192
DISK_SIZE=60G
BRIDGE="vmbr0"
TPM_STORAGE="local-lvm"

# PCI IDs for passthrough (change according to your system)
GPU_PCI="0000:01:00.0"      # GPU principal (RTX 4070 ex)
GPU_AUDIO="0000:01:00.1"    # Audio GPU (habituellement)
NVME_PCI="0000:04:00.0"     # Ton NVMe

# Génère une vraie MAC Intel (OUI officiel)
if [ -z "${MAC_ADDR:-}" ]; then
    OUI_HEX="00:1A:2B"
    MAC_ADDR=$(printf "$OUI_HEX:%02X:%02X:%02X" $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)))
fi

# === FONCTIONS POUR EXTRAIRE LES INFOS SMBIOS HOST ===
get_smbios_value() {
    local type="$1"
    local label="$2"
    sudo dmidecode -t "$type" | grep "$label:" | head -n1 | cut -d: -f2- | sed 's/^[ \t]*//'
}

# --- SMBIOS TYPE 1: SYSTEM ---
SYS_MANUFACTURER=$(get_smbios_value 1 "Manufacturer")
SYS_PRODUCT=$(get_smbios_value 1 "Product Name")
SYS_VERSION=$(get_smbios_value 1 "Version")
SYS_SKU=$(get_smbios_value 1 "SKU Number")
SYS_FAMILY=$(get_smbios_value 1 "Family")
SYS_SERIAL=$(tr -dc 'A-Z0-9' </dev/urandom | head -c10)
SYS_UUID=$(uuidgen)

SMBIOS1_ARGS="manufacturer=${SYS_MANUFACTURER},product=${SYS_PRODUCT},version=${SYS_VERSION},serial=${SYS_SERIAL},uuid=${SYS_UUID}"
[ -n "$SYS_SKU" ] && SMBIOS1_ARGS+=",sku=${SYS_SKU}"
[ -n "$SYS_FAMILY" ] && SMBIOS1_ARGS+=",family=${SYS_FAMILY}"

# --- SMBIOS TYPE 2: BASEBOARD ---
BASE_MANUFACTURER=$(get_smbios_value 2 "Manufacturer")
BASE_PRODUCT=$(get_smbios_value 2 "Product Name")
BASE_VERSION=$(get_smbios_value 2 "Version")
BASE_SERIAL=$(tr -dc 'A-Z0-9' </dev/urandom | head -c10)
BASE_ASSET=$(get_smbios_value 2 "Asset Tag")

SMBIOS2_ARGS="manufacturer=${BASE_MANUFACTURER},product=${BASE_PRODUCT},version=${BASE_VERSION},serial=${BASE_SERIAL}"
[ -n "$BASE_ASSET" ] && SMBIOS2_ARGS+=",asset=${BASE_ASSET}"

# --- SMBIOS TYPE 3: CHASSIS ---
CHASSIS_MANUFACTURER=$(get_smbios_value 3 "Manufacturer")
CHASSIS_TYPE=$(get_smbios_value 3 "Type")
CHASSIS_VERSION=$(get_smbios_value 3 "Version")
CHASSIS_SERIAL=$(tr -dc 'A-Z0-9' </dev/urandom | head -c10)
CHASSIS_ASSET=$(get_smbios_value 3 "Asset Tag")
CHASSIS_SKU=$(get_smbios_value 3 "SKU Number")

SMBIOS3_ARGS="manufacturer=${CHASSIS_MANUFACTURER},type=${CHASSIS_TYPE},version=${CHASSIS_VERSION},serial=${CHASSIS_SERIAL}"
[ -n "$CHASSIS_ASSET" ] && SMBIOS3_ARGS+=",asset=${CHASSIS_ASSET}"
[ -n "$CHASSIS_SKU" ] && SMBIOS3_ARGS+=",sku=${CHASSIS_SKU}"

# === CRÉATION DE LA VM ===
echo "Creating VM $VMID ($VMNAME)..."
qm create $VMID \
  --name "$VMNAME" \
  --memory $RAM_MB \
  --cores $CORES \
  --sockets $SOCKETS \
  --net0 virtio,bridge=$BRIDGE,macaddr=$MAC_ADDR \
  --scsihw virtio-scsi-pci \
  --ostype win11 \
  --machine q35 \
  --bios ovmf \
  --efidisk0 $STORAGE:0,format=qcow2,efitype=4m,pre-enrolled-keys=0 \
  --tpmstate0 $TPM_STORAGE:0,version=v2.0 \
  --scsi0 $STORAGE:0,format=qcow2,size=$DISK_SIZE \
  --boot order=scsi0;ide2;net0 \
  --cdrom $ISO_STORAGE:iso/$ISO_NAME \
  --vga std \
  --agent enabled=1

# === PASSTHROUGH GPU + NVMe ===
echo "Adding GPU and NVMe passthrough..."
qm set $VMID --hostpci0 "$GPU_PCI,pcie=1,rombar=0,multifunction=on"
qm set $VMID --hostpci1 "$GPU_AUDIO,pcie=1"
qm set $VMID --hostpci2 "$NVME_PCI,pcie=1"

# === QEMU ARGS ANTI-DETECTION ===
echo "Applying advanced anti-detection QEMU arguments..."
qm set $VMID \
  --cpu host,hidden=1,flags=+aes,+vmx \
  --args "-device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    -machine vmport=off \
    -global kvm-pit.lost_tick_policy=discard \
    -no-hpet \
    -rtc base=localtime,driftfix=slew \
    -device usb-ehci,id=ehci \
    -device usb-tablet,bus=ehci.0 \
    -overcommit mem-lock=off \
    -msg timestamp=on \
    -device ich9-intel-hda -device hda-output"

# === SMBIOS HOST ALIGN (1, 2, 3) ===
echo "Setting SMBIOS (host-aligned, serials random)..."
qm set $VMID --smbios1 "$SMBIOS1_ARGS"
qm set $VMID --smbios2 "$SMBIOS2_ARGS"
qm set $VMID --smbios3 "$SMBIOS3_ARGS"

# === AUDIT FINAL ===
echo -e "\n=== VM $VMID CONFIGURATION SUMMARY ==="
qm config $VMID

echo -e "\n✅ VM $VMID created and fully configured with:"
echo "   - GPU ($GPU_PCI), NVMe ($NVME_PCI) passthrough"
echo "   - SMBIOS 1/2/3 = aligné host (sauf serials/uuid random)"
echo -e "➡️  Start with: qm start $VMID\n"
