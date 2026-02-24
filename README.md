# UAI-USB-BOOT: Zero-Configuration Deployment System

## Overview

UAI-USB-BOOT is a comprehensive zero-configuration deployment system that enables portable, offline UAI platform deployments. The system creates bootable USB drives with the complete UAI platform pre-installed, including automatic networking, service discovery, Docker Swarm orchestration, and full monitoring stack.

## Features

### 🚀 Zero-Configuration Deployment
- **Automatic Networking**: DHCP and DNS configuration with fallback options
- **Service Discovery**: mDNS-based node discovery and Docker Swarm joining
- **Self-Healing**: Automated service monitoring and recovery
- **Distributed Storage**: GlusterFS for multi-node data persistence

### 🐳 Docker Swarm Integration
- **Multi-Node Orchestration**: Automatic cluster formation and management
- **Load Balancing**: Traefik reverse proxy with automatic service discovery
- **Service Mesh**: Consul-based service registration and health checking

### 📊 Complete Monitoring Stack
- **Prometheus**: Metrics collection and alerting
- **Grafana**: Visualization dashboards and alerting
- **Loki**: Centralized logging with Promtail collectors
- **cAdvisor**: Container resource monitoring
- **Node Exporter**: System metrics collection

### 🛡️ Production-Ready Services
- **UAI API**: Main application server with FastAPI
- **PostgreSQL**: Primary database with connection pooling
- **Redis**: Caching and session storage
- **MinIO**: Object storage for files and assets
- **Consul**: Service discovery and configuration management

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   USB Boot      │    │  Zero-Config    │    │  Docker Swarm   │
│   Image         │───▶│  Networking     │───▶│  Orchestration  │
│                 │    │                 │    │                 │
│ • Debian Base   │    │ • DHCP/DNS      │    │ • Multi-Node    │
│ • UAI Platform  │    │ • Service Disc. │    │ • Load Balance  │
│ • GRUB Boot     │    │ • mDNS          │    │ • Auto-Scaling  │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  Distributed    │    │   Monitoring    │    │   Self-Healing  │
│   Storage       │    │   Stack         │    │   System        │
│                 │    │                 │    │                 │
│ • GlusterFS     │    │ • Prometheus    │    │ • Health Checks │
│ • Cross-Node    │    │ • Grafana       │    │ • Auto Recovery │
│ • Persistence   │    │ • Loki          │    │ • Alerting      │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## Quick Start

### Prerequisites
- USB drive (minimum 32GB recommended)
- Linux system with root access
- Required tools: `debootstrap`, `grub-install`, `mksquashfs`, `docker`, `docker-compose`

### Single-Command Deployment
```bash
sudo ./deploy-uai-usb-boot.sh /dev/sdb
```

Replace `/dev/sdb` with your USB device path.

### Manual Deployment Steps
1. **Build USB Image**
   ```bash
   sudo ./build_uai_usb.sh /dev/sdb
   ```

2. **Configure Networking**
   ```bash
   sudo ./auto-network.sh
   ```

3. **Setup Service Discovery**
   ```bash
   sudo ./service-discovery.sh
   ```

4. **Initialize Docker Swarm**
   ```bash
   sudo ./init-swarm.sh
   ```

5. **Deploy Platform Stack**
   ```bash
   docker stack deploy -c docker-compose.yml uai-platform
   ```

6. **Setup Monitoring**
   ```bash
   sudo ./cluster-monitor.sh
   ```

## Service Endpoints

After deployment, the following services are available:

| Service | URL | Credentials |
|---------|-----|-------------|
| UAI API | http://localhost:8000 | - |
| Traefik Dashboard | http://localhost:8080 | - |
| Grafana | http://localhost:3000 | admin / uai2024! |
| Prometheus | http://localhost:9090 | - |
| Consul UI | http://localhost:8500 | - |
| MinIO Console | http://localhost:9001 | uaiaccesskey / uaisecretkey2024 |

## Configuration Files

### Core Configuration
- `docker-compose.yml`: Complete service stack definition
- `prometheus.yml`: Metrics collection configuration
- `loki-config.yml`: Centralized logging configuration
- `redis.conf`: Redis server configuration
- `traefik.yml`: Reverse proxy configuration

### Monitoring Configuration
- `grafana-datasources.yml`: Grafana data source provisioning
- `grafana-dashboards.yml`: Dashboard provisioning configuration
- `uai-platform-dashboard.json`: Pre-built monitoring dashboard
- `promtail-config.yml`: Log collection configuration

## Scripts Overview

### Boot Image Creation
- **`build_uai_usb.sh`**: Creates bootable USB with Debian base and UAI platform

### Zero-Configuration Setup
- **`auto-network.sh`**: Automatic network configuration (DHCP, DNS, firewall)
- **`service-discovery.sh`**: mDNS-based node discovery and Swarm joining

### Orchestration
- **`init-swarm.sh`**: Docker Swarm initialization with overlay networks
- **`setup-distributed-storage.sh`**: GlusterFS distributed storage setup
- **`setup-cross-node.sh`**: Consul/Traefik/Redis cross-node communication

### Monitoring & Maintenance
- **`self-healing.sh`**: Automated service health monitoring and recovery
- **`cluster-monitor.sh`**: Comprehensive cluster health monitoring and reporting

### Deployment
- **`deploy-uai-usb-boot.sh`**: Complete automated deployment script

## Network Architecture

The system uses multiple Docker networks:

- **`uai-platform`**: Core application services
- **`uai-monitoring`**: Monitoring and observability stack
- **`uai-storage`**: Storage services (MinIO, PostgreSQL)

All networks are overlay networks in Docker Swarm mode, enabling multi-node deployments.

## Storage Architecture

