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
    echo "  • API Health: http://localhost:$API_PORT/health"
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
    echo
    echo -e "${GREEN}📁 Important Files:${NC}"
    echo "  • Configuration: $INSTALL_DIR/app/backend/exec/.env"
    echo "  • Proxy Database: $LOG_DIR/proxies.json"
    echo "  • nginx Config: /etc/nginx/conf.d/oceanproxy-stream.conf"
    echo "  • Scripts: $INSTALL_DIR/app/backend/scripts/"
    echo
    echo -e "${GREEN}📈 Next Steps:${NC}"
    echo "  1. Update DNS records to point subdomains to this server"
    echo "  2. Test proxy creation: curl -X POST -H 'Authorization: Bearer $BEARER_TOKEN' \\"
    echo "                               -d 'reseller=residential&bandwidth=1&username=test&password=test123' \\"
    echo "                               http://localhost:$API_PORT/plan"
    echo "  3. Build customer dashboard frontend"
    echo "  4. Integrate payment processing"
    echo "  5. Set up monitoring and alerting"
    echo
    echo -e "${YELLOW}⚠️  Important Notes:${NC}"
    echo "  • Keep your API keys secure and rotate them regularly"
    echo "  • Monitor log files for any issues"
    echo "  • Set up regular backups of proxy data"
    echo "  • Test your setup before accepting customers"
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    log "Your OceanProxy whitelabel service is ready! 🌊💰"
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
    start_services
    
    # Testing
    test_installation
    
    # Summary
    print_summary
    
    log "Setup completed successfully! 🎉"
}

# Run main function
main "$@"
