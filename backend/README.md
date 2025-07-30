# 🌊 OceanProxy Backend - Complete Project Walkthrough
## Your Whitelabel HTTP Proxy Service

---

## 🎯 Project Overview

**OceanProxy** is a sophisticated whitelabel HTTP proxy service that transforms you into a proxy reseller. You purchase bulk proxy access from upstream providers (proxies.fo, nettify.xyz) and resell it under your own brand (oceanproxy.io) with premium pricing.

### **💰 Business Model**
- **Buy wholesale**: $5/month per proxy from providers
- **Sell retail**: $15/month per proxy under your brand  
- **Keep the difference**: $10/month profit per customer
- **Scale infinitely**: Handle thousands of customers automatically

### **🔄 Technical Flow**
```
Customer Request → Go API → Create Upstream Account → Spawn 3proxy → Update nginx → Customer Ready
Customer Traffic → nginx Load Balancer → 3proxy Instance → Upstream Provider → Response
```

---

## 🏗️ System Architecture

### **Component Stack**
1. **Go REST API** - Customer management, billing, plan creation
2. **nginx Stream Module** - Load balances customer connections
3. **3proxy Instances** - Individual proxy processes (one per customer)  
4. **Shell Scripts** - System automation and maintenance
5. **JSON Log** - Centralized proxy plan storage

### **Data Flow Diagram**
```mermaid
graph TD
    A[Customer API Request] --> B[Go Handlers]
    B --> C[Provider APIs]
    C --> D[Create Upstream Account]
    D --> E[Spawn 3proxy Instance]
    E --> F[Update nginx Config]
    F --> G[Customer Ready]
    
    H[Customer Traffic] --> I[nginx :1337/:1338/:9876]
    I --> J[3proxy :10000+]
    J --> K[Upstream Provider]
    K --> J --> I --> H
```

---

## 📁 Project Structure Deep Dive

```
oceanproxy-api/backend/
├── cmd/main.go                 # 🚀 API Server Entry Point
├── config/env.go              # ⚙️ Environment Configuration  
├── exec/                      # 📦 Compiled Binaries
│   ├── oceanproxy            # Main executable
│   └── .env                  # Environment variables
├── handlers/                  # 🌐 HTTP Request Handlers
│   ├── auth.go              # 🔐 Bearer token authentication
│   ├── create_plan.go       # ➕ Plan creation logic
│   ├── get_proxies.go       # 📋 List proxy plans
│   ├── json.go              # 🔧 JSON utilities
│   ├── ports.go             # 🔌 Port monitoring
│   └── restore.go           # 🔄 System recovery
├── providers/                 # 🔗 Upstream Provider APIs
│   ├── nettify.go           # Nettify.xyz integration
│   └── proxiesfo.go         # Proxies.fo integration
├── proxy/                     # 🎯 Core Proxy Management
│   ├── entry.go             # Data structures
│   ├── log.go               # JSON logging
│   └── spawn.go             # 3proxy management
└── scripts/                   # 🔧 Automation Scripts
    ├── create_proxy_plan.sh     # Create individual plan
    ├── automatic_proxy_manager.sh # Full system rebuild
    ├── activate_all_proxies.sh   # Start all instances
    ├── check_expired_plans.sh    # Cleanup expired
    ├── cleanup_invalid_plans.sh  # Fix broken plans
    ├── curl_commands.sh          # Test all proxies
    └── ensure_proxies.sh         # Health monitoring
```

---

## 🔧 Go Application Breakdown

### **1. cmd/main.go - The Heart of Your API**

**Purpose**: HTTP server that handles all customer requests

```go
// Key Features:
// ✅ Chi router with middleware
// ✅ Bearer token authentication  
// ✅ Health check endpoint
// ✅ Plan creation endpoints
// ✅ System monitoring
```

**Server Configuration**:
- **Port**: 9090 (internal API)
- **Host**: 0.0.0.0 (accepts all connections)
- **Middleware**: Logging, recovery, authentication

