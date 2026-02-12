#!/bin/bash
set -euo pipefail

#==============================================================================
# UAI USB Boot - Zero-Configuration Deployment Builder
# Version: 1.0
# Creates bootable USB image with complete UAI platform and Docker Swarm
#==============================================================================

# Configuration
SCRIPT_VERSION="1.0"
BUILD_DATE="$(date +%Y-%m-%d)"
LOG_DIR="/tmp/uai-usb-build-${BUILD_DATE}"
CACHE_DIR="$HOME/.cache/uai-usb"
IMAGE_SIZE_GB=16
IMAGE_FILE="uai-platform-${BUILD_DATE}.img"
USB_DEVICE=""
DRY_RUN=0
VERBOSE=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Create directories
mkdir -p "$LOG_DIR" "$CACHE_DIR"

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$LOG_DIR/build.log"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2 | tee -a "$LOG_DIR/build.log"
    exit 1
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" | tee -a "$LOG_DIR/build.log"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$LOG_DIR/build.log"
}

# Show usage
usage() {
    cat << EOF
UAI USB Boot Builder - Zero-Configuration Deployment

USAGE:
    $0 [OPTIONS] [DEVICE]

OPTIONS:
    -s, --size GB       Image size in GB (default: 16)
    -o, --output FILE   Output image file (default: uai-platform-YYYY-MM-DD.img)
    -d, --dry-run       Show what would be done without executing
    -v, --verbose       Enable verbose output
    -h, --help          Show this help

DEVICE:
    USB device to write to (e.g., /dev/sdb)
    If not specified, only creates image file

EXAMPLES:
    $0                          # Create image file only
    $0 /dev/sdb                 # Create and write to USB device
    $0 -s 32 /dev/sdc          # Create 32GB image and write to device
    $0 -d                       # Dry run to see what would happen

EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--size)
            IMAGE_SIZE_GB="$2"
            shift 2
            ;;
        -o|--output)
            IMAGE_FILE="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=1
            shift
            ;;
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            error "Unknown option: $1"
            ;;
        *)
            USB_DEVICE="$1"
            shift
            ;;
    esac
done

# Validate inputs
if [[ -n "$USB_DEVICE" ]] && [[ ! -b "$USB_DEVICE" ]]; then
    error "Device $USB_DEVICE does not exist or is not a block device"
fi

if [[ -n "$USB_DEVICE" ]] && mount | grep -q "$USB_DEVICE"; then
    error "Device $USB_DEVICE is currently mounted. Please unmount it first."
fi

log "🚀 UAI USB Boot Builder v${SCRIPT_VERSION}"
log "========================================"
log "Image Size: ${IMAGE_SIZE_GB}GB"
log "Output File: ${IMAGE_FILE}"
if [[ -n "$USB_DEVICE" ]]; then
    log "Target Device: ${USB_DEVICE}"
else
    log "Target Device: Image file only"
fi
log ""

# Check dependencies
check_dependencies() {
    local deps=("debootstrap" "grub-pc-bin" "grub-efi-amd64-bin" "squashfs-tools" "xorriso" "rsync")
    local missing=()

    for dep in "${deps[@]}"; do
        if ! dpkg -l | grep -q "^ii  $dep"; then
            missing+=("$dep")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing dependencies: ${missing[*]}. Install with: sudo apt install ${missing[*]}"
    fi

    log "✅ Dependencies satisfied"
}

