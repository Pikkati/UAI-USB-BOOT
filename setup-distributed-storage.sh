#!/bin/bash
set -euo pipefail

#==============================================================================
# UAI Distributed Storage Setup
# Sets up GlusterFS for distributed storage across UAI nodes
#==============================================================================

LOG_FILE="/var/log/uai-distributed-storage.log"

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

# Check if GlusterFS is installed
check_glusterfs() {
    if ! command -v gluster &>/dev/null; then
        info "Installing GlusterFS..."

        apt update
        apt install -y glusterfs-server

        systemctl enable glusterd
        systemctl start glusterd

        info "GlusterFS installed and started"
    else
        info "GlusterFS already installed"
    fi
}

# Get UAI node IPs
get_uai_nodes() {
    info "Discovering UAI nodes..."

    # Get nodes from Docker Swarm
    local swarm_nodes=$(docker node ls --format "{{.Hostname}} {{.Status}} {{.ManagerStatus}}" 2>/dev/null | \
                       grep -v "Down" | awk '{print $1}' || true)

    UAI_NODES=()

    for node in $swarm_nodes; do
        # Get IP of the node
        local node_ip=$(docker node inspect "$node" --format "{{.Status.Addr}}" 2>/dev/null || \
                      getent hosts "$node" | awk '{print $1}' || echo "")

        if [[ -n "$node_ip" ]]; then
            UAI_NODES+=("$node_ip")
        fi
    done

    # Fallback: use network discovery
    if [[ ${#UAI_NODES[@]} -eq 0 ]]; then
        warn "No nodes found via Docker Swarm, using network discovery..."
        local subnet=$(ip route | grep -E '^default|0\.0\.0\.0' | awk '{print $3}' | cut -d. -f1-3)

        for i in {1..254}; do
            local ip="${subnet}.${i}"
            if ping -c 1 -W 1 "$ip" &>/dev/null; then
                if timeout 2 nc -z "$ip" 8000 2>/dev/null; then
                    UAI_NODES+=("$ip")
                fi
            fi
        done
    fi

    if [[ ${#UAI_NODES[@]} -eq 0 ]]; then
        error "No UAI nodes found"
    fi

    info "Found UAI nodes: ${UAI_NODES[*]}"
}

# Setup GlusterFS on local node
setup_local_gluster() {
    info "Setting up GlusterFS on local node..."

    # Create brick directory
    mkdir -p /var/lib/uai-storage/brick

    # Start GlusterFS service
    systemctl start glusterd
    systemctl enable glusterd

    # Wait for service to be ready
    sleep 5

    info "Local GlusterFS setup completed"
}

# Create GlusterFS volume
create_gluster_volume() {
    info "Creating GlusterFS volume..."

    local volume_name="uai-data"
    local local_ip=$(hostname -I | awk '{print $1}')

    # Probe other nodes
    for node_ip in "${UAI_NODES[@]}"; do
        if [[ "$node_ip" != "$local_ip" ]]; then
            info "Probing GlusterFS peer: $node_ip"
            gluster peer probe "$node_ip" || warn "Failed to probe $node_ip"
        fi
    done

    # Wait for peers to be connected
    sleep 10

    # Check peer status
    gluster peer status

    # Create volume with all nodes
    local brick_list=""
    for node_ip in "${UAI_NODES[@]}"; do
        brick_list="$brick_list $node_ip:/var/lib/uai-storage/brick"
    done

    info "Creating distributed volume with bricks: $brick_list"

    # Create distributed volume
    gluster volume create "$volume_name" transport tcp $brick_list force

    # Start volume
    gluster volume start "$volume_name"

    # Set volume options
    gluster volume set "$volume_name" network.ping-timeout 10
    gluster volume set "$volume_name" network.remote-dio enable
    gluster volume set "$volume_name" performance.quick-read off
    gluster volume set "$volume_name" performance.read-ahead off

    info "GlusterFS volume '$volume_name' created and started"
}

# Mount GlusterFS volume
mount_gluster_volume() {
    info "Mounting GlusterFS volume..."

    local volume_name="uai-data"
    local mount_point="/mnt/uai-storage"

    # Create mount point
    mkdir -p "$mount_point"

    # Add to fstab for persistence
    local mount_entry="localhost:/$volume_name $mount_point glusterfs defaults,_netdev 0 0"
    if ! grep -q "$mount_entry" /etc/fstab; then
        echo "$mount_entry" >> /etc/fstab
    fi

    # Mount volume
    mount -t glusterfs "localhost:/$volume_name" "$mount_point"

    # Create subdirectories
    mkdir -p "$mount_point/data"
    mkdir -p "$mount_point/config"
    mkdir -p "$mount_point/logs"
    mkdir -p "$mount_point/backups"

    info "GlusterFS volume mounted at $mount_point"
}

# Setup Docker volume plugin
setup_docker_volume_plugin() {
    info "Setting up Docker GlusterFS volume plugin..."

    # Install GlusterFS Docker plugin if available
    if docker plugin ls | grep -q gluster; then
        info "GlusterFS Docker plugin already installed"
    else
        # Try to install glusterfs volume plugin
        docker plugin install --grant-all-permissions glusterfs 2>/dev/null || \
        warn "GlusterFS Docker plugin not available, using bind mounts"
    fi

    # Create Docker volume
    docker volume create --driver local \
        --opt type=glusterfs \
        --opt o=vol=uai-data \
        --opt device=localhost:/uai-data \
        uai-distributed-storage 2>/dev/null || \
    warn "Failed to create Docker volume, will use bind mounts"
}

# Test distributed storage
test_distributed_storage() {
    info "Testing distributed storage..."

    local test_file="/mnt/uai-storage/test-file.txt"
    local test_content="UAI Distributed Storage Test - $(date)"

    # Write test file
    echo "$test_content" > "$test_file"

    # Read test file
    local read_content=$(cat "$test_file")

    if [[ "$read_content" == "$test_content" ]]; then
        info "✅ Distributed storage test passed"
        rm "$test_file"
    else
        error "❌ Distributed storage test failed"
    fi
}

# Main setup function
setup_distributed_storage() {
    log "💾 Setting up UAI distributed storage..."

    check_glusterfs
    get_uai_nodes
    setup_local_gluster

    # Only create volume if we're the first node or it's not already created
    if ! gluster volume info uai-data &>/dev/null; then
        create_gluster_volume
    else
        info "GlusterFS volume 'uai-data' already exists"
    fi

    mount_gluster_volume
    setup_docker_volume_plugin
    test_distributed_storage

    log "✅ Distributed storage setup completed"
}

# Main function
main() {
    case "${1:-setup}" in
        "setup")
            setup_distributed_storage
            ;;
        "test")
            test_distributed_storage
            ;;
        "status")
            gluster volume info uai-data
            gluster peer status
            ;;
        *)
            error "Usage: $0 [setup|test|status]"
            ;;
    esac
}

# Run main function
main "$@"