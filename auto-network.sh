#!/bin/bash
set -euo pipefail

#==============================================================================
# UAI Zero-Configuration Network Setup
# Automatically configures network interfaces for UAI platform
#==============================================================================

LOG_FILE="/var/log/uai-network-setup.log"

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

# Detect network interfaces
detect_interfaces() {
    info "Detecting network interfaces..."

    # Get all network interfaces
    INTERFACES=$(ip link show | grep -E '^[0-9]+: (en|eth|wl)' | cut -d: -f2 | tr -d ' ')

    WIRED_INTERFACES=()
    WIRELESS_INTERFACES=()

    for iface in $INTERFACES; do
        if [[ $iface == wl* ]]; then
            WIRELESS_INTERFACES+=("$iface")
        else
            WIRED_INTERFACES+=("$iface")
        fi
    done

    info "Found wired interfaces: ${WIRED_INTERFACES[*]:-none}"
    info "Found wireless interfaces: ${WIRELESS_INTERFACES[*]:-none}"
}

# Configure wired interfaces
configure_wired() {
    info "Configuring wired interfaces..."

    for iface in "${WIRED_INTERFACES[@]}"; do
        info "Configuring $iface..."

        # Bring interface up
        ip link set "$iface" up

        # Try DHCP
        if timeout 10 dhclient -v "$iface" 2>/dev/null; then
            info "DHCP successful on $iface"
            return 0
        else
            warn "DHCP failed on $iface, trying static configuration"

            # Fallback to static IP
            local ip_addr="192.168.1.$(shuf -i 100-200 -n 1)"
            ip addr add "$ip_addr/24" dev "$iface"
            ip route add default via 192.168.1.1 dev "$iface"

            info "Static IP configured: $ip_addr on $iface"
        fi
    done
}

# Configure wireless interfaces
configure_wireless() {
    info "Configuring wireless interfaces..."

    for iface in "${WIRELESS_INTERFACES[@]}"; do
        info "Configuring $iface..."

        # Bring interface up
        ip link set "$iface" up

        # Scan for networks
        info "Scanning for wireless networks..."
        iwlist "$iface" scan 2>/dev/null | grep -E 'ESSID|Signal' || true

        # Try to connect to open networks first
        local networks=$(iwlist "$iface" scan 2>/dev/null | grep 'ESSID' | sed 's/.*ESSID:"\(.*\)".*/\1/' | head -5)

        for network in $networks; do
            info "Trying to connect to: $network"

            if nmcli device wifi connect "$network" 2>/dev/null; then
                info "Successfully connected to $network"
                return 0
            fi
        done

        warn "Could not connect to any wireless network"
    done
}

# Test network connectivity
test_connectivity() {
    info "Testing network connectivity..."

    # Test local connectivity
    if ping -c 1 192.168.1.1 &>/dev/null; then
        info "Local network connectivity: OK"
    else
        warn "Local network connectivity: FAILED"
    fi

    # Test internet connectivity
    if ping -c 1 8.8.8.8 &>/dev/null; then
        info "Internet connectivity: OK"

        # Update system time
        if command -v ntpdate &>/dev/null; then
            ntpdate pool.ntp.org || true
        fi

        return 0
    else
        warn "Internet connectivity: FAILED"
        return 1
    fi
}

# Configure DNS
configure_dns() {
    info "Configuring DNS..."

    # Backup existing resolv.conf
    cp /etc/resolv.conf /etc/resolv.conf.backup 2>/dev/null || true

    # Set DNS servers
    cat > /etc/resolv.conf << 'EOF'
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
EOF

    info "DNS configured"
}

# Configure hostname
configure_hostname() {
    info "Configuring hostname..."

    # Generate unique hostname based on MAC address
    local mac_addr=$(ip link show | grep -A1 'link/ether' | head -1 | awk '{print $2}' | tr -d ':')
    local hostname="uai-node-${mac_addr: -6}"

    hostnamectl set-hostname "$hostname"

    # Update /etc/hosts
    sed -i "s/127.0.1.1.*/127.0.1.1\t$hostname/" /etc/hosts 2>/dev/null || true

    info "Hostname set to: $hostname"
}

# Configure firewall
configure_firewall() {
    info "Configuring firewall..."

    # Allow essential services
    ufw --force enable
    ufw allow ssh
    ufw allow 2376/tcp  # Docker Swarm
    ufw allow 7946/tcp  # Docker Swarm
    ufw allow 7946/udp  # Docker Swarm
    ufw allow 4789/udp  # Docker Swarm overlay
    ufw allow 8500/tcp  # Consul
    ufw allow 8600/tcp  # Consul DNS
    ufw allow 80/tcp    # HTTP
    ufw allow 443/tcp   # HTTPS
    ufw allow 8000/tcp  # UAI API
    ufw allow 3000/tcp  # Grafana
    ufw allow 9090/tcp  # Prometheus

    info "Firewall configured"
}

# Main function
main() {
    log "🌐 Starting UAI zero-configuration network setup..."

    detect_interfaces

    # Try wired first, then wireless
    if [[ ${#WIRED_INTERFACES[@]} -gt 0 ]]; then
        configure_wired
    fi

    if [[ ${#WIRELESS_INTERFACES[@]} -gt 0 ]]; then
        configure_wireless
    fi

    configure_dns
    configure_hostname
    configure_firewall

    if test_connectivity; then
        log "✅ Network configuration completed successfully"
        exit 0
    else
        log "⚠️ Network configuration completed with warnings"
        exit 1
    fi
}

# Run main function
main "$@"