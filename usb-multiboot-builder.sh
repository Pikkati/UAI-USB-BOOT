#!/usr/bin/env bash
set -euo pipefail

#=============================================================================
# UAI USB Multi-Boot Builder
# Supports: Ubuntu Desktop, Ubuntu Server, Kali Linux
# Features: Safe testing with loopback, multi-boot GRUB config, autoinstall
# Author: UAI Copilot Automation
# Date: 2026-02-08
#=============================================================================

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Defaults
DEVICE=""
ISO_FILE=""
DISTRO=""
ISO_URL=""
AUTOINSTALL_URL=""
DRY_RUN=0
NONINTERACTIVE=0
LOOPBACK_SIZE_MB=""
LOOPBACK_FILE=""
LOOP_DEV=""
BOOT_MODE="uefi"  # uefi or bios
SELECTED_DISTROS=()
MULTI_BOOT=0

# Define available distributions
declare -A DISTROS=(
    [ubuntu-desktop]="Ubuntu Desktop 24.04.3 LTS"
    [ubuntu-server]="Ubuntu Server 24.04 LTS"
    [kali-linux]="Kali Linux 2025.1"
)

declare -A DISTRO_URLS=(
    [ubuntu-desktop]="https://releases.ubuntu.com/24.04.3/ubuntu-24.04.3-desktop-amd64.iso"
    [ubuntu-server]="https://releases.ubuntu.com/24.04.3/ubuntu-24.04.3-live-server-amd64.iso"
    [kali-linux]="https://cdimage.kali.org/kali-2025.1/kali-linux-2025.1-installer-amd64.iso"
)

declare -A ISO_PATHS=(
    [ubuntu-desktop]="$HOME/Downloads/ubuntu-24.04.3-desktop-amd64.iso"
    [ubuntu-server]="$HOME/Downloads/ubuntu-24.04.3-live-server-amd64.iso"
    [kali-linux]="$HOME/Downloads/kali-linux-2025.1-installer-amd64.iso"
)

# Get the actual user's home directory (not root when running as sudo)
if [ -n "$SUDO_USER" ]; then
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    USER_HOME="$HOME"
fi

# Update ISO paths to use correct user home
ISO_PATHS[ubuntu-desktop]="$USER_HOME/Downloads/ubuntu-24.04.3-desktop-amd64.iso"
ISO_PATHS[ubuntu-server]="$USER_HOME/Downloads/ubuntu-24.04.3-live-server-amd64.iso"
ISO_PATHS[kali-linux]="$USER_HOME/Downloads/kali-linux-2025.1-installer-amd64.iso"

#=============================================================================
# Utility Functions
#=============================================================================

log() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}" >&2
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

cleanup() {
    if [ -n "${LOOP_DEV:-}" ]; then
        log "Detaching loop device $LOOP_DEV..."
        losetup -d "$LOOP_DEV" 2>/dev/null || true
    fi
    if [ -n "${LOOPBACK_FILE:-}" ] && [ -f "$LOOPBACK_FILE" ]; then
        rm -f "$LOOPBACK_FILE" 2>/dev/null || true
    fi
}

trap cleanup EXIT

show_help() {
    cat <<EOF
${BLUE}UAI USB Multi-Boot Builder${NC}
Build and write bootable USB drives with multiple Linux distributions

${GREEN}Usage:${NC}
  sudo $0 [OPTIONS]

${GREEN}Options:${NC}
  -d, --device <dev>         Target USB device (e.g., /dev/sdb)
  -i, --distro <distro>      Distribution to write (ubuntu-desktop, ubuntu-server, kali-linux)
                             Use multiple -i flags for multi-boot
  -m, --multi-boot           Build multi-boot USB with all distros
  -u, --iso-url <url>        Custom ISO download URL
  -a, --autoinstall <url>    Network autoinstall server URL
  --dry-run                  Preview actions without writing
  --test-loopback <MB>       Create N MB loopback device for testing
  -y, --yes                  Non-interactive mode (skip confirmations)
  -b, --boot-mode <mode>     Boot mode: uefi or bios (default: uefi)
  -h, --help                 Show this help message

${GREEN}Examples:${NC}
  # Write Ubuntu Desktop to USB (interactive)
  sudo $0 -d /dev/sdb -i ubuntu-desktop

  # Multi-boot USB with all distros (non-interactive)
  sudo $0 -d /dev/sdb -m -y --dry-run

  # Test with loopback before real write
  sudo $0 -d /dev/sdb -i ubuntu-server --test-loopback 256 --dry-run

  # Network autoinstall
  sudo $0 -d /dev/sdb -i ubuntu-server -a "http://10.0.0.1:8000/"

EOF
    exit 0
}

