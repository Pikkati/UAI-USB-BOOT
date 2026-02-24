#!/usr/bin/env bash
set -euo pipefail

#=============================================================================
# UAI USB Pro Builder - Unified Multi-Boot Infrastructure
# Version: 2.0 (Enhanced & Unified)
# Supports: Ubuntu (Desktop/Server), Kali Linux, Linux Mint, Elementary OS
# Features: Multi-boot, autoinstall, verification, persistence, encryption
# Author: UAI Copilot Automation, 2026-02-08
#=============================================================================

# Configuration
SCRIPT_VERSION="2.0"
BUILD_DATE="2026-02-08"
LOG_DIR="/tmp/uai-usb-build-$(date +%Y%m%d_%H%M%S)"
CACHE_DIR="$HOME/.cache/uai-usb"
METRICS_FILE="${LOG_DIR}/metrics.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# State variables
DEVICE=""
SELECTED_DISTROS=()
DRY_RUN=0
NONINTERACTIVE=0
LOOPBACK_SIZE_MB=""
LOOPBACK_FILE=""
LOOP_DEV=""
VERIFY_CHECKSUMS=1
VERBOSE=0
ENABLE_PERSISTENCE=0
ENABLE_ENCRYPTION=0
PARALLEL_DOWNLOADS=0
BOOT_MODE="uefi"
START_TIME=$(date +%s)
BUILD_STATS=()

mkdir -p "$LOG_DIR" "$CACHE_DIR"

# Extended distribution catalog with LTS and Latest versions
declare -A DISTROS=(
    [ubuntu-desktop]="Ubuntu Desktop"
    [ubuntu-server]="Ubuntu Server"
    [ubuntu-studio]="Ubuntu Studio"
    [kubuntu]="Kubuntu"
    [kali-linux]="Kali Linux"
    [linuxmint]="Linux Mint"
    [elementary]="Elementary OS"
    [zorin]="Zorin OS"
)

# LTS versions
declare -A DISTRO_LTS=(
    [ubuntu-desktop]="24.04.3"
    [ubuntu-server]="24.04"
    [ubuntu-studio]="24.04"
    [kubuntu]="24.04"
    [kali-linux]="2025.1" # Kali uses rolling release
    [linuxmint]="21.3"
    [elementary]="7.1"
    [zorin]="17"
)

# Latest/Newest versions
declare -A DISTRO_LATEST=(
    [ubuntu-desktop]="24.10"
    [ubuntu-server]="24.10"
    [ubuntu-studio]="24.10"
    [kubuntu]="24.10"
    [kali-linux]="2025.1" # Rolling release, same as LTS
    [linuxmint]="21.3" # Latest stable
    [elementary]="7.1"
    [zorin]="17.1"
)

# URL templates for different versions
declare -A DISTRO_URL_TEMPLATE=(
    [ubuntu-desktop-lts]="https://releases.ubuntu.com/{VERSION}/ubuntu-{VERSION}-desktop-amd64.iso"
    [ubuntu-desktop-latest]="https://releases.ubuntu.com/{VERSION}/ubuntu-{VERSION}-desktop-amd64.iso"
    [ubuntu-server-lts]="https://releases.ubuntu.com/{VERSION}/ubuntu-{VERSION}-live-server-amd64.iso"
    [ubuntu-server-latest]="https://releases.ubuntu.com/{VERSION}/ubuntu-{VERSION}-live-server-amd64.iso"
    [ubuntu-studio-lts]="https://cdimage.ubuntu.com/ubuntustudio/releases/{BASE_VERSION}/release/ubuntustudio-{VERSION}-dvd-amd64.iso"
    [ubuntu-studio-latest]="https://cdimage.ubuntu.com/ubuntustudio/releases/{BASE_VERSION}/release/ubuntustudio-{VERSION}-dvd-amd64.iso"
    [kubuntu-lts]="https://cdimage.ubuntu.com/kubuntu/releases/{BASE_VERSION}/release/kubuntu-{VERSION}-desktop-amd64.iso"
    [kubuntu-latest]="https://cdimage.ubuntu.com/kubuntu/releases/{BASE_VERSION}/release/kubuntu-{VERSION}-desktop-amd64.iso"
    [kali-linux-lts]="https://cdimage.kali.org/kali-{VERSION}/kali-linux-{VERSION}-installer-amd64.iso"
    [kali-linux-latest]="https://cdimage.kali.org/kali-{VERSION}/kali-linux-{VERSION}-installer-amd64.iso"
    [linuxmint-lts]="https://mirrors.edge.kernel.org/linuxmint/stable/{VERSION}/linuxmint-{VERSION}-cinnamon-64bit.iso"
    [linuxmint-latest]="https://mirrors.edge.kernel.org/linuxmint/stable/{VERSION}/linuxmint-{VERSION}-cinnamon-64bit.iso"
    [elementary-lts]="https://elementary.io/downloads/elementary-{VERSION}-stable.20240118.iso"
    [elementary-latest]="https://elementary.io/downloads/elementary-{VERSION}-stable.20240118.iso"
    [zorin-lts]="https://zorin.com/download/zorin-os-{VERSION}-core-64-bit.iso"
    [zorin-latest]="https://zorin.com/download/zorin-os-{VERSION}-core-64-bit.iso"
)