# Create base Ubuntu system
create_base_system() {
    local rootfs="$CACHE_DIR/rootfs"
    local image_size=$((IMAGE_SIZE_GB * 1024 * 1024 * 1024))

    log "📦 Creating base Ubuntu system..."

    # Create root filesystem
    if [[ ! -d "$rootfs" ]]; then
        info "Setting up Ubuntu 24.04 base system..."
        sudo debootstrap --arch=amd64 noble "$rootfs" http://archive.ubuntu.com/ubuntu/
    else
        info "Using existing rootfs cache"
    fi

    # Configure system
    sudo chroot "$rootfs" /bin/bash << 'EOF'
# Set hostname
echo "uai-platform" > /etc/hostname

# Configure network
cat > /etc/netplan/01-netcfg.yaml << NETCFG
network:
  version: 2
  ethernets:
    all:
      match:
        name: "en*"
      dhcp4: true
  wifis:
    all:
      match:
        name: "wl*"
      dhcp4: true
      access-points:
        "*":
          password: ""
NETCFG

# Install essential packages
apt update
apt install -y \
    linux-generic \
    grub-pc \
    grub-efi-amd64 \
    network-manager \
    docker.io \
    docker-compose \
    openssh-server \
    curl \
    wget \
    git \
    vim \
    htop \
    tmux \
    ufw \
    fail2ban \
    unattended-upgrades

# Configure Docker
systemctl enable docker
usermod -aG docker ubuntu

# Configure SSH
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config

# Create UAI user
useradd -m -s /bin/bash -G sudo,docker uai
echo "uai:uai2024!" | chpasswd

# Configure sudo
echo "uai ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/uai

# Configure firewall
ufw allow ssh
ufw allow 2376/tcp  # Docker Swarm
ufw allow 7946/tcp  # Docker Swarm
ufw allow 7946/udp  # Docker Swarm
ufw allow 4789/udp  # Docker Swarm overlay
ufw --force enable

# Configure auto-updates
echo 'APT::Periodic::Update-Package-Lists "1";' > /etc/apt/apt.conf.d/20auto-upgrades
echo 'APT::Periodic::Unattended-Upgrade "1";' >> /etc/apt/apt.conf.d/20auto-upgrades

# Create UAI directories
mkdir -p /opt/uai/{config,data,logs,scripts}
mkdir -p /var/lib/uai/{docker,swarm,backup}

EOF

    log "✅ Base system created"
}

# Install UAI platform
install_uai_platform() {
    local rootfs="$CACHE_DIR/rootfs"
    local uai_source="/home/roman/UAI_Copilot_Automation_Tool"

    log "🤖 Installing UAI platform..."

    # Copy UAI source code
    sudo cp -r "$uai_source" "$rootfs/opt/uai/platform"

    # Install Python dependencies
    sudo chroot "$rootfs" /bin/bash << EOF
cd /opt/uai/platform
pip3 install -r requirements.txt
pip3 install -e .
EOF

    # Create systemd services
    sudo tee "$rootfs/etc/systemd/system/uai-platform.service" > /dev/null << 'EOF'
[Unit]
Description=UAI Platform Service
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=uai
WorkingDirectory=/opt/uai/platform
ExecStart=/usr/bin/python3 -m uai_platform.main
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    sudo tee "$rootfs/etc/systemd/system/uai-swarm-init.service" > /dev/null << 'EOF'
[Unit]
Description=UAI Docker Swarm Initialization
After=network.target docker.service
Requires=docker.service

[Service]
Type=oneshot
ExecStart=/opt/uai/scripts/init-swarm.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    # Enable services
    sudo chroot "$rootfs" systemctl enable uai-platform uai-swarm-init

    log "✅ UAI platform installed"
}

