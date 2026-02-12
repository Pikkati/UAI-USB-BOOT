#!/bin/bash
set -euo pipefail

#==============================================================================
# UAI Cross-Node Communication Setup
# Sets up communication channels between UAI nodes
#==============================================================================

LOG_FILE="/var/log/uai-cross-node.log"

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

# Setup Consul for service discovery
setup_consul() {
    info "Setting up Consul for service discovery..."

    # Check if Consul is already running
    if docker ps | grep -q consul; then
        info "Consul is already running"
        return 0
    fi

    # Create Consul configuration
    mkdir -p /opt/uai/config/consul

    cat > /opt/uai/config/consul/server.json << 'EOF'
{
    "datacenter": "uai-dc",
    "data_dir": "/consul/data",
    "log_level": "INFO",
    "server": true,
    "bootstrap_expect": 1,
    "ui": true,
    "client_addr": "0.0.0.0",
    "bind_addr": "{{ GetInterfaceIP \"eth0\" }}",
    "advertise_addr": "{{ GetInterfaceIP \"eth0\" }}",
    "ports": {
        "dns": 8600,
        "http": 8500,
        "https": -1,
        "grpc": 8502
    },
    "recursors": ["8.8.8.8", "1.1.1.1"],
    "services": [
        {
            "name": "uai-platform",
            "port": 8000,
            "checks": [
                {
                    "http": "http://localhost:8000/health",
                    "interval": "30s",
                    "timeout": "5s"
                }
            ]
        }
    ]
}
EOF

    # Run Consul in Docker
    docker run -d \
        --name consul \
        --network uai-platform \
        -p 8500:8500 \
        -p 8600:8600 \
        -p 8502:8502 \
        -v /opt/uai/config/consul:/consul/config \
        -v consul-data:/consul/data \
        consul:latest agent -config-dir=/consul/config

    # Wait for Consul to be ready
    local retries=30
    while [[ $retries -gt 0 ]]; do
        if curl -s http://localhost:8500/v1/status/leader &>/dev/null; then
            break
        fi
        sleep 2
        ((retries--))
    done

    if [[ $retries -eq 0 ]]; then
        error "Consul failed to start"
    fi

    info "Consul started successfully"
}

# Setup Traefik for load balancing
setup_traefik() {
    info "Setting up Traefik for load balancing..."

    # Check if Traefik is already running
    if docker ps | grep -q traefik; then
        info "Traefik is already running"
        return 0
    fi

    # Create Traefik configuration
    mkdir -p /opt/uai/config/traefik

    # Static configuration
    cat > /opt/uai/config/traefik/traefik.yml << 'EOF'
global:
  checkNewVersion: false
  sendAnonymousUsage: false

log:
  level: INFO

api:
  dashboard: true
  insecure: true

providers:
  docker:
    exposedByDefault: false
    swarmMode: true
  consulCatalog:
    exposedByDefault: false
    prefix: traefik
    refreshInterval: 15s

entryPoints:
  web:
    address: ":80"
  websecure:
    address: ":443"

certificatesResolvers:
  letsencrypt:
    acme:
      email: admin@uai-platform.local
      storage: /letsencrypt/acme.json
      httpChallenge:
        entryPoint: web
EOF

    # Dynamic configuration
    cat > /opt/uai/config/traefik/dynamic.yml << 'EOF'
http:
  routers:
    uai-platform:
      rule: "Host(`uai-platform.local`) || PathPrefix(`/api`)"
      service: uai-platform
      entryPoints:
        - web

    uai-grafana:
      rule: "Host(`grafana.uai-platform.local`)"
      service: uai-grafana
      entryPoints:
        - web

  services:
    uai-platform:
      loadBalancer:
        servers:
          - url: "http://uai-api:8000"

    uai-grafana:
      loadBalancer:
        servers:
          - url: "http://uai-grafana:3000"
EOF

    # Run Traefik
    docker run -d \
        --name traefik \
        --network uai-platform \
        -p 80:80 \
        -p 443:443 \
        -p 8080:8080 \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v /opt/uai/config/traefik:/etc/traefik \
        -v traefik-letsencrypt:/letsencrypt \
        traefik:latest

    info "Traefik started successfully"
}