**API Routes**:
```go
GET  /health              # Health check (no auth required)
POST /plan                # Create proxies.fo plan (auth required)
POST /nettify/plan        # Create nettify plan (auth required)  
GET  /ports               # List ports in use (auth required)
GET  /proxies             # List all proxy plans (auth required)
POST /restore             # Restore system from log (auth required)
```

### **2. config/env.go - Environment Management**

**Purpose**: Centralizes all configuration and API keys

```bash
# Your actual environment variables:
API_KEY=883a66ee-5a59-660b-9daf-1577e6b447ba          # Proxies.fo API key
BEARER_TOKEN=UVvSib3fZ5cJvpSG5zSsTOZXqaqJ6mTcH6wiZQ3... # Your API auth token
DOMAIN=oceanproxy.io                                   # Your brand domain
NETTIFY_API_KEY=Dr1N47VFDszVsDd7DDKQgTZZfIJ-gN3k9O6... # Nettify API key
```

**Security Features**:
- ✅ Masks sensitive data in logs
- ✅ Validates required variables on startup
- ✅ Graceful fallback to system environment

### **3. handlers/ - HTTP Request Processing**

#### **handlers/auth.go - Security Layer**
```go
// Simple but effective Bearer token auth
// All protected endpoints require:
// Authorization: Bearer UVvSib3fZ5cJvpSG5zSsTOZXqaqJ6mTcH6wiZQ3...
```

#### **handlers/create_plan.go - The Money Maker**

**Two main endpoints for different providers:**

1. **POST /plan** - Proxies.fo Plans
```bash
curl -X POST http://your-server:9090/plan \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d "reseller=residential&bandwidth=5&username=customer1&password=pass123"
```

2. **POST /nettify/plan** - Nettify Plans  
```bash
curl -X POST http://your-server:9090/nettify/plan \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d "plan_type=residential&bandwidth=2&username=customer2&password=pass456"
```

**What happens when you create a plan:**
1. 📝 Validates request parameters
2. 🔗 Calls upstream provider API
3. 📦 Creates upstream proxy account
4. 🚀 Spawns local 3proxy instance
5. ⚙️ Updates nginx load balancer
6. 📋 Logs plan to JSON file
7. ✅ Returns branded endpoint to customer

**Response Format:**
```json
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

#### **handlers/restore.go - Disaster Recovery**

**Purpose**: Rebuild entire system from the proxy log

**What it does:**
- 📖 Reads `/var/log/oceanproxy/proxies.json`
- 🛑 Kills stale processes on conflicting ports
- 🚀 Restarts all active proxy instances  
- 🔧 Recreates missing regional pairs (EU/USA)
- 📊 Reports success/failure statistics

### **4. providers/ - Upstream API Integration**

#### **providers/proxiesfo.go - Proxies.fo Integration**

**Supported Plan Types:**
- **Residential**: Rotating residential IPs
- **ISP**: Internet Service Provider proxies  
- **Datacenter**: High-speed datacenter proxies

**API Integration:**
```go
// Creates account like: pr-us.proxies.fo:13337:username:password
// Automatically creates both EU and USA endpoints
```

**Plan Configuration:**
- **Datacenter**: Duration-based (days), thread limits
- **Residential/ISP**: Bandwidth-based (GB), 180-day expiry

#### **providers/nettify.go - Nettify Integration**

**Supported Plan Types:**
- **Residential**: Rotating residential proxies
- **Datacenter**: High-speed datacenter proxies
- **Mobile**: Mobile carrier proxies
- **Unlimited**: Time-based unlimited proxies

**API Features:**
- ✅ Automatic username uniqueness (appends timestamp)
- ✅ Bandwidth conversion (GB to MB)
- ✅ Detailed debug logging
- ✅ Comprehensive error handling

### **5. proxy/ - Core Proxy Management**

#### **proxy/entry.go - Data Structures**

**The proxy.Entry struct** is the heart of your system:
```go
type Entry struct {
    PlanID    string `json:"plan_id"`     // Unique plan identifier
    Username  string `json:"username"`    // Customer username  
    Password  string `json:"password"`    // Customer password
    AuthHost  string `json:"auth_host"`   // Upstream provider host
    LocalHost string `json:"local_host"`  // Your branded domain
    AuthPort  int    `json:"auth_port"`   // Upstream provider port
    LocalPort int    `json:"local_port"`  // Your local 3proxy port
    Subdomain string `json:"subdomain"`   // Region (usa/eu/alpha/etc)
    ExpiresAt int64  `json:"expires_at"`  // Plan expiration timestamp
    CreatedAt int64  `json:"created_at"`  // Creation timestamp
}
```

#### **proxy/log.go - Centralized Logging**

**JSON Log Location**: `/var/log/oceanproxy/proxies.json`

**What it stores:**
- 📝 All proxy plan details
- 🕒 Creation and expiration timestamps  
- 🔌 Port assignments
- 👤 Customer credentials
- 🌐 Endpoint mappings

#### **proxy/spawn.go - 3proxy Management**

**Key Function**: `Spawn3proxy(e Entry)`

**What it does:**
1. 🔍 Validates shell script exists
2. 📋 Logs spawn attempt with full details
3. 🚀 Executes `create_proxy_plan.sh` with parameters
4. 📊 Captures and logs output/errors
5. ✅ Confirms successful startup

**Shell Script Parameters:**
```bash
./create_proxy_plan.sh \
  $PLAN_ID \         # d5cb155c-c1ca-1df2-5410-3f46f5ef6582
  $LOCAL_PORT \      # 10000
  $USERNAME \        # yourfbeh4s  
  $PASSWORD \        # lulqvwesuj
  $AUTH_HOST \       # pr-us.proxies.fo
  $AUTH_PORT \       # 13337
  $SUBDOMAIN         # usa
