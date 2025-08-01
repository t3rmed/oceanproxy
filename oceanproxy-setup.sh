#!/bin/bash

# 🌊 OceanProxy - Complete Server Setup Script
# Automated deployment for your whitelabel HTTP proxy service
# Author: OceanProxy Team
# Version: 1.0.0

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_VERSION="1.0.0"
INSTALL_DIR="/opt/oceanproxy"
LOG_DIR="/var/log/oceanproxy"
CONFIG_DIR="/etc/oceanproxy"
SERVICE_USER="oceanproxy"
REPO_URL="https://github.com/t3rmed/oceanproxy.git"

# Default values
DEFAULT_DOMAIN="oceanproxy.io"
DEFAULT_API_PORT="9090"
DEFAULT_BEARER_TOKEN=""
DEFAULT_PROXIES_FO_API_KEY=""
DEFAULT_NETTIFY_API_KEY=""

# Runtime flags
UNATTENDED=false
SKIP_DEPS=false
SKIP_SSL=false
DEV_MODE=false

# Function definitions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
    exit 1
}

banner() {
    echo -e "${BLUE}"
    cat << 'EOF'
    ╔═══════════════════════════════════════════════════════════╗
    ║                    🌊 OceanProxy Setup                    ║
    ║            Whitelabel HTTP Proxy Service                  ║
    ║                                                           ║
    ║  Transform into a proxy reseller with your own brand!     ║
    ╚═══════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    echo "Version: $SCRIPT_VERSION"
    echo
}

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

OceanProxy Server Setup Script

OPTIONS:
    --unattended            Run in unattended mode (requires env vars)
    --skip-deps            Skip dependency installation
    --skip-ssl             Skip SSL certificate setup
    --dev-mode             Development mode (local testing)
    --help                 Show this help message

ENVIRONMENT VARIABLES (for unattended mode):
    GITHUB_TOKEN          GitHub personal access token
    GITHUB_USERNAME       GitHub username (optional)
    PROXIES_FO_API_KEY    Proxies.fo API key
    NETTIFY_API_KEY       Nettify.xyz API key
    DOMAIN                Your branded domain (default: oceanproxy.io)
    BEARER_TOKEN          API authentication token
    API_PORT              API server port (default: 9090)

EXAMPLES:
    # Interactive setup
    sudo ./oceanproxy-setup.sh

    # Unattended setup
    sudo GITHUB_TOKEN="ghp_xxx" \\
         PROXIES_FO_API_KEY="your_key" \\
         NETTIFY_API_KEY="your_key" \\
         DOMAIN="myproxy.com" \\
         BEARER_TOKEN="secure_token" \\
         ./oceanproxy-setup.sh --unattended

EOF
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root. Use: sudo $0"
    fi
}

check_os() {
    if [[ ! -f /etc/os-release ]]; then
        error "Cannot determine OS version. This script supports Ubuntu/Debian and CentOS/RHEL."
    fi
    
    source /etc/os-release
    
    case $ID in
        ubuntu|debian)
            OS_TYPE="debian"
            PACKAGE_MANAGER="apt"
            log "Detected: $PRETTY_NAME"
            ;;
        centos|rhel|rocky|almalinux)
            OS_TYPE="rhel"
            PACKAGE_MANAGER="yum"
            log "Detected: $PRETTY_NAME"
            ;;
        *)
            error "Unsupported OS: $ID. This script supports Ubuntu/Debian and CentOS/RHEL."
            ;;
    esac
}

