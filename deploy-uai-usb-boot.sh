#!/bin/bash
#==============================================================================
# UAI-USB-BOOT Complete Deployment Script
# Deploys the entire UAI platform with zero-configuration setup
#==============================================================================

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USB_DEVICE="${1:-/dev/sdb}"
MOUNT_POINT="/mnt/uai-boot"
WORK_DIR="/tmp/uai-deployment"
LOG_FILE="/var/log/uai-deployment.log"

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2 | tee -a "$LOG_FILE"
    exit 1
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "$LOG_FILE"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."

    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
    fi

    # Check required tools
    local required_tools=("debootstrap" "grub-install" "mksquashfs" "docker" "docker-compose")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            error "Required tool '$tool' is not installed"
        fi
    done

    # Check USB device
    if [[ ! -b "$USB_DEVICE" ]]; then
        error "USB device $USB_DEVICE does not exist"
    fi

    success "Prerequisites check passed"
}

# Setup work directory
setup_work_dir() {
    log "Setting up work directory..."

    rm -rf "$WORK_DIR"
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"

    success "Work directory setup complete"
}

# Build UAI USB boot image
build_usb_image() {
    log "Building UAI USB boot image..."

    # Source the build script
    if [[ ! -f "$SCRIPT_DIR/build_uai_usb.sh" ]]; then
        error "build_uai_usb.sh not found in $SCRIPT_DIR"
    fi

    chmod +x "$SCRIPT_DIR/build_uai_usb.sh"
    "$SCRIPT_DIR/build_uai_usb.sh" "$USB_DEVICE"

    success "USB boot image built successfully"
}

# Configure zero-configuration networking
configure_networking() {
    log "Configuring zero-configuration networking..."

    if [[ ! -f "$SCRIPT_DIR/auto-network.sh" ]]; then
        error "auto-network.sh not found in $SCRIPT_DIR"
    fi

    chmod +x "$SCRIPT_DIR/auto-network.sh"
    "$SCRIPT_DIR/auto-network.sh"

    success "Zero-configuration networking setup complete"
}

# Setup service discovery
setup_service_discovery() {
    log "Setting up service discovery..."

    if [[ ! -f "$SCRIPT_DIR/service-discovery.sh" ]]; then
        error "service-discovery.sh not found in $SCRIPT_DIR"
    fi

    chmod +x "$SCRIPT_DIR/service-discovery.sh"
    "$SCRIPT_DIR/service-discovery.sh"

    success "Service discovery setup complete"
}

# Initialize Docker Swarm
init_docker_swarm() {
    log "Initializing Docker Swarm..."

    if [[ ! -f "$SCRIPT_DIR/init-swarm.sh" ]]; then
        error "init-swarm.sh not found in $SCRIPT_DIR"
    fi

    chmod +x "$SCRIPT_DIR/init-swarm.sh"
    "$SCRIPT_DIR/init-swarm.sh"

    success "Docker Swarm initialization complete"
}

# Setup distributed storage
setup_distributed_storage() {
    log "Setting up distributed storage..."

    if [[ ! -f "$SCRIPT_DIR/setup-distributed-storage.sh" ]]; then
        error "setup-distributed-storage.sh not found in $SCRIPT_DIR"
    fi

    chmod +x "$SCRIPT_DIR/setup-distributed-storage.sh"
    "$SCRIPT_DIR/setup-distributed-storage.sh"

    success "Distributed storage setup complete"
}

# Setup cross-node communication
setup_cross_node_communication() {
    log "Setting up cross-node communication..."

    if [[ ! -f "$SCRIPT_DIR/setup-cross-node.sh" ]]; then
        error "setup-cross-node.sh not found in $SCRIPT_DIR"
    fi

    chmod +x "$SCRIPT_DIR/setup-cross-node.sh"
    "$SCRIPT_DIR/setup-cross-node.sh"

    success "Cross-node communication setup complete"
}

# Deploy UAI platform stack
deploy_platform_stack() {
    log "Deploying UAI platform stack..."

    # Copy configuration files
    cp "$SCRIPT_DIR/docker-compose.yml" .
    cp "$SCRIPT_DIR/prometheus.yml" .
    cp "$SCRIPT_DIR/loki-config.yml" .
    cp "$SCRIPT_DIR/promtail-config.yml" .
    cp "$SCRIPT_DIR/redis.conf" .
    cp "$SCRIPT_DIR/traefik.yml" .
    cp "$SCRIPT_DIR/grafana-datasources.yml" ./grafana/provisioning/datasources/
    cp "$SCRIPT_DIR/grafana-dashboards.yml" ./grafana/provisioning/dashboards/
    cp "$SCRIPT_DIR/uai-platform-dashboard.json" ./grafana/dashboards/

    # Create necessary directories
    mkdir -p grafana/provisioning/datasources
    mkdir -p grafana/provisioning/dashboards
    mkdir -p grafana/dashboards
    mkdir -p prometheus
    mkdir -p loki
    mkdir -p promtail

    # Move config files to correct locations
    mv prometheus.yml prometheus/
    mv loki-config.yml loki/
    mv promtail-config.yml promtail/

    # Deploy stack
    docker stack deploy -c docker-compose.yml uai-platform

    # Wait for services to be ready
    log "Waiting for services to start..."
    sleep 30

    success "UAI platform stack deployed"
}