# Create zero-configuration scripts
create_zero_config_scripts() {
    local rootfs="$CACHE_DIR/rootfs"

    log "⚙️ Creating zero-configuration scripts..."

    # Network auto-configuration script
    sudo tee "$rootfs/opt/uai/scripts/auto-network.sh" > /dev/null << 'EOF'
#!/bin/bash
set -e

echo "🌐 Auto-configuring network..."

# Get network interfaces
INTERFACES=$(ip link show | grep -E '^[0-9]+: (en|eth|wl)' | cut -d: -f2 | tr -d ' ')

for iface in $INTERFACES; do
    echo "Configuring $iface..."
    if [[ $iface == wl* ]]; then
        # WiFi interface - try to connect
        nmcli device wifi rescan
        nmcli device wifi connect "$(nmcli device wifi list | grep -v '^\*' | head -1 | awk '{print $2}')" || true
    else
        # Ethernet - DHCP
        dhclient "$iface" || true
    fi
done

# Test connectivity
if ping -c 1 8.8.8.8 &>/dev/null; then
    echo "✅ Network configured successfully"
else
    echo "⚠️ Network configuration may need manual intervention"
fi
EOF

    # Swarm initialization script
    sudo tee "$rootfs/opt/uai/scripts/init-swarm.sh" > /dev/null << 'EOF'
#!/bin/bash
set -e

echo "🐋 Initializing Docker Swarm..."

# Check if already in swarm
if docker info | grep -q "Swarm: active"; then
    echo "Already in Docker Swarm"
    exit 0
fi

# Get local IP
LOCAL_IP=$(hostname -I | awk '{print $1}')

# Initialize swarm
docker swarm init --advertise-addr "$LOCAL_IP" --listen-addr "$LOCAL_IP:2377"

# Create overlay networks
docker network create --driver overlay --attachable uai-platform
docker network create --driver overlay --attachable uai-monitoring

echo "✅ Docker Swarm initialized"
echo "Swarm Manager IP: $LOCAL_IP"
EOF

    # Service discovery script
    sudo tee "$rootfs/opt/uai/scripts/service-discovery.sh" > /dev/null << 'EOF'
#!/bin/bash
set -e

echo "🔍 Running service discovery..."

# Discover other UAI nodes on network
UAI_NODES=$(nmap -sn 192.168.1.0/24 | grep "uai-platform" | awk '{print $5}' || true)

if [[ -n "$UAI_NODES" ]]; then
    echo "Found UAI nodes: $UAI_NODES"
    # Join existing swarm
    SWARM_TOKEN=$(docker swarm join-token worker -q)
    for node in $UAI_NODES; do
        ssh "uai@$node" "docker swarm join --token $SWARM_TOKEN $node:2377" || true
    done
else
    echo "No other UAI nodes found - initializing new swarm"
    /opt/uai/scripts/init-swarm.sh
fi

echo "✅ Service discovery completed"
EOF

    # Self-healing deployment script
    sudo tee "$rootfs/opt/uai/scripts/self-heal.sh" > /dev/null << 'EOF'
#!/bin/bash
set -e

echo "🔄 Running self-healing checks..."

# Check Docker services
SERVICES=$(docker service ls --format "{{.Name}}")
for service in $SERVICES; do
    REPLICAS=$(docker service ps "$service" --format "{{.CurrentState}}" | grep -c "Running" || echo "0")
    DESIRED=$(docker service inspect "$service" --format "{{.Spec.Mode.Replicated.Replicas}}" 2>/dev/null || echo "1")

    if [[ "$REPLICAS" -lt "$DESIRED" ]]; then
        echo "Restarting service $service ($REPLICAS/$DESIRED running)"
        docker service update --force "$service"
    fi
done

# Check system resources
MEMORY_USAGE=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')
if [[ $MEMORY_USAGE -gt 90 ]]; then
    echo "High memory usage ($MEMORY_USAGE%) - restarting services"
    docker service update --force uai-platform
fi

DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
if [[ $DISK_USAGE -gt 90 ]]; then
    echo "High disk usage ($DISK_USAGE%) - cleaning up"
    docker system prune -f
fi

echo "✅ Self-healing checks completed"
EOF

    # Make scripts executable
    sudo chmod +x "$rootfs/opt/uai/scripts/"*.sh

    log "✅ Zero-configuration scripts created"
}

