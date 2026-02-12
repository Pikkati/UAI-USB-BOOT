#!/bin/bash
set -euo pipefail

#==============================================================================
# UAI Docker Swarm Initialization
# Initializes Docker Swarm with UAI-specific configuration
#==============================================================================

LOG_FILE="/var/log/uai-swarm-init.log"

# Logging functions
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

error() {
    echo "[ERROR] $*" >&2 | tee -a "$LOG_FILE"
    exit 1
}

warn() {
    echo "[WARN] $*" | tee -a "$LOG_FILE"
}

info() {
    echo "[INFO] $*" | tee -a "$LOG_FILE"
}

# Check if Docker is installed and running
check_docker() {
    info "Checking Docker installation..."

    if ! command -v docker &>/dev/null; then
        error "Docker is not installed"
    fi

    if ! docker info &>/dev/null; then
        info "Starting Docker service..."
        systemctl start docker

        # Wait for Docker to be ready
        local retries=10
        while [[ $retries -gt 0 ]]; do
            if docker info &>/dev/null; then
                break
            fi
            sleep 2
            ((retries--))
        done

        if [[ $retries -eq 0 ]]; then
            error "Failed to start Docker service"
        fi
    fi

    info "Docker is ready"
}

# Check if already in swarm
check_existing_swarm() {
    if docker info 2>/dev/null | grep -q "Swarm: active"; then
        info "Already in Docker Swarm"

        # Check if we're a manager
        if docker node ls &>/dev/null; then
            info "We are a Swarm manager"
            return 0
        else
            info "We are a Swarm worker"
            return 1
        fi
    fi

    return 2  # Not in swarm
}

# Get network interfaces and IPs
get_network_info() {
    info "Detecting network interfaces..."

    # Get all IP addresses
    local ips=$(hostname -I)

    # Prefer non-loopback IPs
    for ip in $ips; do
        if [[ $ip != 127.0.0.1 && $ip != ::1 ]]; then
            ADVERTISE_ADDR="$ip"
            break
        fi
    done

    if [[ -z "${ADVERTISE_ADDR:-}" ]]; then
        error "No suitable IP address found"
    fi

    info "Using advertise address: $ADVERTISE_ADDR"
}

# Initialize Docker Swarm
init_swarm() {
    info "Initializing Docker Swarm..."

    local listen_addr="${ADVERTISE_ADDR}:2377"

    if docker swarm init --advertise-addr "$ADVERTISE_ADDR" --listen-addr "$listen_addr"; then
        info "Docker Swarm initialized successfully"
        info "Swarm Manager IP: $ADVERTISE_ADDR"

        # Save swarm info
        mkdir -p /opt/uai/config
        cat > /opt/uai/config/swarm-info.json << EOF
{
    "manager_ip": "$ADVERTISE_ADDR",
    "initialized_at": "$(date -Iseconds)",
    "node_id": "$(docker node ls --format '{{.ID}}' | head -1)"
}
EOF

        return 0
    else
        error "Failed to initialize Docker Swarm"
        return 1
    fi
}

# Create overlay networks
create_networks() {
    info "Creating overlay networks..."

    # UAI Platform network
    if ! docker network ls --format "{{.Name}}" | grep -q "^uai-platform$"; then
        docker network create --driver overlay --attachable --scope swarm uai-platform
        info "Created uai-platform network"
    else
        info "uai-platform network already exists"
    fi

    # UAI Monitoring network
    if ! docker network ls --format "{{.Name}}" | grep -q "^uai-monitoring$"; then
        docker network create --driver overlay --attachable --scope swarm uai-monitoring
        info "Created uai-monitoring network"
    else
        info "uai-monitoring network already exists"
    fi

    # UAI Storage network
    if ! docker network ls --format "{{.Name}}" | grep -q "^uai-storage$"; then
        docker network create --driver overlay --attachable --scope swarm uai-storage
        info "Created uai-storage network"
    else
        info "uai-storage network already exists"
    fi
}

# Configure Swarm labels
configure_labels() {
    info "Configuring node labels..."

    local node_id=$(docker node ls --format "{{.ID}}" | head -1)

    # Add labels for UAI services
    docker node update --label-add "uai.platform=true" "$node_id"
    docker node update --label-add "uai.monitoring=true" "$node_id"
    docker node update --label-add "uai.storage=true" "$node_id"

    info "Node labels configured"
}

# Create initial services
create_initial_services() {
    info "Creating initial UAI services..."

    # Create volumes first
    docker volume create uai-data 2>/dev/null || true
    docker volume create uai-config 2>/dev/null || true
    docker volume create uai-logs 2>/dev/null || true

    # Deploy stack if compose file exists
    if [[ -f /opt/uai/docker-compose.yml ]]; then
        info "Deploying UAI stack..."
        docker stack deploy -c /opt/uai/docker-compose.yml uai-platform
        info "UAI stack deployed"
    else
        warn "Docker Compose file not found, skipping stack deployment"
    fi
}

# Configure Swarm settings
configure_swarm_settings() {
    info "Configuring Swarm settings..."

    # Set task history limit
    docker swarm update --task-history-limit 5

    # Configure auto-lock (optional)
    # docker swarm update --autolock

    info "Swarm settings configured"
}

# Setup firewall rules for Swarm
configure_firewall() {
    info "Configuring firewall for Docker Swarm..."

    # Allow Swarm ports
    ufw allow 2376/tcp  # Docker Swarm management
    ufw allow 2377/tcp  # Docker Swarm node communication
    ufw allow 7946/tcp  # Docker Swarm container network discovery
    ufw allow 7946/udp  # Docker Swarm container network discovery
    ufw allow 4789/udp  # Docker Swarm overlay network

    # Reload firewall
    ufw reload

    info "Firewall configured for Swarm"
}

# Generate join tokens
generate_join_tokens() {
    info "Generating join tokens..."

    mkdir -p /opt/uai/config

    # Worker token
    local worker_token=$(docker swarm join-token worker -q)
    echo "$worker_token" > /opt/uai/config/worker-token.txt

    # Manager token
    local manager_token=$(docker swarm join-token manager -q)
    echo "$manager_token" > /opt/uai/config/manager-token.txt

    info "Join tokens generated and saved"
}

# Main initialization function
initialize_swarm() {
    log "🐋 Starting UAI Docker Swarm initialization..."

    check_docker

    # Check if already initialized
    local swarm_status=$(check_existing_swarm)
    case $swarm_status in
        0)
            info "Swarm already initialized and we are manager"
            return 0
            ;;
        1)
            info "Already a worker in existing swarm"
            return 0
            ;;
        2)
            info "Not in swarm, proceeding with initialization"
            ;;
    esac

    get_network_info
    init_swarm
    create_networks
    configure_labels
    configure_swarm_settings
    configure_firewall
    generate_join_tokens
    create_initial_services

    log "✅ Docker Swarm initialization completed successfully"
    log "Manager IP: $ADVERTISE_ADDR"
    log "Worker token saved to: /opt/uai/config/worker-token.txt"
    log "Manager token saved to: /opt/uai/config/manager-token.txt"
}

# Main function
main() {
    case "${1:-init}" in
        "init")
            initialize_swarm
            ;;
        "status")
            check_existing_swarm
            ;;
        "networks")
            create_networks
            ;;
        *)
            error "Usage: $0 [init|status|networks]"
            ;;
    esac
}

# Run main function
main "$@"