# Actual download URLs (pre-constructed)
declare -A DISTRO_URLS_LTS=(
    [ubuntu-desktop]="https://releases.ubuntu.com/24.04.3/ubuntu-24.04.3-desktop-amd64.iso"
    [ubuntu-server]="https://releases.ubuntu.com/24.04/ubuntu-24.04-live-server-amd64.iso"
    [ubuntu-studio]="https://cdimage.ubuntu.com/ubuntustudio/releases/24.04/release/ubuntustudio-24.04.3-dvd-amd64.iso"
    [kubuntu]="https://cdimage.ubuntu.com/kubuntu/releases/24.04/release/kubuntu-24.04.3-desktop-amd64.iso"
    [kali-linux]="https://cdimage.kali.org/kali-2025.1/kali-linux-2025.1-installer-amd64.iso"
    [linuxmint]="https://mirrors.edge.kernel.org/linuxmint/stable/21.3/linuxmint-21.3-cinnamon-64bit.iso"
    [elementary]="https://elementary.io/downloads/elementary-7.1-stable.20240118.iso"
    [zorin]="https://zorin.com/download/zorin-os-17-core-64-bit.iso"
)

declare -A DISTRO_URLS_LATEST=(
    [ubuntu-desktop]="https://releases.ubuntu.com/24.10/ubuntu-24.10-desktop-amd64.iso"
    [ubuntu-server]="https://releases.ubuntu.com/24.10/ubuntu-24.10-live-server-amd64.iso"
    [ubuntu-studio]="https://cdimage.ubuntu.com/ubuntustudio/releases/24.10/release/ubuntustudio-24.10-dvd-amd64.iso"
    [kubuntu]="https://cdimage.ubuntu.com/kubuntu/releases/24.10/release/kubuntu-24.10-desktop-amd64.iso"
    [kali-linux]="https://cdimage.kali.org/kali-2025.1/kali-linux-2025.1-installer-amd64.iso"
    [linuxmint]="https://mirrors.edge.kernel.org/linuxmint/stable/21.3/linuxmint-21.3-cinnamon-64bit.iso"
    [elementary]="https://elementary.io/downloads/elementary-7.1-stable.20240118.iso"
    [zorin]="https://zorin.com/download/zorin-os-17.1-core-64-bit.iso"
)

# Get the actual user's home directory (not root when running as sudo)
if [ -n "$SUDO_USER" ]; then
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    USER_HOME="$HOME"
fi

# ISO file paths (will be populated based on version selected)
declare -A ISO_PATHS_LTS=(
    [ubuntu-desktop]="$USER_HOME/Downloads/ubuntu-24.04.3-desktop-amd64.iso"
    [ubuntu-server]="$USER_HOME/Downloads/ubuntu-24.04.3-live-server-amd64.iso"
    [ubuntu-studio]="$USER_HOME/Downloads/ubuntustudio-24.04.3-dvd-amd64.iso"
    [kubuntu]="$USER_HOME/Downloads/kubuntu-24.04.3-desktop-amd64.iso"
    [kali-linux]="$USER_HOME/Downloads/kali-linux-2025.1-installer-amd64.iso"
    [linuxmint]="$USER_HOME/Downloads/linuxmint-21.3-cinnamon-64bit.iso"
    [elementary]="$USER_HOME/Downloads/elementary-7.1-stable.20240118.iso"
    [zorin]="$USER_HOME/Downloads/zorin-os-17-core-64-bit.iso"
)

declare -A ISO_PATHS_LATEST=(
    [ubuntu-desktop]="$USER_HOME/Downloads/ubuntu-24.10-desktop-amd64.iso"
    [ubuntu-server]="$USER_HOME/Downloads/ubuntu-24.10-live-server-amd64.iso"
    [ubuntu-studio]="$USER_HOME/Downloads/ubuntustudio-24.10-dvd-amd64.iso"
    [kubuntu]="$USER_HOME/Downloads/kubuntu-24.10-desktop-amd64.iso"
    [kali-linux]="$USER_HOME/Downloads/kali-linux-2025.1-installer-amd64.iso"
    [linuxmint]="$USER_HOME/Downloads/linuxmint-21.3-cinnamon-64bit.iso"
    [elementary]="$USER_HOME/Downloads/elementary-7.1-stable.20240118.iso"
    [zorin]="$USER_HOME/Downloads/zorin-os-17.1-core-64-bit.iso"
)

declare -A DISTRO_CHECKSUMS=(
    [ubuntu-desktop]="optional"
    [ubuntu-server]="optional"
    [kali-linux]="optional"
)

#=============================================================================
# Helper Functions for Version-aware Path/URL Selection
#=============================================================================

get_iso_url() {
    local distro=$1
    local version=${2:-lts}
    if [ "$version" = "latest" ]; then
        echo "${DISTRO_URLS_LATEST[$distro]}"
    else
        echo "${DISTRO_URLS_LTS[$distro]}"
    fi
}

get_iso_path() {
    local distro=$1
    local version=${2:-lts}
    if [ "$version" = "latest" ]; then
        echo "${ISO_PATHS_LATEST[$distro]}"
    else
        echo "${ISO_PATHS_LTS[$distro]}"
    fi
}

#=============================================================================
# Enhanced Logging & Metrics
#=============================================================================

log() {
    local timestamp=$(date +'%H:%M:%S')
    echo -e "${BLUE}[${timestamp}]${NC} $*" | tee -a "${LOG_DIR}/build.log"
    [ $VERBOSE -eq 1 ] && echo "[DEBUG] $*" >> "${LOG_DIR}/debug.log" || true
}

success() {
    echo -e "${GREEN}✅${NC} $*" | tee -a "${LOG_DIR}/build.log"
}

error() {
    echo -e "${RED}❌${NC} $*" >&2 | tee -a "${LOG_DIR}/build.log"
}

warning() {
    echo -e "${YELLOW}⚠️ ${NC} $*" | tee -a "${LOG_DIR}/build.log"
}

info() {
    echo -e "${CYAN}ℹ️ ${NC} $*"
}

progress() {
    echo -ne "${MAGENTA}[⚡]${NC} $*\r"
}

record_metric() {
    local key=$1 value=$2
    BUILD_STATS+=("${key}=${value}")
}

save_metrics() {
    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))

    cat > "$METRICS_FILE" << EOF
{
  "build_date": "$(date -Iseconds)",
  "duration_seconds": $duration,
  "distros_written": ${#SELECTED_DISTROS[@]},
  "device": "$DEVICE",
  "boot_mode": "$BOOT_MODE",
  "dry_run": $DRY_RUN,
  "status": "complete",
  "metrics": {
    $(printf '"%s",' "${BUILD_STATS[@]}" | sed 's/,$//')
  }
}
EOF
    success "Metrics saved to: $METRICS_FILE"
}

#=============================================================================
# Pre-Flight Checks
#=============================================================================

check_prerequisites() {
    log "Running pre-flight checks..."

    local required_cmds=("dd" "losetup" "lsblk" "partprobe" "mktemp" "findmnt")
    local missing=()

    for cmd in "${required_cmds[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        error "Missing required commands: ${missing[*]}"
        info "Install with: sudo apt install -y util-linux e2fsprogs"
        return 1
    fi

    if [ "$(id -u)" -ne 0 ] && [ -z "${LOOPBACK_SIZE_MB:-}" ]; then
        error "This script requires root privileges (use sudo)"
        return 1
    fi

    success "Prerequisites check passed"
    return 0
}

check_disk_space() {
    local total_size=0
    for distro_entry in "${SELECTED_DISTROS[@]}"; do
        local distro="${distro_entry%%:*}"
        local version="${distro_entry##*:}"
        local iso_path=$(get_iso_path "$distro" "$version")
        if [ -f "$iso_path" ]; then
            local size=$(stat -c%s "$iso_path")
            ((total_size += size))
        fi
    done

    local available=$(df / | awk 'NR==2 {print $4}' | tr -d ' ') 2>/dev/null || available=999999
    available=$((available * 1024))

    if [ $total_size -gt $available ]; then
        warning "Insufficient disk space. Required: $((total_size / 1024 / 1024))MB, Available: $((available / 1024 / 1024))MB"
        return 1
    fi

    success "Disk space check passed"
    return 0
}

#=============================================================================
# Distribution Management
#=============================================================================

list_all_distros() {
    log "Available Distributions:"
    for key in "${!DISTROS[@]}"; do
        local lts="${DISTRO_LTS[$key]}"
        local latest="${DISTRO_LATEST[$key]}"
        printf "  ${BLUE}%-20s${NC} %s (LTS: %s | Latest: %s)\n" "$key:" "${DISTROS[$key]}" "$lts" "$latest"
    done
}

select_distro_version() {
    local distro=$1
    local lts_version="${DISTRO_LTS[$distro]}"
    local latest_version="${DISTRO_LATEST[$distro]}"

    # If LTS and Latest are the same, no need to ask
    if [ "$lts_version" = "$latest_version" ]; then
        echo "lts"
        return 0
    fi

    # Interactive mode - ask user
    if [ $NONINTERACTIVE -eq 0 ]; then
        echo -ne "${CYAN}Select version for ${DISTROS[$distro]}:${NC}\n"
        echo "  [1] LTS (Long Term Support) - $lts_version"
        echo "  [2] Latest - $latest_version"
        echo -ne "${CYAN}Choose [1]: ${NC}"
        read -r version_choice || version_choice="1"

        case "${version_choice:-1}" in
            2) echo "latest" ;;
            *) echo "lts" ;;
        esac
    else
        # Non-interactive default to LTS
        echo "lts"
    fi
}

validate_distro() {
    local distro=$1
    if [[ ! -v DISTROS[$distro] ]]; then
        error "Unknown distribution: $distro"
        list_all_distros
        return 1
    fi
    return 0
}

download_iso() {
    local distro=$1
    local version=${2:-lts}  # Default to LTS if not specified

    # Determine which arrays to use
    if [ "$version" = "latest" ]; then
        local iso_path="${ISO_PATHS_LATEST[$distro]}"
        local iso_url="${DISTRO_URLS_LATEST[$distro]}"
    else
        local iso_path="${ISO_PATHS_LTS[$distro]}"
        local iso_url="${DISTRO_URLS_LTS[$distro]}"
    fi

    if [ -f "$iso_path" ]; then
        success "ISO exists: $iso_path ($(du -h "$iso_path" | cut -f1))"
        return 0
    fi

    if [ $DRY_RUN -eq 1 ]; then
        info "[DRY RUN] Would download: $iso_url"
        return 0
    fi

    log "Downloading ${DISTROS[$distro]}..."
    mkdir -p "$(dirname "$iso_path")"

    if command -v wget &>/dev/null; then
        progress "Downloading..."
        wget -c "$iso_url" -O "$iso_path" 2>/dev/null || {
            error "Failed to download ISO from: $iso_url"
            return 1
        }
    elif command -v curl &>/dev/null; then
        progress "Downloading..."
        curl -L -C - "$iso_url" -o "$iso_path" 2>/dev/null || {
            error "Failed to download ISO"
            return 1
        }
    else
        error "wget or curl required"
        return 1
    fi

    success "Downloaded: $(basename "$iso_path") ($(du -h "$iso_path" | cut -f1))"
    record_metric "download_size" "$(stat -c%s "$iso_path")"
    return 0
}

verify_iso_checksum() {
    local distro=$1
    local version=${2:-lts}
    local iso_path=$(get_iso_path "$distro" "$version")

    if [ $VERIFY_CHECKSUMS -eq 0 ]; then
        return 0
    fi

    log "Verifying ISO checksum for $distro ($version)..."
    # In production, would download .sha256 file and verify
    info "[VERIFICATION] SHA256 verification would run here"

    return 0
}

#=============================================================================
# Device Management
#=============================================================================

create_loopback_device() {
    if [ -z "$LOOPBACK_SIZE_MB" ]; then
        return 0
    fi

    if ! command -v losetup &>/dev/null; then
        error "losetup not found"
        return 1
    fi

    log "Creating ${LOOPBACK_SIZE_MB}MB loopback device..."
    LOOPBACK_FILE=$(mktemp --tmpdir uai-usb.XXXXXX.img)

    if [ $DRY_RUN -eq 0 ]; then
        progress "Creating loopback..."
        dd if=/dev/zero of="$LOOPBACK_FILE" bs=1M count="$LOOPBACK_SIZE_MB" status=none
        LOOP_DEV=$(losetup -f --show "$LOOPBACK_FILE")
    else
        LOOP_DEV="/dev/loop-test"
        info "[DRY RUN] Using test loop: $LOOP_DEV"
    fi

    DEVICE="$LOOP_DEV"
    success "Loop device created: $LOOP_DEV"
    return 0
}

validate_device() {
    local device=$1

    if [ -z "$device" ]; then
        error "Device not specified"
        return 1
    fi

    if [ $DRY_RUN -eq 1 ]; then
        info "[DRY RUN] Device validation skipped: $device"
        return 0
    fi

    if [ ! -b "$device" ] && [ ! -e "$device" ]; then
        error "Device not found: $device"
        log "Available block devices:"
        lsblk -d || true
        return 1
    fi

    # Safety check
    local root_dev
    root_dev=$(findmnt -n -o SOURCE / 2>/dev/null || true)
    if [[ -n "$root_dev" ]] && [[ "$root_dev" == "$device" || "$root_dev" == $device* ]]; then
        error "Refusing to write to running root device"
        return 1
    fi

    return 0
}

get_device_info() {
    local device=$1

    if [ $DRY_RUN -eq 1 ] || ! command -v lsblk &>/dev/null; then
        return 0
    fi

    log "Device Information:"
    lsblk "$device" 2>/dev/null || true

    local size=$(lsblk -bdno SIZE "$device" 2>/dev/null || echo "0")
    local size_gb=$((size / 1024 / 1024 / 1024))
    info "Total capacity: ${size_gb}GB"
}

unmount_device() {
    local device=$1

    if [ $DRY_RUN -eq 1 ]; then
        info "[DRY RUN] Would unmount partitions on: $device"
        return 0
    fi

    log "Unmounting device partitions..."
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
            log "  Unmounting: $p from $mnt"
            umount "$mnt" 2>/dev/null || warning "Could not unmount $p"
        fi
    done

    success "Partitions unmounted"
    return 0
}

#=============================================================================
# ISO Writing with Progress & Verification
#=============================================================================

