#!/usr/bin/env bash

set -e

VERDE='\033[0;32m'
ROJO='\033[0;31m'
AZUL='\033[0;34m'
NC='\033[0m'

echo -e "${AZUL}====================================================${NC}"
echo -e "${AZUL}  Instalador Automatizado de Arch Linux ARM - RPi4  ${NC}"
echo -e "${AZUL}====================================================${NC}"

if [ "$EUID" -ne 0 ]; then
  echo -e "${ROJO}[!] Este script debe ejecutarse como root (sudo).${NC}"
  exit 1
fi

if [ -z "$1" ]; then
  echo -e "${ROJO}[!] Error: Debes especificar el dispositivo de la tarjeta SD.${NC}"
  echo -e "Uso: sudo $0 /dev/sdX"
  exit 1
fi

TARGET_DEV="$1"

# Identificar particiones de forma robusta
if [[ "$TARGET_DEV" == *"mmcblk"* ]]; then
    PART_BOOT="${TARGET_DEV}p1"
    PART_ROOT="${TARGET_DEV}p2"
else
    PART_BOOT="${TARGET_DEV}1"
    PART_ROOT="${TARGET_DEV}2"
fi

# Desmontar cualquier montaje previo
echo -e "\n${AZUL}[*] Desmontando particiones existentes...${NC}"
umount ${TARGET_DEV}* 2>/dev/null || true

echo -e "${AZUL}[*] Rediseñando tabla de particiones (DOS/MBR) en ${TARGET_DEV}...${NC}"
dd if=/dev/zero of=${TARGET_DEV} bs=1M count=10 status=none

# Crear particiones: Boot (200MB, Tipo de id 'c' para FAT32 LBA) y Root (Resto del disco)
sfdisk ${TARGET_DEV} << EOF
label: dos
device: ${TARGET_DEV}
unit: sectors

${TARGET_DEV}1 : start=2048, size=409600, type=c
${TARGET_DEV}2 : start=411648, type=83
EOF

# Notificar al Kernel
partprobe ${TARGET_DEV}
sleep 2

# Formatear
echo -e "\n${AZUL}[*] Formateando particiones...${NC}"
mkfs.vfat -F 32 "$PART_BOOT"
mkfs.ext4 -F "$PART_ROOT"

# Montaje
MOUNT_DIR=$(mktemp -d /tmp/arch_rpi4_XXXXXX)
mkdir -p "$MOUNT_DIR/root"

mount "$PART_ROOT" "$MOUNT_DIR/root"
mkdir -p "$MOUNT_DIR/root/boot"
mount "$PART_BOOT" "$MOUNT_DIR/root/boot"

# Descarga y Extracción
TARBALL="ArchLinuxARM-rpi-aarch64-latest.tar.gz"
cd "$MOUNT_DIR"

if [ ! -f "/tmp/$TARBALL" ]; then
    echo -e "${AZUL}[*] Descargando tarball oficial...${NC}"
    wget -O "/tmp/$TARBALL" "http://os.archlinuxarm.org/os/$TARBALL"
fi

echo -e "${AZUL}[*] Extrayendo sistema de archivos en la SD...${NC}"

if command -v bsdtar &> /dev/null; then
    bsdtar -xpf "/tmp/$TARBALL" -C "$MOUNT_DIR/root"
else
    tar -xpf "/tmp/$TARBALL" -C "$MOUNT_DIR/root"
fi

echo -e "${AZUL}[*] Sincronizando datos (sync)...${NC}"
sync

# Limpieza
echo -e "${AZUL}[*] Desmontando...${NC}"
umount "$MOUNT_DIR/root/boot"
umount "$MOUNT_DIR/root"
rm -rf "$MOUNT_DIR"

echo -e "\n${VERDE}[✓] ¡Proceso completado con éxito para /dev/sda!${NC}"
