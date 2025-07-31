#!/bin/bash

# Automatic Proxy Manager - HTTP Proxy Whitelabel Service

PROXY_LOG="/var/log/oceanproxy/proxies.json"
CONFIG_DIR="/etc/3proxy/plans"

# Port ranges for each plan type (internal ports)
declare -A PORT_RANGES
PORT_RANGES["pr-us.proxies.fo_usa"]="10000"     # USA: 10000-19999
PORT_RANGES["pr-eu.proxies.fo_eu"]="20000"      # EU: 20000-29999  
PORT_RANGES["proxy.nettify.xyz_alpha"]="30000"  # Alpha: 30000-39999
PORT_RANGES["proxy.nettify.xyz_beta"]="40000"   # Beta: 40000-49999
PORT_RANGES["proxy.nettify.xyz_mobile"]="50000" # Mobile: 50000-59999
PORT_RANGES["proxy.nettify.xyz_unlim"]="60000"  # Unlimited: 60000-69999
PORT_RANGES["dcp.proxies.fo_datacenter"]="40000" # Datacenter: 40000-49999

# Public ports (what clients connect to)
declare -A PUBLIC_PORTS
PUBLIC_PORTS["pr-us.proxies.fo_usa"]="1337"
PUBLIC_PORTS["pr-eu.proxies.fo_eu"]="1338"
PUBLIC_PORTS["proxy.nettify.xyz_alpha"]="9876"
PUBLIC_PORTS["proxy.nettify.xyz_beta"]="8765"
PUBLIC_PORTS["proxy.nettify.xyz_mobile"]="7654"
PUBLIC_PORTS["proxy.nettify.xyz_unlim"]="6543"
PUBLIC_PORTS["dcp.proxies.fo_datacenter"]="1339"

# Subdomains for each plan type
declare -A SUBDOMAINS
SUBDOMAINS["pr-us.proxies.fo_usa"]="usa"
SUBDOMAINS["pr-eu.proxies.fo_eu"]="eu"
SUBDOMAINS["proxy.nettify.xyz_alpha"]="alpha"
SUBDOMAINS["proxy.nettify.xyz_beta"]="beta"
SUBDOMAINS["proxy.nettify.xyz_mobile"]="mobile"
SUBDOMAINS["proxy.nettify.xyz_unlim"]="unlim"
SUBDOMAINS["dcp.proxies.fo_datacenter"]="datacenter"

echo "🚀 HTTP Proxy Whitelabel Manager - Rebuilding entire system..."

# Create directories
mkdir -p "$CONFIG_DIR"

# Install jq if not present
if ! command -v jq &> /dev/null; then
    echo "📦 Installing jq..."
    apt-get update && apt-get install -y jq
fi

# Stop all existing 3proxy processes
echo "🛑 Stopping all existing 3proxy processes..."
sudo pkill -f 3proxy
sleep 2

