#!/bin/bash
set -euo pipefail

#==============================================================================
# Ubuntu 25.10 Direct SSD Installation Script
# Installs Ubuntu directly to SSD (not bootable USB, but actual installation)
# Target: Samsung SSD 840 EVO 1TB at /dev/sdi
#==============================================================================

# Configuration
UBUNTU_VERSION="25.10"
UBUNTU_ISO_URL="https://releases.ubuntu.com/${UBUNTU_VERSION}/ubuntu-${UBUNTU_VERSION}-desktop-amd64.iso"
ISO_FILE="$HOME/Downloads/ubuntu-${UBUNTU_VERSION}-desktop-amd64.iso"
TARGET_DEVICE="${1:-/dev/sdi}"
MOUNT_POINT="/mnt/ubuntu-install"
EFI_SIZE="512M"
ROOT_SIZE="100%"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
info() { echo -e "${BLUE}[INFO]${NC} $*"; }

# Check root
[[ $EUID -eq 0 ]] || error "This script must be run as root (sudo)"

# Validate device
[[ -b "$TARGET_DEVICE" ]] || error "Device $TARGET_DEVICE not found"

echo ""
echo "============================================================"
echo "  Ubuntu ${UBUNTU_VERSION} Direct SSD Installation"
echo "============================================================"
echo ""
echo "  Target Device: $TARGET_DEVICE"
lsblk "$TARGET_DEVICE" 2>/dev/null || true
echo ""
echo "  ⚠️  WARNING: This will ERASE ALL DATA on $TARGET_DEVICE"
echo ""
read -p "  Type 'YES' to confirm: " confirm
[[ "$confirm" == "YES" ]] || error "Aborted by user"

# Step 1: Download Ubuntu ISO if needed
log "📥 Checking for Ubuntu ${UBUNTU_VERSION} ISO..."
mkdir -p "$(dirname "$ISO_FILE")"

if [[ -f "$ISO_FILE" ]]; then
    info "ISO already exists: $ISO_FILE"
else
    log "Downloading Ubuntu ${UBUNTU_VERSION} Desktop ISO..."
    wget --progress=bar:force -O "$ISO_FILE" "$UBUNTU_ISO_URL"
fi

# Verify ISO
log "🔍 Verifying ISO integrity..."
ISO_SIZE=$(stat -c%s "$ISO_FILE" 2>/dev/null || echo "0")
if [[ "$ISO_SIZE" -lt 1000000000 ]]; then
    warn "ISO seems too small (${ISO_SIZE} bytes). Re-downloading..."
    rm -f "$ISO_FILE"
    wget --progress=bar:force -O "$ISO_FILE" "$UBUNTU_ISO_URL"
fi

# Step 2: Unmount any existing partitions
log "🔓 Unmounting existing partitions on $TARGET_DEVICE..."
for part in $(lsblk -nlo NAME "$TARGET_DEVICE" | tail -n +2); do
    umount "/dev/$part" 2>/dev/null || true
done
swapoff "${TARGET_DEVICE}"* 2>/dev/null || true

# Step 3: Create partition table
log "💾 Creating GPT partition table on $TARGET_DEVICE..."
wipefs -a "$TARGET_DEVICE"
parted -s "$TARGET_DEVICE" mklabel gpt

# EFI partition (512MB)
log "Creating EFI System Partition..."
parted -s "$TARGET_DEVICE" mkpart primary fat32 1MiB 513MiB
parted -s "$TARGET_DEVICE" set 1 esp on

# Root partition (rest of disk)
log "Creating root partition..."
parted -s "$TARGET_DEVICE" mkpart primary ext4 513MiB 100%

# Wait for partitions
sleep 2
partprobe "$TARGET_DEVICE"
sleep 2

# Determine partition names
if [[ "$TARGET_DEVICE" == *"nvme"* ]]; then
    EFI_PART="${TARGET_DEVICE}p1"
    ROOT_PART="${TARGET_DEVICE}p2"
else
    EFI_PART="${TARGET_DEVICE}1"
    ROOT_PART="${TARGET_DEVICE}2"
fi

# Step 4: Format partitions
log "📁 Formatting partitions..."
mkfs.vfat -F32 -n "EFI" "$EFI_PART"
mkfs.ext4 -L "Ubuntu" -F "$ROOT_PART"

# Step 5: Mount partitions
log "📂 Mounting partitions..."
mkdir -p "$MOUNT_POINT"
mount "$ROOT_PART" "$MOUNT_POINT"
mkdir -p "$MOUNT_POINT/boot/efi"
mount "$EFI_PART" "$MOUNT_POINT/boot/efi"

# Step 6: Extract Ubuntu from ISO using unsquashfs
log "📦 Installing Ubuntu ${UBUNTU_VERSION}..."

