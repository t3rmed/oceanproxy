#!/bin/bash

# 🧹 OceanProxy Complete Cleanup Script
# This script removes EVERYTHING installed by the OceanProxy setup script
# Updated to handle 12 proxy endpoints and new port configurations
# Author: OceanProxy Team
# Version: 1.1.0

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_VERSION="1.1.0"  # Updated version
INSTALL_DIR="/opt/oceanproxy"
LOG_DIR="/var/log/oceanproxy"
CONFIG_DIR="/etc/oceanproxy"
SERVICE_USER="oceanproxy"

# Runtime flags
FORCE=false
KEEP_DEPS=false
KEEP_NGINX=false
KEEP_GO=false

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
    echo -e "${RED}"
    cat << 'EOF'
    ╔═══════════════════════════════════════════════════════════╗
    ║                🧹 OceanProxy Cleanup                      ║
    ║          Complete Removal of All Components              ║
    ║         Including All 12 Proxy Endpoints                 ║
    ║                                                           ║
    ║        ⚠️  THIS WILL DELETE EVERYTHING! ⚠️                ║
    ╚═══════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    echo "Version: $SCRIPT_VERSION"
    echo
}

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

OceanProxy Complete Cleanup Script - Removes ALL OceanProxy components

OPTIONS:
    --force             Skip confirmation prompts
    --keep-deps         Keep system dependencies (nginx, fail2ban, etc.)
    --keep-nginx        Keep nginx (only remove OceanProxy configs)
    --keep-go           Keep Go installation
    --help              Show this help message

EXAMPLES:
    # Interactive cleanup (recommended)
    sudo ./oceanproxy-cleanup.sh

    # Force cleanup without prompts
    sudo ./oceanproxy-cleanup.sh --force

    # Keep nginx but remove OceanProxy configs
    sudo ./oceanproxy-cleanup.sh --keep-nginx

    # Keep all dependencies, only remove OceanProxy
    sudo ./oceanproxy-cleanup.sh --keep-deps

EOF
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root. Use: sudo $0"
    fi
}