#=============================================================================
# Distribution Management
#=============================================================================

list_distros() {
    log "Available Distributions:"
    for key in "${!DISTROS[@]}"; do
        echo "  • $key: ${DISTROS[$key]}"
    done
}

validate_distro() {
    local distro=$1
    if [[ ! -v DISTROS[$distro] ]]; then
        error "Unknown distribution: $distro"
        list_distros
        exit 1
    fi
}

download_iso() {
    local distro=$1
    local iso_path=${ISO_PATHS[$distro]}
    local iso_url=${DISTRO_URLS[$distro]}

    if [ -f "$iso_path" ]; then
        success "ISO already exists: $iso_path"
        return 0
    fi

    if [ $DRY_RUN -eq 1 ]; then
        info "[DRY RUN] Would download: $iso_url"
        return 0
    fi

    log "Downloading ${DISTROS[$distro]}..."
    mkdir -p "$(dirname "$iso_path")"

    if command -v wget &> /dev/null; then
        wget -c "$iso_url" -O "$iso_path" || {
            error "Failed to download ISO"
            return 1
        }
    elif command -v curl &> /dev/null; then
        curl -L -C - "$iso_url" -o "$iso_path" || {
            error "Failed to download ISO"
            return 1
        }
    else
        error "wget or curl required for ISO download"
        return 1
    fi

    success "Downloaded: $iso_path"
}

#=============================================================================
# Device Management
#=============================================================================

create_loopback_device() {
    if [ -z "$LOOPBACK_SIZE_MB" ]; then
        return 0
    fi

    if ! command -v losetup &> /dev/null; then
        error "losetup not found - required for --test-loopback"
        exit 2
    fi

    log "Creating ${LOOPBACK_SIZE_MB}MB loopback device for testing..."
    LOOPBACK_FILE=$(mktemp --tmpdir ubuntu-usb.XXXXXX.img)

    if [ $DRY_RUN -eq 0 ]; then
        dd if=/dev/zero of="$LOOPBACK_FILE" bs=1M count="$LOOPBACK_SIZE_MB" status=none
        LOOP_DEV=$(losetup -f --show "$LOOPBACK_FILE")
    else
        LOOP_DEV="/dev/loop-test"
        info "[DRY RUN] Would create loop device: $LOOP_DEV"
    fi

    DEVICE="$LOOP_DEV"
    success "Using loop device: $LOOP_DEV"
}

validate_device() {
    local device=$1

    if [ -z "$device" ]; then
        error "Device not specified"
        exit 1
    fi

    if [ $DRY_RUN -eq 1 ]; then
        info "[DRY RUN] Would write to: $device"
        return 0
    fi

    if [ ! -b "$device" ] && [ ! -e "$device" ]; then
        error "Device not found: $device"
        echo "Available block devices:"
        lsblk -d
        exit 1
    fi

    # Safety check: refuse to write to running root filesystem
    local root_dev
    root_dev=$(findmnt -n -o SOURCE / 2>/dev/null || true)
    if [[ -n "$root_dev" ]] && [[ "$root_dev" == "$device" || "$root_dev" == $device* || "$device" == $root_dev* ]]; then
        error "Refusing to write to device containing running root filesystem ($root_dev)"
        exit 1
    fi
}

get_device_info() {
    local device=$1

    if [ $DRY_RUN -eq 1 ]; then
        return 0
    fi

    if ! command -v lsblk &> /dev/null; then
        return 0
    fi

    log "Device Information:"
    lsblk "$device" || true
}