# Clean up old configs
echo "🗑️ Cleaning up old configs..."
rm -f ${CONFIG_DIR}/*.cfg
rm -f /etc/nginx/upstreams/*.conf 2>/dev/null
rm -f /etc/nginx/sites-available/*-proxy 2>/dev/null
rm -f /etc/nginx/sites-enabled/*-proxy 2>/dev/null
rm -f /etc/nginx/conf.d/proxy_*.conf 2>/dev/null

# Track used ports to avoid conflicts
declare -A USED_PORTS

# Group plans by type and collect server entries
declare -A PLAN_GROUPS
declare -A PLAN_SERVERS  # Store server entries for each plan type
echo "📋 Analyzing plans..."

# Read all plans and group them
while IFS= read -r entry; do
    plan_id=$(echo "$entry" | jq -r '.plan_id')
    username=$(echo "$entry" | jq -r '.username')
    password=$(echo "$entry" | jq -r '.password')
    auth_host=$(echo "$entry" | jq -r '.auth_host')
    auth_port=$(echo "$entry" | jq -r '.auth_port')
    subdomain=$(echo "$entry" | jq -r '.subdomain')
    
    # Skip malformed entries
    if [ "$plan_id" = "null" ] || [ "$username" = "null" ]; then
        continue
    fi
    
    PLAN_TYPE="${auth_host}_${subdomain}"
    
    # Add to group
    if [ -z "${PLAN_GROUPS[$PLAN_TYPE]}" ]; then
        PLAN_GROUPS[$PLAN_TYPE]="$entry"
    else
        PLAN_GROUPS[$PLAN_TYPE]="${PLAN_GROUPS[$PLAN_TYPE]}|$entry"
    fi
    
done < <(jq -c '.[]' "$PROXY_LOG")

echo "🔧 Creating individual 3proxy configs for HTTP proxies..."

# Process each plan type
for plan_type in "${!PLAN_GROUPS[@]}"; do
    echo ""
    echo "📦 Processing plan type: $plan_type"
    
    # Get base port for this plan type
    base_port=${PORT_RANGES[$plan_type]}
    public_port=${PUBLIC_PORTS[$plan_type]}
    subdomain=${SUBDOMAINS[$plan_type]}
    
    if [ -z "$base_port" ] || [ -z "$public_port" ] || [ -z "$subdomain" ]; then
        echo "   ⚠️ No configuration for plan type: $plan_type - skipping"
        continue
    fi
    
    echo "   📡 Public endpoint: ${subdomain}.oceanproxy.io:${public_port}"
    echo "   🔢 Internal port range: ${base_port}+"
    
    # Initialize server list for this plan type
    PLAN_SERVERS[$plan_type]=""
    
    # Process each plan in this group
    current_port=$base_port
    plan_count=0
    
    IFS='|' read -ra PLANS <<< "${PLAN_GROUPS[$plan_type]}"
    for plan_entry in "${PLANS[@]}"; do
        plan_id=$(echo "$plan_entry" | jq -r '.plan_id')
        username=$(echo "$plan_entry" | jq -r '.username')
        password=$(echo "$plan_entry" | jq -r '.password')
        auth_host=$(echo "$plan_entry" | jq -r '.auth_host')
        auth_port=$(echo "$plan_entry" | jq -r '.auth_port')
        plan_subdomain=$(echo "$plan_entry" | jq -r '.subdomain')
        
        # Find next available port
        while [[ ${USED_PORTS[$current_port]} ]]; do
            ((current_port++))
        done
        USED_PORTS[$current_port]=1
        
        echo "   🔄 Plan $plan_id ($username) → Internal port $current_port"
        echo "      Client connects: ${subdomain}.oceanproxy.io:${public_port}:${username}:${password}"
        echo "      Routes through: 127.0.0.1:${current_port} → ${auth_host}:${auth_port}"
        
        # Create individual 3proxy config for this specific user
        config_file="${CONFIG_DIR}/${plan_id}_${plan_subdomain}.cfg"
        cat << EOF > "$config_file"
# 3proxy config for user: $username
# Client endpoint: ${subdomain}.oceanproxy.io:${public_port}:${username}:${password}
# Internal port: $current_port
# Upstream: ${auth_host}:${auth_port}:${username}:${password}

nscache 65536
timeouts 1 5 30 60 180 1800 15 60

# Authentication for this specific user
users $username:CL:$password
auth strong
allow $username

# Parent proxy (upstream provider)
parent 1000 http $auth_host $auth_port $username $password

# HTTP proxy listening on port $current_port
proxy -n -a -p$current_port -i0.0.0.0 -e0.0.0.0
EOF
        
        # Start 3proxy for this specific user
        echo "      🚀 Starting 3proxy for user $username on port $current_port"
        nohup /usr/bin/3proxy "$config_file" > "/var/log/3proxy_${plan_id}_${plan_subdomain}.log" 2>&1 &
        
        # Add server entry to the list for this plan type
        if [ -z "${PLAN_SERVERS[$plan_type]}" ]; then
            PLAN_SERVERS[$plan_type]="    server 127.0.0.1:$current_port;"
        else
            PLAN_SERVERS[$plan_type]="${PLAN_SERVERS[$plan_type]}
    server 127.0.0.1:$current_port;"
        fi
        
        # Update proxy log with assigned internal port
        jq --arg plan_id "$plan_id" --arg port "$current_port" '(.[] | select(.plan_id == $plan_id) | .local_port) = ($port | tonumber)' "$PROXY_LOG" > /tmp/updated_proxies.json
        mv /tmp/updated_proxies.json "$PROXY_LOG"
        
        ((plan_count++))
        ((current_port++))
        
        # Small delay to avoid overwhelming the system
        sleep 0.1
    done
    
    echo "   📝 Created ${plan_count} individual proxy instances for ${plan_type}"
done

echo ""
echo "🔄 Updating nginx configuration for HTTP proxy load balancing..."

# Check if nginx.conf already has stream block
NGINX_CONF="/etc/nginx/nginx.conf"
STREAM_CONFIG="/etc/nginx/stream.d"

# Create stream config directory
mkdir -p "$STREAM_CONFIG"

# Create stream configs for each plan type with direct server entries
for plan_type in "${!PLAN_GROUPS[@]}"; do
    public_port=${PUBLIC_PORTS[$plan_type]}
    subdomain=${SUBDOMAINS[$plan_type]}
    
    if [ -n "$public_port" ] && [ -n "$subdomain" ] && [ -n "${PLAN_SERVERS[$plan_type]}" ]; then
        echo "   📝 Creating nginx stream config for ${subdomain} (HTTP proxy load balancer)"
        cat << EOF > "${STREAM_CONFIG}/${subdomain}.conf"
# HTTP Proxy Load Balancer for ${subdomain}.oceanproxy.io:${public_port}
# Distributes clients across multiple 3proxy instances

upstream ${plan_type}_pool {
    least_conn;
${PLAN_SERVERS[$plan_type]}
}

server {
    listen ${public_port};
    proxy_pass ${plan_type}_pool;
    proxy_timeout 10s;
    proxy_responses 1;
    proxy_connect_timeout 5s;
    error_log /var/log/nginx/${subdomain}_proxy_error.log;
}
EOF
    fi
done

# Check if stream block exists in nginx.conf
if ! grep -q "stream {" "$NGINX_CONF"; then
    echo "📝 Adding stream block to nginx.conf..."
    
    # Backup original nginx.conf
    cp "$NGINX_CONF" "${NGINX_CONF}.backup.$(date +%s)"
    
    # Add stream block before the last closing brace
    sed -i '/^}$/i\\nstream {\n    include /etc/nginx/stream.d/*.conf;\n}' "$NGINX_CONF"
else
    echo "✅ Stream block already exists in nginx.conf"
fi

# Test and reload nginx
echo "🧪 Testing nginx configuration..."
if nginx -t; then
    echo "✅ Nginx config valid - reloading..."
    systemctl reload nginx
    
    # Verify nginx is listening on public ports
    echo "🔍 Verifying nginx is listening on public HTTP proxy ports..."
    for plan_type in "${!PLAN_GROUPS[@]}"; do
        public_port=${PUBLIC_PORTS[$plan_type]}
        subdomain=${SUBDOMAINS[$plan_type]}
        if [ -n "$public_port" ] && [ -n "$subdomain" ]; then
            if netstat -tlnp | grep -q ":${public_port} "; then
                echo "   ✅ ${subdomain}.oceanproxy.io:${public_port} is listening"
            else
                echo "   ❌ ${subdomain}.oceanproxy.io:${public_port} is NOT listening"
            fi
        fi
    done
else
    echo "❌ Nginx config invalid - check logs"
    exit 1
fi

echo ""
echo "🎉 HTTP Proxy Whitelabel System Ready!"
echo ""
echo "📊 Summary:"
total_plans=$(jq length "$PROXY_LOG")
active_processes=$(ps aux | grep 3proxy | grep -v grep | wc -l)
echo "   Total proxy plans: $total_plans"
echo "   Active 3proxy instances: $active_processes"
echo "   Plan types configured: ${#PLAN_GROUPS[@]}"
echo ""
echo "🌐 Your Whitelabel HTTP Proxy Endpoints:"
for plan_type in "${!PLAN_GROUPS[@]}"; do
    subdomain=${SUBDOMAINS[$plan_type]}
    public_port=${PUBLIC_PORTS[$plan_type]}
    if [ -n "${PLAN_GROUPS[$plan_type]}" ]; then
        plan_count=$(echo "${PLAN_GROUPS[$plan_type]}" | tr '|' '\n' | wc -l)
        echo "   ${subdomain}.oceanproxy.io:${public_port} → ${plan_count} users"
        
        # Show example usage for first user in this plan type
        first_plan=$(echo "${PLAN_GROUPS[$plan_type]}" | cut -d'|' -f1)
        example_user=$(echo "$first_plan" | jq -r '.username')
        example_pass=$(echo "$first_plan" | jq -r '.password')
        echo "     Example: curl -x ${subdomain}.oceanproxy.io:${public_port} -U ${example_user}:${example_pass} http://httpbin.org/ip"
    fi
done
echo ""
echo "✅ Clients can now connect to your branded endpoints with their individual credentials!"
echo "✅ Each user gets routed through their own dedicated 3proxy instance!"
echo ""
echo "📋 Traffic Flow:"
echo "   Client → nginx (${subdomain}.oceanproxy.io:${public_port}) → 3proxy (127.0.0.1:1000X) → Upstream Provider"
