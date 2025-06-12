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

get_smbios_value() {
    local type="$1"
    local label="$2"
    dmidecode -t "$type" | grep "$label:" | head -n1 | cut -d: -f2- | sed 's/^[ \t]*//'
}

random_serial()    { tr -dc 'A-Z0-9' </dev/urandom | head -c 12; }
random_version()   { echo "$((RANDOM % 3 + 1)).$((RANDOM % 10))"; }
random_manufacturer() { local arr=("Dell" "HP" "Lenovo" "ASUS" "Acer" "MSI" "Gigabyte" "Apple" "Fujitsu" "HPE" "Toshiba"); echo "${arr[$RANDOM % ${#arr[@]}]}"; }
random_product()   { local arr=("ThinkPad X1" "EliteBook 840" "MacBookPro15,2" "Inspiron 15" "VivoBook S14" "Omen 17" "Aspire 5" "Pavilion 14"); echo "${arr[$RANDOM % ${#arr[@]}]}"; }
random_family()    { local arr=("Server" "Desktop" "Workstation" "Laptop" "UltraBook" "Gaming" "Pro" "Business"); echo "${arr[$RANDOM % ${#arr[@]}]}"; }
random_type()      { echo "$((RANDOM % 16 + 1))"; } # chassis type

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

# SMBIOS type 1 (system)
SYS_MANUFACTURER=$(get_smbios_value 1 "Manufacturer")
SYS_PRODUCT=$(get_smbios_value 1 "Product Name")
SYS_VERSION=$(get_smbios_value 1 "Version")
SYS_SERIAL=$(get_smbios_value 1 "Serial Number")
SYS_SKU=$(get_smbios_value 1 "SKU Number")
SYS_FAMILY=$(get_smbios_value 1 "Family")

[[ -z "$SYS_MANUFACTURER" ]] && SYS_MANUFACTURER=$(random_manufacturer)
[[ -z "$SYS_PRODUCT" ]]      && SYS_PRODUCT=$(random_product)
[[ -z "$SYS_VERSION" ]]      && SYS_VERSION=$(random_version)
[[ -z "$SYS_SERIAL" ]]       && SYS_SERIAL=$(random_serial)
[[ -z "$SYS_SKU" ]]          && SYS_SKU=$(random_serial)
[[ -z "$SYS_FAMILY" ]]       && SYS_FAMILY=$(random_family)

# SMBIOS type 2 (baseboard)
BASE_MANUFACTURER=$(get_smbios_value 2 "Manufacturer")
BASE_PRODUCT=$(get_smbios_value 2 "Product Name")
BASE_VERSION=$(get_smbios_value 2 "Version")
BASE_SERIAL=$(get_smbios_value 2 "Serial Number")
BASE_ASSET=$(get_smbios_value 2 "Asset Tag")

[[ -z "$BASE_MANUFACTURER" ]] && BASE_MANUFACTURER=$(random_manufacturer)
[[ -z "$BASE_PRODUCT" ]]      && BASE_PRODUCT=$(random_product)
[[ -z "$BASE_VERSION" ]]      && BASE_VERSION=$(random_version)
[[ -z "$BASE_SERIAL" ]]       && BASE_SERIAL=$(random_serial)
[[ -z "$BASE_ASSET" ]]        && BASE_ASSET=$(random_serial)

# SMBIOS type 3 (chassis)
CHASSIS_MANUFACTURER=$(get_smbios_value 3 "Manufacturer")
CHASSIS_TYPE=$(get_smbios_value 3 "Type")
CHASSIS_VERSION=$(get_smbios_value 3 "Version")
CHASSIS_SERIAL=$(get_smbios_value 3 "Serial Number")
CHASSIS_ASSET=$(get_smbios_value 3 "Asset Tag")
CHASSIS_SKU=$(get_smbios_value 3 "SKU Number")

[[ -z "$CHASSIS_MANUFACTURER" ]] && CHASSIS_MANUFACTURER=$(random_manufacturer)
[[ -z "$CHASSIS_TYPE" ]]         && CHASSIS_TYPE=$(random_type)
[[ -z "$CHASSIS_VERSION" ]]      && CHASSIS_VERSION=$(random_version)
[[ -z "$CHASSIS_SERIAL" ]]       && CHASSIS_SERIAL=$(random_serial)
[[ -z "$CHASSIS_ASSET" ]]        && CHASSIS_ASSET=$(random_serial)
[[ -z "$CHASSIS_SKU" ]]          && CHASSIS_SKU=$(random_serial)

# Prévisualisation
cat <<EOF | tee "$PREVIEW_FILE"
====== Prévisualisation SMBIOS type 1 ======
  UUID         : $SMBIOS_UUID
  Manufacturer : $SYS_MANUFACTURER
  Product      : $SYS_PRODUCT
  Version      : $SYS_VERSION
  Serial       : $SYS_SERIAL
  SKU          : $SYS_SKU
  Family       : $SYS_FAMILY

====== Prévisualisation SMBIOS type 2 ======
  Manufacturer : $BASE_MANUFACTURER
  Product      : $BASE_PRODUCT
  Version      : $BASE_VERSION
  Serial       : $BASE_SERIAL
  Asset Tag    : $BASE_ASSET

====== Prévisualisation SMBIOS type 3 ======
  Manufacturer : $CHASSIS_MANUFACTURER
  Type         : $CHASSIS_TYPE
  Version      : $CHASSIS_VERSION
  Serial       : $CHASSIS_SERIAL
  Asset Tag    : $CHASSIS_ASSET
  SKU          : $CHASSIS_SKU
=====================================================
EOF

read -p "Valider ces valeurs pour la VM $VMID ? (oui/non) : " CONFIRM
if [[ "$CONFIRM" =~ ^[Oo][Uu][Ii]$ ]]; then
    SMBIOS1_ARGS="uuid=${SMBIOS_UUID},manufacturer=${SYS_MANUFACTURER},product=${SYS_PRODUCT},version=${SYS_VERSION},serial=${SYS_SERIAL},sku=${SYS_SKU},family=${SYS_FAMILY}"
    SMBIOS2_ARGS="manufacturer=${BASE_MANUFACTURER},product=${BASE_PRODUCT},version=${BASE_VERSION},serial=${BASE_SERIAL},asset=${BASE_ASSET}"
    SMBIOS3_ARGS="manufacturer=${CHASSIS_MANUFACTURER},type=${CHASSIS_TYPE},version=${CHASSIS_VERSION},serial=${CHASSIS_SERIAL},asset=${CHASSIS_ASSET},sku=${CHASSIS_SKU}"

    qm set $VMID --smbios1 "$SMBIOS1_ARGS"
    qm set $VMID --smbios2 "$SMBIOS2_ARGS"
    qm set $VMID --smbios3 "$SMBIOS3_ARGS"
    echo -e "\n✅ SMBIOS types 1, 2, 3 appliqués à la VM $VMID"
else
    echo "Aucune modification appliquée."
fi
