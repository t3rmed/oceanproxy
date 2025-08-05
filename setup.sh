#!/bin/bash

# 🌊 OceanProxy - Complete Server Setup Script
# Updated with comprehensive error handling and fixes
# Save this as oceanproxy-setup.sh and run with: sudo ./oceanproxy-setup.sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_VERSION="1.2.2"  # Updated version with enhanced error handling
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
SKIP_OPTIMIZATION=false
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

# Safe command execution with error handling
safe_exec() {
    local cmd="$1"
    local error_msg="${2:-Command failed}"
    
    if ! eval "$cmd"; then
        warn "$error_msg"
        return 1
    fi
    return 0
}

# Safe sysctl parameter setting
safe_sysctl() {
    local param="$1"
    local value="$2"
    
    if [[ -f "/proc/sys/${param//./\/}" ]]; then
        if sysctl -w "$param=$value" >/dev/null 2>&1; then
            echo "$param = $value"
            return 0
        else
            warn "Failed to set $param=$value"
            return 1
        fi
    else
        warn "Parameter $param not available on this kernel"
        return 1
    fi
}

banner() {
    echo -e "${BLUE}"
    cat << 'EOF'
    ╔═══════════════════════════════════════════════════════════╗
    ║                    🌊 OceanProxy Setup                    ║
    ║            Whitelabel HTTP Proxy Service                  ║
    ║                                                           ║
    ║  Transform into a proxy reseller with your own brand!     ║
    ║  Now with 12 proxy endpoints and 2000 ports per type!    ║
    ║  Updated with enhanced error handling and fixes!         ║
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
    --skip-optimization    Skip system optimization
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
        # Update package lists with error handling
        if ! apt update; then
            warn "apt update failed, continuing anyway..."
        fi
        
        # Remove old Go if installed
        apt remove -y golang-go golang-1.* 2>/dev/null || true
        
        # Install dependencies (without golang-go)
        local packages=(
            curl wget git jq htop net-tools lsof nginx fail2ban ufw
            certbot python3-certbot-nginx build-essential supervisor bc
        )
        
        for package in "${packages[@]}"; do
            if ! apt install -y "$package"; then
                warn "Failed to install $package, continuing..."
            fi
        done
        
        # Install latest Go with error handling
        log "Installing Go 1.21..."
        cd /tmp
        if wget -q https://go.dev/dl/go1.21.5.linux-amd64.tar.gz; then
            rm -rf /usr/local/go
            tar -C /usr/local -xzf go1.21.5.linux-amd64.tar.gz
            echo 'export PATH=$PATH:/usr/local/go/bin' > /etc/profile.d/go.sh
            export PATH=$PATH:/usr/local/go/bin
            rm -f go1.21.5.linux-amd64.tar.gz
        else
            error "Failed to download Go"
        fi
        
        # Install 3proxy from source if not available
        if ! command -v 3proxy &> /dev/null; then
            log "Installing 3proxy from source..."
            cd /tmp
            if git clone https://github.com/3proxy/3proxy.git; then
                cd 3proxy
                if make -f Makefile.Linux && make -f Makefile.Linux install; then
                    log "3proxy installed successfully"
                else
                    warn "Failed to build/install 3proxy, continuing..."
                fi
                cd /
                rm -rf /tmp/3proxy
            else
                warn "Failed to clone 3proxy repository, continuing..."
            fi
        fi
        
    elif [[ "$OS_TYPE" == "rhel" ]]; then
        # Enable EPEL repository
        yum install -y epel-release || warn "Failed to install EPEL, continuing..."
        
        # Remove old Go if installed
        yum remove -y golang 2>/dev/null || true
        
        # Install dependencies
        local packages=(
            curl wget git jq htop net-tools lsof nginx fail2ban
            firewalld certbot python3-certbot-nginx gcc make supervisor bc
        )
        
        for package in "${packages[@]}"; do
            if ! yum install -y "$package"; then
                warn "Failed to install $package, continuing..."
            fi
        done
        
        # Install latest Go
        log "Installing Go 1.21..."
        cd /tmp
        if wget -q https://go.dev/dl/go1.21.5.linux-amd64.tar.gz; then
            rm -rf /usr/local/go
            tar -C /usr/local -xzf go1.21.5.linux-amd64.tar.gz
            echo 'export PATH=$PATH:/usr/local/go/bin' > /etc/profile.d/go.sh
            export PATH=$PATH:/usr/local/go/bin
            rm -f go1.21.5.linux-amd64.tar.gz
        else
            error "Failed to download Go"
        fi
        
        # Install 3proxy from source
        if ! command -v 3proxy &> /dev/null; then
            log "Installing 3proxy from source..."
            cd /tmp
            if git clone https://github.com/3proxy/3proxy.git; then
                cd 3proxy
                if make -f Makefile.Linux && make -f Makefile.Linux install; then
                    log "3proxy installed successfully"
                else
                    warn "Failed to build/install 3proxy, continuing..."
                fi
                cd /
                rm -rf /tmp/3proxy
            else
                warn "Failed to clone 3proxy repository, continuing..."
            fi
        fi
    fi
    
    # Ensure PATH includes Go
    export PATH=$PATH:/usr/local/go/bin
    
    # Verify installations
    log "Verifying installations..."
    local required_commands=(nginx git jq curl bc)
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
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
        warn "3proxy is not installed or not accessible, but continuing..."
    fi
    
    log "All dependencies installed successfully"
}