```

---

## 🔧 Shell Scripts System

### **Core Management Scripts**

#### **create_proxy_plan.sh - Instant Plan Creation**
**Purpose**: Creates individual proxy plans with instant nginx integration

**What it does step-by-step:**
1. 🔍 **Validates inputs** - Checks all 7 required parameters
2. 🛑 **Kills conflicts** - Terminates any process using the target port  
3. 📝 **Creates 3proxy config** - Generates individual config file
4. 🚀 **Starts 3proxy** - Launches process in background
5. 📋 **Updates proxy log** - Adds entry to JSON log
6. ⚙️ **Updates nginx** - Adds server to load balancer instantly
7. 🧪 **Tests nginx** - Validates and reloads configuration
8. ✅ **Reports success** - Shows test commands and status

**Result**: Customer can immediately use `usa.oceanproxy.io:1337:username:password`

#### **automatic_proxy_manager.sh - Full System Rebuild**
**Purpose**: Rebuilds entire proxy system from scratch

**When to use:**
- 🆕 Initial system setup
- 💥 After major crashes
- 🔄 Server migrations
- 🧹 Clean slate rebuilds

**Process:**
1. 📊 **Analyzes proxy log** - Groups plans by type
2. 🛑 **Stops all processes** - Kills existing 3proxy instances
3. 🗑️ **Cleans configs** - Removes old configuration files
4. 🔧 **Creates instances** - Spawns all proxy processes
5. ⚙️ **Rebuilds nginx** - Recreates all stream configurations
6. 📈 **Reports status** - Shows comprehensive system summary

### **Maintenance Scripts**

#### **activate_all_proxies.sh - Startup Script**
**Perfect for:**
- 🔄 Server reboots
- ⚡ Mass restarts
- 🚑 Emergency recovery

#### **ensure_proxies.sh - Health Monitor**
**Automated monitoring with options:**
```bash
./ensure_proxies.sh                    # Basic health check
./ensure_proxies.sh --restart          # Auto-restart failed instances  
./ensure_proxies.sh --check-connectivity # Test HTTP connectivity
./ensure_proxies.sh --restart --quiet  # Silent monitoring (for cron)
```

#### **check_expired_plans.sh - Expiration Management**
**Automated cleanup:**
```bash
./check_expired_plans.sh              # Check for expired plans
./check_expired_plans.sh --cleanup    # Remove expired plans
./check_expired_plans.sh --dry-run    # Preview what would be removed
```

#### **curl_commands.sh - Testing Suite**
**Comprehensive proxy testing:**
```bash
./curl_commands.sh                     # Test all via public endpoints
./curl_commands.sh --local            # Test local ports directly
./curl_commands.sh --parallel --jobs 10 # Parallel testing
./curl_commands.sh --url http://icanhazip.com # Custom test URL
```

---

## 🌐 Complete API Reference

### **Authentication**
All protected endpoints require Bearer token:
```bash
Authorization: Bearer UVvSib3fZ5cJvpSG5zSsTOZXqaqJ6mTcH6wiZQ3GgP9XL4M0xk8e6MZVldHVwuH0
```

### **Health Check (No Auth Required)**
```bash
GET http://your-server:9090/health

