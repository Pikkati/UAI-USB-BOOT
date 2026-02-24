#!/bin/bash
set -euo pipefail

#==============================================================================
# UAI-USB-BOOT Validation and Testing Script
# Comprehensive testing of the zero-configuration deployment
#==============================================================================

LOG_FILE="/var/log/uai-validation.log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}✅ $1${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}❌ $1${NC}" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}⚠️ $1${NC}" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}ℹ️ $1${NC}" | tee -a "$LOG_FILE"
}

# Test network configuration
test_network() {
    log "Testing network configuration..."

    # Check if we have IP address
    local ip=$(hostname -I | awk '{print $1}')
    if [[ -z "$ip" ]]; then
        error "No IP address assigned"
        return 1
    fi
    success "IP address: $ip"

    # Test internet connectivity
    if ping -c 1 -W 5 8.8.8.8 &>/dev/null; then
        success "Internet connectivity OK"
    else
        warning "No internet connectivity"
    fi

    # Test DNS resolution
    if nslookup google.com &>/dev/null; then
        success "DNS resolution OK"
    else
        warning "DNS resolution failed"
    fi
}

# Test Docker installation and configuration
test_docker() {
    log "Testing Docker installation..."

    # Check if Docker is installed
    if ! command -v docker &>/dev/null; then
        error "Docker is not installed"
        return 1
    fi
    success "Docker is installed"

    # Check if Docker daemon is running
    if ! docker info &>/dev/null; then
        error "Docker daemon is not running"
        return 1
    fi
    success "Docker daemon is running"

    # Check if user is in docker group
    if ! groups | grep -q docker; then
        warning "Current user is not in docker group"
    else
        success "User is in docker group"
    fi
}

# Test Docker Swarm configuration
test_swarm() {
    log "Testing Docker Swarm configuration..."

    # Check if in swarm mode
    if ! docker info 2>/dev/null | grep -q "Swarm: active"; then
        warning "Not in Docker Swarm mode"
        return 1
    fi
    success "Docker Swarm is active"

    # Check swarm nodes
    local node_count=$(docker node ls 2>/dev/null | grep -c "Ready" || echo "0")
    if [[ "$node_count" -gt 0 ]]; then
        success "Swarm nodes: $node_count"
    else
        warning "No swarm nodes found"
    fi

    # Check if current node is manager
    if docker node ls &>/dev/null; then
        success "Current node is swarm manager"
    else
        info "Current node is swarm worker"
    fi
}

# Test UAI platform services
test_uai_services() {
    log "Testing UAI platform services..."

    # Check if docker-compose.yml exists
    if [[ ! -f "docker-compose.yml" ]]; then
        error "docker-compose.yml not found"
        return 1
    fi
    success "docker-compose.yml found"

    # Check if services are running
    local services=("uai-api" "consul" "traefik" "prometheus" "grafana")
    local running_count=0

    for service in "${services[@]}"; do
        if docker service ls 2>/dev/null | grep -q "$service"; then
            success "Service $service is deployed"
            ((running_count++))
        else
            warning "Service $service not found"
        fi
    done

    if [[ "$running_count" -eq "${#services[@]}" ]]; then
        success "All core services are deployed"
    else
        warning "Some services are missing ($running_count/${#services[@]})"
    fi
}

# Test service endpoints
test_endpoints() {
    log "Testing service endpoints..."

    local endpoints=(
        "UAI API:http://localhost:8000/health"
        "Traefik Dashboard:http://localhost:8080"
        "Grafana:http://localhost:3000"
        "Prometheus:http://localhost:9090"
        "Consul:http://localhost:8500"
    )

    for endpoint in "${endpoints[@]}"; do
        local name=$(echo "$endpoint" | cut -d: -f1)
        local url=$(echo "$endpoint" | cut -d: -f2-)

        if curl -f -s --max-time 10 "$url" &>/dev/null; then
            success "$name endpoint is accessible"
        else
            warning "$name endpoint is not accessible"
        fi
    done
}

# Test monitoring stack
test_monitoring() {
    log "Testing monitoring stack..."

    # Check Prometheus targets
    if curl -s http://localhost:9090/api/v1/targets | grep -q '"health":"up"'; then
        success "Prometheus targets are healthy"
    else
        warning "Prometheus targets health check failed"
    fi

    # Check Grafana
    if curl -s http://localhost:3000/api/health | grep -q '"database":"ok"'; then
        success "Grafana is healthy"
    else
        warning "Grafana health check failed"
    fi
}

