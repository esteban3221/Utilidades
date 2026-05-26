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
# Validar que el dispositivo realmente exista y sea hardware (block device)
if [ ! -b "$TARGET_DEV" ]; then
  echo -e "${ROJO}[!] Error: $TARGET_DEV no existe o no es un dispositivo físico. ¿Se desconectó?${NC}"
  exit 1
fi

if [[ "$TARGET_DEV" == *"mmcblk"* ]]; then
    PART_BOOT="${TARGET_DEV}p1"
    PART_ROOT="${TARGET_DEV}p2"
else
    PART_BOOT="${TARGET_DEV}1"
    PART_ROOT="${TARGET_DEV}2"
fi

echo -e "\n${AZUL}[*] Desmontando particiones existentes...${NC}"
umount ${TARGET_DEV}* 2>/dev/null || true

echo -e "${AZUL}[*] Rediseñando tabla de particiones (DOS/MBR) en ${TARGET_DEV}...${NC}"
dd if=/dev/zero of=${TARGET_DEV} bs=1M count=10 status=none

sfdisk ${TARGET_DEV} << EOF
label: dos
device: ${TARGET_DEV}
unit: sectors

${TARGET_DEV}1 : start=2048, size=1024000, type=c
${TARGET_DEV}2 : start=1026048, type=83
EOF

partprobe ${TARGET_DEV}
sleep 2

echo -e "\n${AZUL}[*] Formateando particiones...${NC}"
mkfs.vfat -F 32 "$PART_BOOT"
mkfs.ext4 -F "$PART_ROOT"

# DIRECTORIOS DE MONTAJE SEPARADOS PARA EVITAR EL DESBORDAMIENTO
MOUNT_DIR=$(mktemp -d /tmp/arch_rpi4_XXXXXX)
mkdir -p "$MOUNT_DIR/root"
mkdir -p "$MOUNT_DIR/boot"

echo -e "${AZUL}[*] Montando partición ROOT temporalmente...${NC}"
mount "$PART_ROOT" "$MOUNT_DIR/root"

TARBALL="ArchLinuxARM-rpi-aarch64-latest.tar.gz"
cd "$MOUNT_DIR"

if [ ! -f "/tmp/$TARBALL" ]; then
    echo -e "${AZUL}[*] Descargando tarball oficial...${NC}"
    wget -O "/tmp/$TARBALL" "http://os.archlinuxarm.org/os/$TARBALL"
fi

echo -e "${AZUL}[*] Extrayendo el sistema completo en ROOT (EXT4)...${NC}"
if command -v bsdtar &> /dev/null; then
    bsdtar -xpf "/tmp/$TARBALL" -C "$MOUNT_DIR/root"
else
    tar -xpf "/tmp/$TARBALL" -C "$MOUNT_DIR/root"
fi

# AQUÍ ESTÁ EL TRUCO CORRECTO:
# Ahora que todo se extrajo en la partición grande, movemos el contenido de boot a su lugar real
echo -e "${AZUL}[*] Montando partición BOOT (FAT32) para transferir archivos de arranque...${NC}"
mount "$PART_BOOT" "$MOUNT_DIR/boot"

echo -e "${AZUL}[*] Desplazando archivos de arranque específicos a la partición BOOT...${NC}"
# Movemos los archivos generados en root/boot hacia el punto de montaje real de la partición FAT32
mv "$MOUNT_DIR/root/boot/"* "$MOUNT_DIR/boot/" || true

echo -e "${AZUL}[*] Sincronizando datos en el disco (sync)...${NC}"
sync

echo -e "${AZUL}[*] Desmontando limpiamente las unidades...${NC}"
umount "$MOUNT_DIR/boot"
umount "$MOUNT_DIR/root"
rm -rf "$MOUNT_DIR"

echo -e "\n${VERDE}[✓] ¡Proceso completado con éxito absoluto para RPi4!${NC}"
