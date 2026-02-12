#!/bin/bash
set -euo pipefail

#==============================================================================
# UAI Self-Healing Deployment
# Automatically monitors and heals UAI platform services
#==============================================================================

LOG_FILE="/var/log/uai-self-healing.log"
CHECK_INTERVAL=300  # 5 minutes
MAX_RESTARTS=3

# Logging functions
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

error() {
    echo "[ERROR] $*" >&2 | tee -a "$LOG_FILE"
}

warn() {
    echo "[WARN] $*" | tee -a "$LOG_FILE"
}

info() {
    echo "[INFO] $*" | tee -a "$LOG_FILE"
}

# Check Docker daemon
check_docker_daemon() {
    if ! docker info &>/dev/null; then
        warn "Docker daemon is not running, attempting to start..."
        systemctl start docker

        # Wait for Docker to start
        local retries=10
        while [[ $retries -gt 0 ]]; do
            if docker info &>/dev/null; then
                info "Docker daemon started successfully"
                return 0
            fi
            sleep 2
            ((retries--))
        done

        error "Failed to start Docker daemon"
        return 1
    fi

    return 0
}

# Check swarm status
check_swarm_status() {
    if ! docker info 2>/dev/null | grep -q "Swarm: active"; then
        warn "Not in Docker Swarm, attempting to rejoin..."
        /opt/uai/scripts/service-discovery.sh
        return 1
    fi

    return 0
}

# Check service health
check_service_health() {
    local service_name="$1"

    info "Checking health of service: $service_name"

    # Get service status
    local service_info=$(docker service ps "$service_name" --format "{{.CurrentState}}" 2>/dev/null || echo "")

    if [[ -z "$service_info" ]]; then
        warn "Service $service_name not found"
        return 1
    fi

    # Check if service is running
    local running_count=$(echo "$service_info" | grep -c "Running" || echo "0")
    local desired_count=$(docker service inspect "$service_name" --format "{{.Spec.Mode.Replicated.Replicas}}" 2>/dev/null || echo "1")

    if [[ $running_count -lt $desired_count ]]; then
        warn "Service $service_name has $running_count/$desired_count running replicas"

        # Try to restart service
        if docker service update --force "$service_name"; then
            info "Restarted service $service_name"
            return 0
        else
            error "Failed to restart service $service_name"
            return 1
        fi
    fi

    info "Service $service_name is healthy ($running_count/$desired_count running)"
    return 0
}

# Check container health
check_container_health() {
    info "Checking container health..."

    # Get unhealthy containers
    local unhealthy=$(docker ps --filter "health=unhealthy" --format "{{.Names}}" 2>/dev/null || true)

    if [[ -n "$unhealthy" ]]; then
        warn "Found unhealthy containers: $unhealthy"

        for container in $unhealthy; do
            info "Restarting unhealthy container: $container"
            docker restart "$container"
        done
    fi

    # Check for exited containers that should be running
    local exited=$(docker ps -a --filter "status=exited" --filter "label=uai-platform" --format "{{.Names}}" 2>/dev/null || true)

    if [[ -n "$exited" ]]; then
        warn "Found exited UAI containers: $exited"

        for container in $exited; do
            info "Removing exited container: $container"
            docker rm "$container"
        done
    fi
}

# Check system resources
check_system_resources() {
    info "Checking system resources..."

    # Check memory usage
    local memory_usage=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')

    if [[ $memory_usage -gt 90 ]]; then
        warn "High memory usage: ${memory_usage}%"

        # Try to free memory
        sync
        echo 3 > /proc/sys/vm/drop_caches

        # Restart non-critical services if memory is still high
        memory_usage=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')
        if [[ $memory_usage -gt 90 ]]; then
            warn "Memory still high after cache cleanup, restarting services"
            docker service update --force uai-monitoring 2>/dev/null || true
        fi
    fi

    # Check disk usage
    local disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')

    if [[ $disk_usage -gt 90 ]]; then
        warn "High disk usage: ${disk_usage}%"

        # Clean up Docker
        docker system prune -f

        # Remove old logs
        find /var/log -name "*.log" -mtime +7 -delete 2>/dev/null || true

        # Check again
        disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
        if [[ $disk_usage -gt 90 ]]; then
            warn "Disk still full after cleanup"
        fi
    fi

    # Check CPU usage
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')

    if [[ $(echo "$cpu_usage > 90" | bc -l) -eq 1 ]]; then
        warn "High CPU usage: ${cpu_usage}%"

        # Throttle CPU intensive services
        docker service update --limit-cpu 0.5 uai-worker 2>/dev/null || true
    fi
}

