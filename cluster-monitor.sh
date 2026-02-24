#!/bin/bash
set -euo pipefail

#==============================================================================
# UAI Cluster Monitoring
# Monitors health and status of UAI cluster nodes
#==============================================================================

LOG_FILE="/var/log/uai-cluster-monitor.log"

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

# Get cluster nodes
get_cluster_nodes() {
    info "Getting cluster nodes..."

    # Get nodes from Docker Swarm
    CLUSTER_NODES=$(docker node ls --format "table {{.Hostname}}\t{{.Status}}\t{{.ManagerStatus}}" 2>/dev/null || echo "")

    if [[ -z "$CLUSTER_NODES" ]]; then
        warn "No cluster nodes found via Docker Swarm"
        return 1
    fi

    echo "$CLUSTER_NODES"
}

# Check node health
check_node_health() {
    local node_name="$1"
    info "Checking health of node: $node_name"

    # Get node status
    local node_status=$(docker node inspect "$node_name" --format "{{.Status.State}}" 2>/dev/null || echo "unknown")

    case "$node_status" in
        "ready")
            info "✅ Node $node_name is healthy"
            return 0
            ;;
        "down")
            warn "❌ Node $node_name is down"
            return 1
            ;;
        *)
            warn "⚠️ Node $node_name status: $node_status"
            return 1
            ;;
    esac
}