gather_config() {
    if [[ "$UNATTENDED" == "true" ]]; then
        # Validate required environment variables
        [[ -z "${PROXIES_FO_API_KEY:-}" ]] && error "PROXIES_FO_API_KEY environment variable is required"
        [[ -z "${NETTIFY_API_KEY:-}" ]] && error "NETTIFY_API_KEY environment variable is required"
        [[ -z "${BEARER_TOKEN:-}" ]] && error "BEARER_TOKEN environment variable is required"
        
        DOMAIN="${DOMAIN:-$DEFAULT_DOMAIN}"
        API_PORT="${API_PORT:-$DEFAULT_API_PORT}"
        
        log "Using unattended mode with provided configuration"
    else
        # Interactive configuration
        echo
        log "Gathering configuration information..."
        echo
        
        read -p "Enter your domain (e.g., oceanproxy.io): " -i "$DEFAULT_DOMAIN" -e DOMAIN
        [[ -z "$DOMAIN" ]] && DOMAIN="$DEFAULT_DOMAIN"
        
        read -p "Enter API port [$DEFAULT_API_PORT]: " -i "$DEFAULT_API_PORT" -e API_PORT
        [[ -z "$API_PORT" ]] && API_PORT="$DEFAULT_API_PORT"
        
        read -p "Enter your Proxies.fo API key: " -s PROXIES_FO_API_KEY
        echo
        [[ -z "$PROXIES_FO_API_KEY" ]] && error "Proxies.fo API key is required"
        
        read -p "Enter your Nettify API key: " -s NETTIFY_API_KEY
        echo
        [[ -z "$NETTIFY_API_KEY" ]] && error "Nettify API key is required"
        
        read -p "Enter Bearer token for API authentication: " -s BEARER_TOKEN
        echo
        [[ -z "$BEARER_TOKEN" ]] && error "Bearer token is required"
        
        echo
        read -p "GitHub username (optional): " GITHUB_USERNAME
        read -p "GitHub personal access token (for private repos): " -s GITHUB_TOKEN
        echo
    fi
    
    # Display configuration summary
    echo
    log "Configuration Summary:"
    echo "  Domain: $DOMAIN"
    echo "  API Port: $API_PORT"
    echo "  GitHub User: ${GITHUB_USERNAME:-'(not set)'}"
    echo "  Proxies.fo API: ${PROXIES_FO_API_KEY:0:8}..."
    echo "  Nettify API: ${NETTIFY_API_KEY:0:8}..."
    echo "  Bearer Token: ${BEARER_TOKEN:0:8}..."
    echo
    
    if [[ "$UNATTENDED" != "true" ]]; then
        read -p "Continue with this configuration? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Setup cancelled by user"
            exit 0
        fi
    fi
}

install_dependencies() {
    if [[ "$SKIP_DEPS" == "true" ]]; then
        log "Skipping dependency installation"
        return
    fi
    
    log "Installing system dependencies..."
    
    if [[ "$OS_TYPE" == "debian" ]]; then
        # Update package lists
        apt update
        
        # Install dependencies
        DEBIAN_FRONTEND=noninteractive apt install -y \
            curl \
            wget \
            git \
            jq \
            htop \
            net-tools \
            lsof \
            nginx \
            fail2ban \
            ufw \
            certbot \
            python3-certbot-nginx \
            build-essential \
            golang-go \
            supervisor
            
        # Install 3proxy from source if not available
        if ! command -v 3proxy &> /dev/null; then
            log "Installing 3proxy from source..."
            cd /tmp
            git clone https://github.com/3proxy/3proxy.git
            cd 3proxy
            make -f Makefile.Linux
            make -f Makefile.Linux install
            cd /
            rm -rf /tmp/3proxy
        fi
        
    elif [[ "$OS_TYPE" == "rhel" ]]; then
        # Enable EPEL repository
        yum install -y epel-release
        
        # Install dependencies
        yum install -y \
            curl \
            wget \
            git \
            jq \
            htop \
            net-tools \
            lsof \
            nginx \
            fail2ban \
            firewalld \
            certbot \
            python3-certbot-nginx \
            gcc \
            make \
            golang \
            supervisor
            
        # Install 3proxy from source
        if ! command -v 3proxy &> /dev/null; then
            log "Installing 3proxy from source..."
            cd /tmp
            git clone https://github.com/3proxy/3proxy.git
            cd 3proxy
            make -f Makefile.Linux
            make -f Makefile.Linux install
            cd /
            rm -rf /tmp/3proxy
        fi
    fi
    
    # Verify installations
    log "Verifying installations..."
    for cmd in nginx 3proxy go git jq curl; do
        if ! command -v $cmd &> /dev/null; then
            error "$cmd is not installed or not in PATH"
        fi
    done
    
    log "All dependencies installed successfully"
}