confirm_cleanup() {
    if [[ "$FORCE" == "true" ]]; then
        log "Force mode enabled, skipping confirmations"
        return
    fi
    
    echo
    warn "This will PERMANENTLY DELETE all OceanProxy components:"
    echo "  • All 12 proxy endpoints and their configurations"
    echo "  • All proxy services (up to 24,000 proxies)"
    echo "  • User data and logs"
    echo "  • nginx configurations"
    echo "  • System services"
    echo "  • Firewall rules (12 proxy ports)"
    echo "  • SSL certificates (if any)"
    echo "  • Port monitoring scripts"
    
    if [[ "$KEEP_DEPS" != "true" ]]; then
        echo "  • System dependencies (nginx, fail2ban, etc.)"
    fi
    
    if [[ "$KEEP_GO" != "true" ]]; then
        echo "  • Go installation"
    fi
    
    echo
    read -p "Are you ABSOLUTELY SURE you want to continue? (type 'DELETE' to confirm): " -r
    if [[ $REPLY != "DELETE" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    echo
    read -p "Last chance! This cannot be undone. Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
}

stop_services() {
    log "Stopping all OceanProxy services..."
    
    # Stop systemd services
    systemctl stop oceanproxy-api 2>/dev/null || true
    systemctl stop oceanproxy-monitor.timer 2>/dev/null || true
    systemctl stop oceanproxy-cleanup.timer 2>/dev/null || true
    systemctl stop oceanproxy-monitor.service 2>/dev/null || true
    systemctl stop oceanproxy-cleanup.service 2>/dev/null || true
    
    # Disable services
    systemctl disable oceanproxy-api 2>/dev/null || true
    systemctl disable oceanproxy-monitor.timer 2>/dev/null || true
    systemctl disable oceanproxy-cleanup.timer 2>/dev/null || true
    
    # Kill any remaining 3proxy processes
    log "Killing all 3proxy processes..."
    pkill -f 3proxy 2>/dev/null || true
    pkill -f oceanproxy 2>/dev/null || true
    
    # Wait for processes to die
    sleep 2
    
    # Force kill if still running
    pkill -9 -f 3proxy 2>/dev/null || true
    pkill -9 -f oceanproxy 2>/dev/null || true
    
    # Stop nginx if we're not keeping it
    if [[ "$KEEP_NGINX" != "true" ]]; then
        systemctl stop nginx 2>/dev/null || true
    fi
    
    log "Services stopped"
}

remove_systemd_services() {
    log "Removing systemd services..."
    
    # Remove service files
    rm -f /etc/systemd/system/oceanproxy-api.service
    rm -f /etc/systemd/system/oceanproxy-monitor.service
    rm -f /etc/systemd/system/oceanproxy-monitor.timer
    rm -f /etc/systemd/system/oceanproxy-cleanup.service
    rm -f /etc/systemd/system/oceanproxy-cleanup.timer
    
    # Reload systemd
    systemctl daemon-reload
    systemctl reset-failed 2>/dev/null || true
    
    log "Systemd services removed"
}

remove_nginx_configs() {
    log "Removing nginx configurations..."
    
    # Remove OceanProxy nginx configs
    rm -f /etc/nginx/conf.d/oceanproxy*.conf
    rm -f /etc/nginx/sites-available/oceanproxy
    rm -f /etc/nginx/sites-enabled/oceanproxy
    
    # Remove stream configurations directory
    rm -rf /etc/nginx/stream.d
    
    # Restore original nginx.conf if backup exists
    if [[ -f /etc/nginx/nginx.conf.backup ]]; then
        log "Restoring original nginx configuration..."
        cp /etc/nginx/nginx.conf.backup /etc/nginx/nginx.conf
        rm -f /etc/nginx/nginx.conf.backup
    else
        warn "No nginx backup found, you may need to reinstall nginx configuration manually"
    fi
    
    # Remove all nginx.conf backups created by the setup script
    rm -f /etc/nginx/nginx.conf.backup.* 2>/dev/null || true
    
    # Test nginx configuration
    if [[ "$KEEP_NGINX" == "true" ]] || [[ "$KEEP_DEPS" == "true" ]]; then
        if nginx -t 2>/dev/null; then
            systemctl restart nginx
            log "nginx configuration restored and restarted"
        else
            warn "nginx configuration test failed, you may need to fix it manually"
        fi
    fi
    
    log "nginx configurations removed"
}

remove_ssl_certificates() {
    log "Removing SSL certificates..."
    
    # Check for certbot certificates
    if command -v certbot &> /dev/null; then
        # List and remove OceanProxy certificates
        CERTS=$(certbot certificates 2>/dev/null | grep -E "(oceanproxy|api\.)" | grep "Certificate Name:" | awk '{print $3}' || true)
        
        if [[ -n "$CERTS" ]]; then
            log "Found SSL certificates to remove:"
            echo "$CERTS"
            
            while IFS= read -r cert; do
                if [[ -n "$cert" ]]; then
                    log "Removing certificate: $cert"
                    certbot delete --cert-name "$cert" --non-interactive 2>/dev/null || true
                fi
            done <<< "$CERTS"
        else
            log "No OceanProxy SSL certificates found"
        fi
    else
        log "certbot not found, skipping SSL certificate removal"
    fi
    
    # Remove certbot timer if no certificates remain
    REMAINING_CERTS=$(certbot certificates 2>/dev/null | grep "Certificate Name:" | wc -l || echo "0")
    if [[ "$REMAINING_CERTS" -eq 0 ]]; then
        systemctl stop certbot.timer 2>/dev/null || true
        systemctl disable certbot.timer 2>/dev/null || true
        log "Disabled certbot timer (no certificates remaining)"
    fi
    
    log "SSL certificates removed"
}

remove_firewall_rules() {
    log "Removing firewall rules for all 12 proxy endpoints..."
    
    # Check OS type for firewall management
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        case $ID in
            ubuntu|debian)
                # Reset UFW if it's active
                if ufw status | grep -q "Status: active"; then
                    log "Resetting UFW firewall rules..."
                    ufw --force reset
                    ufw default deny incoming
                    ufw default allow outgoing
                    ufw allow 22/tcp  # Keep SSH access
                    ufw --force enable
                fi
                ;;
            centos|rhel|rocky|almalinux)
                # Remove specific firewall rules for all proxy ports
                if systemctl is-active --quiet firewalld; then
                    log "Removing firewall rules for all proxy ports..."
                    # Original ports
                    firewall-cmd --permanent --remove-port=1337/tcp 2>/dev/null || true
                    firewall-cmd --permanent --remove-port=1338/tcp 2>/dev/null || true
                    firewall-cmd --permanent --remove-port=9876/tcp 2>/dev/null || true
                    firewall-cmd --permanent --remove-port=8765/tcp 2>/dev/null || true
                    firewall-cmd --permanent --remove-port=7654/tcp 2>/dev/null || true
                    firewall-cmd --permanent --remove-port=6543/tcp 2>/dev/null || true
                    firewall-cmd --permanent --remove-port=1339/tcp 2>/dev/null || true
                    # New ports
                    firewall-cmd --permanent --remove-port=5432/tcp 2>/dev/null || true
                    firewall-cmd --permanent --remove-port=4321/tcp 2>/dev/null || true
                    firewall-cmd --permanent --remove-port=3210/tcp 2>/dev/null || true
                    firewall-cmd --permanent --remove-port=2109/tcp 2>/dev/null || true
                    firewall-cmd --permanent --remove-port=1098/tcp 2>/dev/null || true
                    # API port
                    firewall-cmd --permanent --remove-port=9090/tcp 2>/dev/null || true
                    firewall-cmd --reload 2>/dev/null || true
                fi
                ;;
        esac
    fi
    
    log "Firewall rules updated"
}