# Setup inter-node messaging with Redis
setup_redis_cluster() {
    info "Setting up Redis cluster for inter-node messaging..."

    # Check if Redis cluster is already running
    if docker ps | grep -q redis-cluster; then
        info "Redis cluster is already running"
        return 0
    fi

    # Create Redis configuration
    mkdir -p /opt/uai/config/redis

    cat > /opt/uai/config/redis/redis.conf << 'EOF'
bind 0.0.0.0
protected-mode no
tcp-backlog 511
timeout 0
tcp-keepalive 300
daemonize no
supervised no
loglevel notice
databases 16
always-show-logo yes
save 900 1
save 300 10
save 60 10000
stop-writes-on-bgsave-error yes
rdbcompression yes
rdbchecksum yes
dbfilename dump.rdb
dir /data
slave-serve-stale-data yes
slave-read-only yes
repl-diskless-sync no
repl-diskless-sync-delay 5
slave-priority 100
lazyfree-lazy-eviction no
lazyfree-lazy-expire no
lazyfree-lazy-server-delurk no
slave-lazy-flush no
appendonly yes
appendfilename "appendonly.aof"
appendfsync everysec
no-appendfsync-on-rewrite no
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb
aof-load-truncated yes
aof-use-rdb-preamble yes
lua-time-limit 5000
cluster-enabled yes
cluster-config-file nodes.conf
cluster-node-timeout 15000
cluster-migration-barrier 1
cluster-require-full-coverage yes
slowlog-log-slower-than 10000
slowlog-max-len 128
latency-monitor-threshold 0
notify-keyspace-events ""
hash-max-ziplist-entries 512
hash-max-ziplist-value 64
list-max-ziplist-size -2
list-max-ziplist-entries 512
list-max-ziplist-value 64
set-max-intset-entries 512
zset-max-ziplist-entries 128
zset-max-ziplist-value 64
hll-sparse-max-bytes 3000
stream-node-max-bytes 4096
stream-node-max-entries 100
activerehashing yes
client-output-buffer-limit normal 0 0 0
client-output-buffer-limit slave 256mb 64mb 60
client-output-buffer-limit pubsub 32mb 8mb 60
hz 10
dynamic-hz yes
aof-rewrite-incremental-fsync yes
rdb-save-incremental-fsync yes
EOF

    # Run Redis cluster
    docker run -d \
        --name redis-cluster \
        --network uai-platform \
        -p 6379:6379 \
        -p 16379:16379 \
        -v /opt/uai/config/redis/redis.conf:/etc/redis/redis.conf \
        -v redis-data:/data \
        redis:latest redis-server /etc/redis/redis.conf

    info "Redis cluster started successfully"
}

# Setup monitoring with Prometheus
setup_monitoring() {
    info "Setting up cross-node monitoring..."

    # Check if Prometheus is already running
    if docker ps | grep -q uai-monitoring; then
        info "Monitoring is already running"
        return 0
    fi

    # Create Prometheus configuration for multi-node setup
    mkdir -p /opt/uai/config/prometheus

    cat > /opt/uai/config/prometheus/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  # - "first_rules.yml"
  # - "second_rules.yml"

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'uai-platform'
    consul_sd_configs:
      - server: 'consul:8500'
        services: ['uai-platform']
    relabel_configs:
      - source_labels: [__meta_consul_service_address]
        target_label: __address__
        replacement: '$1:8000'

  - job_name: 'docker'
    static_configs:
      - targets: ['localhost:9323']

  - job_name: 'node-exporter'
    consul_sd_configs:
      - server: 'consul:8500'
        services: ['node-exporter']
    relabel_configs:
      - source_labels: [__meta_consul_service_address]
        target_label: __address__
        replacement: '$1:9100'
EOF

    # Run Prometheus
    docker run -d \
        --name uai-monitoring \
        --network uai-monitoring \
        -p 9090:9090 \
        -v /opt/uai/config/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml \
        -v prometheus-data:/prometheus \
        prom/prometheus:latest

    # Run Grafana
    docker run -d \
        --name uai-grafana \
        --network uai-monitoring \
        -p 3000:3000 \
        -e GF_SECURITY_ADMIN_PASSWORD=uai2024! \
        -v grafana-data:/var/lib/grafana \
        grafana/grafana:latest

    info "Monitoring stack started successfully"
}

# Setup node exporter on all nodes
setup_node_exporter() {
    info "Setting up Node Exporter for system monitoring..."

    # Check if node exporter is already running
    if docker ps | grep -q node-exporter; then
        info "Node Exporter is already running"
        return 0
    fi

    # Run Node Exporter
    docker run -d \
        --name node-exporter \
        --network uai-monitoring \
        -p 9100:9100 \
        --pid host \
        --volume /:/host:ro,rslave \
        quay.io/prometheus/node-exporter:latest \
        --path.rootfs=/host

    # Register with Consul
    sleep 5
    curl -X PUT -d '{"name": "node-exporter", "port": 9100}' \
         http://localhost:8500/v1/agent/service/register

    info "Node Exporter started and registered"
}

# Test cross-node communication
test_communication() {
    info "Testing cross-node communication..."

    # Test Consul
    if curl -s http://localhost:8500/v1/status/leader | grep -q '"'; then
        info "✅ Consul communication working"
    else
        warn "❌ Consul communication failed"
    fi

    # Test Traefik
    if curl -s http://localhost:8080/api/http/routers | grep -q '"'; then
        info "✅ Traefik communication working"
    else
        warn "❌ Traefik communication failed"
    fi

    # Test Redis
    if docker exec redis-cluster redis-cli ping | grep -q PONG; then
        info "✅ Redis communication working"
    else
        warn "❌ Redis communication failed"
    fi
}

# Main setup function
setup_cross_node_communication() {
    log "🔗 Setting up UAI cross-node communication..."

    setup_consul
    setup_traefik
    setup_redis_cluster
    setup_monitoring
    setup_node_exporter
    test_communication

    log "✅ Cross-node communication setup completed"
}

# Main function
main() {
    case "${1:-setup}" in
        "setup")
            setup_cross_node_communication
            ;;
        "test")
            test_communication
            ;;
        "status")
            echo "=== Consul Services ==="
            curl -s http://localhost:8500/v1/agent/services | jq . || echo "Consul not available"

            echo "=== Docker Networks ==="
            docker network ls

            echo "=== Running Services ==="
            docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
            ;;
        *)
            error "Usage: $0 [setup|test|status]"
            ;;
    esac
}

# Run main function
main "$@"