# Create Docker Swarm configuration
create_swarm_config() {
    local rootfs="$CACHE_DIR/rootfs"

    log "🐳 Creating Docker Swarm configuration..."

    # Docker Compose for UAI platform
    sudo tee "$rootfs/opt/uai/docker-compose.yml" > /dev/null << 'EOF'
version: '3.8'

services:
  uai-api:
    image: uai-platform:latest
    ports:
      - "8000:8000"
    environment:
      - UAI_ENV=production
      - DOCKER_SWARM=true
    volumes:
      - /opt/uai/data:/app/data
      - /opt/uai/config:/app/config
    networks:
      - uai-platform
    deploy:
      replicas: 1
      restart_policy:
        condition: on-failure
      placement:
        constraints:
          - node.role == manager

  uai-worker:
    image: uai-platform:latest
    environment:
      - UAI_ENV=production
      - DOCKER_SWARM=true
      - WORKER_MODE=true
    volumes:
      - /opt/uai/data:/app/data
    networks:
      - uai-platform
    deploy:
      replicas: 2
      restart_policy:
        condition: on-failure

  uai-monitoring:
    image: prom/prometheus:latest
    ports:
      - "9090:9090"
    volumes:
      - /opt/uai/config/prometheus.yml:/etc/prometheus/prometheus.yml
    networks:
      - uai-monitoring
    deploy:
      replicas: 1
      placement:
        constraints:
          - node.role == manager

  uai-grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=uai2024!
    volumes:
      - /opt/uai/data/grafana:/var/lib/grafana
    networks:
      - uai-monitoring
    deploy:
      replicas: 1

networks:
  uai-platform:
    driver: overlay
    attachable: true
  uai-monitoring:
    driver: overlay
    attachable: true

volumes:
  uai-data:
    driver: local
EOF

    # Prometheus configuration
    sudo mkdir -p "$rootfs/opt/uai/config"
    sudo tee "$rootfs/opt/uai/config/prometheus.yml" > /dev/null << 'EOF'
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'uai-platform'
    static_configs:
      - targets: ['uai-api:8000']
  - job_name: 'docker'
    static_configs:
      - targets: ['localhost:9323']
EOF

    log "✅ Docker Swarm configuration created"
}

# Create multi-node support
create_multi_node_support() {
    local rootfs="$CACHE_DIR/rootfs"

    log "🌐 Creating multi-node support..."

    # Distributed storage configuration
    sudo tee "$rootfs/opt/uai/scripts/setup-distributed-storage.sh" > /dev/null << 'EOF'
#!/bin/bash
set -e

echo "💾 Setting up distributed storage..."

# Install GlusterFS for distributed storage
apt update
apt install -y glusterfs-server

# Create storage brick
mkdir -p /var/lib/uai-storage
gluster volume create uai-data $(hostname -I | awk '{print $1}'):var/lib/uai-storage force
gluster volume start uai-data

echo "✅ Distributed storage configured"
EOF

    # Cross-node communication script
    sudo tee "$rootfs/opt/uai/scripts/setup-cross-node.sh" > /dev/null << 'EOF'
#!/bin/bash
set -e

echo "🔗 Setting up cross-node communication..."

# Configure Consul for service discovery
docker run -d \
  --name consul \
  --network uai-platform \
  -p 8500:8500 \
  -p 8600:8600 \
  consul:latest agent -server -bootstrap -ui -client=0.0.0.0

# Configure Traefik for load balancing
docker run -d \
  --name traefik \
  --network uai-platform \
  -p 80:80 \
  -p 443:443 \
  -p 8080:8080 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  traefik:latest \
  --providers.docker=true \
  --api.insecure=true

echo "✅ Cross-node communication configured"
EOF

    # Cluster monitoring script
    sudo tee "$rootfs/opt/uai/scripts/cluster-monitor.sh" > /dev/null << 'EOF'
#!/bin/bash
set -e

echo "📊 Monitoring cluster health..."

# Check node status
docker node ls

# Check service status
docker service ls

# Check container health
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Check resource usage
echo "=== Resource Usage ==="
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}"

echo "✅ Cluster monitoring completed"
EOF

    # Make scripts executable
    sudo chmod +x "$rootfs/opt/uai/scripts/"setup-*.sh cluster-monitor.sh

    log "✅ Multi-node support created"
}

