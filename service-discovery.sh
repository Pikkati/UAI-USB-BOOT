#!/bin/bash
set -euo pipefail

#==============================================================================
# UAI Service Discovery
# Automatically discovers and joins UAI nodes in the network
#==============================================================================

LOG_FILE="/var/log/uai-service-discovery.log"

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

# Check if Docker is running
check_docker() {
    if ! docker info &>/dev/null; then
        error "Docker is not running"
    fi
}

# Check if already in swarm
check_swarm_status() {
    if docker info 2>/dev/null | grep -q "Swarm: active"; then
        info "Already in Docker Swarm"
        return 0
    else
        info "Not in Docker Swarm"
        return 1
    fi
}

# Discover UAI nodes on network
discover_uai_nodes() {
    info "Discovering UAI nodes on network..."

    local subnet=$(ip route | grep -E '^default|0\.0\.0\.0' | awk '{print $3}' | cut -d. -f1-3)
    local current_ip=$(hostname -I | awk '{print $1}')

    info "Scanning subnet: ${subnet}.0/24"

    # Use nmap if available, otherwise fallback to ping sweep
    if command -v nmap &>/dev/null; then
        # Quick nmap scan for SSH ports (assuming UAI nodes run SSH)
        local nodes=$(nmap -sn "${subnet}.0/24" -oG - | grep "Up" | awk '{print $2}' | \
                     xargs -I {} sh -c 'timeout 2 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=2 uai@{} "echo {}" 2>/dev/null || true' | \
                     grep -v "$current_ip" || true)
    else
        # Fallback: ping sweep and check for UAI services
        info "Using fallback discovery method..."
        local nodes=""

        for i in {1..254}; do
            local ip="${subnet}.${i}"
            if [[ "$ip" != "$current_ip" ]]; then
                # Quick ping test
                if ping -c 1 -W 1 "$ip" &>/dev/null; then
                    # Check if it has UAI services
                    if timeout 2 nc -z "$ip" 8000 2>/dev/null; then
                        nodes="$nodes $ip"
                    fi
                fi
            fi
        done
    fi

    # Also check for nodes advertising via mDNS/avahi
    if command -v avahi-browse &>/dev/null; then
        local avahi_nodes=$(avahi-browse -t _uai-platform._tcp | grep "=;.*;" | awk -F';' '{print $8}' || true)
        nodes="$nodes $avahi_nodes"
    fi

    # Remove duplicates and current IP
    UAI_NODES=$(echo "$nodes" | tr ' ' '\n' | grep -v "$current_ip" | sort | uniq)

    if [[ -n "$UAI_NODES" ]]; then
        info "Found UAI nodes: $UAI_NODES"
        echo "$UAI_NODES"
    else
        info "No other UAI nodes found"
        echo ""
    fi
}

# Get swarm join token from manager
get_swarm_token() {
    local manager_ip="$1"

    info "Getting swarm join token from $manager_ip..."

    # Try to get worker token
    local token=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 uai@"$manager_ip" \
                   "docker swarm join-token worker -q" 2>/dev/null || true)

    if [[ -z "$token" ]]; then
        warn "Could not get worker token, trying manager token..."
        token=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 uai@"$manager_ip" \
               "docker swarm join-token manager -q" 2>/dev/null || true)
    fi

    if [[ -n "$token" ]]; then
        info "Got swarm token"
        echo "$token"
    else
        warn "Could not get swarm token from $manager_ip"
        echo ""
    fi
}

# Join existing swarm
join_swarm() {
    local manager_ip="$1"
    local token="$2"

    info "Joining swarm at $manager_ip..."

    if docker swarm join --token "$token" "$manager_ip:2377"; then
        info "Successfully joined swarm"
        return 0
    else
        error "Failed to join swarm"
        return 1
    fi
}

# Initialize new swarm
init_swarm() {
    info "Initializing new Docker Swarm..."

    local local_ip=$(hostname -I | awk '{print $1}')

    if docker swarm init --advertise-addr "$local_ip" --listen-addr "$local_ip:2377"; then
        info "Swarm initialized successfully"
        info "Swarm Manager IP: $local_ip"

        # Create overlay networks
        docker network create --driver overlay --attachable uai-platform 2>/dev/null || true
        docker network create --driver overlay --attachable uai-monitoring 2>/dev/null || true

        return 0
    else
        error "Failed to initialize swarm"
        return 1
    fi
}

# Setup mDNS advertising
setup_mdns() {
    info "Setting up mDNS advertising..."

    if command -v avahi-publish &>/dev/null; then
        # Create avahi service file
        cat > /etc/avahi/services/uai-platform.service << EOF
<?xml version="1.0" standalone='no'?><!--*-nxml-*-->
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">UAI Platform on %h</name>
  <service>
    <type>_uai-platform._tcp</type>
    <port>8000</port>
    <txt-record>version=1.0</txt-record>
    <txt-record>swarm_manager=$(docker info 2>/dev/null | grep -q "Is Manager: true" && echo "true" || echo "false")</txt-record>
  </service>
</service-group>
EOF

        systemctl restart avahi-daemon 2>/dev/null || true
        info "mDNS advertising configured"
    else
        warn "Avahi not available, skipping mDNS setup"
    fi
}

# Main function
main() {
    log "🔍 Starting UAI service discovery..."

    check_docker

    # Check if already in swarm
    if check_swarm_status; then
        info "Already part of a swarm, checking if we're a manager..."
        if docker node ls &>/dev/null; then
            info "We are a swarm manager"
            setup_mdns
        else
            info "We are a swarm worker"
        fi
        log "✅ Service discovery completed (already in swarm)"
        exit 0
    fi

    # Discover existing UAI nodes
    local nodes=$(discover_uai_nodes)

    if [[ -n "$nodes" ]]; then
        info "Found existing UAI nodes, attempting to join..."

        # Try to join each discovered node
        for node_ip in $nodes; do
            info "Trying to join swarm via $node_ip..."

            local token=$(get_swarm_token "$node_ip")

            if [[ -n "$token" ]]; then
                if join_swarm "$node_ip" "$token"; then
                    info "Successfully joined swarm via $node_ip"
                    setup_mdns
                    log "✅ Service discovery completed (joined existing swarm)"
                    exit 0
                fi
            fi
        done

        warn "Could not join any existing swarms"
    fi

    # No existing nodes found, initialize new swarm
    info "No existing UAI nodes found, initializing new swarm..."
    if init_swarm; then
        setup_mdns
        log "✅ Service discovery completed (new swarm initialized)"
        exit 0
    else
        error "Failed to initialize swarm"
    fi
}

# Run main function
main "$@"