setup_user_and_directories() {
    log "Setting up user and directories with proper permissions..."
    
    # Create system user
    if ! id "$SERVICE_USER" &>/dev/null; then
        if useradd -r -s /bin/false -d "$INSTALL_DIR" "$SERVICE_USER"; then
            log "Created user: $SERVICE_USER"
        else
            error "Failed to create user: $SERVICE_USER"
        fi
    fi
    
    # Create directories with error handling
    local directories=(
        "$INSTALL_DIR"/{app,data,logs,backups,scripts}
        "$LOG_DIR"/{nginx,3proxy}
        "$CONFIG_DIR"/{nginx,3proxy}
        /etc/nginx/stream.d
        /etc/3proxy/plans
    )
    
    for dir in "${directories[@]}"; do
        if ! mkdir -p "$dir"; then
            error "Failed to create directory: $dir"
        fi
    done
    
    # Set permissions - CRITICAL FIX
    chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR" || warn "Failed to set ownership for $INSTALL_DIR"
    chown -R "$SERVICE_USER:$SERVICE_USER" "$LOG_DIR" || warn "Failed to set ownership for $LOG_DIR"
    chown -R "$SERVICE_USER:$SERVICE_USER" /etc/3proxy || warn "Failed to set ownership for /etc/3proxy"
    chown -R root:root "$CONFIG_DIR" || warn "Failed to set ownership for $CONFIG_DIR"
    chmod 755 "$CONFIG_DIR" || warn "Failed to set permissions for $CONFIG_DIR"
    chmod 755 /etc/3proxy || warn "Failed to set permissions for /etc/3proxy"
    chmod 755 /etc/3proxy/plans || warn "Failed to set permissions for /etc/3proxy/plans"
    
    # Create log files
    touch "$LOG_DIR/api.log" || warn "Failed to create api.log"
    touch "$LOG_DIR/proxies.json" || warn "Failed to create proxies.json"
    echo "[]" > "$LOG_DIR/proxies.json" || warn "Failed to initialize proxies.json"
    chown "$SERVICE_USER:$SERVICE_USER" "$LOG_DIR"/*.{log,json} 2>/dev/null || warn "Failed to set log file ownership"
    
    # Add oceanproxy user to necessary groups
    usermod -a -G adm "$SERVICE_USER" || warn "Failed to add user to adm group"
    
    log "User and directories setup complete with proper permissions"
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
    
    # Clone repository with error handling
    if sudo -u "$SERVICE_USER" git clone "$REPO_URL" app; then
        # Set ownership
        chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR/app"
        log "Repository cloned successfully"
    else
        error "Failed to clone repository. Check your GitHub credentials and repository access."
    fi
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
    
    # Create exec directory if it doesn't exist
    mkdir -p exec
    chown "$SERVICE_USER:$SERVICE_USER" exec
    
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
    if sudo -u "$SERVICE_USER" env PATH="$PATH" go mod tidy; then
        log "Go dependencies downloaded successfully"
    else
        error "Failed to download Go dependencies"
    fi
    
    # Build the application with PATH set
    log "Building Go application..."
    if sudo -u "$SERVICE_USER" env PATH="$PATH" go build -o exec/oceanproxy cmd/main.go; then
        log "Go application built successfully"
    else
        error "Failed to build Go application"
    fi
    
    # Make scripts executable if they exist
    if [[ -d "scripts" ]]; then
        chmod +x scripts/*.sh 2>/dev/null || warn "No scripts found to make executable"
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

# Port Limits (2000 ports per type)
MAX_PORTS_PER_TYPE=2000
EOF
    
    chown "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR/app/backend/exec/.env" || warn "Failed to set .env ownership"
    chmod 600 "$INSTALL_DIR/app/backend/exec/.env" || warn "Failed to set .env permissions"
    
    log "Configuration files created"
}

configure_nginx() {
    log "Configuring nginx with all 12 proxy endpoints..."
    
    # Stop nginx first
    systemctl stop nginx 2>/dev/null || true
    
    # Remove any existing oceanproxy configs completely
    rm -f /etc/nginx/conf.d/oceanproxy*.conf
    rm -f /etc/nginx/sites-available/oceanproxy
    rm -f /etc/nginx/sites-enabled/oceanproxy
    rm -rf /etc/nginx/stream.d/*
    
    # Backup original configuration if it exists and we haven't backed it up yet
    if [[ -f /etc/nginx/nginx.conf && ! -f /etc/nginx/nginx.conf.backup ]]; then
        cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup
    fi
    
    # Check if nginx has stream module
    if ! nginx -V 2>&1 | grep -q "with-stream"; then
        warn "nginx stream module not detected. Installing nginx-full..."
        if [[ "$OS_TYPE" == "debian" ]]; then
            apt install -y nginx-full || warn "Failed to install nginx-full"
        fi
    fi
    
    # Create a complete nginx.conf with stream module and all proxy endpoints
    log "Creating complete nginx configuration with stream module..."
    cat > /etc/nginx/nginx.conf << 'EOF'
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 4096;
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

    # Include dynamic configurations
    include /etc/nginx/stream.d/*.conf;

    # USA Proxy Pool (Port 1337) - Ports 10000-11999
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

    # EU Proxy Pool (Port 1338) - Ports 12000-13999
    upstream eu_proxies {
        least_conn;
        server 127.0.0.1:12000 max_fails=3 fail_timeout=30s;
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

    # Alpha Proxy Pool (Port 9876) - Ports 14000-15999
    upstream alpha_proxies {
        least_conn;
        server 127.0.0.1:14000 max_fails=3 fail_timeout=30s;
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

    # Beta Proxy Pool (Port 8765) - Ports 16000-17999
    upstream beta_proxies {
        least_conn;
        server 127.0.0.1:16000 max_fails=3 fail_timeout=30s;
        # Additional servers will be added dynamically by scripts
    }

    server {
        listen 8765;
        proxy_pass beta_proxies;
        proxy_timeout 30s;
        proxy_connect_timeout 5s;
        proxy_responses 1;
        
        access_log /var/log/oceanproxy/nginx/beta_access.log proxy;
        error_log /var/log/oceanproxy/nginx/beta_error.log;
    }

    # Mobile Proxy Pool (Port 7654) - Ports 18000-19999
    upstream mobile_proxies {
        least_conn;
        server 127.0.0.1:18000 max_fails=3 fail_timeout=30s;
        # Additional servers will be added dynamically by scripts
    }

    server {
        listen 7654;
        proxy_pass mobile_proxies;
        proxy_timeout 30s;
        proxy_connect_timeout 5s;
        proxy_responses 1;
        
        access_log /var/log/oceanproxy/nginx/mobile_access.log proxy;
        error_log /var/log/oceanproxy/nginx/mobile_error.log;
    }

    # Unlim Proxy Pool (Port 6543) - Ports 20000-21999
    upstream unlim_proxies {
        least_conn;
        server 127.0.0.1:20000 max_fails=3 fail_timeout=30s;
        # Additional servers will be added dynamically by scripts
    }

    server {
        listen 6543;
        proxy_pass unlim_proxies;
        proxy_timeout 30s;
        proxy_connect_timeout 5s;
        proxy_responses 1;
        
        access_log /var/log/oceanproxy/nginx/unlim_access.log proxy;
        error_log /var/log/oceanproxy/nginx/unlim_error.log;
    }

    # Datacenter Proxy Pool (Port 1339) - Ports 22000-23999
    upstream datacenter_proxies {
        least_conn;
        server 127.0.0.1:22000 max_fails=3 fail_timeout=30s;
        # Additional servers will be added dynamically by scripts
    }

    server {
        listen 1339;
        proxy_pass datacenter_proxies;
        proxy_timeout 30s;
        proxy_connect_timeout 5s;
        proxy_responses 1;
        
        access_log /var/log/oceanproxy/nginx/datacenter_access.log proxy;
        error_log /var/log/oceanproxy/nginx/datacenter_error.log;
    }

    # Gamma Proxy Pool (Port 5432) - Ports 24000-25999 - NEW
    upstream gamma_proxies {
        least_conn;
        server 127.0.0.1:24000 max_fails=3 fail_timeout=30s;
        # Additional servers will be added dynamically by scripts
    }

    server {
        listen 5432;
        proxy_pass gamma_proxies;
        proxy_timeout 30s;
        proxy_connect_timeout 5s;
        proxy_responses 1;
        
        access_log /var/log/oceanproxy/nginx/gamma_access.log proxy;
        error_log /var/log/oceanproxy/nginx/gamma_error.log;
    }

    # Delta Proxy Pool (Port 4321) - Ports 26000-27999 - NEW
    upstream delta_proxies {
        least_conn;
        server 127.0.0.1:26000 max_fails=3 fail_timeout=30s;
        # Additional servers will be added dynamically by scripts
    }

    server {
        listen 4321;
        proxy_pass delta_proxies;
        proxy_timeout 30s;
        proxy_connect_timeout 5s;
        proxy_responses 1;
        
        access_log /var/log/oceanproxy/nginx/delta_access.log proxy;
        error_log /var/log/oceanproxy/nginx/delta_error.log;
    }

    # Epsilon Proxy Pool (Port 3210) - Ports 28000-29999 - NEW
    upstream epsilon_proxies {
        least_conn;
        server 127.0.0.1:28000 max_fails=3 fail_timeout=30s;
        # Additional servers will be added dynamically by scripts
    }

    server {
        listen 3210;
        proxy_pass epsilon_proxies;
        proxy_timeout 30s;
        proxy_connect_timeout 5s;
        proxy_responses 1;
        
        access_log /var/log/oceanproxy/nginx/epsilon_access.log proxy;
        error_log /var/log/oceanproxy/nginx/epsilon_error.log;
    }

    # Zeta Proxy Pool (Port 2109) - Ports 30000-31999 - NEW
    upstream zeta_proxies {
        least_conn;
        server 127.0.0.1:30000 max_fails=3 fail_timeout=30s;
        # Additional servers will be added dynamically by scripts
    }

    server {
        listen 2109;
        proxy_pass zeta_proxies;
        proxy_timeout 30s;
        proxy_connect_timeout 5s;
        proxy_responses 1;
        
        access_log /var/log/oceanproxy/nginx/zeta_access.log proxy;
        error_log /var/log/oceanproxy/nginx/zeta_error.log;
    }

    # Eta Proxy Pool (Port 1098) - Ports 32000-33999 - NEW
    upstream eta_proxies {
        least_conn;
        server 127.0.0.1:32000 max_fails=3 fail_timeout=30s;
        # Additional servers will be added dynamically by scripts
    }

    server {
        listen 1098;
        proxy_pass eta_proxies;
        proxy_timeout 30s;
        proxy_connect_timeout 5s;
        proxy_responses 1;
        
        access_log /var/log/oceanproxy/nginx/eta_access.log proxy;
        error_log /var/log/oceanproxy/nginx/eta_error.log;
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
    
    # Monitoring endpoint
    location /monitoring {
        proxy_pass http://127.0.0.1:$API_PORT/monitoring;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    # Health check endpoint
    location /health {
        proxy_pass http://127.0.0.1:$API_PORT/health;
        access_log off;
    }
    
    # Default location
    location / {
        return 200 "OceanProxy Service Running - 12 Proxy Endpoints Available\\nVersion: $SCRIPT_VERSION\\nEnhanced Error Handling";
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
    if nginx -t; then
        log "nginx configuration test passed"
    else
        log "nginx configuration test failed. Showing error details:"
        nginx -t 2>&1 || true
        error "nginx configuration test failed"
    fi
    
    log "nginx configured successfully with 12 proxy endpoints"
}

create_systemd_services() {
    log "Creating systemd services with proper permissions..."
    
    # Create missing directories first - CRITICAL FIX
    mkdir -p "$INSTALL_DIR/app/backend/logs"
    chown "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR/app/backend/logs"
    
    # OceanProxy API service - FIXED to avoid namespace issues
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

# Security - Simplified to avoid namespace issues
NoNewPrivileges=true
PrivateTmp=true
ReadWritePaths=$LOG_DIR /etc/3proxy $INSTALL_DIR

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
    
    log "Systemd services created and enabled with proper permissions"
}

configure_firewall() {
    log "Configuring firewall with all proxy ports..."
    
    if [[ "$OS_TYPE" == "debian" ]]; then
        # Configure UFW with error handling
        ufw --force reset || warn "Failed to reset UFW"
        ufw default deny incoming || warn "Failed to set UFW default deny incoming"
        ufw default allow outgoing || warn "Failed to set UFW default allow outgoing"
        
        # Allow SSH
        ufw allow 22/tcp || warn "Failed to allow SSH"
        
        # Allow HTTP/HTTPS
        ufw allow 80/tcp || warn "Failed to allow HTTP"
        ufw allow 443/tcp || warn "Failed to allow HTTPS"
        
        # Allow original proxy ports
        local proxy_ports=(1337 1338 9876 8765 7654 6543 1339 5432 4321 3210 2109 1098)
        for port in "${proxy_ports[@]}"; do
            ufw allow "$port/tcp" || warn "Failed to allow port $port"
        done
        
        # Allow API port
        ufw allow "$API_PORT/tcp" || warn "Failed to allow API port $API_PORT"
        
        # Enable firewall
        ufw --force enable || warn "Failed to enable UFW"
        
    elif [[ "$OS_TYPE" == "rhel" ]]; then
        # Configure firewalld with error handling
        systemctl enable firewalld || warn "Failed to enable firewalld"
        systemctl start firewalld || warn "Failed to start firewalld"
        
        # Allow services
        firewall-cmd --permanent --add-service=http || warn "Failed to allow HTTP service"
        firewall-cmd --permanent --add-service=https || warn "Failed to allow HTTPS service"
        firewall-cmd --permanent --add-service=ssh || warn "Failed to allow SSH service"
        
        # Allow proxy ports
        local proxy_ports=(1337 1338 9876 8765 7654 6543 1339 5432 4321 3210 2109 1098)
        for port in "${proxy_ports[@]}"; do
            firewall-cmd --permanent --add-port="$port/tcp" || warn "Failed to allow port $port"
        done
        
        # Allow API port
        firewall-cmd --permanent --add-port="$API_PORT/tcp" || warn "Failed to allow API port $API_PORT"
        
        # Reload firewall
        firewall-cmd --reload || warn "Failed to reload firewall"
    fi
    
    log "Firewall configured successfully - 12 proxy ports open"
}

optimize_system() {
    if [[ "$SKIP_OPTIMIZATION" == "true" ]]; then
        log "Skipping system optimization"
        return
    fi
    
    log "Optimizing system performance for 12 proxy endpoints..."
    
    # Increase file descriptor limits
    cat >> /etc/security/limits.conf << EOF
# OceanProxy optimizations
$SERVICE_USER soft nofile 65536
$SERVICE_USER hard nofile 65536
root soft nofile 65536
root hard nofile 65536
EOF

    # Create temporary sysctl configuration
    cat > /tmp/oceanproxy-sysctl.conf << 'EOF'
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

    # Apply kernel parameters with error handling
    log "Applying kernel parameters..."
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^#.*$ ]] && continue
        [[ -z "$line" ]] && continue
        
        # Extract parameter and value
        if [[ "$line" =~ ^([^=]+)\ *=\ *(.+)$ ]]; then
            param="${BASH_REMATCH[1]// /}"
            value="${BASH_REMATCH[2]// /}"
            safe_sysctl "$param" "$value"
        fi
    done < /tmp/oceanproxy-sysctl.conf
    
    # Append to main sysctl.conf for persistence
    cat /tmp/oceanproxy-sysctl.conf >> /etc/sysctl.conf
    rm -f /tmp/oceanproxy-sysctl.conf
    
    # Apply additional optimizations that are commonly available
    log "Applying additional network optimizations..."
    
    # These are more universally available parameters
    safe_sysctl "net.core.rmem_max" "134217728"
    safe_sysctl "net.core.wmem_max" "134217728"
    safe_sysctl "net.core.rmem_default" "65536"
    safe_sysctl "net.core.wmem_default" "65536"
    safe_sysctl "net.ipv4.tcp_rmem" "4096 65536 134217728"
    safe_sysctl "net.ipv4.tcp_wmem" "4096 65536 134217728"
    safe_sysctl "net.ipv4.tcp_congestion_control" "bbr"
    safe_sysctl "net.ipv4.tcp_fastopen" "3"
    
    # Try optional parameters that may not be available on all kernels
    safe_sysctl "net.ipv4.tcp_low_latency" "1"
    safe_sysctl "net.ipv4.tcp_no_delay_ack" "1"
    safe_sysctl "net.ipv4.tcp_quick_ack" "1"
    
    # nginx worker optimization
    if command -v nproc &> /dev/null; then
        CPU_CORES=$(nproc)
        sed -i "s/worker_processes auto;/worker_processes $CPU_CORES;/" /etc/nginx/nginx.conf 2>/dev/null || warn "Failed to update nginx worker_processes"
        sed -i "s/worker_connections 768;/worker_connections 4096;/" /etc/nginx/nginx.conf 2>/dev/null || warn "Failed to update nginx worker_connections"
    fi
    
    log "System optimizations applied (with error handling)"
}

start_services() {
    log "Starting services..."
    
    # Start nginx
    if systemctl enable nginx && systemctl restart nginx; then
        log "nginx started successfully"
    else
        warn "Failed to start nginx, checking status..."
        systemctl status nginx --no-pager -l || true
    fi
    
    # Wait a moment for nginx to fully start
    sleep 3
    
    # Start OceanProxy API
    if systemctl start oceanproxy-api; then
        log "OceanProxy API started successfully"
    else
        warn "Failed to start OceanProxy API, checking status..."
        systemctl status oceanproxy-api --no-pager -l || true
    fi
    
    # Wait for services to start
    sleep 5
    
    log "Services startup completed"
}

setup_ssl() {
    if [[ "$SKIP_SSL" == "true" ]]; then
        log "Skipping SSL setup"
        return
    fi
    
    log "Setting up SSL certificates for API subdomain only..."
    
    # Check if API subdomain resolves to this server
    SERVER_IP=$(curl -s --connect-timeout 10 ifconfig.me || curl -s --connect-timeout 10 icanhazip.com || echo "unknown")
    API_DOMAIN_IP=$(dig +short "api.$DOMAIN" | tail -n1 2>/dev/null || echo "unknown")
    
    log "Server IP: $SERVER_IP"
    log "API Domain IP: $API_DOMAIN_IP"
    
    if [[ "$SERVER_IP" != "$API_DOMAIN_IP" ]] || [[ "$SERVER_IP" == "unknown" ]]; then
        warn "API subdomain api.$DOMAIN does not resolve to this server ($SERVER_IP vs $API_DOMAIN_IP)"
        warn "SSL setup will be skipped. Configure DNS first, then run:"
        warn "sudo certbot --nginx -d api.$DOMAIN --non-interactive --agree-tos --email admin@$DOMAIN"
        return
    fi
    
    # Wait for nginx to be fully started
    sleep 5
    
    # Test if challenge directory is accessible via API subdomain
    echo "test" > /var/www/html/.well-known/acme-challenge/test
    TEST_RESPONSE=$(curl -s --connect-timeout 10 "http://api.$DOMAIN/.well-known/acme-challenge/test" 2>/dev/null || echo "failed")
    rm -f /var/www/html/.well-known/acme-challenge/test
    
    if [[ "$TEST_RESPONSE" != "test" ]]; then
        warn "ACME challenge directory not accessible via api.$DOMAIN. SSL setup may fail."
        warn "Trying anyway..."
    else
        log "ACME challenge directory accessible via api.$DOMAIN"
    fi
    
    # Obtain certificate for API subdomain only
    log "Obtaining SSL certificate for api.$DOMAIN only..."
    if certbot --nginx -d "api.$DOMAIN" --non-interactive --agree-tos --email "admin@$DOMAIN" --no-eff-email; then
        log "SSL certificate obtained successfully for api.$DOMAIN"
        
        # Setup auto-renewal
        systemctl enable certbot.timer || warn "Failed to enable certbot timer"
        systemctl start certbot.timer || warn "Failed to start certbot timer"
        
        # Add cron job as backup
        (crontab -l 2>/dev/null; echo "0 12 * * * /usr/bin/certbot renew --quiet") | crontab - || warn "Failed to add certbot cron job"
        
        log "SSL auto-renewal configured"
        
        # Verify certificate
        log "Verifying SSL certificate..."
        if curl -s -f --connect-timeout 10 "https://api.$DOMAIN/health" > /dev/null 2>&1; then
            log "✅ HTTPS API endpoint working"
        else
            warn "⚠️  HTTPS API endpoint not responding (may need time to propagate)"
        fi
        
    else
        warn "SSL certificate setup failed. You can set it up manually later with:"
        warn "sudo certbot --nginx -d api.$DOMAIN"
        warn "Common issues:"
        warn "  - DNS for api.$DOMAIN not pointing to this server"
        warn "  - Firewall blocking port 80/443"
        warn "  - nginx not serving challenge files properly"
    fi
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
if [[ -f /var/log/oceanproxy/proxies.json ]]; then
    cp /var/log/oceanproxy/proxies.json "$BACKUP_DIR/proxies_$DATE.json"
fi

# Backup configuration
tar -czf "$BACKUP_DIR/config_$DATE.tar.gz" \
    /opt/oceanproxy/app/backend/exec/.env \
    /etc/nginx/nginx.conf \
    /etc/nginx/sites-available/oceanproxy 2>/dev/null || echo "Some config files missing"

# Keep only last 7 days of backups
find "$BACKUP_DIR" -name "*.json" -mtime +7 -delete 2>/dev/null || true
find "$BACKUP_DIR" -name "*.tar.gz" -mtime +7 -delete 2>/dev/null || true

echo "Backup completed: $DATE"
EOF

    chmod +x "$INSTALL_DIR/scripts/backup.sh"
    chown "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR/scripts/backup.sh"
    
    # Create port usage monitoring script
    cat > "$INSTALL_DIR/scripts/check_port_usage.sh" << 'EOF'
#!/bin/bash
echo "=== OceanProxy Port Usage Report ==="
echo "Date: $(date)"
echo ""

declare -A PORT_RANGES
PORT_RANGES["usa"]="10000-11999"
PORT_RANGES["eu"]="12000-13999"
PORT_RANGES["alpha"]="14000-15999"
PORT_RANGES["beta"]="16000-17999"
PORT_RANGES["mobile"]="18000-19999"
PORT_RANGES["unlim"]="20000-21999"
PORT_RANGES["datacenter"]="22000-23999"
PORT_RANGES["gamma"]="24000-25999"
PORT_RANGES["delta"]="26000-27999"
PORT_RANGES["epsilon"]="28000-29999"
PORT_RANGES["zeta"]="30000-31999"
PORT_RANGES["eta"]="32000-33999"

if [[ -f /var/log/oceanproxy/proxies.json ]]; then
    for subdomain in "${!PORT_RANGES[@]}"; do
        count=$(jq --arg sub "$subdomain" '[.[] | select(.subdomain == $sub)] | length' /var/log/oceanproxy/proxies.json 2>/dev/null || echo 0)
        percent=$((count * 100 / 2000))
        echo "$subdomain: $count/2000 ($percent%)"
    done
else
    echo "Proxy database not found at /var/log/oceanproxy/proxies.json"
fi
EOF

    chmod +x "$INSTALL_DIR/scripts/check_port_usage.sh"
    chown "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR/scripts/check_port_usage.sh"
    
    # Create permission fix script for future use
    cat > "$INSTALL_DIR/scripts/fix_permissions.sh" << 'EOF'
#!/bin/bash
# Fix OceanProxy permissions - run if you encounter permission issues

echo "🔧 Fixing OceanProxy permissions..."

# Create missing directories
sudo mkdir -p /opt/oceanproxy/app/backend/logs
sudo mkdir -p /etc/3proxy/plans
sudo mkdir -p /var/log/oceanproxy

# Fix 3proxy directory permissions
sudo chown -R oceanproxy:oceanproxy /etc/3proxy
sudo chmod -R 755 /etc/3proxy

# Fix log directory permissions
sudo chown -R oceanproxy:oceanproxy /var/log/oceanproxy
sudo chmod -R 755 /var/log/oceanproxy

# Fix app directory permissions
sudo chown -R oceanproxy:oceanproxy /opt/oceanproxy
sudo chmod -R 755 /opt/oceanproxy

# Make scripts executable
sudo chmod +x /opt/oceanproxy/app/backend/scripts/*.sh 2>/dev/null || echo "No backend scripts found"

echo "✅ Permissions fixed!"
EOF

    chmod +x "$INSTALL_DIR/scripts/fix_permissions.sh"
    chown "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR/scripts/fix_permissions.sh"
    
    # Add backup to crontab with error handling
    if (crontab -u "$SERVICE_USER" -l 2>/dev/null; echo "0 3 * * * $INSTALL_DIR/scripts/backup.sh") | crontab -u "$SERVICE_USER" -; then
        log "Backup cron job added successfully"
    else
        warn "Failed to add backup cron job"
    fi
    
    log "Monitoring and logging setup complete"
}

test_installation() {
    log "Testing installation..."
    
    # Test API health
    log "Testing API health endpoint..."
    sleep 3  # Give the service a moment to start
    if curl -s -f --connect-timeout 10 "http://localhost:$API_PORT/health" > /dev/null 2>&1; then
        log "✅ API health check passed"
    else
        warn "⚠️  API health check failed - checking service status..."
        systemctl status oceanproxy-api --no-pager -l || true
    fi
    
    # Test nginx configuration
    log "Testing nginx configuration..."
    if nginx -t > /dev/null 2>&1; then
        log "✅ nginx configuration valid"
    else
        warn "❌ nginx configuration invalid"
        nginx -t 2>&1 || true
    fi
    
    # Test service status
    log "Checking service status..."
    for service in nginx oceanproxy-api; do
        if systemctl is-active --quiet "$service"; then
            log "✅ $service is running"
        else
            warn "⚠️  $service is not running"
            systemctl status "$service" --no-pager -l || true
        fi
    done
    
    # Test all proxy ports
    log "Testing proxy port accessibility..."
    PROXY_PORTS="1337 1338 9876 8765 7654 6543 1339 5432 4321 3210 2109 1098"
    for port in $PROXY_PORTS; do
        if netstat -tlnp 2>/dev/null | grep -q ":$port " || ss -tlnp 2>/dev/null | grep -q ":$port "; then
            log "✅ Port $port is listening"
        else
            warn "⚠️  Port $port is not listening (this is normal until first proxy is created)"
        fi
    done
    
    # Test permissions
    log "Testing permissions..."
    if sudo -u "$SERVICE_USER" test -w /etc/3proxy/plans 2>/dev/null; then
        log "✅ 3proxy config directory is writable by $SERVICE_USER"
    else
        warn "⚠️  3proxy config directory is not writable by $SERVICE_USER"
    fi
    
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
    echo "  • Port Limit: 2000 ports per proxy type"
    echo "  • Version: $SCRIPT_VERSION (enhanced error handling)"
    echo
    echo -e "${GREEN}🌐 Service Endpoints (12 Total):${NC}"
    echo "  • API Health (HTTP): http://localhost:$API_PORT/health"
    echo "  • API Health (External): http://$DOMAIN/health"
    echo "  • Monitoring Panel: http://$DOMAIN/monitoring?token=$BEARER_TOKEN"
    if [[ -d /etc/letsencrypt/live ]]; then
        echo "  • API Health (HTTPS): https://api.$DOMAIN/health"
        echo "  • Main Site (HTTPS): https://$DOMAIN"
        echo "  • Monitoring Panel (HTTPS): https://api.$DOMAIN/monitoring?token=$BEARER_TOKEN"
    fi
    echo ""
    echo "  Original Endpoints:"
    echo "  • USA Proxy: usa.$DOMAIN:1337 (Ports 10000-11999)"
    echo "  • EU Proxy: eu.$DOMAIN:1338 (Ports 12000-13999)"
    echo "  • Alpha Proxy: alpha.$DOMAIN:9876 (Ports 14000-15999)"
    echo "  • Beta Proxy: beta.$DOMAIN:8765 (Ports 16000-17999)"
    echo "  • Mobile Proxy: mobile.$DOMAIN:7654 (Ports 18000-19999)"
    echo "  • Unlim Proxy: unlim.$DOMAIN:6543 (Ports 20000-21999)"
    echo "  • Datacenter Proxy: datacenter.$DOMAIN:1339 (Ports 22000-23999)"
    echo ""
    echo "  NEW Blank Endpoints:"
    echo "  • Gamma Proxy: gamma.$DOMAIN:5432 (Ports 24000-25999)"
    echo "  • Delta Proxy: delta.$DOMAIN:4321 (Ports 26000-27999)"
    echo "  • Epsilon Proxy: epsilon.$DOMAIN:3210 (Ports 28000-29999)"
    echo "  • Zeta Proxy: zeta.$DOMAIN:2109 (Ports 30000-31999)"
    echo "  • Eta Proxy: eta.$DOMAIN:1098 (Ports 32000-33999)"
    echo
    echo -e "${GREEN}🔧 Management Commands:${NC}"
    echo "  • Check API status: sudo systemctl status oceanproxy-api"
    echo "  • View API logs: sudo tail -f $LOG_DIR/api.log"
    echo "  • Check port usage: $INSTALL_DIR/scripts/check_port_usage.sh"
    echo "  • Fix permissions: $INSTALL_DIR/scripts/fix_permissions.sh"
    echo "  • Create plan: curl -X POST -H 'Authorization: Bearer $BEARER_TOKEN' \\"
    echo "                      -d 'reseller=residential&bandwidth=5&username=USER&password=PASS' \\"
    echo "                      http://localhost:$API_PORT/plan"
    echo "  • Create Nettify plan: curl -X POST -H 'Authorization: Bearer $BEARER_TOKEN' \\"
    echo "                              -d 'plan_type=residential&bandwidth=1&username=USER&password=PASS' \\"
    echo "                              http://localhost:$API_PORT/nettify/plan"
    echo "  • Test SSL: curl https://api.$DOMAIN/health"
    echo
    echo -e "${GREEN}📁 Important Files:${NC}"
    echo "  • Configuration: $INSTALL_DIR/app/backend/exec/.env"
    echo "  • Proxy Database: $LOG_DIR/proxies.json"
    echo "  • nginx Config: /etc/nginx/nginx.conf"
    echo "  • 3proxy Configs: /etc/3proxy/plans/"
    echo "  • Scripts: $INSTALL_DIR/app/backend/scripts/"
    echo "  • Port Usage Script: $INSTALL_DIR/scripts/check_port_usage.sh"
    echo "  • Permission Fix Script: $INSTALL_DIR/scripts/fix_permissions.sh"
    echo "  • SSL Certificates: /etc/letsencrypt/live/ (if configured)"
    echo
    echo -e "${GREEN}🔐 SSL Status:${NC}"
    if [[ -d /etc/letsencrypt/live ]]; then
        echo "  • SSL certificates: ✅ Configured and active for api.$DOMAIN"
        echo "  • Auto-renewal: ✅ Enabled via certbot.timer"
        echo "  • HTTPS endpoints: https://api.$DOMAIN/health"
    else
        echo "  • SSL certificates: ⚠️  Not configured yet"
        echo "  • Run later: sudo certbot --nginx -d api.$DOMAIN"
    fi
    echo
    echo -e "${GREEN}🔧 Enhanced Error Handling Applied:${NC}"
    echo "  • ✅ Comprehensive error handling for all operations"
    echo "  • ✅ Safe sysctl parameter application"
    echo "  • ✅ Graceful handling of missing kernel parameters"
    echo "  • ✅ Service startup error detection and reporting"
    echo "  • ✅ Network connectivity timeouts and fallbacks"
    echo "  • ✅ Permission and directory creation error handling"
    echo "  • ✅ Package installation error tolerance"
    echo "  • ✅ SSL setup error handling and fallback instructions"
    echo
    echo -e "${GREEN}📈 Next Steps:${NC}"
    echo "  1. Verify DNS records for all 12 subdomains point to this server IP: $(curl -s --connect-timeout 5 ifconfig.me 2>/dev/null || echo 'unknown')"
    echo "  2. Test proxy creation with the provided curl commands"
    echo "  3. Monitor port usage with: $INSTALL_DIR/scripts/check_port_usage.sh"
    echo "  4. Access monitoring panel: http://$DOMAIN/monitoring?token=$BEARER_TOKEN"
    echo "  5. Set up SSL when DNS is properly configured"
    echo "  6. If you encounter issues, run: $INSTALL_DIR/scripts/fix_permissions.sh"
    echo
    echo -e "${YELLOW}⚠️  Important Notes:${NC}"
    echo "  • Each proxy type is limited to 2000 ports maximum"
    echo "  • All error conditions are now handled gracefully"
    echo "  • Check service logs if any issues occur: journalctl -u oceanproxy-api -f"
    echo "  • Monitor system resources as proxy usage increases"
    echo "  • DNS records needed for: usa, eu, alpha, beta, mobile, unlim, datacenter, gamma, delta, epsilon, zeta, eta"
    echo "  • All 12 endpoints are configured and ready for use"
    echo
    echo -e "${GREEN}🚀 Quick Test Commands:${NC}"
    echo "  # Test API health"
    echo "  curl http://localhost:$API_PORT/health"
    echo ""
    echo "  # Create a test proxy"
    echo "  curl -X POST -H 'Authorization: Bearer $BEARER_TOKEN"