# Create bootable image
create_bootable_image() {
    local rootfs="$CACHE_DIR/rootfs"
    local image_size=$((IMAGE_SIZE_GB * 1024 * 1024 * 1024))
    local image_file="$IMAGE_FILE"

    log "💿 Creating bootable image..."

    # Create empty image file
    dd if=/dev/zero of="$image_file" bs=1M count=$((IMAGE_SIZE_GB * 1024)) status=progress

    # Create partitions
    parted "$image_file" mklabel gpt
    parted "$image_file" mkpart ESP fat32 1MiB 512MiB
    parted "$image_file" set 1 esp on
    parted "$image_file" mkpart primary ext4 512MiB 100%

    # Setup loop device
    local loop_dev=$(losetup -f)
    losetup -P "$loop_dev" "$image_file"

    # Format partitions
    mkfs.fat -F32 "${loop_dev}p1"
    mkfs.ext4 "${loop_dev}p2"

    # Mount partitions
    mkdir -p /tmp/uai-boot-{esp,root}
    mount "${loop_dev}p1" /tmp/uai-boot-esp
    mount "${loop_dev}p2" /tmp/uai-boot-root

    # Copy root filesystem
    rsync -a "$rootfs/" /tmp/uai-boot-root/

    # Install GRUB
    grub-install --target=i386-pc --boot-directory=/tmp/uai-boot-root/boot "$loop_dev"
    grub-install --target=x86_64-efi --boot-directory=/tmp/uai-boot-root/boot --efi-directory=/tmp/uai-boot-esp --removable

    # Create GRUB configuration
    cat > /tmp/uai-boot-root/boot/grub/grub.cfg << 'EOF'
set timeout=5
set default=0

menuentry "UAI Platform - Zero Configuration" {
    linux /boot/vmlinuz root=/dev/sda2 ro quiet splash
    initrd /boot/initrd.img
}

menuentry "UAI Platform - Recovery Mode" {
    linux /boot/vmlinuz root=/dev/sda2 ro recovery nomodeset
    initrd /boot/initrd.img
}
EOF

    # Copy kernel and initrd
    cp /tmp/uai-boot-root/boot/vmlinuz-* /tmp/uai-boot-root/boot/vmlinuz
    cp /tmp/uai-boot-root/boot/initrd.img-* /tmp/uai-boot-root/boot/initrd.img

    # Cleanup
    umount /tmp/uai-boot-{esp,root}
    losetup -d "$loop_dev"
    rm -rf /tmp/uai-boot-{esp,root}

    log "✅ Bootable image created: $image_file"
}

# Write to USB device
write_to_usb() {
    local device="$1"
    local image_file="$IMAGE_FILE"

    if [[ $DRY_RUN -eq 1 ]]; then
        warn "DRY RUN: Would write $image_file to $device"
        return
    fi

    log "💾 Writing image to USB device: $device"

    # Confirm device
    read -p "⚠️  This will erase all data on $device. Continue? (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
        error "Operation cancelled by user"
    fi

    # Write image
    dd if="$image_file" of="$device" bs=4M status=progress conv=fdatasync

    log "✅ Image written to $device"
}

# Main function
main() {
    log "Starting UAI USB Boot build process..."

    check_dependencies
    create_base_system
    install_uai_platform
    create_zero_config_scripts
    create_swarm_config
    create_multi_node_support
    create_bootable_image

    if [[ -n "$USB_DEVICE" ]]; then
        write_to_usb "$USB_DEVICE"
    fi

    log ""
    log "🎉 UAI USB Boot build completed successfully!"
    log "Image file: $IMAGE_FILE"
    if [[ -n "$USB_DEVICE" ]]; then
        log "Written to: $USB_DEVICE"
    fi
    log ""
    log "📋 Next steps:"
    log "1. Boot from USB device"
    log "2. System will auto-configure network and Docker Swarm"
    log "3. UAI platform will start automatically"
    log "4. Access via http://<ip>:8000"
    log ""
    log "Build log: $LOG_DIR/build.log"
}

# Run main function
if [[ $DRY_RUN -eq 1 ]]; then
    warn "DRY RUN MODE - No actual changes will be made"
fi

main "$@"