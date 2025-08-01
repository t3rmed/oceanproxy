# 🌊 OceanProxy - Whitelabel HTTP Proxy Service

[![Go Version](https://img.shields.io/badge/Go-1.19+-blue.svg)](https://golang.org)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Build Status](https://img.shields.io/badge/Build-Passing-success.svg)](https://github.com/t3rmed/oceanproxy)

**Transform into a proxy reseller with your own brand!** OceanProxy is a sophisticated whitelabel HTTP proxy service that allows you to purchase bulk proxy access from upstream providers and resell it under your own brand with premium pricing.

## 💰 Business Model

- **Buy wholesale**: $5/month per proxy from providers
- **Sell retail**: $15/month per proxy under your brand  
- **Keep the difference**: $10/month profit per customer
- **Scale infinitely**: Handle thousands of customers automatically

## 🏗️ Architecture

```
Customer Request → Go API → Create Upstream Account → Spawn 3proxy → Update nginx → Customer Ready
Customer Traffic → nginx Load Balancer → 3proxy Instance → Upstream Provider → Response
```

### Component Stack
- **Go REST API** - Customer management, billing, plan creation
- **nginx Stream Module** - Load balances customer connections
- **3proxy Instances** - Individual proxy processes (one per customer)  
- **Shell Scripts** - System automation and maintenance
- **JSON Log** - Centralized proxy plan storage

## 🚀 Quick Start

### Prerequisites

- **Server**: Ubuntu 20.04+ or CentOS 7+ with 2GB+ RAM
- **Network**: Public IP with ports 80, 443, 1337, 1338, 9876, 9090 open
- **Domain**: Your branded domain (e.g., oceanproxy.io)
- **API Keys**: Proxies.fo and Nettify.xyz accounts

### DNS Configuration

Point these subdomains to your server IP:
```
usa.yourdomain.com     → YOUR_SERVER_IP
eu.yourdomain.com      → YOUR_SERVER_IP  
alpha.yourdomain.com   → YOUR_SERVER_IP
api.yourdomain.com     → YOUR_SERVER_IP (optional)
```

### Automated Installation

```bash
# Download setup script
curl -o oceanproxy-setup.sh https://raw.githubusercontent.com/t3rmed/oceanproxy/main/setup/oceanproxy-setup.sh
chmod +x oceanproxy-setup.sh

# Interactive setup
sudo ./oceanproxy-setup.sh

# Or unattended setup
sudo GITHUB_TOKEN="your_token" \
     PROXIES_FO_API_KEY="your_key" \
     NETTIFY_API_KEY="your_key" \
     DOMAIN="oceanproxy.io" \
     BEARER_TOKEN="your_secure_token" \
     ./oceanproxy-setup.sh --unattended
```

## 📖 Manual Installation

If you prefer manual setup or the script fails, follow these steps:

### 1. Install Dependencies

```bash
# Ubuntu/Debian
sudo apt update && sudo apt install -y \
    golang-go nginx 3proxy git curl jq htop \
    fail2ban ufw certbot python3-certbot-nginx

# CentOS/RHEL
sudo yum install -y epel-release && sudo yum install -y \
    golang nginx git curl jq htop fail2ban firewalld \
    certbot python3-certbot-nginx
```

### 2. Clone Repository

```bash
sudo mkdir -p /opt/oceanproxy
cd /opt/oceanproxy
sudo git clone https://github.com/t3rmed/oceanproxy.git app
sudo useradd -r -s /bin/false oceanproxy
sudo chown -R oceanproxy:oceanproxy /opt/oceanproxy
```

### 3. Build Application

```bash
cd /opt/oceanproxy/app/backend
sudo -u oceanproxy go mod tidy
sudo -u oceanproxy go build -o exec/oceanproxy cmd/main.go
sudo chmod +x scripts/*.sh
```

### 4. Configure Environment

```bash
sudo -u oceanproxy tee /opt/oceanproxy/app/backend/exec/.env << EOF
API_KEY=your_proxies_fo_api_key
BEARER_TOKEN=your_secure_bearer_token
DOMAIN=oceanproxy.io
NETTIFY_API_KEY=your_nettify_api_key
PORT=9090
HOST=0.0.0.0
EOF
```

### 5. Configure nginx

See the setup script for complete nginx configuration examples.

### 6. Create System Services

Create systemd services for API, monitoring, and cleanup. See the setup script for complete service definitions.

## 🌐 API Reference

### Authentication
All protected endpoints require Bearer token:
```bash
Authorization: Bearer your_secure_bearer_token
```

### Endpoints

#### Health Check
```bash
GET /health
# Response: {"status":"healthy","timestamp":"2025-01-XX..."}
```

#### Create Proxies.fo Plan
```bash
POST /plan
Authorization: Bearer YOUR_TOKEN
Content-Type: application/x-www-form-urlencoded

reseller=residential&bandwidth=5&username=customer1&password=pass123

# Response:
{
  "success": true,
  "plan_id": "d5cb155c-c1ca-1df2-5410-3f46f5ef6582",
  "username": "yourfbeh4s", 
  "password": "lulqvwesuj",
  "expires_at": 1734567890,
  "proxies": [
    "http://yourfbeh4s:lulqvwesuj@usa.oceanproxy.io:1337",
    "http://yourfbeh4s:lulqvwesuj@eu.oceanproxy.io:1338"
  ]
}
```

#### Create Nettify Plan
```bash
POST /nettify/plan
Authorization: Bearer YOUR_TOKEN
Content-Type: application/x-www-form-urlencoded

plan_type=residential&bandwidth=2&username=customer2&password=pass456

# Response:
{
  "success": true,
  "plan_id": "abc123def456",
  "username": "customer2_1722386305",
  "password": "pass456",
  "expires_at": 0,
  "proxies": [
    "http://customer2_1722386305:pass456@alpha.oceanproxy.io:9876"
  ]
}
```

#### List All Proxies
```bash
GET /proxies
Authorization: Bearer YOUR_TOKEN

# Returns raw JSON from /var/log/oceanproxy/proxies.json
```

#### System Restore
```bash
POST /restore
Authorization: Bearer YOUR_TOKEN

# Rebuilds all proxy instances from log
```

#### Port Monitoring
```bash
GET /ports
Authorization: Bearer YOUR_TOKEN

# Returns list of ports in use
```

## 🔧 Management Commands

### Daily Operations

```bash
# Check API status
sudo systemctl status oceanproxy-api

# View API logs
sudo tail -f /var/log/oceanproxy/api.log

# Health check all proxies
cd /opt/oceanproxy/app/backend/scripts
./ensure_proxies.sh

# Test all proxy connectivity
./curl_commands.sh --parallel

# Check for expired plans
./check_expired_plans.sh --cleanup

# Create backup
./backup.sh
```

### Scripts Reference

| Script | Purpose | Usage |
|--------|---------|-------|
| `create_proxy_plan.sh` | Create individual proxy plan | `./create_proxy_plan.sh $PLAN_ID $PORT $USER $PASS $HOST $AUTH_PORT $SUBDOMAIN` |
| `automatic_proxy_manager.sh` | Rebuild entire system | `./automatic_proxy_manager.sh` |
| `activate_all_proxies.sh` | Start all proxy instances | `./activate_all_proxies.sh` |
| `ensure_proxies.sh` | Health monitoring | `./ensure_proxies.sh --restart --quiet` |
| `check_expired_plans.sh` | Clean expired plans | `./check_expired_plans.sh --cleanup` |
| `cleanup_invalid_plans.sh` | Fix broken plans | `./cleanup_invalid_plans.sh --fix` |
| `curl_commands.sh` | Test all proxies | `./curl_commands.sh --parallel` |

## 📁 Project Structure

```
oceanproxy/
├── backend/
│   ├── cmd/main.go              # API server entry point
│   ├── config/env.go            # Environment configuration
│   ├── handlers/                # HTTP request handlers
│   │   ├── auth.go              # Authentication
│   │   ├── create_plan.go       # Plan creation
│   │   ├── get_proxies.go       # List proxies
│   │   └── restore.go           # System recovery
│   ├── providers/               # Upstream provider APIs
│   │   ├── nettify.go           # Nettify integration
│   │   └── proxiesfo.go         # Proxies.fo integration
│   ├── proxy/                   # Core proxy management
│   │   ├── entry.go             # Data structures
│   │   ├── log.go               # JSON logging
│   │   └── spawn.go             # 3proxy management
│   ├── scripts/                 # Automation scripts
│   └── exec/                    # Compiled binaries
├── setup/
│   └── oceanproxy-setup.sh      # Automated setup script
└── docs/                        # Documentation
```

## 🔐 Security

### Firewall Configuration
```bash
# Ports that need to be open:
# 22   - SSH
# 80   - HTTP
# 443  - HTTPS
# 1337 - USA proxy endpoint
# 1338 - EU proxy endpoint
# 9876 - Alpha proxy endpoint
# 9090 - API (consider restricting)
```

### fail2ban Protection
The system includes fail2ban jails for:
- API authentication failures
- Proxy abuse attempts
- nginx connection flooding

### SSL/TLS
- Automatic Let's Encrypt certificates
- HTTPS redirect for web traffic
- Secure proxy connections

## 📊 Monitoring

### Health Checks
```bash
# API health
curl http://localhost:9090/health

# Service status
sudo systemctl status oceanproxy-api nginx

# Proxy connectivity
cd /opt/oceanproxy/app/backend/scripts
./curl_commands.sh
```

### Log Files
- **API Logs**: `/var/log/oceanproxy/api.log`
- **Proxy Database**: `/var/log/oceanproxy/proxies.json`
- **nginx Logs**: `/var/log/oceanproxy/nginx/`
- **3proxy Logs**: `/var/log/oceanproxy/3proxy/`

### Performance Metrics
- **Active 3proxy processes**: `ps aux | grep 3proxy | wc -l`
- **Total plans**: `jq length /var/log/oceanproxy/proxies.json`
- **Port usage**: `netstat -tlnp | grep ":1337\|:1338\|:9876"`

## 🚨 Troubleshooting

### Common Issues

#### API Won't Start
```bash
# Check logs
sudo journalctl -u oceanproxy-api -f

# Verify environment
sudo cat /opt/oceanproxy/app/backend/exec/.env

# Test manually
cd /opt/oceanproxy/app/backend
sudo -u oceanproxy ./exec/oceanproxy
```

#### nginx Errors
```bash
# Test configuration
sudo nginx -t

# Check error logs  
sudo tail -f /var/log/nginx/error.log

# Reload configuration
sudo systemctl reload nginx
```

#### Proxy Connection Issues
```bash
# Check 3proxy processes
ps aux | grep 3proxy

# Test upstream providers
curl -x pr-us.proxies.fo:13337 -U username:password http://httpbin.org/ip

# Restart all proxies
cd /opt/oceanproxy/app/backend/scripts
./activate_all_proxies.sh
```

#### Port Conflicts
```bash
# Find what's using a port
sudo lsof -i :10000

# Clean up conflicts
./scripts/cleanup_invalid_plans.sh --fix
```

### Emergency Recovery
```bash
# Nuclear option: rebuild everything
cd /opt/oceanproxy/app/backend/scripts
sudo -u oceanproxy ./automatic_proxy_manager.sh

# Restore from logs
curl -X POST -H "Authorization: Bearer YOUR_TOKEN" \
     http://localhost:9090/restore
```

## 🎯 Customer Experience

Your customers get:
- **Branded Endpoints**: `usa.oceanproxy.io:1337`, `eu.oceanproxy.io:1338`
- **Simple Credentials**: Username and password authentication
- **Instant Activation**: Ready within seconds
- **Load Balanced**: Automatic distribution
- **Regional Options**: Multiple geographic endpoints

### Customer Usage Example
```bash
# Your customer uses your branded service
curl -x usa.oceanproxy.io:1337 -U customer123:password123 http://httpbin.org/ip

# Behind the scenes:
# nginx → 3proxy → upstream provider → response
```

## 📈 Scaling

### Performance Tuning
The setup script automatically optimizes:
- File descriptor limits
- Kernel network parameters
- nginx worker processes
- Connection pooling

### Scaling Indicators
- **100+ plans**: Consider dedicated monitoring
- **500+ plans**: Implement database storage
- **1000+ plans**: Consider clustering
- **5000+ plans**: You're generating serious revenue! 💰

## 🎨 Next Steps

1. **Build Frontend**: Create customer dashboard
2. **Add Billing**: Integrate Stripe/PayPal
3. **Add Analytics**: Track usage and metrics
4. **Implement Monitoring**: Set up alerting
5. **Scale Globally**: Add more regions
6. **Go Enterprise**: Offer dedicated pools

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [3proxy](https://github.com/3proxy/3proxy) - Lightweight proxy server
- [nginx](https://nginx.org/) - High-performance web server
- [Go](https://golang.org/) - The Go programming language

## 📞 Support

- **Documentation**: Check this README and inline code comments
- **Issues**: Use GitHub Issues for bug reports
- **Security**: Email security issues privately

---

**Start your proxy reselling business today!** 🌊💰

Transform bulk proxy access into a profitable whitelabel service with OceanProxy.