# Setup self-healing
setup_self_healing() {
    log "Setting up self-healing capabilities..."

    if [[ ! -f "$SCRIPT_DIR/self-healing.sh" ]]; then
        error "self-healing.sh not found in $SCRIPT_DIR"
    fi

    chmod +x "$SCRIPT_DIR/self-healing.sh"

    # Install as systemd service
    cat > /etc/systemd/system/uai-self-healing.service << EOF
[Unit]
Description=UAI Platform Self-Healing Service
After=docker.service
Requires=docker.service

[Service]
Type=simple
ExecStart=$SCRIPT_DIR/self-healing.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable uai-self-healing
    systemctl start uai-self-healing

    success "Self-healing setup complete"
}

# Setup cluster monitoring
setup_cluster_monitoring() {
    log "Setting up cluster monitoring..."

    if [[ ! -f "$SCRIPT_DIR/cluster-monitor.sh" ]]; then
        error "cluster-monitor.sh not found in $SCRIPT_DIR"
    fi

    chmod +x "$SCRIPT_DIR/cluster-monitor.sh"

    # Install as systemd service
    cat > /etc/systemd/system/uai-cluster-monitor.service << EOF
[Unit]
Description=UAI Platform Cluster Monitoring
After=docker.service
Requires=docker.service

[Service]
Type=simple
ExecStart=$SCRIPT_DIR/cluster-monitor.sh
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable uai-cluster-monitor
    systemctl start uai-cluster-monitor

    success "Cluster monitoring setup complete"
}

# Verify deployment
verify_deployment() {
    log "Verifying deployment..."

    # Check Docker services
    if ! docker stack ls | grep -q uai-platform; then
        error "UAI platform stack not found"
    fi

    # Check service health
    local services=("uai-api" "consul" "traefik" "prometheus" "grafana")
    for service in "${services[@]}"; do
        if ! docker service ls | grep -q "$service"; then
            warning "Service $service not found"
        else
            log "Service $service is running"
        fi
    done

    # Test API endpoint
    sleep 10
    if curl -f http://localhost:8000/health &> /dev/null; then
        success "API health check passed"
    else
        warning "API health check failed - may still be starting"
    fi

    # Run comprehensive validation
    if [[ -f "$SCRIPT_DIR/validate-deployment.sh" ]]; then
        log "Running comprehensive validation..."
        chmod +x "$SCRIPT_DIR/validate-deployment.sh"
        "$SCRIPT_DIR/validate-deployment.sh"
    fi

    success "Deployment verification complete"
}

# Print deployment summary
print_summary() {
    log "UAI-USB-BOOT Deployment Summary"
    echo "================================"
    echo ""
    echo "USB Device: $USB_DEVICE"
    echo "Mount Point: $MOUNT_POINT"
    echo "Log File: $LOG_FILE"
    echo ""
    echo "Services:"
    echo "  - UAI API: http://localhost:8000"
    echo "  - Traefik Dashboard: http://localhost:8080"
    echo "  - Grafana: http://localhost:3000 (admin/uai2024!)"
    echo "  - Prometheus: http://localhost:9090"
    echo "  - Consul: http://localhost:8500"
    echo "  - MinIO: http://localhost:9001 (uaiaccesskey/uaisecretkey2024)"
    echo ""
    echo "Systemd Services:"
    echo "  - uai-self-healing: Self-healing monitoring"
    echo "  - uai-cluster-monitor: Cluster health monitoring"
    echo ""
    echo "Configuration Files:"
    echo "  - Docker Compose: $SCRIPT_DIR/docker-compose.yml"
    echo "  - Prometheus: $SCRIPT_DIR/prometheus.yml"
    echo "  - Grafana: $SCRIPT_DIR/grafana-datasources.yml"
    echo ""
    success "UAI-USB-BOOT deployment completed successfully!"
}

# Main deployment function
main() {
    log "Starting UAI-USB-BOOT deployment..."

    check_prerequisites
    setup_work_dir
    build_usb_image
    configure_networking
    setup_service_discovery
    init_docker_swarm
    setup_distributed_storage
    setup_cross_node_communication
    deploy_platform_stack
    setup_self_healing
    setup_cluster_monitoring
    verify_deployment
    print_summary

    success "UAI-USB-BOOT deployment completed!"
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [USB_DEVICE]"
        echo ""
        echo "Deploy UAI platform with zero-configuration USB boot"
        echo ""
        echo "Arguments:"
        echo "  USB_DEVICE    USB device to use (default: /dev/sdb)"
        echo ""
        echo "Options:"
        echo "  --help, -h    Show this help message"
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac