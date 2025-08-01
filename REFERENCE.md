# 🌊 OceanProxy Quick Reference Card

## 🚀 Installation Commands

```bash
# Download and run setup script
curl -o oceanproxy-setup.sh https://raw.githubusercontent.com/t3rmed/oceanproxy/main/setup/oceanproxy-setup.sh
chmod +x oceanproxy-setup.sh
sudo ./oceanproxy-setup.sh

# Unattended installation
sudo GITHUB_TOKEN="ghp_xxx" \
     PROXIES_FO_API_KEY="your_key" \
     NETTIFY_API_KEY="your_key" \
     DOMAIN="oceanproxy.io" \
     BEARER_TOKEN="secure_token" \
     ./oceanproxy-setup.sh --unattended
```

## 🔧 Daily Management Commands

```bash
# Service Management
sudo systemctl status oceanproxy-api        # Check API status
sudo systemctl restart oceanproxy-api       # Restart API
sudo systemctl reload nginx                 # Reload nginx config

# Logs and Monitoring
sudo tail -f /var/log/oceanproxy/api.log    # View API logs
sudo tail -f /var/log/nginx/error.log       # View nginx errors
sudo journalctl -u oceanproxy-api -f        # Follow API service logs

# Health Checks
cd /opt/oceanproxy/app/backend/scripts
./ensure_proxies.sh                         # Check all proxies
./ensure_proxies.sh --restart               # Restart failed proxies
./curl_commands.sh --parallel               # Test all connectivity

# Maintenance
./check_expired_plans.sh --cleanup          # Remove expired plans
./cleanup_invalid_plans.sh --fix            # Fix broken configurations
./automatic_proxy_manager.sh                # Nuclear rebuild option
```

## 🌐 API Quick Commands

```bash
# Set your Bearer token
export BEARER_TOKEN="your_secure_bearer_token"
export API_URL="http://localhost:9090"

# Health check
curl $API_URL/health

# Create Proxies.fo plan
curl -X POST $API_URL/plan \
  -H "Authorization: Bearer $BEARER_TOKEN" \
  -d "reseller=residential&bandwidth=5&username=customer1&password=pass123"

# Create Nettify plan
curl -X POST $API_URL/nettify/plan \
  -H "Authorization: Bearer $BEARER_TOKEN" \
  -d "plan_type=residential&bandwidth=2&username=customer2&password=pass456"

# List all proxies
curl -H "Authorization: Bearer $BEARER_TOKEN" $API_URL/proxies | jq .

# System restore
curl -X POST -H "Authorization: Bearer $BEARER_TOKEN" $API_URL/restore

# Check ports
curl -H "Authorization: Bearer $BEARER_TOKEN" $API_URL/ports | jq .
```

## 📁 Important File Locations

```bash
# Configuration
/opt/oceanproxy/app/backend/exec/.env           # Environment variables
/etc/nginx/conf.d/oceanproxy-stream.conf        # nginx stream config
/etc/systemd/system/oceanproxy-*.service        # System services

# Data and Logs
/var/log/oceanproxy/proxies.json                # Proxy plans database
/var/log/oceanproxy/api.log                     # API logs
/var/log/oceanproxy/nginx/                      # nginx proxy logs
/var/log/oceanproxy/3proxy/                     # 3proxy logs

# Scripts
/opt/oceanproxy/app/backend/scripts/            # All management scripts
/opt/oceanproxy/backups/                        # Backup storage
```

## 🔥 Emergency Commands

```bash
# Full system restart
sudo systemctl restart oceanproxy-api nginx
cd /opt/oceanproxy/app/backend/scripts && ./activate_all_proxies.sh

# Emergency rebuild (if everything breaks)
cd /opt/oceanproxy/app/backend/scripts
sudo -u oceanproxy ./automatic_proxy_manager.sh

# Restore from backup
curl -X POST -H "Authorization: Bearer $BEARER_TOKEN" \
     http://localhost:9090/restore

# Find and kill rogue processes
sudo pkill -f 3proxy
sudo systemctl restart oceanproxy-api

# Fix port conflicts
cd /opt/oceanproxy/app/backend/scripts
./cleanup_invalid_plans.sh --fix

# Check what's using specific port
sudo lsof -i :10000
sudo netstat -tlnp | grep :1337
```

## 🚨 Troubleshooting Quick Fixes

```bash
# API won't start
sudo journalctl -u oceanproxy-api --no-pager -l
cd /opt/oceanproxy/app/backend && sudo -u oceanproxy ./exec/oceanproxy

# nginx errors
sudo nginx -t
sudo systemctl reload nginx

# Proxy not working
ps aux | grep 3proxy
curl -x pr-us.proxies.fo:13337 -U username:password http://httpbin.org/ip

# Disk space issues
sudo du -sh /var/log/oceanproxy/*
sudo logrotate -f /etc/logrotate.d/oceanproxy

# Performance issues
sudo htop
sudo netstat -tulnp
sudo ss -tulnp
```

## 📊 Monitoring One-Liners

```bash
# Count active proxies
ps aux | grep 3proxy | grep -v grep | wc -l

# Count total plans
jq length /var/log/oceanproxy/proxies.json

# Check listening ports
sudo netstat -tlnp | grep -E ":(1337|1338|9876|9090) "

# Memory usage
sudo systemctl status oceanproxy-api | grep Memory

# Disk usage
df -h /opt/oceanproxy /var/log/oceanproxy

# Last 10 API requests
sudo tail -10 /var/log/oceanproxy/api.log

# Check nginx upstream status
sudo nginx -T | grep -A 5 upstream

# Test all proxy endpoints
for port in 1337 1338 9876; do
  echo "Testing port $port..."
  curl -s --max-time 5 -I http://localhost:$port || echo "Failed"
done