# Check network connectivity
check_network_connectivity() {
    info "Checking network connectivity..."

    # Test internet connectivity
    if ! ping -c 1 -W 5 8.8.8.8 &>/dev/null; then
        warn "Internet connectivity lost"

        # Try to restart network
        systemctl restart NetworkManager 2>/dev/null || true
        /opt/uai/scripts/auto-network.sh

        # Test again
        if ! ping -c 1 -W 5 8.8.8.8 &>/dev/null; then
            error "Network connectivity still down"
        fi
    fi

    # Check Docker network
    if ! docker network ls | grep -q "uai-platform"; then
        warn "UAI platform network missing, recreating..."
        docker network create --driver overlay --attachable uai-platform 2>/dev/null || true
    fi
}

# Update service configurations
update_service_configs() {
    info "Checking for service configuration updates..."

    # Check if docker-compose.yml has changed
    if [[ -f /opt/uai/docker-compose.yml ]]; then
        local current_hash=$(md5sum /opt/uai/docker-compose.yml | awk '{print $1}')
        local stored_hash=$(cat /opt/uai/config/docker-compose.hash 2>/dev/null || echo "")

        if [[ "$current_hash" != "$stored_hash" ]]; then
            info "Docker Compose configuration changed, updating services..."

            # Update services
            docker stack deploy -c /opt/uai/docker-compose.yml uai-platform

            # Store new hash
            echo "$current_hash" > /opt/uai/config/docker-compose.hash

            info "Services updated"
        fi
    fi
}

# Backup critical data
perform_backup() {
    info "Performing automated backup..."

    local backup_dir="/opt/uai/backups"
    mkdir -p "$backup_dir"

    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$backup_dir/uai-backup-$timestamp.tar.gz"

    # Backup configuration and data
    tar -czf "$backup_file" \
        /opt/uai/config \
        /opt/uai/data \
        /var/lib/docker/volumes 2>/dev/null || true

    # Keep only last 7 backups
    ls -t "$backup_dir"/uai-backup-*.tar.gz 2>/dev/null | tail -n +8 | xargs rm -f 2>/dev/null || true

    info "Backup completed: $backup_file"
}

# Send health report
send_health_report() {
    info "Sending health report..."

    local report_file="/tmp/uai-health-report.json"

    # Generate health report
    cat > "$report_file" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "hostname": "$(hostname)",
    "docker_swarm": $(docker info 2>/dev/null | grep -q "Swarm: active" && echo "true" || echo "false"),
    "services": $(docker service ls --format "json" 2>/dev/null | jq -s '.' || echo "[]"),
    "containers": $(docker ps --format "json" 2>/dev/null | jq -s '.' || echo "[]"),
    "system_resources": {
        "memory_usage": $(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}'),
        "disk_usage": $(df / | tail -1 | awk '{print $5}' | sed 's/%//'),
        "cpu_usage": $(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
    },
    "network_status": $(ping -c 1 -W 2 8.8.8.8 &>/dev/null && echo "true" || echo "false")
}
EOF

    # Send to monitoring service if available
    if docker service ls | grep -q uai-monitoring; then
        # Could send to monitoring endpoint
        info "Health report generated: $report_file"
    fi
}

# Main healing function
perform_healing() {
    log "🔄 Starting self-healing checks..."

    # Basic checks
    check_docker_daemon
    check_swarm_status
    check_network_connectivity

    # Service checks
    local services=("uai-api" "uai-worker" "uai-monitoring" "uai-grafana")
    for service in "${services[@]}"; do
        check_service_health "$service" || true
    done

    # Container checks
    check_container_health

    # System checks
    check_system_resources

    # Configuration updates
    update_service_configs

    # Periodic tasks
    local current_minute=$(date +%M)
    if [[ $current_minute == "00" ]]; then
        # Hourly tasks
        perform_backup
    fi

    if [[ $current_minute == "30" ]]; then
        # Half-hourly tasks
        send_health_report
    fi

    log "✅ Self-healing checks completed"
}

# Daemon mode
run_daemon() {
    info "Starting self-healing daemon (interval: ${CHECK_INTERVAL}s)"

    while true; do
        perform_healing
        sleep "$CHECK_INTERVAL"
    done
}

# Single run mode
run_once() {
    perform_healing
}

# Main function
main() {
    case "${1:-once}" in
        "daemon")
            run_daemon
            ;;
        "once"|*)
            run_once
            ;;
    esac
}

# Run main function
main "$@"