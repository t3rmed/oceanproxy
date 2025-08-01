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
```

## 🔐 Security Quick Checks

```bash
# Check firewall status
sudo ufw status                              # Ubuntu/Debian
sudo firewall-cmd --list-all                 # CentOS/RHEL

# fail2ban status
sudo fail2ban-client status
sudo fail2ban-client status oceanproxy-api

# Check for suspicious connections
sudo netstat -tulnp | grep :1337 | wc -l
sudo ss -tunap | grep :1338

# SSL certificate status
sudo certbot certificates
sudo systemctl status certbot.timer

# Check for failed login attempts
sudo grep "Authentication failed" /var/log/oceanproxy/api.log | tail -10

# Monitor active connections
sudo watch -n 2 'netstat -an | grep -E ":(1337|1338|9876)" | wc -l'
```

## 💾 Backup & Recovery

```bash
# Manual backup
sudo cp /var/log/oceanproxy/proxies.json \
       /opt/oceanproxy/backups/proxies-$(date +%F).json

# Full config backup
sudo tar -czf /opt/oceanproxy/backups/config-$(date +%F).tar.gz \
       /opt/oceanproxy/app/backend/exec/.env \
       /etc/nginx/conf.d/oceanproxy-stream.conf \
       /etc/nginx/sites-available/oceanproxy

# Restore from backup
sudo cp /opt/oceanproxy/backups/proxies-YYYY-MM-DD.json \
        /var/log/oceanproxy/proxies.json
curl -X POST -H "Authorization: Bearer $BEARER_TOKEN" \
     http://localhost:9090/restore

# Check backup schedule
sudo crontab -u oceanproxy -l
```

## 📈 Performance Optimization

```bash
# Check system resources
htop
free -h
df -h
iostat 1 5

# nginx performance tuning
sudo nginx -T | grep worker
sudo systemctl reload nginx

# Check connection limits
ulimit -n
cat /proc/sys/fs/file-max

# Monitor 3proxy performance
sudo strace -p $(pgrep 3proxy | head -1) -c 10

# Network performance
sudo ss -i
sudo netstat -s | grep -i error
```

## 🔄 Update and Deployment

```bash
# Update from Git
cd /opt/oceanproxy/app
sudo -u oceanproxy git pull origin main

# Rebuild application
cd backend
sudo -u oceanproxy go build -o exec/oceanproxy cmd/main.go

# Rolling restart
sudo systemctl restart oceanproxy-api
sleep 5
cd scripts && ./ensure_proxies.sh --restart

# Verify deployment
curl http://localhost:9090/health
./curl_commands.sh --parallel
```

## 📞 Customer Support Debugging

```bash
# Find customer's proxy plan
export CUSTOMER_USER="customer123"
jq ".[] | select(.username == \"$CUSTOMER_USER\")" /var/log/oceanproxy/proxies.json

# Check if customer's proxy is running
export CUSTOMER_PORT=10005
sudo lsof -i :$CUSTOMER_PORT
ps aux | grep $CUSTOMER_PORT

# Test customer's specific proxy
export PROXY_URL="customer123:password123@usa.oceanproxy.io:1337"
curl -x $PROXY_URL http://httpbin.org/ip

# Check customer's connection logs
sudo grep "$CUSTOMER_USER" /var/log/oceanproxy/nginx/*_access.log | tail -10

# Restart customer's specific proxy
cd /opt/oceanproxy/app/backend/scripts
./create_proxy_plan.sh PLAN_ID $CUSTOMER_PORT $CUSTOMER_USER password auth_host auth_port subdomain
```

## 🌐 DNS and Network Diagnostics

```bash
# Check DNS resolution
dig usa.oceanproxy.io
nslookup eu.oceanproxy.io

# Test external connectivity
curl -4 ifconfig.me
curl -6 ifconfig.me

# Check routing
traceroute google.com
mtr --report google.com

# Test upstream providers
curl -x pr-us.proxies.fo:13337 -U test:test http://httpbin.org/ip --max-time 10
curl -x rotating-residential.nettify.xyz:8000 -U test:test http://httpbin.org/ip --max-time 10
```

## 📱 Mobile/Remote Management

```bash
# SSH tunnel for secure remote access
ssh -L 9090:localhost:9090 user@your-server.com

# Check status via API (from anywhere)
curl -H "Authorization: Bearer $BEARER_TOKEN" \
     https://api.oceanproxy.io/health

# Remote log monitoring
ssh user@server 'tail -f /var/log/oceanproxy/api.log'

# Emergency shutdown (if needed)
ssh user@server 'sudo systemctl stop oceanproxy-api nginx'
```

## 🎯 Business Metrics

```bash
# Count paying customers
jq '[.[] | select(.expires_at > now)] | length' /var/log/oceanproxy/proxies.json

# Revenue calculation (assuming $15/month per customer)
ACTIVE_CUSTOMERS=$(jq '[.[] | select(.expires_at > now)] | length' /var/log/oceanproxy/proxies.json)
echo "Monthly Revenue: \$(($ACTIVE_CUSTOMERS * 15))"

# Usage analytics
sudo awk '{print $1}' /var/log/oceanproxy/nginx/*_access.log | sort | uniq -c | sort -nr | head -10

# Top customers by usage
sudo awk '{print $1}' /var/log/oceanproxy/nginx/*_access.log | sort | uniq -c | sort -nr | head -20
```

## 🎉 Success Indicators

```bash
# System health check
echo "=== OceanProxy Health Report ==="
echo "API Status: $(curl -s http://localhost:9090/health | jq -r .status 2>/dev/null || echo 'ERROR')"
echo "nginx Status: $(systemctl is-active nginx)"
echo "Active Proxies: $(ps aux | grep 3proxy | grep -v grep | wc -l)"
echo "Total Plans: $(jq length /var/log/oceanproxy/proxies.json 2>/dev/null || echo '0')"
echo "Disk Usage: $(df -h /opt/oceanproxy | tail -1 | awk '{print $5}')"
echo "Memory Usage: $(free | grep Mem | awk '{printf("%.1f%%\n", $3/$2 * 100.0)}')"
echo "Load Average: $(uptime | awk -F'load average:' '{print $2}')"
echo "================================"

# Quick profit calculator
echo "=== Profit Calculator ==="
TOTAL_PLANS=$(jq length /var/log/oceanproxy/proxies.json 2>/dev/null || echo 0)
MONTHLY_REVENUE=$((TOTAL_PLANS * 15))
MONTHLY_COSTS=$((TOTAL_PLANS * 5))
MONTHLY_PROFIT=$((MONTHLY_REVENUE - MONTHLY_COSTS))
echo "Total Customers: $TOTAL_PLANS"
echo "Monthly Revenue: \$MONTHLY_REVENUE"
echo "Monthly Costs: \$MONTHLY_COSTS"
echo "Monthly Profit: \$MONTHLY_PROFIT"
echo "============================="
```

---

## 🔖 Bookmarks for Quick Access

**Save these URLs for quick access:**
- Health Check: `http://localhost:9090/health`
- Server Stats: `htop`
- Log Viewer: `tail -f /var/log/oceanproxy/api.log`
- Script Directory: `cd /opt/oceanproxy/app/backend/scripts`

**Remember:** 
- Always test changes in a staging environment first
- Keep backups of your proxy database
- Monitor your upstream provider quotas
- Scale gradually and monitor performance

**Your OceanProxy service is now ready to generate recurring revenue! 🌊💰**