remove_fail2ban_config() {
    log "Removing fail2ban configuration..."
    
    # Remove OceanProxy fail2ban configs
    rm -f /etc/fail2ban/jail.d/oceanproxy.conf
    rm -f /etc/fail2ban/filter.d/oceanproxy-api.conf
    
    # Restart fail2ban if it's running and we're keeping it
    if [[ "$KEEP_DEPS" == "true" ]] && systemctl is-active --quiet fail2ban; then
        systemctl restart fail2ban
        log "fail2ban configuration updated"
    fi
    
    log "fail2ban configuration removed"
}

remove_3proxy_configs() {
    log "Removing all 3proxy configurations..."
    
    # Remove 3proxy config directory
    rm -rf /etc/3proxy/plans
    
    # Remove individual 3proxy configs if they exist elsewhere
    find /etc -name "*3proxy*oceanproxy*" -type f -delete 2>/dev/null || true
    
    # Remove 3proxy logs
    rm -f /var/log/3proxy_* 2>/dev/null || true
    
    log "3proxy configurations removed"
}

remove_user_and_directories() {
    log "Removing user and directories..."
    
    # Remove service user
    if id "$SERVICE_USER" &>/dev/null; then
        userdel -r "$SERVICE_USER" 2>/dev/null || true
        log "Removed user: $SERVICE_USER"
    fi
    
    # Remove directories
    rm -rf "$INSTALL_DIR"
    rm -rf "$LOG_DIR"
    rm -rf "$CONFIG_DIR"
    
    # Remove 3proxy config directory
    rm -rf /etc/3proxy
    
    # Remove log rotation config
    rm -f /etc/logrotate.d/oceanproxy
    
    # Remove any remaining process files
    rm -f /run/oceanproxy.pid
    rm -f /var/run/oceanproxy.pid
    
    # Remove any backup directories
    rm -rf /opt/oceanproxy/backups
    
    log "Directories and user removed"
}

remove_cron_jobs() {
    log "Removing cron jobs..."
    
    # Remove root cron jobs
    (crontab -l 2>/dev/null | grep -v "/usr/bin/certbot renew" | grep -v "oceanproxy" || true) | crontab -
    
    # Remove oceanproxy user cron jobs (if user still exists)
    if id "$SERVICE_USER" &>/dev/null; then
        (crontab -u "$SERVICE_USER" -l 2>/dev/null | grep -v "oceanproxy" || true) | crontab -u "$SERVICE_USER" -
    fi
    
    log "Cron jobs removed"
}