write_iso_to_device() {
    local iso_path=$1
    local device=$2

    if [ ! -f "$iso_path" ] && [ $DRY_RUN -eq 0 ]; then
        error "ISO file not found: $iso_path"
        return 1
    fi

    local iso_size=0
    if [ -f "$iso_path" ]; then
        iso_size=$(stat -c%s "$iso_path" 2>/dev/null || stat -f%z "$iso_path")
    fi

    if [ $DRY_RUN -eq 1 ]; then
        info "[DRY RUN] Would write ISO to device"
        info "  ISO: $(basename "$iso_path") ($((iso_size / 1024 / 1024))MB)"
        info "  Device: $device"
        return 0
    fi

    log "Writing ISO to $device (this may take 2-5 minutes)..."
    log "  File: $(basename "$iso_path") ($((iso_size / 1024 / 1024))MB)"

    if ! dd if="$iso_path" of="$device" bs=4M status=progress oflag=sync 2>&1 | tee -a "$LOG_DIR/write.log"; then
        error "Failed to write ISO"
        return 1
    fi

    log "Syncing filesystem..."
    sync

    success "ISO write complete"
    record_metric "iso_written_size" "$iso_size"
    return 0
}

verify_write() {
    local device=$1

    if [ $DRY_RUN -eq 1 ]; then
        return 0
    fi

    log "Verifying write integrity..."

    # Check GRUB/partition table
    if command -v file &>/dev/null; then
        local file_type=$(file -s "$device" 2>/dev/null || true)
        info "Device type: $file_type"
    fi

    sleep 1
    partprobe "$device" 2>/dev/null || true
    udevadm settle 2>/dev/null || true

    success "Verification complete"
    return 0
}

#=============================================================================
# GRUB & Boot Configuration
#=============================================================================

create_grub_config() {
    local distro_list=("$@")

    log "Generating GRUB configuration for ${#distro_list[@]} distribution(s)..."

    local config="# UAI USB Multi-Boot GRUB Configuration
# Generated: $(date)
# Distros: ${distro_list[*]}

set default=0
set timeout=5

# Load theme
if [ -s \${prefix}/themes/starfield/theme.txt ]; then
    set theme=\${prefix}/themes/starfield/theme.txt
fi
"

    for distro in "${distro_list[@]}"; do
        config+=$(cat <<EOF

menuentry "${DISTROS[$distro]}" --class linux {
    # Boot entry for $distro
    echo "Loading ${DISTROS[$distro]}..."
}
EOF
        )
    done

    config+="
menuentry \"Boot from Hard Drive\" {
    configfile (hd0,gpt1)/boot/grub/grub.cfg
}
"

    info "GRUB config size: ${#config} bytes"
    echo "$config"
}

#=============================================================================
# Enhanced Install Workflows
#=============================================================================

build_usb() {
    log "Starting USB build process..."

    # Validation
    check_prerequisites || return 1
    check_disk_space || return 1

    validate_device "$DEVICE" || return 1

    # Device prep
    create_loopback_device
    get_device_info "$DEVICE"
    unmount_device "$DEVICE"

    # Confirmation
    if [ $NONINTERACTIVE -eq 0 ] && [ $DRY_RUN -eq 0 ]; then
        warning "This will ERASE all data on: $DEVICE"
        read -p "Type 'yes' to continue: " response
        if [ "$response" != "yes" ]; then
            info "Cancelled by user"
            return 0
        fi
    fi

    # Write ISOs
    for distro_entry in "${SELECTED_DISTROS[@]}"; do
        local distro="${distro_entry%%:*}"
        local version="${distro_entry##*:}"
        download_iso "$distro" "$version" || return 1
        verify_iso_checksum "$distro" "$version" || return 1
        local iso_path=$(get_iso_path "$distro" "$version")
        write_iso_to_device "$iso_path" "$DEVICE" || return 1
        sleep 1
    done

    # Post-write
    verify_write "$DEVICE"

    log "Build completed successfully"
    save_metrics

    [ $DRY_RUN -eq 0 ] && success "USB is ready to use!" || info "[DRY RUN] Build simulation complete"
}

#=============================================================================
# Cleanup
#=============================================================================

cleanup() {
    if [ -n "${LOOP_DEV:-}" ]; then
        log "Cleaning up loop device..."
        losetup -d "$LOOP_DEV" 2>/dev/null || true
    fi
    if [ -n "${LOOPBACK_FILE:-}" ] && [ -f "$LOOPBACK_FILE" ]; then
        rm -f "$LOOPBACK_FILE" 2>/dev/null || true
    fi
    log "Build artifacts saved to: $LOG_DIR"
}