ISO_MOUNT="/mnt/iso-mount"
mkdir -p "$ISO_MOUNT"
mount -o loop "$ISO_FILE" "$ISO_MOUNT"

# Find squashfs filesystem
SQUASHFS=""
for sq in "$ISO_MOUNT/casper/filesystem.squashfs" "$ISO_MOUNT/casper/ubuntu.squashfs" "$ISO_MOUNT/live/filesystem.squashfs"; do
    if [[ -f "$sq" ]]; then
        SQUASHFS="$sq"
        break
    fi
done

if [[ -z "$SQUASHFS" ]]; then
    # List what's in casper for debugging
    ls -la "$ISO_MOUNT/casper/" || true
    error "Could not find squashfs filesystem in ISO"
fi

log "Extracting filesystem from $SQUASHFS..."
unsquashfs -f -d "$MOUNT_POINT" "$SQUASHFS"

# Step 7: Configure the installed system
log "⚙️ Configuring installed system..."

# Mount essential filesystems
mount --bind /dev "$MOUNT_POINT/dev"
mount --bind /dev/pts "$MOUNT_POINT/dev/pts"
mount --bind /proc "$MOUNT_POINT/proc"
mount --bind /sys "$MOUNT_POINT/sys"
mount --bind /run "$MOUNT_POINT/run"

# Get UUIDs
EFI_UUID=$(blkid -s UUID -o value "$EFI_PART")
ROOT_UUID=$(blkid -s UUID -o value "$ROOT_PART")

# Create fstab
cat > "$MOUNT_POINT/etc/fstab" << EOF
# /etc/fstab: static file system information
UUID=$ROOT_UUID  /           ext4  errors=remount-ro  0  1
UUID=$EFI_UUID   /boot/efi   vfat  umask=0077         0  1
EOF

# Set hostname
echo "uai-workstation" > "$MOUNT_POINT/etc/hostname"
cat > "$MOUNT_POINT/etc/hosts" << EOF
127.0.0.1   localhost
127.0.1.1   uai-workstation

::1         localhost ip6-localhost ip6-loopback
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters
EOF

# Configure network
mkdir -p "$MOUNT_POINT/etc/netplan"
cat > "$MOUNT_POINT/etc/netplan/01-network-manager-all.yaml" << EOF
network:
  version: 2
  renderer: NetworkManager
EOF

# Install GRUB bootloader
log "🔧 Installing GRUB bootloader..."
chroot "$MOUNT_POINT" /bin/bash << CHROOT_EOF
# Update package lists
apt update 2>/dev/null || true

# Install GRUB for UEFI
apt install -y grub-efi-amd64 grub-efi-amd64-signed shim-signed 2>/dev/null || true

# Install GRUB to EFI partition
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ubuntu --recheck

# Generate GRUB config
update-grub

# Set root password (temporary - change on first boot!)
echo "root:ubuntu" | chpasswd

# Create default user
useradd -m -s /bin/bash -G sudo,adm,cdrom,dip,plugdev roman 2>/dev/null || true
echo "roman:ubuntu" | chpasswd

# Enable NetworkManager
systemctl enable NetworkManager 2>/dev/null || true

# Clean up live CD artifacts
rm -f /etc/casper.conf 2>/dev/null || true
rm -rf /var/lib/casper 2>/dev/null || true

CHROOT_EOF

# Step 8: Cleanup
log "🧹 Cleaning up..."
umount "$MOUNT_POINT/run" 2>/dev/null || true
umount "$MOUNT_POINT/sys" 2>/dev/null || true
umount "$MOUNT_POINT/proc" 2>/dev/null || true
umount "$MOUNT_POINT/dev/pts" 2>/dev/null || true
umount "$MOUNT_POINT/dev" 2>/dev/null || true
umount "$ISO_MOUNT" 2>/dev/null || true
umount "$MOUNT_POINT/boot/efi" 2>/dev/null || true
umount "$MOUNT_POINT" 2>/dev/null || true

sync

echo ""
echo "============================================================"
echo "  ✅ Ubuntu ${UBUNTU_VERSION} Installation Complete!"
echo "============================================================"
echo ""
echo "  Target Device: $TARGET_DEVICE"
echo "  EFI Partition: $EFI_PART"
echo "  Root Partition: $ROOT_PART"
echo ""
echo "  Default credentials:"
echo "    Username: roman"
echo "    Password: ubuntu"
echo ""
echo "  ⚠️  PLEASE CHANGE PASSWORD ON FIRST BOOT!"
echo ""
echo "  To boot from this SSD:"
echo "  1. Shutdown this computer"
echo "  2. Replace internal drive with this SSD"
echo "  3. Or select USB boot from BIOS/UEFI"
echo ""