Response:
{
  "status": "healthy",
  "timestamp": "2025-07-30T23:11:45Z"
}
```

### **Create Proxies.fo Plan**
```bash
POST http://your-server:9090/plan
Authorization: Bearer YOUR_TOKEN
Content-Type: application/x-www-form-urlencoded

reseller=residential&bandwidth=5&username=customer1&password=pass123

Response:
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

### **Create Nettify Plan**
```bash
POST http://your-server:9090/nettify/plan
Authorization: Bearer YOUR_TOKEN
Content-Type: application/x-www-form-urlencoded

plan_type=residential&bandwidth=2&username=customer2&password=pass456

Response:
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

### **List All Proxies**
```bash
GET http://your-server:9090/proxies
Authorization: Bearer YOUR_TOKEN

Response: (Raw JSON from /var/log/oceanproxy/proxies.json)
[
  {
    "plan_id": "d5cb155c-c1ca-1df2-5410-3f46f5ef6582",
    "username": "yourfbeh4s",
    "password": "lulqvwesuj",
    "auth_host": "pr-us.proxies.fo",
    "local_host": "usa.oceanproxy.io", 
    "auth_port": 13337,
    "local_port": 10000,
    "subdomain": "usa",
    "expires_at": 1734567890,
    "created_at": 1722386305
  }
]
```

### **System Restore**
```bash
POST http://your-server:9090/restore
Authorization: Bearer YOUR_TOKEN

Response:
{
  "restored": ["plan1-usa", "plan1-eu", "plan2-alpha"],
  "failed": ["plan3-usa"]
}
```

### **Port Monitoring**
```bash
GET http://your-server:9090/ports
Authorization: Bearer YOUR_TOKEN

Response:
{
  "ports_in_use": [
    {
      "command": "3proxy",
      "pid": "12345", 
      "user": "root",
      "port": "*:10000"
    }
  ]
}
```

---

## 🚀 Deployment & Operations Guide

### **1. Initial Setup**
```bash
# Clone and build
cd /root/oceanproxy-api/backend
go build -o exec/oceanproxy cmd/main.go

# Set environment variables
cp exec/.env .env
# Edit .env with your API keys

# Start API server
./exec/oceanproxy
```

### **2. Create Your First Customer**
```bash
# Create a residential proxy plan
curl -X POST http://localhost:9090/plan \
  -H "Authorization: Bearer UVvSib3fZ5cJvpSG5zSsTOZXqaqJ6mTcH6wiZQ3GgP9XL4M0xk8e6MZVldHVwuH0" \
  -d "reseller=residential&bandwidth=5&username=testcustomer&password=testpass123"

# Customer can immediately use:
# USA: usa.oceanproxy.io:1337:testcustomer:testpass123  
# EU: eu.oceanproxy.io:1338:testcustomer:testpass123
```

### **3. Daily Operations**
```bash
# Morning health check
cd /root/oceanproxy-api/backend/scripts
./ensure_proxies.sh --restart --quiet

# Test all proxies
./curl_commands.sh --parallel