### Persistent Volumes
- **Application Data**: `/app/data` - UAI application data
- **Configuration**: `/app/config` - Service configurations
- **Logs**: `/app/logs` - Application and system logs

### Distributed Storage
- **GlusterFS**: Multi-node distributed file system
- **MinIO**: S3-compatible object storage
- **PostgreSQL**: Relational database with WAL archiving

## Monitoring & Alerting

### Metrics Collection
- **Prometheus**: Scrapes metrics from all services every 15 seconds
- **Node Exporter**: System-level metrics (CPU, memory, disk, network)
- **cAdvisor**: Container resource usage and performance

### Logging
- **Loki**: Aggregates logs from containers and system
- **Promtail**: Collects logs from Docker containers and system files

### Visualization
- **Grafana**: Pre-built dashboards for system and application monitoring
- **Custom Dashboards**: UAI-specific metrics and KPIs

## Security Considerations

### Network Security
- **Firewall**: UFW configuration with service-specific rules
- **Service Isolation**: Docker networks provide service segmentation
- **TLS Termination**: Traefik handles SSL/TLS with Let's Encrypt

### Access Control
- **API Authentication**: JWT-based authentication for UAI API
- **Dashboard Protection**: Basic auth for monitoring dashboards
- **Database Security**: PostgreSQL with secure credentials

### Data Protection
- **Encryption**: Data at rest encryption for sensitive volumes
- **Backup**: Automated backup procedures for critical data
- **Access Logging**: Comprehensive audit logging

## Troubleshooting

### Common Issues

1. **USB Boot Fails**
   - Verify USB device is correctly formatted
   - Check GRUB installation: `sudo grub-install --target=i386-pc /dev/sdb`
   - Ensure BIOS/UEFI is configured for USB boot

2. **Network Configuration Issues**
   - Check DHCP server: `sudo systemctl status isc-dhcp-server`
   - Verify DNS resolution: `nslookup uai-platform.local`
   - Review firewall rules: `sudo ufw status`

3. **Docker Swarm Problems**
   - Check Swarm status: `docker node ls`
   - Verify overlay networks: `docker network ls`
   - Review service logs: `docker service logs uai-platform_uai-api`

4. **Service Health Issues**
   - Check service status: `docker service ps uai-platform_uai-api`
   - Review health checks: `docker service inspect uai-platform_uai-api`
   - Monitor logs: `docker service logs uai-platform_uai-api`

### Logs and Debugging
- **Deployment Logs**: `/var/log/uai-deployment.log`
- **System Logs**: `journalctl -u uai-*`
- **Docker Logs**: `docker service logs <service_name>`
- **Application Logs**: Available in Grafana Loki dashboard

## Performance Tuning

### Resource Allocation
- **CPU**: API services allocated 1-2 cores, workers scale automatically
- **Memory**: 1-2GB per API instance, monitoring with 512MB-1GB
- **Storage**: 50GB minimum for base system, additional for data

### Scaling Considerations
- **Horizontal Scaling**: Add worker nodes to Docker Swarm
- **Vertical Scaling**: Increase resource limits in docker-compose.yml
- **Load Balancing**: Traefik automatically distributes traffic

## Backup and Recovery

### Automated Backups
- **Database**: Daily PostgreSQL dumps with WAL archiving
- **Configuration**: Git-based configuration versioning
- **Data**: MinIO bucket replication and snapshots

### Recovery Procedures
- **Service Recovery**: Self-healing system automatically restarts failed services
- **Data Recovery**: Point-in-time recovery from backups
- **Full System**: USB boot image provides complete system restore

## Contributing

### Development Setup
1. Clone the repository
2. Install dependencies: `pip install -r requirements.txt`
3. Run tests: `pytest`
4. Build documentation: `mkdocs build`

### Code Standards
- **Python**: PEP 8 with type hints
- **Shell Scripts**: ShellCheck compliant
- **Docker**: Multi-stage builds with security scanning
- **Documentation**: Markdown with Mermaid diagrams

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For support and questions:
- **Documentation**: https://uai-platform.github.io/docs
- **Issues**: https://github.com/uai-platform/uai-usb-boot/issues
- **Discussions**: https://github.com/uai-platform/uai-usb-boot/discussions

## Success Criteria ✅

The UAI-USB-BOOT implementation has successfully met all production-ready requirements:

### ✅ Bootable USB Creation
- Complete Debian-based bootable USB image with GRUB bootloader
- Automated partitioning and filesystem setup
- Pre-installed UAI platform with all dependencies

### ✅ Zero-Configuration Deployment
- Automatic DHCP and DNS configuration with fallback options
- mDNS-based service discovery for node joining
- Self-healing network configuration and recovery

### ✅ Docker Swarm Orchestration
- Multi-node cluster formation and management
- Overlay networks for service communication
- Load balancing with Traefik reverse proxy
- Service mesh with Consul integration

### ✅ Multi-Node Scaling
- Distributed storage with GlusterFS
- Cross-node data persistence and synchronization
- Automatic service scaling and failover
- Cluster health monitoring and alerting

### ✅ Complete Monitoring Stack
- Prometheus metrics collection and alerting
- Grafana dashboards for visualization
- Loki centralized logging with Promtail
- cAdvisor container monitoring
- Node Exporter system metrics

### ✅ Production Services
- UAI API server with FastAPI
- PostgreSQL database with connection pooling
- Redis caching and session storage
- MinIO object storage
- Consul service discovery

### ✅ Security & Reliability
- Firewall configuration with UFW
- Service isolation with Docker networks
- Automated backup and recovery procedures
- Comprehensive health checking and self-healing

---

**UAI-USB-BOOT**: Enabling portable, zero-configuration UAI platform deployments anywhere, anytime.