remove_dependencies() {
    if [[ "$KEEP_DEPS" == "true" ]]; then
        log "Skipping dependency removal (--keep-deps flag)"
        return
    fi
    
    log "Removing system dependencies..."
    
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        case $ID in
            ubuntu|debian)
                if [[ "$KEEP_NGINX" != "true" ]]; then
                    systemctl stop nginx 2>/dev/null || true
                    systemctl disable nginx 2>/dev/null || true
                    apt remove -y nginx nginx-full nginx-core nginx-common 2>/dev/null || true
                fi
                
                # Remove other OceanProxy-specific dependencies
                apt remove -y 3proxy supervisor bc 2>/dev/null || true
                
                # Remove fail2ban, ufw, certbot (optional)
                read -p "Remove security tools (fail2ban, ufw, certbot)? (y/N): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    apt remove -y fail2ban ufw certbot python3-certbot-nginx 2>/dev/null || true
                fi
                ;;
            centos|rhel|rocky|almalinux)
                if [[ "$KEEP_NGINX" != "true" ]]; then
                    systemctl stop nginx 2>/dev/null || true
                    systemctl disable nginx 2>/dev/null || true
                    yum remove -y nginx 2>/dev/null || true
                fi
                
                yum remove -y supervisor bc 2>/dev/null || true
                
                read -p "Remove security tools (fail2ban, firewalld, certbot)? (y/N): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    yum remove -y fail2ban certbot python3-certbot-nginx 2>/dev/null || true
                fi
                ;;
        esac
        
        # Clean up package cache
        apt autoremove -y 2>/dev/null || yum autoremove -y 2>/dev/null || true
    fi
    
    log "Dependencies removed"
}

remove_go_installation() {
    if [[ "$KEEP_GO" == "true" ]]; then
        log "Skipping Go removal (--keep-go flag)"
        return
    fi
    
    log "Removing Go installation..."
    
    # Remove Go installation
    rm -rf /usr/local/go
    
    # Remove Go from PATH
    rm -f /etc/profile.d/go.sh
    
    # Remove from current session
    export PATH=$(echo $PATH | sed 's|:/usr/local/go/bin||g' | sed 's|/usr/local/go/bin:||g')
    
    log "Go installation removed"
}

cleanup_git_credentials() {
    log "Cleaning up Git credentials..."
    
    # Remove git credentials file
    rm -f /root/.git-credentials
    
    # Reset git global config
    git config --global --unset credential.helper 2>/dev/null || true
    
    log "Git credentials cleaned up"
}

cleanup_kernel_optimizations() {
    log "Removing kernel optimizations..."
    
    # Remove OceanProxy optimizations from sysctl.conf
    if [[ -f /etc/sysctl.conf ]]; then
        # Create backup
        cp /etc/sysctl.conf /etc/sysctl.conf.backup
        
        # Remove OceanProxy optimizations
        sed -i '/# OceanProxy network optimizations/,/^$/d' /etc/sysctl.conf
        
        # Apply changes
        sysctl -p 2>/dev/null || true
    fi
    
    # Remove file descriptor limits
    if [[ -f /etc/security/limits.conf ]]; then
        # Create backup
        cp /etc/security/limits.conf /etc/security/limits.conf.backup
        
        # Remove OceanProxy limits
        sed -i '/# OceanProxy optimizations/,/^$/d' /etc/security/limits.conf
    fi
    
    log "Kernel optimizations removed"
}

verify_cleanup() {
    log "Verifying cleanup..."
    
    # Check for remaining processes
    REMAINING_PROCESSES=$(ps aux | grep -E "(oceanproxy|3proxy)" | grep -v grep | wc -l)
    if [[ $REMAINING_PROCESSES -gt 0 ]]; then
        warn "Found $REMAINING_PROCESSES remaining OceanProxy processes"
        ps aux | grep -E "(oceanproxy|3proxy)" | grep -v grep || true
    else
        log "✅ No remaining OceanProxy processes found"
    fi
    
    # Check for remaining files
    REMAINING_FILES=0
    for dir in "$INSTALL_DIR" "$LOG_DIR" "$CONFIG_DIR" "/etc/3proxy"; do
        if [[ -d "$dir" ]]; then
            ((REMAINING_FILES++))
        fi
    done
    
    if [[ $REMAINING_FILES -gt 0 ]]; then
        warn "Found $REMAINING_FILES remaining directories"
    else
        log "✅ All directories removed"
    fi
    
    # Check for remaining systemd services
    REMAINING_SERVICES=$(systemctl list-unit-files | grep oceanproxy | wc -l)
    if [[ $REMAINING_SERVICES -gt 0 ]]; then
        warn "Found $REMAINING_SERVICES remaining systemd services"
        systemctl list-unit-files | grep oceanproxy || true
    else
        log "✅ All systemd services removed"
    fi
    
    # Check for remaining nginx configs
    REMAINING_NGINX=$(find /etc/nginx -name "*oceanproxy*" 2>/dev/null | wc -l)
    if [[ $REMAINING_NGINX -gt 0 ]]; then
        warn "Found $REMAINING_NGINX remaining nginx configs"
        find /etc/nginx -name "*oceanproxy*" 2>/dev/null || true
    else
        log "✅ All nginx configurations removed"
    fi
    
    # Check for remaining firewall rules (on Ubuntu/Debian)
    if command -v ufw &> /dev/null; then
        REMAINING_RULES=$(ufw status numbered 2>/dev/null | grep -E "(1337|1338|9876|8765|7654|6543|1339|5432|4321|3210|2109|1098|9090)" | wc -l || echo "0")
        if [[ $REMAINING_RULES -gt 0 ]]; then
            warn "Found $REMAINING_RULES remaining firewall rules"
        else
            log "✅ All firewall rules removed"
        fi
    fi
    
    log "Cleanup verification complete"
}