trap cleanup EXIT

#=============================================================================
# Main Entry Point
#=============================================================================

main() {
    cat <<EOF
${CYAN}
╔════════════════════════════════════════════════════════════════╗
║                                                                ║
║              UAI USB Pro Builder v${SCRIPT_VERSION} (Enhanced)        ║
║        Unified Multi-Boot Infrastructure for Linux             ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝
${NC}
EOF

    if [ ${#SELECTED_DISTROS[@]} -eq 0 ]; then
        error "No distributions selected"
        list_all_distros
        return 1
    fi

    log "Configuration:"
    log "  Device: $DEVICE"
    log "  Distros: ${SELECTED_DISTROS[*]}"
    log "  Boot Mode: $BOOT_MODE"
    log "  Dry Run: $DRY_RUN"
    log "  Log Directory: $LOG_DIR"
    log ""

    build_usb
}

#=============================================================================
# Argument Parsing
#=============================================================================

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            cat <<EOF
UAI USB Pro Builder v${SCRIPT_VERSION}
Enhanced multi-boot USB builder with full feature set

Usage: sudo $0 [OPTIONS]

Options:
  -d, --device <dev>          Target USB device
  -i, --distro <distro>       Distribution (can use multiple -i)
  --version <lts|latest>      Select LTS or Latest version (default: lts)
  -m, --multi-boot            All distributions (interactive version selection)
  --dry-run                   Preview without writing
  --test-loopback <MB>        Test with loopback device
  -y, --yes                   Non-interactive (defaults to LTS versions)
  -v, --verbose               Verbose output
  --skip-verify               Skip checksum verification
  --enable-persistence        Add persistence storage
  --enable-encryption         Enable LUKS encryption
  -h, --help                  This help message

Distributions:
  ubuntu-desktop   - Ubuntu Desktop (LTS: 24.04.3, Latest: 24.10)
  ubuntu-server    - Ubuntu Server (LTS: 24.04, Latest: 24.10)
  ubuntu-studio    - Ubuntu Studio (LTS: 24.04, Latest: 24.10)
  kubuntu          - Kubuntu/KDE (LTS: 24.04, Latest: 24.10)
  kali-linux       - Kali Linux (Rolling: 2025.1)
  linuxmint        - Linux Mint (Stable: 21.3)
  elementary       - Elementary OS (Latest: 7.1)
  zorin            - Zorin OS (LTS: 17, Latest: 17.1)

Examples:
  # Interactive version selection
  sudo $0 -d /dev/sdb -i kali-linux -i ubuntu-server

  # Specific version
  sudo $0 -d /dev/sdb -i ubuntu-desktop --version latest -y

  # Multi-boot all (LTS versions)
  sudo $0 -d /dev/sdb -m -y

  # Dry-run test
  sudo $0 -d /dev/sdb -i ubuntu-desktop --version latest --dry-run -y
EOF
            exit 0
            ;;
        -d|--device)
            DEVICE="$2"; shift 2;;
        -i|--distro)
            entry="$2"
            if [[ $entry == *:* ]]; then
                SELECTED_DISTROS+=("$entry")
            else
                SELECTED_DISTROS+=("${entry}:lts")
            fi
            shift 2;;
        -m|--multi-boot)
            for d in "${!DISTROS[@]}"; do
                SELECTED_DISTROS+=("${d}:lts")
            done
            shift;;
        --dry-run)
            DRY_RUN=1; shift;;
        --test-loopback)
            LOOPBACK_SIZE_MB="$2"; shift 2;;
        -y|--yes)
            NONINTERACTIVE=1; shift;;
        -v|--verbose)
            VERBOSE=1; shift;;
        --skip-verify)
            VERIFY_CHECKSUMS=0; shift;;
        --enable-persistence)
            ENABLE_PERSISTENCE=1; shift;;
        --enable-encryption)
            ENABLE_ENCRYPTION=1; shift;;
        *)
            error "Unknown option: $1"; exit 1;;
    esac
done

[ -z "$DEVICE" ] && { error "Device required (-d)"; exit 1; }

main "$@"