# Weekly cleanup
./cleanup_invalid_plans.sh --fix
./check_expired_plans.sh --cleanup
```

### **4. Monitoring & Alerts**
```bash
# Add to crontab for automated monitoring:
*/5 * * * * /root/oceanproxy-api/backend/scripts/ensure_proxies.sh --restart --quiet
0 2 * * * /root/oceanproxy-api/backend/scripts/check_expired_plans.sh --cleanup
```

---

## 🎯 Customer Experience

### **What Your Customers Get**
1. **Branded Endpoints**: `usa.oceanproxy.io:1337`, `eu.oceanproxy.io:1338`
2. **Simple Credentials**: Username and password (no complex auth)
3. **Instant Activation**: Ready within seconds of payment
4. **Load Balanced**: Automatic distribution across multiple instances
5. **Regional Options**: USA, EU, Alpha, Beta endpoints

### **Customer Usage Example**
```bash
# Your customer uses your branded service
curl -x usa.oceanproxy.io:1337 -U customer123:password123 http://httpbin.org/ip

# Behind the scenes:
# 1. nginx receives connection on port 1337
# 2. Routes to 3proxy instance on port 10001  
# 3. 3proxy forwards to pr-us.proxies.fo:13337
# 4. Response returns through same path
```

---

## 🔧 Troubleshooting Guide

### **Common Issues & Solutions**

#### **1. "Script not found" Error**
```bash
# Problem: create_proxy_plan.sh missing
# Solution: Ensure script exists and is executable
ls -la /root/oceanproxy-api/backend/scripts/create_proxy_plan.sh
chmod +x /root/oceanproxy-api/backend/scripts/create_proxy_plan.sh
```

#### **2. nginx Configuration Errors** 
```bash
# Test nginx config
nginx -t

# Common fix: reload configuration
systemctl reload nginx

# Check nginx status
systemctl status nginx
```

#### **3. Port Conflicts**
```bash
# Check what's using a port
lsof -i :10000

# Kill process on specific port
./scripts/cleanup_invalid_plans.sh --fix
```

#### **4. API Connection Issues**
```bash
# Check if API is running
curl http://localhost:9090/health

# Check logs
tail -f /var/log/oceanproxy/api.log
```

#### **5. Upstream Provider Errors**
```bash
# Test credentials manually
curl -x pr-us.proxies.fo:13337 -U username:password http://httpbin.org/ip

# Check API key validity
grep API_KEY .env
```

---

## 📊 System Monitoring

### **Key Metrics to Track**
- **Active 3proxy processes**: `ps aux | grep 3proxy | wc -l`
- **nginx status**: `systemctl status nginx`
- **Total plans**: `jq length /var/log/oceanproxy/proxies.json`
- **Port usage**: `netstat -tlnp | grep ":1337\|:1338\|:9876"`

### **Health Check Commands**
```bash
# Full system status
./scripts/ensure_proxies.sh

# Test all proxies
./scripts/curl_commands.sh --parallel

# Check for issues
./scripts/cleanup_invalid_plans.sh

# Monitor expired plans
./scripts/check_expired_plans.sh
```

---

## 🎉 Success Metrics

### **You'll Know It's Working When:**
- ✅ Customers can connect immediately after plan creation
- ✅ nginx successfully load balances traffic
- ✅ All 3proxy instances are healthy
- ✅ Upstream provider APIs respond correctly
- ✅ Automated monitoring catches and fixes issues
- ✅ You're making profit on every customer!

### **Scaling Indicators:**
- **100+ active plans**: Consider dedicated monitoring
- **500+ active plans**: Implement database storage
- **1000+ active plans**: Consider clustering/load balancing
- **5000+ active plans**: You're making serious money! 💰

---

## 🚀 Next Steps

1. **🎨 Build a Frontend**: Create customer dashboard for self-service
2. **💳 Add Billing**: Integrate Stripe/PayPal for automated payments
3. **📊 Add Analytics**: Track usage, bandwidth, success rates
4. **🔔 Add Monitoring**: Implement alerting for system issues
5. **🌍 Scale Globally**: Add more regions and providers
6. **💼 Go Enterprise**: Offer dedicated proxy pools for large customers

Your OceanProxy whitelabel system is now a complete, scalable business ready to generate recurring revenue! 🎉