print_summary() {
    echo
    log "🧹 OceanProxy Cleanup Complete!"
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    echo -e "${GREEN}✅ Removed Components:${NC}"
    echo "  • OceanProxy application and services"
    echo "  • All 12 proxy endpoints (usa, eu, alpha, beta, mobile, unlim, datacenter, gamma, delta, epsilon, zeta, eta)"
    echo "  • Up to 24,000 proxy configurations (2000 per endpoint)"
    echo "  • User data and logs"
    echo "  • System services and timers"
    echo "  • nginx configurations and stream module settings"
    echo "  • SSL certificates"
    echo "  • Firewall rules for all proxy ports"
    echo "  • fail2ban configurations"
    echo "  • Cron jobs"
    echo "  • 3proxy configurations and logs"
    echo "  • Kernel optimizations"
    echo "  • Port monitoring scripts"
    
    if [[ "$KEEP_DEPS" != "true" ]]; then
        echo "  • System dependencies"
    fi
    
    if [[ "$KEEP_GO" != "true" ]]; then
        echo "  • Go installation"
    fi
    
    echo
    echo -e "${YELLOW}⚠️  What's Left:${NC}"
    if [[ "$KEEP_DEPS" == "true" ]]; then
        echo "  • System dependencies (kept by --keep-deps)"
    fi
    if [[ "$KEEP_NGINX" == "true" ]]; then
        echo "  • nginx installation (kept by --keep-nginx)"
    fi
    if [[ "$KEEP_GO" == "true" ]]; then
        echo "  • Go installation (kept by --keep-go)"
    fi
    echo "  • SSH access (always preserved)"
    echo "  • Basic system configuration"
    echo "  • Backup files in /etc/*.backup (if any)"
    
    echo
    echo -e "${GREEN}🔄 Next Steps:${NC}"
    echo "  • Server is ready for fresh installation"
    echo "  • All OceanProxy data has been permanently deleted"
    echo "  • You can run the setup script again if needed"
    echo "  • Check /etc/sysctl.conf.backup if you need to restore kernel settings"
    echo "  • Check /etc/security/limits.conf.backup if you need to restore limits"
    
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    log "Your server is now clean! 🎉"
    echo
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE=true
            shift
            ;;
        --keep-deps)
            KEEP_DEPS=true
            shift
            ;;
        --keep-nginx)
            KEEP_NGINX=true
            shift
            ;;
        --keep-go)
            KEEP_GO=true
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

# Main execution
main() {
    banner
    
    # Pre-flight checks
    check_root
    
    # Confirmation
    confirm_cleanup
    
    # Cleanup steps
    log "Starting complete OceanProxy cleanup..."
    echo
    
    stop_services
    remove_systemd_services
    remove_nginx_configs
    remove_3proxy_configs
    remove_ssl_certificates
    remove_firewall_rules
    remove_fail2ban_config
    remove_cron_jobs
    remove_user_and_directories
    cleanup_git_credentials
    cleanup_kernel_optimizations
    
    if [[ "$KEEP_DEPS" != "true" ]]; then
        remove_dependencies
    fi
    
    if [[ "$KEEP_GO" != "true" ]]; then
        remove_go_installation
    fi
    
    # Verification
    verify_cleanup
    
    # Summary
    print_summary
    
    log "Cleanup completed successfully! 🧹"
}

# Run main function
main "$@"
