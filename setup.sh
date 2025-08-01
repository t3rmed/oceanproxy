#!/bin/bash

# 🌊 OceanProxy - Complete Server Setup Script
# Save this as oceanproxy-setup.sh and run with: sudo ./oceanproxy-setup.sh

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
        
        read -p "Enter your domain (e.g., oceanproxy.io): " DOMAIN
        [[ -z "$DOMAIN" ]] && DOMAIN="$DEFAULT_DOMAIN"
        
        read -p "Enter API port [$DEFAULT_API_PORT]: " API_PORT
        [[ -z "$API_PORT" ]] && API_PORT="$DEFAULT_API_PORT"
        
        echo "Enter your Proxies.fo API key:"
        read -s PROXIES_FO_API_KEY
        echo
        [[ -z "$PROXIES_FO_API_KEY" ]] && error "Proxies.fo API key is required"
        
        echo "Enter your Nettify API key:"
        read -s NETTIFY_API_KEY
        echo
        [[ -z "$NETTIFY_API_KEY" ]] && error "Nettify API key is required"
        
        echo "Enter Bearer token for API authentication:"
        read -s BEARER_TOKEN
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
        
        # Remove old Go if installed
        apt remove -y golang-go golang-1.* || true
        
        # Install dependencies (without golang-go)
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
            supervisor
        
        # Install latest Go
        log "Installing Go 1.21..."
        cd /tmp
        wget -q https://go.dev/dl/go1.21.5.linux-amd64.tar.gz
        rm -rf /usr/local/go
        tar -C /usr/local -xzf go1.21.5.linux-amd64.tar.gz
        echo 'export PATH=$PATH:/usr/local/go/bin' > /etc/profile.d/go.sh
        export PATH=$PATH:/usr/local/go/bin
        rm -f go1.21.5.linux-amd64.tar.gz
        
        # Install 3proxy from source if not available
        if ! command -v 3proxy &> /dev/null; then
            log "Installing 3proxy from source..."
            cd /tmp
            git clone https://github.com/3proxy/3proxy.git || error "Failed to clone 3proxy"
            cd 3proxy
            make -f Makefile.Linux || error "Failed to build 3proxy"
            make -f Makefile.Linux install || error "Failed to install 3proxy"
            cd /
            rm -rf /tmp/3proxy
        fi
        
    elif [[ "$OS_TYPE" == "rhel" ]]; then
        # Enable EPEL repository
        yum install -y epel-release
        
        # Remove old Go if installed
        yum remove -y golang || true
        
        # Install dependencies (without golang)
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
            supervisor
        
        # Install latest Go
        log "Installing Go 1.21..."
        cd /tmp
        wget -q https://go.dev/dl/go1.21.5.linux-amd64.tar.gz
        rm -rf /usr/local/go
        tar -C /usr/local -xzf go1.21.5.linux-amd64.tar.gz
        echo 'export PATH=$PATH:/usr/local/go/bin' > /etc/profile.d/go.sh
        export PATH=$PATH:/usr/local/go/bin
        rm -f go1.21.5.linux-amd64.tar.gz
        
        # Install 3proxy from source
        if ! command -v 3proxy &> /dev/null; then
            log "Installing 3proxy from source..."
            cd /tmp
            git clone https://github.com/3proxy/3proxy.git || error "Failed to clone 3proxy"
            cd 3proxy
            make -f Makefile.Linux || error "Failed to build 3proxy"
            make -f Makefile.Linux install || error "Failed to install 3proxy"
            cd /
            rm -rf /tmp/3proxy
        fi
    fi
    
    # Ensure PATH includes Go
    export PATH=$PATH:/usr/local/go/bin
    
    # Verify installations
    log "Verifying installations..."
    for cmd in nginx git jq curl; do
        if ! command -v $cmd &> /dev/null; then
            error "$cmd is not installed or not in PATH"
        fi
    done
    
    # Verify Go installation
    if ! command -v go &> /dev/null; then
        error "Go is not installed or not in PATH"
    fi
    
    GO_VERSION=$(go version 2>/dev/null || echo "unknown")
    log "Go version: $GO_VERSION"
    
    # 3proxy may be installed as /usr/local/bin/3proxy
    if ! command -v 3proxy &> /dev/null && [[ ! -f /usr/local/bin/3proxy ]]; then
        error "3proxy is not installed or not accessible"
    fi
    
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
    mkdir -p "$INSTALL_DIR"/{app,data,logs,backups,scripts}
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
    sudo -u "$SERVICE_USER" git clone "$REPO_URL" app || error "Failed to clone repository. Check your GitHub credentials and repository access."
    
    # Set ownership
    chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR/app"
    
    log "Repository cloned successfully"
}

