#!/usr/bin/env bash

# Salir inmediatamente si un comando falla
set -e

# Colores para la terminal
VERDE='\033[0;32m'
ROJO='\033[0;31m'
AZUL='\033[0;34m'
NC='\033[0m' # Sin color

echo -e "${AZUL}====================================================${NC}"
echo -e "${AZUL}  Instalador Automatizado de Arch Linux ARM - RPi4  ${NC}"
echo -e "${AZUL}====================================================${NC}"

# 1. Validación de argumentos y permisos
if [ "$EUID" -ne 0 ]; then
  echo -e "${ROJO}[!] Este script debe ejecutarse como root (sudo).${NC}"
  exit 1
fi

if [ -z "$1" ]; then
  echo -e "${ROJO}[!] Error: Debes especificar el dispositivo de la tarjeta SD.${NC}"
  echo -e "Uso: sudo $0 /dev/sdX  o  sudo $0 /dev/mmcblkX"
  echo -e "\nDispositivos de almacenamiento disponibles actualmente:"
  lsblk -d -n -o NAME,SIZE,MODEL
  exit 1
fi

TARGET_DEV="$1"

# Confirmación de seguridad destructiva
echo -e "${ROJO}¡ADVERTENCIA! Se van a borrar TODOS los datos en: ${TARGET_DEV}${NC}"
read -p "¿Estás absolutamente seguro de que deseas continuar? (s/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[sS]$ ]]; then
    echo -e "${AZUL}Operación cancelada.${NC}"
    exit 0
fi

# Detectar el esquema de nombres de particiones (sdX1 vs mmcblkXp1)
if [[ "$TARGET_DEV" == *"mmcblk"* ]]; then
    PART_BOOT="${TARGET_DEV}p1"
    PART_ROOT="${TARGET_DEV}p2"
else
    PART_BOOT="${TARGET_DEV}1"
    PART_ROOT="${TARGET_DEV}2"
fi

# 2. Desmontar particiones existentes por si acaso
echo -e "\n${AZUL}[*] Desmontando particiones existentes...${NC}"
umount ${TARGET_DEV}* 2>/dev/null || true

# 3. Particionado del disco (MBR / dos)
echo -e "${AZUL}[*] Creando tabla de particiones en ${TARGET_DEV}...${NC}"
# El comando fdisk automatizado mediante un "Here Document"
sed -e 's/\s\([\+0-9a-zA-Z]*\).*/\1/' << EOF | fdisk ${TARGET_DEV}
  o # Crear una nueva tabla de particiones DOS (MBR)
  n # Nueva partición (Boot)
  p # Primaria
  1 # Número de partición 1
    # Sector inicial por defecto
  +200M # Tamaño de la partición de arranque
  t # Cambiar tipo de partición
  c # Tipo 'c' es W95 FAT32 (LBA)
  n # Nueva partición (Root)
  p # Primaria
  2 # Número de partición 2
    # Sector inicial por defecto
    # Utilizar el resto del espacio disponible
  w # Guardar cambios y salir
EOF

# Informar al kernel de los cambios de partición
partprobe ${TARGET_DEV}
sleep 2

# 4. Formateo de las particiones
echo -e "\n${AZUL}[*] Formateando particiones...${NC}"
mkfs.vfat -F 32 "$PART_BOOT"
mkfs.ext4 -F "$PART_ROOT"

# 5. Creación de directorios temporales de montaje
MOUNT_DIR=$(mktemp -d /tmp/arch_rpi4_XXXXXX)
mkdir -p "$MOUNT_DIR/root"

echo -e "${AZUL}[*] Montando particiones en el directorio temporal...${NC}"
mount "$PART_ROOT" "$MOUNT_DIR/root"
mkdir -p "$MOUNT_DIR/root/boot"
mount "$PART_BOOT" "$MOUNT_DIR/root/boot"

# 6. Descarga e instalación del sistema base
TARBALL="ArchLinuxARM-rpi-aarch64-latest.tar.gz"

cd "$MOUNT_DIR"
if [ ! -f "/tmp/$TARBALL" ]; then
    echo -e "${AZUL}[*] Descargando el tarball oficial de Arch Linux ARM (64-bit)...${NC}"
    wget -O "/tmp/$TARBALL" "http://os.archlinuxarm.org/os/$TARBALL"
else
    echo -e "${VERDE}[+] Se encontró una copia previa de $TARBALL en /tmp. Usando esa.${NC}"
fi

echo -e "${AZUL}[*] Extrayendo el sistema de archivos (esto puede tardar unos minutos)...${NC}"
# Se usa bsdtar porque preserva los atributos extendidos (necesario para Arch ARM)
# Si no tienes bsdtar, el script intentará usar tar normal (pero se recomienda bsdtar)
if command -v bsdtar &> /dev/null; then
    bsdtar -xpf "/tmp/$TARBALL" -C "$MOUNT_DIR/root"
else
    echo -e "${ROJO}[!] bsdtar no encontrado. Usando tar normal (¡Atención: se recomiendan ACLs!).${NC}"
    tar -xpf "/tmp/$TARBALL" -C "$MOUNT_DIR/root"
fi

# Sincronizar datos a la tarjeta SD
echo -e "${AZUL}[*] Sincronizando datos pendientes en la tarjeta (sync)...${NC}"
sync

# 7. Limpieza y Desmontaje
echo -e "${AZUL}[*] Desmontando y limpiando...${NC}"
umount "$MOUNT_DIR/root/boot"
umount "$MOUNT_DIR/root"
rm -rf "$MOUNT_DIR"

echo -e "\n${VERDE}[✓] ¡Proceso completado con éxito!${NC}"
echo -e "Ya puedes retirar la tarjeta SD y colocarla en tu Raspberry Pi 4."
echo -e "Credenciales por defecto:"
echo -e "  - Usuario: ${AZUL}alarm${NC} (Contraseña: ${AZUL}alarm${NC})"
echo -e "  - Root:    ${AZUL}root${NC}  (Contraseña: ${AZUL}root${NC})"