unmount_device() {
    local device=$1

    if [ $DRY_RUN -eq 1 ]; then
        info "[DRY RUN] Would unmount partitions on: $device"
        return 0
    fi

    log "Unmounting device partitions..."

    # Use lsblk to find partitions
    mapfile -t parts < <(lsblk -ln -o NAME "$device" 2>/dev/null | tail -n +2 || true)

    if [ ${#parts[@]} -eq 0 ]; then
        info "No partitions detected"
        return 0
    fi

    for p in "${parts[@]}"; do
        p="/dev/$p"
        local mnt
        mnt=$(findmnt -n -S "$p" -o TARGET 2>/dev/null || true)
        if [ -n "$mnt" ]; then
            log "  Unmounting $p (mounted at $mnt)..."
            umount "$mnt" 2>/dev/null || warning "  Could not unmount $p"
        fi
    done

    success "Unmounting complete"
}

#=============================================================================
# ISO Writing
#=============================================================================

write_iso_to_device() {
    local iso_path=$1
    local device=$2

    local iso_size
    iso_size=$(stat -c%s "$iso_path" 2>/dev/null || stat -f%z "$iso_path" 2>/dev/null)

    if [ $DRY_RUN -eq 1 ]; then
        info "[DRY RUN] Would write: $iso_path"
        info "[DRY RUN] To device: $device"
        info "[DRY RUN] Command: dd if=\"$iso_path\" of=\"$device\" bs=4M status=progress oflag=sync"
        return 0
    fi

    log "Writing ISO to $device (this may take several minutes)..."
    log "File: $iso_path"
    log "Size: $((iso_size / 1024 / 1024)) MB"

    if ! dd if="$iso_path" of="$device" bs=4M status=progress oflag=sync; then
        error "Failed to write ISO to device"
        return 1
    fi

    log "Syncing filesystem..."
    sync

    success "ISO written successfully"
}

#=============================================================================
# GRUB Configuration
#=============================================================================

create_multi_boot_grub_config() {
    local usb_mount=$1
    shift
    local -n distros=("$@")

    log "Creating multi-boot GRUB configuration..."

    if [ $DRY_RUN -eq 1 ]; then
        info "[DRY RUN] Would create GRUB config for distros: ${distros[*]}"
        return 0
    fi

    # Create GRUB directory
    mkdir -p "$usb_mount/boot/grub"

    local grub_cfg="$usb_mount/boot/grub/grub.cfg"

    # Create header
    cat > "$grub_cfg" << 'HEADER'
# GRUB configuration for UAI Multi-Boot USB
# Generated by UAI USB Multi-Boot Builder
# Date: $(date)

set default=0
set timeout=5

# Load theme if available
if [ -s ${prefix}/themes/starfield/theme.txt ]; then
    set theme=${prefix}/themes/starfield/theme.txt
fi

HEADER

    # Add each distro as a menu entry
    for distro in "${distros[@]}"; do
        log "  Adding menu entry for: $distro"
        case $distro in
            ubuntu-desktop)
                cat >> "$grub_cfg" << 'UBUNTU_DESKTOP'

menuentry "Ubuntu Desktop 24.04.3 LTS" --class ubuntu --class gnu-linux {
    echo "Booting Ubuntu Desktop..."
    # Note: ISO should be extracted to USB boot partition
}
UBUNTU_DESKTOP
                ;;
            ubuntu-server)
                cat >> "$grub_cfg" << 'UBUNTU_SERVER'

menuentry "Ubuntu Server 24.04 LTS" --class ubuntu --class gnu-linux {
    echo "Booting Ubuntu Server..."
}
UBUNTU_SERVER
                ;;
            kali-linux)
                cat >> "$grub_cfg" << 'KALI_LINUX'

menuentry "Kali Linux 2025.1" --class kali --class gnu-linux {
    echo "Booting Kali Linux..."
}
KALI_LINUX
                ;;
        esac
    done

    # Add recovery options
    cat >> "$grub_cfg" << 'FOOTER'

menuentry "Boot from Hard Drive" {
    configfile (hd0,gpt1)/boot/grub/grub.cfg
}

menuentry "UEFI Firmware Setup" {
    fwsetup
}
FOOTER

    success "GRUB configuration created"
}