build_application() {
    log "Building Go application..."
    
    # Ensure Go is in PATH
    export PATH=$PATH:/usr/local/go/bin
    
    cd "$INSTALL_DIR/app/backend"
    
    # Check if backend directory exists
    if [[ ! -d "cmd" ]]; then
        error "Backend structure not found. Please check your repository structure."
    fi
    
    # Get the ACTUAL installed Go version (we installed 1.21.5)
    INSTALLED_GO_VERSION="1.21"
    log "Using Go version: $INSTALLED_GO_VERSION"
    
    # Fix go.mod - replace ANY go version with 1.21
    if [[ -f "go.mod" ]]; then
        log "Original go.mod content:"
        cat go.mod
        
        log "Fixing go.mod to use Go $INSTALLED_GO_VERSION..."
        # Replace any "go 1.XX" or "go 1.XX.X" with "go 1.21"
        sudo -u "$SERVICE_USER" sed -i 's/^go [0-9]\+\.[0-9]\+\(\.[0-9]\+\)\?$/go 1.21/' go.mod
        
        log "Fixed go.mod content:"
        cat go.mod
    else
        # Create go.mod if it doesn't exist
        log "Creating go.mod file..."
        sudo -u "$SERVICE_USER" go mod init oceanproxy
        sudo -u "$SERVICE_USER" sed -i "s/go .*/go $INSTALLED_GO_VERSION/" go.mod
        log "Created go.mod with Go version: $INSTALLED_GO_VERSION"
    fi
    
    # Initialize Go modules with PATH set
    log "Running go mod tidy..."
    sudo -u "$SERVICE_USER" env PATH="$PATH" go mod tidy || error "Failed to download Go dependencies"
    
    # Build the application with PATH set
    log "Building Go application..."
    sudo -u "$SERVICE_USER" env PATH="$PATH" go build -o exec/oceanproxy cmd/main.go || error "Failed to build Go application"
    
    # Make scripts executable if they exist
    if [[ -d "scripts" ]]; then
        chmod +x scripts/*.sh
        log "Made scripts executable"
    fi
    
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
    
    # Stop nginx first
    systemctl stop nginx 2>/dev/null || true
    
    # Remove any existing oceanproxy configs completely
    rm -f /etc/nginx/conf.d/oceanproxy*.conf
    rm -f /etc/nginx/sites-available/oceanproxy
    rm -f /etc/nginx/sites-enabled/oceanproxy
    
    # Backup original configuration if it exists and we haven't backed it up yet
    if [[ -f /etc/nginx/nginx.conf && ! -f /etc/nginx/nginx.conf.backup ]]; then
        cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup
    fi
    
    # Check if nginx has stream module
    if ! nginx -V 2>&1 | grep -q "with-stream"; then
        warn "nginx stream module not detected. Installing nginx-full..."
        if [[ "$OS_TYPE" == "debian" ]]; then
            apt install -y nginx-full
        fi
    fi
    
    # Create a complete nginx.conf with stream module
    log "Creating complete nginx configuration with stream module..."
    cat > /etc/nginx/nginx.conf << 'EOF'
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 768;
}

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;

    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;

    gzip on;

    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}

# OceanProxy Stream Configuration
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
        
        access_log /var/log/oceanproxy/nginx/alpha_access.log proxy;
        error_log /var/log/oceanproxy/nginx/alpha_error.log;
    }
}
EOF

    # Create challenge directory for SSL
    mkdir -p /var/www/html/.well-known/acme-challenge
    chown -R www-data:www-data /var/www/html

    # Create HTTP configuration for API and management with SSL support
    cat > /etc/nginx/sites-available/oceanproxy << EOF
# OceanProxy API and Management
server {
    listen 80;
    server_name api.$DOMAIN $DOMAIN;
    
    # ACME challenge directory for SSL certificates
    location /.well-known/acme-challenge/ {
        root /var/www/html;
        try_files \$uri \$uri/ =404;
        allow all;
    }
    
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
    log "Testing nginx configuration..."
    if ! nginx -t; then
        log "nginx configuration test failed. Showing error details:"
        nginx -t 2>&1 || true
        error "nginx configuration test failed"
    fi
    
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

    # Reload systemd and enable services
    systemctl daemon-reload
    systemctl enable oceanproxy-api.service
    
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

start_services() {
    log "Starting services..."
    
    # Start nginx
    systemctl enable nginx
    systemctl restart nginx
    
    # Start OceanProxy API
    systemctl start oceanproxy-api
    
    # Wait for services to start
    sleep 5
    
    log "Services started successfully"
}

setup_ssl() {
    if [[ "$SKIP_SSL" == "true" ]]; then
        log "Skipping SSL setup"
        return
    fi
    
    log "Setting up SSL certificates..."
    
    # Check if domain resolves to this server
    SERVER_IP=$(curl -s ifconfig.me || curl -s icanhazip.com || echo "unknown")
    DOMAIN_IP=$(dig +short "$DOMAIN" | tail -n1)
    API_DOMAIN_IP=$(dig +short "api.$DOMAIN" | tail -n1)
    
    log "Server IP: $SERVER_IP"
    log "Domain IP: $DOMAIN_IP"
    log "API Domain IP: $API_DOMAIN_IP"
    
    if [[ "$SERVER_IP" != "$DOMAIN_IP" ]] && [[ "$SERVER_IP" != "$API_DOMAIN_IP" ]]; then
        warn "Domain $DOMAIN does not resolve to this server ($SERVER_IP vs $DOMAIN_IP)"
        warn "SSL setup will be skipped. Configure DNS first, then run:"
        warn "sudo certbot --nginx -d $DOMAIN -d api.$DOMAIN --non-interactive --agree-tos --email admin@$DOMAIN"
        return
    fi
    
    # Wait for nginx to be fully started
    sleep 5
    
    # Test if challenge directory is accessible
    echo "test" > /var/www/html/.well-known/acme-challenge/test
    TEST_RESPONSE=$(curl -s "http://$DOMAIN/.well-known/acme-challenge/test" || echo "failed")
    rm -f /var/www/html/.well-known/acme-challenge/test
    
    if [[ "$TEST_RESPONSE" != "test" ]]; then
        warn "ACME challenge directory not accessible. SSL setup may fail."
        warn "Trying anyway..."
    else
        log "ACME challenge directory accessible"
    fi
    
    # Obtain certificates for both main domain and API subdomain
    log "Obtaining SSL certificate for $DOMAIN and api.$DOMAIN..."
    if certbot --nginx -d "$DOMAIN" -d "api.$DOMAIN" --non-interactive --agree-tos --email "admin@$DOMAIN" --no-eff-email; then
        log "SSL certificates obtained successfully"
        
        # Setup auto-renewal
        systemctl enable certbot.timer
        systemctl start certbot.timer
        
        # Add cron job as backup
        (crontab -l 2>/dev/null; echo "0 12 * * * /usr/bin/certbot renew --quiet") | crontab -
        
        log "SSL auto-renewal configured"
        
        # Verify certificates
        log "Verifying SSL certificates..."
        if curl -s -f "https://api.$DOMAIN/health" > /dev/null; then
            log "✅ HTTPS API endpoint working"
        else
            warn "⚠️  HTTPS API endpoint not responding (may need time to propagate)"
        fi
        
    else
        warn "SSL certificate setup failed. You can set it up manually later with:"
        warn "sudo certbot --nginx -d $DOMAIN -d api.$DOMAIN"
        warn "Common issues:"
        warn "  - DNS not pointing to this server"
        warn "  - Firewall blocking port 80/443"
        warn "  - nginx not serving challenge files properly"
    fi
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
    /etc/nginx/nginx.conf \
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

test_installation() {
    
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
            warn "⚠️  Port $port is not listening (this is normal until first proxy is created)"
        fi
    done
    
    log "Installation testing complete"
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
    echo "  • API Health (HTTP): http://localhost:$API_PORT/health"
    echo "  • API Health (External): http://$DOMAIN/health"
    if [[ -d /etc/letsencrypt/live ]]; then
        echo "  • API Health (HTTPS): https://api.$DOMAIN/health"
        echo "  • Main Site (HTTPS): https://$DOMAIN"
    fi
    echo "  • USA Proxy: usa.$DOMAIN:1337"
    echo "  • EU Proxy: eu.$DOMAIN:1338" 
    echo "  • Alpha Proxy: alpha.$DOMAIN:9876"
    echo
    echo -e "${GREEN}🔧 Management Commands:${NC}"
    echo "  • Check API status: sudo systemctl status oceanproxy-api"
    echo "  • View API logs: sudo tail -f $LOG_DIR/api.log"
    echo "  • Create plan: curl -X POST -H 'Authorization: Bearer $BEARER_TOKEN' \\"
    echo "                      -d 'reseller=residential&bandwidth=5&username=USER&password=PASS' \\"
    echo "                      http://localhost:$API_PORT/plan"
    echo "  • Test SSL: curl https://api.$DOMAIN/health"
    echo
    echo -e "${GREEN}📁 Important Files:${NC}"
    echo "  • Configuration: $INSTALL_DIR/app/backend/exec/.env"
    echo "  • Proxy Database: $LOG_DIR/proxies.json"
    echo "  • nginx Config: /etc/nginx/nginx.conf"
    echo "  • Scripts: $INSTALL_DIR/app/backend/scripts/"
    echo "  • SSL Certificates: /etc/letsencrypt/live/ (if configured)"
    echo
    echo -e "${GREEN}🔐 SSL Status:${NC}"
    if [[ -d /etc/letsencrypt/live ]]; then
        echo "  • SSL certificates: ✅ Configured and active"
        echo "  • Auto-renewal: ✅ Enabled via certbot.timer"
        echo "  • HTTPS endpoints: https://api.$DOMAIN/health"
    else
        echo "  • SSL certificates: ⚠️  Not configured yet"
        echo "  • Run: sudo certbot --nginx -d $DOMAIN -d api.$DOMAIN"
    fi
    echo
    echo -e "${GREEN}📈 Next Steps:${NC}"
    echo "  1. Verify DNS records point to this server IP: $(curl -s ifconfig.me || echo 'unknown')"
    echo "  2. Test SSL setup: curl https://api.$DOMAIN/health"
    echo "  3. Create test proxy: curl -X POST -H 'Authorization: Bearer $BEARER_TOKEN' \\"
    echo "                             -d 'reseller=residential&bandwidth=1&username=test&password=test123' \\"
    echo "                             http://localhost:$API_PORT/plan"
    echo "  4. Build customer dashboard frontend"
    echo "  5. Integrate payment processing"
    echo "  6. Set up monitoring and alerting"
    echo
    echo -e "${YELLOW}⚠️  Important Notes:${NC}"
    echo "  • Keep your API keys secure and rotate them regularly"
    echo "  • Monitor log files for any issues: sudo tail -f $LOG_DIR/api.log"
    echo "  • SSL certificates auto-renew via certbot.timer"
    echo "  • Backup script runs daily at 3 AM: $INSTALL_DIR/scripts/backup.sh"
    echo "  • System optimizations applied for high performance"
    echo "  • Firewall configured - ensure DNS points to: $(curl -s ifconfig.me || echo 'unknown')"
    echo
    echo -e "${GREEN}🔧 SSL Setup Commands (if needed):${NC}"
    echo "  • Manual SSL setup: sudo certbot --nginx -d $DOMAIN -d api.$DOMAIN"
    echo "  • Check certificates: sudo certbot certificates"
    echo "  • Test renewal: sudo certbot renew --dry-run"
    echo "  • View SSL logs: sudo tail -f /var/log/letsencrypt/letsencrypt.log"
    echo
    echo -e "${GREEN}🚨 Troubleshooting Commands:${NC}"
    echo "  • Check services: sudo systemctl status nginx oceanproxy-api"
    echo "  • Test API manually: curl http://localhost:$API_PORT/health"
    echo "  • Check ports: sudo netstat -tlnp | grep -E ':(80|443|1337|1338|9876|$API_PORT)'"
    echo "  • View nginx logs: sudo tail -f /var/log/nginx/error.log"
    echo "  • Restart services: sudo systemctl restart nginx oceanproxy-api"
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    if [[ -d /etc/letsencrypt/live ]]; then
        log "Your OceanProxy whitelabel service is ready with SSL! 🌊🔐💰"
    else
        log "Your OceanProxy whitelabel service is ready! Configure SSL for production use. 🌊💰"
    fi
    echo
}

cleanup_on_error() {
    error "Setup failed. Check the error message above and try again."
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
    optimize_system
    setup_monitoring
    start_services
    
    # Setup SSL after services are running
    if [[ "$SKIP_SSL" != "true" ]]; then
        setup_ssl
    fi
    
    # Summary
    print_summary
    
    log "Setup completed successfully! 🎉"
}

# Run main function
main "$@"