setup_user_and_directories() {
    log "Setting up user and directories..."
    
    # Create system user
    if ! id "$SERVICE_USER" &>/dev/null; then
        useradd -r -s /bin/false -d "$INSTALL_DIR" "$SERVICE_USER"
        log "Created user: $SERVICE_USER"
    fi
    
    # Create directories
    mkdir -p "$INSTALL_DIR"/{app,data,logs,backups}
    mkdir -p "$LOG_DIR"/{nginx,3proxy}
    mkdir -p "$CONFIG_DIR"/{nginx,3proxy}
    
    # Set permissions
    chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR"
    chown -R "$SERVICE_USER:$SERVICE_USER" "$LOG_DIR"
    chown -R root:root "$CONFIG_DIR"
    chmod 755 "$CONFIG_DIR"
    
    # Create log files
    touch "$LOG_DIR/api.log"
    touch "$LOG_DIR/proxies.json"
    echo "[]" > "$LOG_DIR/proxies.json"
    chown "$SERVICE_USER:$SERVICE_USER" "$LOG_DIR"/*.{log,json}
    
    log "User and directories setup complete"
}

clone_repository() {
    log "Cloning OceanProxy repository..."
    
    cd "$INSTALL_DIR"
    
    # Remove existing clone if present
    if [[ -d "app" ]]; then
        rm -rf app
    fi
    
    # Setup git credentials if provided
    if [[ -n "${GITHUB_USERNAME:-}" && -n "${GITHUB_TOKEN:-}" ]]; then
        git config --global credential.helper store
        echo "https://$GITHUB_USERNAME:$GITHUB_TOKEN@github.com" > /root/.git-credentials
    fi
    
    # Clone repository
    sudo -u "$SERVICE_USER" git clone "$REPO_URL" app
    
    # Set ownership
    chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR/app"
    
    log "Repository cloned successfully"
}

build_application() {
    log "Building Go application..."
    
    cd "$INSTALL_DIR/app/backend"
    
    # Initialize Go modules
    sudo -u "$SERVICE_USER" go mod tidy
    
    # Build the application
    sudo -u "$SERVICE_USER" go build -o exec/oceanproxy cmd/main.go
    
    # Make scripts executable
    chmod +x scripts/*.sh
    
    # Verify build
    if [[ ! -f "exec/oceanproxy" ]]; then
        error "Failed to build oceanproxy binary"
    fi
    
    log "Application built successfully"
}

create_configuration() {
    log "Creating configuration files..."
    
    # Create environment file
    cat > "$INSTALL_DIR/app/backend/exec/.env" << EOF
# OceanProxy Configuration
API_KEY=$PROXIES_FO_API_KEY
BEARER_TOKEN=$BEARER_TOKEN
DOMAIN=$DOMAIN
NETTIFY_API_KEY=$NETTIFY_API_KEY
PORT=$API_PORT
HOST=0.0.0.0

# Logging
LOG_LEVEL=info
LOG_FILE=$LOG_DIR/api.log

# Paths
PROXY_LOG_FILE=$LOG_DIR/proxies.json
SCRIPT_DIR=$INSTALL_DIR/app/backend/scripts
EOF
    
    chown "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR/app/backend/exec/.env"
    chmod 600 "$INSTALL_DIR/app/backend/exec/.env"
    
    log "Configuration files created"
}

configure_nginx() {
    log "Configuring nginx..."
    
    # Backup original configuration
    cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup
    
    # Create stream configuration
    cat > /etc/nginx/conf.d/oceanproxy-stream.conf << 'EOF'
# OceanProxy Stream Module Configuration
stream {
    log_format proxy '$remote_addr [$time_local] '
                    '$protocol $status $bytes_sent $bytes_received '
                    '$session_time "$upstream_addr" '
                    '"$upstream_bytes_sent" "$upstream_bytes_received" "$upstream_connect_time"';

    # USA Proxy Pool (Port 1337)
    upstream usa_proxies {
        least_conn;
        server 127.0.0.1:10000 max_fails=3 fail_timeout=30s;
        # Additional servers will be added dynamically by scripts
    }

    server {
        listen 1337;
        proxy_pass usa_proxies;
        proxy_timeout 30s;
        proxy_connect_timeout 5s;
        proxy_responses 1;
        proxy_bind $remote_addr transparent;
        
        access_log /var/log/oceanproxy/nginx/usa_access.log proxy;
        error_log /var/log/oceanproxy/nginx/usa_error.log;
    }

    # EU Proxy Pool (Port 1338)
    upstream eu_proxies {
        least_conn;
        server 127.0.0.1:10001 max_fails=3 fail_timeout=30s;
        # Additional servers will be added dynamically by scripts
    }

    server {
        listen 1338;
        proxy_pass eu_proxies;
        proxy_timeout 30s;
        proxy_connect_timeout 5s;
        proxy_responses 1;
        proxy_bind $remote_addr transparent;
        
        access_log /var/log/oceanproxy/nginx/eu_access.log proxy;
        error_log /var/log/oceanproxy/nginx/eu_error.log;
    }

    # Alpha Proxy Pool (Port 9876)
    upstream alpha_proxies {
        least_conn;
        server 127.0.0.1:10002 max_fails=3 fail_timeout=30s;
        # Additional servers will be added dynamically by scripts
    }

    server {
        listen 9876;
        proxy_pass alpha_proxies;
        proxy_timeout 30s;
        proxy_connect_timeout 5s;
        proxy_responses 1;
        proxy_bind $remote_addr transparent;
        
        access_log /var/log/oceanproxy/nginx/alpha_access.log proxy;
        error_log /var/log/oceanproxy/nginx/alpha_error.log;
    }
}
EOF

    # Create HTTP configuration for API and management
    cat > /etc/nginx/sites-available/oceanproxy << EOF
# OceanProxy API and Management
server {
    listen 80;
    server_name api.$DOMAIN $DOMAIN;
    
    # API proxy
    location /api/ {
        proxy_pass http://127.0.0.1:$API_PORT/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # Security headers
        add_header X-Content-Type-Options nosniff;
        add_header X-Frame-Options DENY;
        add_header X-XSS-Protection "1; mode=block";
    }
    
    # Health check endpoint
    location /health {
        proxy_pass http://127.0.0.1:$API_PORT/health;
        access_log off;
    }
    
    # Default location
    location / {
        return 200 "OceanProxy Service Running";
        add_header Content-Type text/plain;
    }
    
    access_log /var/log/oceanproxy/nginx/api_access.log;
    error_log /var/log/oceanproxy/nginx/api_error.log;
}
EOF

    # Enable site
    ln -sf /etc/nginx/sites-available/oceanproxy /etc/nginx/sites-enabled/
    
    # Remove default site
    rm -f /etc/nginx/sites-enabled/default
    
    # Test configuration
    nginx -t || error "nginx configuration test failed"
    
    log "nginx configured successfully"
}

create_systemd_services() {
    log "Creating systemd services..."
    
    # OceanProxy API service
    cat > /etc/systemd/system/oceanproxy-api.service << EOF
[Unit]
Description=OceanProxy API Server
After=network.target nginx.service
Wants=nginx.service

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR/app/backend
ExecStart=$INSTALL_DIR/app/backend/exec/oceanproxy
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=5
KillMode=mixed
TimeoutStopSec=30

# Environment
Environment=PATH=/usr/local/bin:/usr/bin:/bin
EnvironmentFile=$INSTALL_DIR/app/backend/exec/.env

# Security
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$LOG_DIR $INSTALL_DIR/data

# Logging
StandardOutput=append:$LOG_DIR/api.log
StandardError=append:$LOG_DIR/api.log
SyslogIdentifier=oceanproxy-api

[Install]
WantedBy=multi-user.target
EOF

    # OceanProxy Monitor service
    cat > /etc/systemd/system/oceanproxy-monitor.service << EOF
[Unit]
Description=OceanProxy Health Monitor
After=oceanproxy-api.service
Requires=oceanproxy-api.service

[Service]
Type=oneshot
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR/app/backend/scripts
ExecStart=$INSTALL_DIR/app/backend/scripts/ensure_proxies.sh --restart --quiet
StandardOutput=append:$LOG_DIR/monitor.log
StandardError=append:$LOG_DIR/monitor.log

[Install]
WantedBy=multi-user.target
EOF

    # Monitor timer
    cat > /etc/systemd/system/oceanproxy-monitor.timer << EOF
[Unit]
Description=Run OceanProxy Health Monitor
Requires=oceanproxy-monitor.service

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
AccuracySec=1min

[Install]
WantedBy=timers.target
EOF

    # Cleanup service for expired plans
    cat > /etc/systemd/system/oceanproxy-cleanup.service << EOF
[Unit]
Description=OceanProxy Cleanup Expired Plans
After=oceanproxy-api.service

[Service]
Type=oneshot
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR/app/backend/scripts
ExecStart=$INSTALL_DIR/app/backend/scripts/check_expired_plans.sh --cleanup
StandardOutput=append:$LOG_DIR/cleanup.log
StandardError=append:$LOG_DIR/cleanup.log

[Install]
WantedBy=multi-user.target
EOF

    # Cleanup timer (daily at 2 AM)
    cat > /etc/systemd/system/oceanproxy-cleanup.timer << EOF
[Unit]
Description=Daily OceanProxy Cleanup
Requires=oceanproxy-cleanup.service

[Timer]
OnCalendar=daily
Persistent=true
AccuracySec=1h

[Install]
WantedBy=timers.target
EOF

    # Reload systemd and enable services
    systemctl daemon-reload
    systemctl enable oceanproxy-api.service
    systemctl enable oceanproxy-monitor.timer
    systemctl enable oceanproxy-cleanup.timer
    
    log "Systemd services created and enabled"
}

configure_firewall() {
    log "Configuring firewall..."
    
    if [[ "$OS_TYPE" == "debian" ]]; then
        # Configure UFW
        ufw --force reset
        ufw default deny incoming
        ufw default allow outgoing
        
        # Allow SSH
        ufw allow 22/tcp
        
        # Allow HTTP/HTTPS
        ufw allow 80/tcp
        ufw allow 443/tcp
        
        # Allow proxy ports
        ufw allow 1337/tcp
        ufw allow 1338/tcp
        ufw allow 9876/tcp
        
        # Allow API port (consider restricting in production)
        ufw allow $API_PORT/tcp
        
        # Enable firewall
        ufw --force enable
        
    elif [[ "$OS_TYPE" == "rhel" ]]; then
        # Configure firewalld
        systemctl enable firewalld
        systemctl start firewalld
        
        # Allow services
        firewall-cmd --permanent --add-service=http
        firewall-cmd --permanent --add-service=https
        firewall-cmd --permanent --add-service=ssh
        
        # Allow proxy ports
        firewall-cmd --permanent --add-port=1337/tcp
        firewall-cmd --permanent --add-port=1338/tcp
        firewall-cmd --permanent --add-port=9876/tcp
        firewall-cmd --permanent --add-port=$API_PORT/tcp
        
        # Reload firewall
        firewall-cmd --reload
    fi
    
    log "Firewall configured successfully"
}

configure_fail2ban() {
    log "Configuring fail2ban..."
    
    # Create OceanProxy jail
    cat > /etc/fail2ban/jail.d/oceanproxy.conf << 'EOF'
[oceanproxy-api]
enabled = true
port = 9090
filter = oceanproxy-api
logpath = /var/log/oceanproxy/api.log
maxretry = 5
bantime = 3600
findtime = 600

[oceanproxy-proxy]
enabled = true
port = 1337,1338,9876
filter = nginx-noproxy
logpath = /var/log/oceanproxy/nginx/*_access.log
maxretry = 50
bantime = 1800
findtime = 300
EOF

    # Create custom filter
    cat > /etc/fail2ban/filter.d/oceanproxy-api.conf << 'EOF'
[Definition]
failregex = ^.*\[ERROR\].*Authentication failed.*<HOST>.*$
            ^.*\[ERROR\].*Invalid request.*<HOST>.*$
            ^.*\[ERROR\].*Unauthorized access.*<HOST>.*$
ignoreregex =
EOF

    # Restart fail2ban
    systemctl enable fail2ban
    systemctl restart fail2ban
    
    log "fail2ban configured successfully"
}

setup_ssl() {
    if [[ "$SKIP_SSL" == "true" ]]; then
        log "Skipping SSL setup"
        return
    fi
    
    log "Setting up SSL certificates..."
    
    # Check if domain resolves to this server
    SERVER_IP=$(curl -s ifconfig.me)
    DOMAIN_IP=$(dig +short "$DOMAIN" | tail -n1)
    
    if [[ "$SERVER_IP" != "$DOMAIN_IP" ]]; then
        warn "Domain $DOMAIN does not resolve to this server ($SERVER_IP vs $DOMAIN_IP)"
        warn "SSL setup will be skipped. Configure DNS first, then run: certbot --nginx -d $DOMAIN"
        return
    fi
    
    # Obtain certificates
    certbot --nginx -d "$DOMAIN" -d "api.$DOMAIN" -d "usa.$DOMAIN" -d "eu.$DOMAIN" -d "alpha.$DOMAIN" --non-interactive --agree-tos --email "admin@$DOMAIN" --no-eff-email
    
    # Setup auto-renewal
    (crontab -l 2>/dev/null; echo "0 12 * * * /usr/bin/certbot renew --quiet") | crontab -
    
    log "SSL certificates configured"
}

optimize_system() {
    log "Optimizing system performance..."
    
    # Increase file descriptor limits
    cat >> /etc/security/limits.conf << EOF
# OceanProxy optimizations
$SERVICE_USER soft nofile 65536
$SERVICE_USER hard nofile 65536
root soft nofile 65536
root hard nofile 65536
EOF

    # Kernel parameter tuning
    cat >> /etc/sysctl.conf << 'EOF'
# OceanProxy network optimizations
net.core.somaxconn = 65536
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_max_syn_backlog = 65536
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_rmem = 4096 65536 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
EOF

    # Apply kernel parameters
    sysctl -p
    
    # nginx worker optimization
    CPU_CORES=$(nproc)
    sed -i "s/worker_processes auto;/worker_processes $CPU_CORES;/" /etc/nginx/nginx.conf
    sed -i "s/worker_connections 768;/worker_connections 4096;/" /etc/nginx/nginx.conf
    
    log "System optimizations applied"
}

setup_monitoring() {
    log "Setting up monitoring and logging..."
    
    # Create log rotation configuration
    cat > /etc/logrotate.d/oceanproxy << 'EOF'
/var/log/oceanproxy/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 644 oceanproxy oceanproxy
    postrotate
        systemctl reload nginx > /dev/null 2>&1 || true
        systemctl reload oceanproxy-api > /dev/null 2>&1 || true
    endscript
}

/var/log/oceanproxy/nginx/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 644 nginx nginx
    postrotate
        systemctl reload nginx > /dev/null 2>&1 || true
    endscript
}
EOF

    # Create backup script
    cat > "$INSTALL_DIR/scripts/backup.sh" << 'EOF'
#!/bin/bash
# OceanProxy Backup Script

BACKUP_DIR="/opt/oceanproxy/backups"
DATE=$(date +%Y%m%d_%H%M%S)

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Backup proxy data
cp /var/log/oceanproxy/proxies.json "$BACKUP_DIR/proxies_$DATE.json"

# Backup configuration
tar -czf "$BACKUP_DIR/config_$DATE.tar.gz" \
    /opt/oceanproxy/app/backend/exec/.env \
    /etc/nginx/conf.d/oceanproxy-stream.conf \
    /etc/nginx/sites-available/oceanproxy

# Keep only last 7 days of backups
find "$BACKUP_DIR" -name "*.json" -mtime +7 -delete
find "$BACKUP_DIR" -name "*.tar.gz" -mtime +7 -delete

echo "Backup completed: $DATE"
EOF

    chmod +x "$INSTALL_DIR/scripts/backup.sh"
    chown "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR/scripts/backup.sh"
    
    # Add backup to crontab
    (crontab -u "$SERVICE_USER" -l 2>/dev/null; echo "0 3 * * * $INSTALL_DIR/scripts/backup.sh") | crontab -u "$SERVICE_USER" -
    
    log "Monitoring and logging setup complete"
}

start_services() {
    log "Starting services..."
    
    # Start nginx
    systemctl enable nginx
    systemctl restart nginx
    
    # Start OceanProxy API
    systemctl start oceanproxy-api
    
    # Start monitoring timer
    systemctl start oceanproxy-monitor.timer
    systemctl start oceanproxy-cleanup.timer
    
    # Wait for services to start
    sleep 5
    
    log "Services started successfully"
}

test_installation() {
    log "Testing installation..."
    
    # Test API health
    log "Testing API health endpoint..."
    if curl -s -f "http://localhost:$API_PORT/health" > /dev/null; then
        log "✅ API health check passed"
    else
        error "❌ API health check failed"
    fi
    
    # Test nginx configuration
    log "Testing nginx configuration..."
    if nginx -t > /dev/null 2>&1; then
        log "✅ nginx configuration valid"
    else
        error "❌ nginx configuration invalid"
    fi
    
    # Test service status
    log "Checking service status..."
    for service in nginx oceanproxy-api; do
        if systemctl is-active --quiet "$service"; then
            log "✅ $service is running"
        else
            warn "⚠️  $service is not running"
        fi
    done
    
    # Test proxy ports
    log "Testing proxy port accessibility..."
    for port in 1337 1338 9876; do
        if netstat -tlnp | grep -q ":$port "; then
            log "✅ Port $port is listening"
        else
            warn "⚠️  Port $port is not listening"
        fi
    done
    
    log "Installation testing complete"
}

create_test_plan() {
    log "Creating test proxy plan..."
    
    # Generate test credentials
    TEST_USERNAME="test_$(date +%s)"
    TEST_PASSWORD="testpass123"
    
    # Create test plan
    RESPONSE=$(curl -s -X POST "http://localhost:$API_PORT/plan" \
        -H "Authorization: Bearer $BEARER_TOKEN" \
        -d "reseller=residential&bandwidth=1&username=$TEST_USERNAME&password=$TEST_PASSWORD" 2>/dev/null)
    
    if echo "$RESPONSE" | jq -e '.success == true' > /dev/null 2>&1; then
        log "✅ Test plan created successfully"
        
        # Extract proxy endpoints
        PROXIES=$(echo "$RESPONSE" | jq -r '.proxies[]')
        
        echo
        log "Test proxy endpoints created:"
        echo "$PROXIES" | while read -r proxy; do
            echo "  $proxy"
        done
        
        # Test connectivity
        log "Testing proxy connectivity..."
        FIRST_PROXY=$(echo "$PROXIES" | head -n1)
        if echo "$FIRST_PROXY" | grep -q "://"; then
            PROXY_URL=$(echo "$FIRST_PROXY" | sed 's|http://||')
            if curl -s --max-time 10 -x "$PROXY_URL" "http://httpbin.org/ip" > /dev/null; then
                log "✅ Proxy connectivity test passed"
            else
                warn "⚠️  Proxy connectivity test failed (this may be normal if upstream credentials need activation)"
            fi
        fi
        
    else
        warn "⚠️  Test plan creation failed: $RESPONSE"
    fi
}

print_summary() {
    echo
    log "🎉 OceanProxy Installation Complete!"
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    echo -e "${GREEN}📊 System Information:${NC}"
    echo "  • Installation Directory: $INSTALL_DIR"
    echo "  • Log Directory: $LOG_DIR"
    echo "  • Service User: $SERVICE_USER"
    echo "  • Domain: $DOMAIN"
    echo "  • API Port: $API_PORT"
    echo
    echo -e "${GREEN}🌐 Service Endpoints:${NC}"
    echo "  • API Health: http://localhost:$API_PORT/health"
    echo "  • USA Proxy: usa.$DOMAIN:1337"
    echo "  • EU Proxy: eu.$DOMAIN:1338" 
    echo "  • Alpha Proxy: alpha.$DOMAIN:9876"
    echo
    echo -e "${GREEN}🔧 Management Commands:${NC}"
    echo "  • Check API status: sudo systemctl status oceanproxy-api"
    echo "  • View API logs: sudo tail -f $LOG_DIR/api.log"
    echo "  • Test all proxies: cd $INSTALL_DIR/app/backend/scripts && ./curl_commands.sh"
    echo "  • Health check: cd $INSTALL_DIR/app/backend/scripts && ./ensure_proxies.sh"
    echo "  • Create plan: curl -X POST -H 'Authorization: Bearer $BEARER_TOKEN' \\"
    echo "                      -d 'reseller=residential&bandwidth=5&username=USER&password=PASS' \\"
    echo "                      http://localhost:$API_PORT/plan"
    echo
    echo -e "${GREEN}📁 Important Files:${NC}"
    echo "  • Configuration: $INSTALL_DIR/app/backend/exec/.env"
    echo "  • Proxy Database: $LOG_DIR/proxies.json"
    echo "  • nginx Config: /etc/nginx/conf.d/oceanproxy-stream.conf"
    echo "  • Scripts: $INSTALL_DIR/app/backend/scripts/"
    echo
    echo -e "${GREEN}🔐 Security:${NC}"
    echo "  • Firewall: Configured with UFW/firewalld"
    echo "  • fail2ban: Active protection enabled"
    echo "  • SSL: $([[ "$SKIP_SSL" == "true" ]] && echo "Skipped (use certbot manually)" || echo "Configured with Let's Encrypt")"
    echo
    echo -e "${GREEN}📈 Next Steps:${NC}"
    echo "  1. Update DNS records to point subdomains to this server"
    echo "  2. Test proxy creation and connectivity"
    echo "  3. Build customer dashboard frontend"
    echo "  4. Integrate payment processing"
    echo "  5. Set up monitoring and alerting"
    echo
    echo -e "${YELLOW}⚠️  Important Notes:${NC}"
    echo "  • Keep your API keys secure and rotate them regularly"
    echo "  • Monitor log files for any issues"
    echo "  • Set up regular backups of proxy data"
    echo "  • Test failover procedures"
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    log "Your OceanProxy whitelabel service is ready to generate revenue! 🌊💰"
    echo
}

cleanup_on_error() {
    error "Setup failed. Cleaning up..."
    
    # Stop services
    systemctl stop oceanproxy-api 2>/dev/null || true
    systemctl stop oceanproxy-monitor.timer 2>/dev/null || true
    systemctl stop oceanproxy-cleanup.timer 2>/dev/null || true
    
    # Remove systemd services
    rm -f /etc/systemd/system/oceanproxy-*.service
    rm -f /etc/systemd/system/oceanproxy-*.timer
    systemctl daemon-reload
    
    # Remove nginx configuration
    rm -f /etc/nginx/conf.d/oceanproxy-stream.conf
    rm -f /etc/nginx/sites-available/oceanproxy
    rm -f /etc/nginx/sites-enabled/oceanproxy
    
    # Restore nginx backup
    if [[ -f /etc/nginx/nginx.conf.backup ]]; then
        mv /etc/nginx/nginx.conf.backup /etc/nginx/nginx.conf
    fi
    
    systemctl reload nginx 2>/dev/null || true
    
    log "Cleanup completed. Check logs for error details."
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --unattended)
            UNATTENDED=true
            shift
            ;;
        --skip-deps)
            SKIP_DEPS=true
            shift
            ;;
        --skip-ssl)
            SKIP_SSL=true
            shift
            ;;
        --dev-mode)
            DEV_MODE=true
            SKIP_SSL=true
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Set error handler
trap cleanup_on_error ERR

# Main execution
main() {
    banner
    
    # Pre-flight checks
    check_root
    check_os
    
    # Configuration
    gather_config
    
    # Installation steps
    install_dependencies
    setup_user_and_directories
    clone_repository
    build_application
    create_configuration
    configure_nginx
    create_systemd_services
    configure_firewall
    configure_fail2ban
    
    if [[ "$SKIP_SSL" != "true" ]]; then
        setup_ssl
    fi
    
    optimize_system
    setup_monitoring
    start_services
    
    # Testing
    test_installation
    
    if [[ "$DEV_MODE" != "true" ]]; then
        create_test_plan
    fi
    
    # Summary
    print_summary
    
    log "Setup completed successfully! 🎉"
}

# Run main function
main "$@"