# Check service health across cluster
check_service_health() {
    info "Checking service health across cluster..."

    # Get all services
    local services=$(docker service ls --format "{{.Name}}" 2>/dev/null || echo "")

    if [[ -z "$services" ]]; then
        warn "No services found"
        return 1
    fi

    local unhealthy_services=()

    for service in $services; do
        info "Checking service: $service"

        # Get service status
        local service_info=$(docker service ps "$service" --format "{{.CurrentState}}" 2>/dev/null || echo "")

        if [[ -z "$service_info" ]]; then
            warn "Service $service not found"
            continue
        fi

        # Count running vs desired replicas
        local running_count=$(echo "$service_info" | grep -c "Running" || echo "0")
        local desired_count=$(docker service inspect "$service" --format "{{.Spec.Mode.Replicated.Replicas}}" 2>/dev/null || echo "1")

        if [[ $running_count -lt $desired_count ]]; then
            warn "Service $service: $running_count/$desired_count replicas running"
            unhealthy_services+=("$service")
        else
            info "✅ Service $service: $running_count/$desired_count replicas running"
        fi
    done

    if [[ ${#unhealthy_services[@]} -gt 0 ]]; then
        warn "Unhealthy services: ${unhealthy_services[*]}"
        return 1
    fi

    return 0
}

# Check resource usage across cluster
check_cluster_resources() {
    info "Checking cluster resource usage..."

    echo "=== Node Resource Usage ==="
    docker node ls --format "table {{.Hostname}}\t{{.Status}}\t{{.ManagerStatus}}"

    echo ""
    echo "=== Service Resource Usage ==="
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}" 2>/dev/null || \
    echo "Unable to get container stats"

    echo ""
    echo "=== System Resource Summary ==="
    echo "Memory Usage: $(free -h | grep '^Mem:' | awk '{print $3 "/" $2}')"
    echo "Disk Usage: $(df -h / | tail -1 | awk '{print $3 "/" $2 " (" $5 ")"}')"
    echo "Load Average: $(uptime | awk -F'load average:' '{print $2}')"
}

# Check network connectivity between nodes
check_network_connectivity() {
    info "Checking network connectivity between nodes..."

    # Get node IPs
    local node_ips=$(docker node ls --format "{{.Status.Addr}}" 2>/dev/null || echo "")

    if [[ -z "$node_ips" ]]; then
        warn "Unable to get node IPs"
        return 1
    fi

    local current_ip=$(hostname -I | awk '{print $1}')

    for node_ip in $node_ips; do
        if [[ "$node_ip" != "$current_ip" ]]; then
            info "Testing connectivity to $node_ip..."

            if ping -c 2 -W 2 "$node_ip" &>/dev/null; then
                info "✅ Can reach $node_ip"
            else
                warn "❌ Cannot reach $node_ip"
            fi
        fi
    done
}

# Check distributed storage health
check_distributed_storage() {
    info "Checking distributed storage health..."

    # Check if GlusterFS volume is mounted
    if mount | grep -q glusterfs; then
        info "✅ GlusterFS volume is mounted"

        # Check volume status
        if gluster volume status uai-data &>/dev/null; then
            info "✅ GlusterFS volume 'uai-data' is online"
        else
            warn "❌ GlusterFS volume 'uai-data' has issues"
        fi
    else
        warn "⚠️ GlusterFS volume not mounted"
    fi

    # Check Docker volumes
    local docker_volumes=$(docker volume ls --format "{{.Name}}" | grep uai || echo "")
    if [[ -n "$docker_volumes" ]]; then
        info "✅ Docker volumes found: $docker_volumes"
    else
        warn "⚠️ No UAI Docker volumes found"
    fi
}

# Generate cluster report
generate_cluster_report() {
    info "Generating cluster health report..."

    local report_file="/tmp/uai-cluster-report-$(date +%Y%m%d_%H%M%S).json"

    # Collect cluster information
    cat > "$report_file" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "cluster_name": "uai-platform",
    "nodes": $(docker node ls --format "json" 2>/dev/null | jq -s '.' || echo "[]"),
    "services": $(docker service ls --format "json" 2>/dev/null | jq -s '.' || echo "[]"),
    "containers": $(docker ps --format "json" 2>/dev/null | jq -s '.' || echo "[]"),
    "networks": $(docker network ls --format "json" 2>/dev/null | jq -s '.' || echo "[]"),
    "system_resources": {
        "memory": "$(free -h | grep '^Mem:' | awk '{print $3 "/" $2}')",
        "disk": "$(df -h / | tail -1 | awk '{print $3 "/" $2 " (" $5 ")"}')",
        "load": "$(uptime | awk -F'load average:' '{print $2}' | xargs)"
    },
    "distributed_storage": {
        "glusterfs_mounted": $(mount | grep -q glusterfs && echo "true" || echo "false"),
        "glusterfs_status": "$(gluster volume info uai-data 2>/dev/null | grep Status | awk '{print $2}' || echo "unknown")"
    }
}
EOF

    info "Cluster report saved to: $report_file"

    # Display summary
    echo ""
    echo "=== Cluster Health Summary ==="
    echo "Report generated: $(date)"
    echo "Nodes online: $(docker node ls 2>/dev/null | grep -c Ready || echo "unknown")"
    echo "Services running: $(docker service ls 2>/dev/null | wc -l || echo "unknown")"
    echo "Containers running: $(docker ps 2>/dev/null | wc -l || echo "unknown")"
    echo "Full report: $report_file"
}

# Alert on critical issues
check_alerts() {
    info "Checking for critical alerts..."

    local alerts=()

    # Check for down nodes
    local down_nodes=$(docker node ls --format "{{.Hostname}} {{.Status}}" 2>/dev/null | grep -v Ready | wc -l || echo "0")
    if [[ $down_nodes -gt 0 ]]; then
        alerts+=("CRITICAL: $down_nodes nodes are down")
    fi

    # Check for failed services
    local failed_services=$(docker service ls --format "{{.Name}} {{.Replicas}}" 2>/dev/null | grep "0/" | wc -l || echo "0")
    if [[ $failed_services -gt 0 ]]; then
        alerts+=("CRITICAL: $failed_services services have no running replicas")
    fi

    # Check disk space
    local disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    if [[ $disk_usage -gt 90 ]]; then
        alerts+=("WARNING: Disk usage is ${disk_usage}%")
    fi

    # Check memory usage
    local memory_usage=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')
    if [[ $memory_usage -gt 90 ]]; then
        alerts+=("WARNING: Memory usage is ${memory_usage}%")
    fi

    # Report alerts
    if [[ ${#alerts[@]} -gt 0 ]]; then
        warn "Alerts detected:"
        for alert in "${alerts[@]}"; do
            warn "  $alert"
        done
    else
        info "✅ No critical alerts"
    fi
}

# Main monitoring function
monitor_cluster() {
    log "📊 Starting UAI cluster monitoring..."

    echo ""
    echo "=========================================="
    echo "        UAI Cluster Health Monitor"
    echo "=========================================="
    echo ""

    # Get cluster nodes
    get_cluster_nodes

    echo ""
    echo "=========================================="
    echo "        Node Health Check"
    echo "=========================================="
    echo ""

    # Check each node
    local node_names=$(docker node ls --format "{{.Hostname}}" 2>/dev/null || echo "")
    for node_name in $node_names; do
        check_node_health "$node_name"
    done

    echo ""
    echo "=========================================="
    echo "        Service Health Check"
    echo "=========================================="
    echo ""

    check_service_health

    echo ""
    echo "=========================================="
    echo "        Resource Usage"
    echo "=========================================="
    echo ""

    check_cluster_resources

    echo ""
    echo "=========================================="
    echo "        Network Connectivity"
    echo "=========================================="
    echo ""

    check_network_connectivity

    echo ""
    echo "=========================================="
    echo "        Distributed Storage"
    echo "=========================================="
    echo ""

    check_distributed_storage

    echo ""
    echo "=========================================="
    echo "        Alerts & Issues"
    echo "=========================================="
    echo ""

    check_alerts

    echo ""
    echo "=========================================="
    echo "        Cluster Report"
    echo "=========================================="
    echo ""

    generate_cluster_report

    log "✅ Cluster monitoring completed"
}

# Main function
main() {
    case "${1:-monitor}" in
        "monitor")
            monitor_cluster
            ;;
        "nodes")
            get_cluster_nodes
            ;;
        "services")
            check_service_health
            ;;
        "resources")
            check_cluster_resources
            ;;
        "alerts")
            check_alerts
            ;;
        *)
            error "Usage: $0 [monitor|nodes|services|resources|alerts]"
            ;;
    esac
}

# Run main function
main "$@"