# Test self-healing capabilities
test_self_healing() {
    log "Testing self-healing capabilities..."

    # Check if self-healing service is running
    if systemctl is-active --quiet uai-self-healing 2>/dev/null; then
        success "Self-healing service is running"
    else
        warning "Self-healing service is not running"
    fi

    # Check cluster monitoring service
    if systemctl is-active --quiet uai-cluster-monitor 2>/dev/null; then
        success "Cluster monitoring service is running"
    else
        warning "Cluster monitoring service is not running"
    fi
}

# Test multi-node capabilities
test_multi_node() {
    log "Testing multi-node capabilities..."

    # Check overlay networks
    local overlay_networks=$(docker network ls --filter driver=overlay --format "{{.Name}}" | wc -l)
    if [[ "$overlay_networks" -gt 0 ]]; then
        success "Overlay networks configured: $overlay_networks"
    else
        warning "No overlay networks found"
    fi

    # Check service replicas
    local replicated_services=$(docker service ls --format "{{.Replicas}}" 2>/dev/null | grep -v "0/0" | wc -l)
    if [[ "$replicated_services" -gt 0 ]]; then
        success "Replicated services: $replicated_services"
    else
        info "No replicated services found (single-node setup)"
    fi
}

# Test distributed storage
test_distributed_storage() {
    log "Testing distributed storage..."

    # Check if GlusterFS is installed
    if command -v gluster &>/dev/null; then
        success "GlusterFS is installed"

        # Check GlusterFS service
        if systemctl is-active --quiet glusterd 2>/dev/null; then
            success "GlusterFS service is running"
        else
            warning "GlusterFS service is not running"
        fi
    else
        info "GlusterFS not installed (single-node setup)"
    fi

    # Check MinIO
    if docker service ls 2>/dev/null | grep -q minio; then
        success "MinIO service is deployed"
    else
        warning "MinIO service not found"
    fi
}

# Generate test report
generate_report() {
    log "Generating test report..."

    local total_tests=8
    local passed_tests=0
    local report_file="/tmp/uai-validation-report-$(date +%Y%m%d-%H%M%S).txt"

    {
        echo "UAI-USB-BOOT Validation Report"
        echo "=============================="
        echo "Date: $(date)"
        echo "System: $(hostname)"
        echo ""

        # Count passed tests (this is a simplified version)
        echo "Test Results Summary:"
        echo "- Network configuration: $(test_network &>/dev/null && echo "PASS" || echo "FAIL")"
        echo "- Docker installation: $(test_docker &>/dev/null && echo "PASS" || echo "FAIL")"
        echo "- Swarm configuration: $(test_swarm &>/dev/null && echo "PASS" || echo "FAIL")"
        echo "- UAI services: $(test_uai_services &>/dev/null && echo "PASS" || echo "FAIL")"
        echo "- Service endpoints: $(test_endpoints &>/dev/null && echo "PASS" || echo "FAIL")"
        echo "- Monitoring stack: $(test_monitoring &>/dev/null && echo "PASS" || echo "FAIL")"
        echo "- Self-healing: $(test_self_healing &>/dev/null && echo "PASS" || echo "FAIL")"
        echo "- Multi-node: $(test_multi_node &>/dev/null && echo "PASS" || echo "FAIL")"
        echo ""

        echo "Log file: $LOG_FILE"
        echo "Report generated: $report_file"
    } > "$report_file"

    success "Report generated: $report_file"
}

# Main test function
main() {
    log "Starting UAI-USB-BOOT validation..."

    # Run all tests
    test_network
    test_docker
    test_swarm
    test_uai_services
    test_endpoints
    test_monitoring
    test_self_healing
    test_multi_node
    test_distributed_storage

    # Generate report
    generate_report

    log "UAI-USB-BOOT validation completed"
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Validate UAI-USB-BOOT deployment"
        echo ""
        echo "Options:"
        echo "  --network         Test network configuration only"
        echo "  --docker          Test Docker installation only"
        echo "  --swarm           Test Swarm configuration only"
        echo "  --services        Test UAI services only"
        echo "  --endpoints       Test service endpoints only"
        echo "  --monitoring      Test monitoring stack only"
        echo "  --self-healing    Test self-healing only"
        echo "  --multi-node      Test multi-node capabilities only"
        echo "  --distributed     Test distributed storage only"
        echo "  --report          Generate test report only"
        echo "  --help, -h        Show this help message"
        exit 0
        ;;
    --network)
        test_network
        ;;
    --docker)
        test_docker
        ;;
    --swarm)
        test_swarm
        ;;
    --services)
        test_uai_services
        ;;
    --endpoints)
        test_endpoints
        ;;
    --monitoring)
        test_monitoring
        ;;
    --self-healing)
        test_self_healing
        ;;
    --multi-node)
        test_multi_node
        ;;
    --distributed)
        test_distributed_storage
        ;;
    --report)
        generate_report
        ;;
    *)
        main "$@"
        ;;
esac