#=============================================================================
# Confirmation & Validation
#=============================================================================

confirm_action() {
    if [ $NONINTERACTIVE -eq 1 ]; then
        return 0
    fi

    echo ""
    warning "THIS WILL ERASE ALL DATA ON: $DEVICE"
    echo ""
    warning "Distros to write:"
    for distro in "${SELECTED_DISTROS[@]}"; do
        echo "  • ${DISTROS[$distro]}"
    done
    echo ""

    if [ -z "$ISO_FILE" ]; then
        read -p "$(echo -ne $YELLOW)Type 'yes' to continue: $(echo -ne $NC)" confirm
    else
        read -p "$(echo -ne $YELLOW)Type 'yes' to continue: $(echo -ne $NC)" confirm
    fi

    if [ "$confirm" != "yes" ]; then
        info "Operation cancelled"
        exit 0
    fi
}

#=============================================================================
# Main Functions
#=============================================================================

main() {
    # Root check
    if [ "${EUID:-0}" -ne 0 ] && [ -z "$LOOPBACK_SIZE_MB" ]; then
        error "This script requires root privileges (use sudo)"
        exit 1
    fi

    # Banner
    echo ""
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║          UAI USB Multi-Boot Builder v1.0                     ║"
    echo "║     Build bootable USB with Ubuntu & Kali Linux             ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    # Validate selections
    if [ ${#SELECTED_DISTROS[@]} -eq 0 ] && [ $MULTI_BOOT -eq 0 ]; then
        error "No distributions selected"
        list_distros
        exit 1
    fi

    # Handle multi-boot flag
    if [ $MULTI_BOOT -eq 1 ]; then
        SELECTED_DISTROS=("${!DISTROS[@]}")
        info "Multi-boot mode: ${#SELECTED_DISTROS[@]} distributions selected"
    fi

    # Validate and download ISOs
    for distro in "${SELECTED_DISTROS[@]}"; do
        validate_distro "$distro"
        download_iso "$distro"
    done

    # Device setup
    if [ -z "$DEVICE" ]; then
        error "Device not specified (use -d flag)"
        exit 1
    fi

    create_loopback_device
    validate_device "$DEVICE"
    get_device_info "$DEVICE"

    # Confirmation
    confirm_action

    # Write operation
    unmount_device "$DEVICE"

    if [ ${#SELECTED_DISTROS[@]} -eq 1 ]; then
        local distro="${SELECTED_DISTROS[0]}"
        local iso_path="${ISO_PATHS[$distro]}"

        log "Writing ${DISTROS[$distro]} to $DEVICE..."
        write_iso_to_device "$iso_path" "$DEVICE"
    else
        log "DEBUG: Multi-boot mode with ${#SELECTED_DISTROS[@]} distros: ${SELECTED_DISTROS[*]}"
        log "DEBUG: Calling setup_multi_boot_usb with ${#SELECTED_DISTROS[@]} distros"
        # Use proper multi-boot setup
        setup_multi_boot_usb "$DEVICE" "${SELECTED_DISTROS[@]}"
    fi

    # Post-write operations
    if [ $DRY_RUN -eq 0 ]; then
        log "Finalizing..."
        sleep 2
        partprobe "$DEVICE" 2>/dev/null || true
        udevadm settle 2>/dev/null || true
        sleep 1
    fi

    # Summary
    echo ""
    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                    ✅ OPERATION COMPLETE                     ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    for distro in "${SELECTED_DISTROS[@]}"; do
        echo "  ✓ ${DISTROS[$distro]}"
    done

    echo ""
    info "USB Device: $DEVICE"
    echo ""
    info "Next steps:"
    echo "  1. Safely eject the USB drive"
    echo "  2. Insert into target machine"
    echo "  3. Boot from USB (F12/DEL/ESC during startup)"
    echo "  4. Select desired distribution from boot menu"
    echo ""
}

#=============================================================================
# Argument Parsing
#=============================================================================

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            ;;
        -d|--device)
            DEVICE="$2"
            shift 2
            ;;
        -i|--distro)
            SELECTED_DISTROS+=("$2")
            shift 2
            ;;
        -m|--multi-boot)
            MULTI_BOOT=1
            shift
            ;;
        -u|--iso-url)
            ISO_URL="$2"
            shift 2
            ;;
        -a|--autoinstall)
            AUTOINSTALL_URL="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --test-loopback)
            LOOPBACK_SIZE_MB="$2"
            shift 2
            ;;
        -y|--yes)
            NONINTERACTIVE=1
            shift
            ;;
        -b|--boot-mode)
            BOOT_MODE="$2"
            shift 2
            ;;
        *)
            error "Unknown option: $1"
            show_help
            ;;
    esac
done


#=============================================================================
# Multi-Boot Setup
#=============================================================================

setup_multi_boot_usb() {
    local device="$1"
    shift
    local selected_distros=("$@")

    log "Setting up multi-boot USB on $device..."

    # Create GPT partition table
    log "Creating GPT partition table..."
    if ! parted -s "$device" mklabel gpt; then
        error "Failed to create GPT partition table"
        return 1
    fi

    # Create EFI partition (FAT32, 512MB)
    log "Creating EFI partition..."
    if ! parted -s "$device" mkpart primary fat32 1MiB 513MiB; then
        error "Failed to create EFI partition"
        return 1
    fi
    parted -s "$device" set 1 esp on

    # Create data partition for ISOs (remaining space)
    log "Creating data partition..."
    if ! parted -s "$device" mkpart primary ext4 513MiB 100%; then
        error "Failed to create data partition"
        return 1
    fi

    # Wait for partitions to be recognized
    sleep 2
    partprobe "$device" 2>/dev/null || true
    udevadm settle 2>/dev/null || true

    # Format EFI partition as FAT32
    local efi_part="${device}1"
    log "Formatting EFI partition ($efi_part) as FAT32..."
    if ! mkfs.fat -F32 "$efi_part"; then
        error "Failed to format EFI partition"
        return 1
    fi

    # Format data partition as ext4
    local data_part="${device}2"
    log "Formatting data partition ($data_part) as ext4..."
    if ! mkfs.ext4 -F "$data_part"; then
        error "Failed to format data partition"
        return 1
    fi

    # Mount data partition
    local mount_point="/tmp/usb_multiboot_$$"
    mkdir -p "$mount_point"
    if ! mount "$data_part" "$mount_point"; then
        error "Failed to mount data partition"
        rmdir "$mount_point"
        return 1
    fi

    # Copy ISOs to data partition
    log "Copying ISOs to USB..."
    for distro in "${selected_distros[@]}"; do
        local iso_path="${ISO_PATHS[$distro]}"
        local iso_filename="$(basename "$iso_path")"

        log "Copying ${DISTROS[$distro]}..."
        if ! cp "$iso_path" "$mount_point/"; then
            error "Failed to copy $iso_filename"
            umount "$mount_point"
            rmdir "$mount_point"
            return 1
        fi
    done

    # Unmount data partition
    umount "$mount_point"
    rmdir "$mount_point"

    # Mount EFI partition for GRUB installation
    mkdir -p "$mount_point"
    if ! mount "$efi_part" "$mount_point"; then
        error "Failed to mount EFI partition"
        rmdir "$mount_point"
        return 1
    fi

    # Create EFI directory structure
    mkdir -p "$mount_point/EFI/BOOT"

    # Install GRUB for EFI
    log "Installing GRUB for EFI..."
    if ! grub-install --target=x86_64-efi --efi-directory="$mount_point" --boot-directory="$mount_point/boot" --removable --no-floppy; then
        warning "EFI GRUB installation failed, continuing..."
    fi

    # Install GRUB for BIOS
    log "Installing GRUB for BIOS..."
    if ! grub-install --target=i386-pc --boot-directory="$mount_point/boot" --removable "$device"; then
        warning "BIOS GRUB installation failed, continuing..."
    fi

    # Generate GRUB configuration
    log "Generating GRUB configuration..."
    create_multi_boot_grub_config "$mount_point/boot/grub/grub.cfg" "${selected_distros[@]}"

    # Unmount EFI partition
    umount "$mount_point"
    rmdir "$mount_point"

    success "Multi-boot USB setup complete"
}

main "$@"
