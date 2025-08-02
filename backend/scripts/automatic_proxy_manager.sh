#!/bin/bash

# Automatic Proxy Manager - HTTP Proxy Whitelabel Service
# Updated with 2000 port limits per type and new proxy endpoints

PROXY_LOG="/var/log/oceanproxy/proxies.json"
CONFIG_DIR="/etc/3proxy/plans"

# Port ranges for each plan type (2000 ports each)
declare -A PORT_RANGES
PORT_RANGES["pr-us.proxies.fo_usa"]="10000"
PORT_RANGES["pr-eu.proxies.fo_eu"]="12000"
PORT_RANGES["proxy.nettify.xyz_alpha"]="14000"
PORT_RANGES["proxy.nettify.xyz_beta"]="16000"
PORT_RANGES["proxy.nettify.xyz_mobile"]="18000"
PORT_RANGES["proxy.nettify.xyz_unlim"]="20000"
PORT_RANGES["dcp.proxies.fo_datacenter"]="22000"
PORT_RANGES["blank_gamma"]="24000"
PORT_RANGES["blank_delta"]="26000"
PORT_RANGES["blank_epsilon"]="28000"
PORT_RANGES["blank_zeta"]="30000"
PORT_RANGES["blank_eta"]="32000"

# Maximum ports per type
MAX_PORTS_PER_TYPE=2000

# Public ports (client-facing)
declare -A PUBLIC_PORTS
PUBLIC_PORTS["pr-us.proxies.fo_usa"]="1337"
PUBLIC_PORTS["pr-eu.proxies.fo_eu"]="1338"
PUBLIC_PORTS["proxy.nettify.xyz_alpha"]="9876"
PUBLIC_PORTS["proxy.nettify.xyz_beta"]="8765"
PUBLIC_PORTS["proxy.nettify.xyz_mobile"]="7654"
PUBLIC_PORTS["proxy.nettify.xyz_unlim"]="6543"
PUBLIC_PORTS["dcp.proxies.fo_datacenter"]="1339"
PUBLIC_PORTS["blank_gamma"]="5432"
PUBLIC_PORTS["blank_delta"]="4321"
PUBLIC_PORTS["blank_epsilon"]="3210"
PUBLIC_PORTS["blank_zeta"]="2109"
PUBLIC_PORTS["blank_eta"]="1098"

# Subdomain mapping
declare -A SUBDOMAINS
SUBDOMAINS["pr-us.proxies.fo_usa"]="usa"
SUBDOMAINS["pr-eu.proxies.fo_eu"]="eu"
SUBDOMAINS["proxy.nettify.xyz_alpha"]="alpha"
SUBDOMAINS["proxy.nettify.xyz_beta"]="beta"
SUBDOMAINS["proxy.nettify.xyz_mobile"]="mobile"
SUBDOMAINS["proxy.nettify.xyz_unlim"]="unlim"
SUBDOMAINS["dcp.proxies.fo_datacenter"]="datacenter"
SUBDOMAINS["blank_gamma"]="gamma"
SUBDOMAINS["blank_delta"]="delta"
SUBDOMAINS["blank_epsilon"]="epsilon"
SUBDOMAINS["blank_zeta"]="zeta"
SUBDOMAINS["blank_eta"]="eta"

echo "🚀 HTTP Proxy Whitelabel Manager - Rebuilding entire system..."
echo "   Port limits: 2000 ports per proxy type"

mkdir -p "$CONFIG_DIR"

# Ensure jq is installed
if ! command -v jq &>/dev/null; then
    echo "📦 Installing jq..."
    apt-get update && apt-get install -y jq
fi

echo "🛑 Stopping all existing 3proxy processes..."
pkill -f 3proxy
sleep 1

echo "🗑️ Cleaning up old configs..."
rm -f ${CONFIG_DIR}/*.cfg
rm -f /etc/nginx/stream.d/*.conf
rm -f /etc/nginx/conf.d/proxy_*.conf

declare -A USED_PORTS
declare -A USED_CONFIGS
declare -A PLAN_GROUPS
declare -A PLAN_SERVERS
declare -A PORT_COUNTS  # Track port usage per type

echo "📋 Analyzing plans..."
while IFS= read -r entry; do
    plan_id=$(echo "$entry" | jq -r '.plan_id')
    username=$(echo "$entry" | jq -r '.username')
    password=$(echo "$entry" | jq -r '.password')
    auth_host=$(echo "$entry" | jq -r '.auth_host')
    auth_port=$(echo "$entry" | jq -r '.auth_port')
    subdomain=$(echo "$entry" | jq -r '.subdomain')

    [[ "$plan_id" == "null" || "$username" == "null" ]] && continue

    # Handle blank proxy types
    if [[ "$auth_host" == "blank" ]] || [[ "$auth_host" == "" ]] || [[ "$auth_host" == "null" ]]; then
        PLAN_TYPE="blank_${subdomain}"
    else
        PLAN_TYPE="${auth_host}_${subdomain}"
    fi
    
    PLAN_GROUPS[$PLAN_TYPE]+="${entry}|"

done < <(jq -c '.[]' "$PROXY_LOG")

echo "🔧 Creating individual 3proxy configs for HTTP proxies..."

for plan_type in "${!PLAN_GROUPS[@]}"; do
    echo -e "\n📦 Processing plan type: $plan_type"

    base_port=${PORT_RANGES[$plan_type]}
    public_port=${PUBLIC_PORTS[$plan_type]}
    subdomain=${SUBDOMAINS[$plan_type]}

    [[ -z "$base_port" || -z "$public_port" || -z "$subdomain" ]] && {
        echo "   ⚠️ Skipping $plan_type (missing config)"
        continue
    }

    echo "   📡 Public endpoint: ${subdomain}.oceanproxy.io:${public_port}"
    echo "   🔢 Internal port range: $base_port-$((base_port + MAX_PORTS_PER_TYPE - 1))"

    PLAN_SERVERS[$plan_type]=""
    current_port=$base_port
    plan_count=0
    PORT_COUNTS[$plan_type]=0

    IFS='|' read -ra PLANS <<< "${PLAN_GROUPS[$plan_type]}"
    for plan_entry in "${PLANS[@]}"; do
        [[ -z "$plan_entry" ]] && continue

        # Check if we've reached the port limit
        if [[ ${PORT_COUNTS[$plan_type]} -ge $MAX_PORTS_PER_TYPE ]]; then
            echo "   ⚠️ Reached maximum port limit (2000) for $plan_type, skipping remaining plans"
            break
        fi

        plan_id=$(echo "$plan_entry" | jq -r '.plan_id')
        username=$(echo "$plan_entry" | jq -r '.username')
        password=$(echo "$plan_entry" | jq -r '.password')
        auth_host=$(echo "$plan_entry" | jq -r '.auth_host')
        auth_port=$(echo "$plan_entry" | jq -r '.auth_port')
        plan_subdomain=$(echo "$plan_entry" | jq -r '.subdomain')

        config_key="${plan_id}_${plan_subdomain}"
        [[ ${USED_CONFIGS[$config_key]} ]] && continue
        USED_CONFIGS[$config_key]=1

        # Find next available port within the 2000 port range
        max_port=$((base_port + MAX_PORTS_PER_TYPE - 1))
        while [[ ${USED_PORTS[$current_port]} ]] && [[ $current_port -le $max_port ]]; do
            ((current_port++))
        done
        
        if [[ $current_port -gt $max_port ]]; then
            echo "   ❌ No more available ports in range for $plan_type"
            break
        fi
        
        USED_PORTS[$current_port]=1
        ((PORT_COUNTS[$plan_type]++))

        echo "   🔄 Plan $plan_id ($username) → Internal port $current_port"
        echo "      Client connects: ${subdomain}.oceanproxy.io:${public_port}:${username}:${password}"
        
        # Handle blank proxy types
        if [[ "$auth_host" == "blank" ]] || [[ "$auth_host" == "" ]] || [[ "$auth_host" == "null" ]]; then
            echo "      ⚠️ Blank proxy type - no upstream configured"
            config_file="${CONFIG_DIR}/${plan_id}_${plan_subdomain}.cfg"
            cat << EOF > "$config_file"
# 3proxy config for blank proxy type: $username
# Plan ID: $plan_id
# Subdomain: $plan_subdomain
# Client endpoint: ${subdomain}.oceanproxy.io:${public_port}:${username}:${password}
# Internal port: $current_port
# Upstream: NONE (blank proxy)

nscache 65536
timeouts 1 5 30 60 180 1800 15 60
maxconn 512

users $username:CL:$password
auth strong
allow $username

# Blank proxy - direct connection without upstream
proxy -n -a -p$current_port -i0.0.0.0 -e0.0.0.0
EOF
        else
            echo "      Routes through: 127.0.0.1:$current_port → $auth_host:$auth_port"
            config_file="${CONFIG_DIR}/${plan_id}_${plan_subdomain}.cfg"
            cat << EOF > "$config_file"
# 3proxy config for user: $username
# Plan ID: $plan_id
# Subdomain: $plan_subdomain
# Client endpoint: ${subdomain}.oceanproxy.io:${public_port}:${username}:${password}
# Internal port: $current_port
# Upstream: ${auth_host}:${auth_port}:${username}:${password}

nscache 65536
timeouts 1 5 30 60 180 1800 15 60
maxconn 512

users $username:CL:$password
auth strong
allow $username

parent 1000 http $auth_host $auth_port $username $password

proxy -n -a -p$current_port -i0.0.0.0 -e0.0.0.0
EOF
        fi

        echo "      🚀 Starting 3proxy for user $username on port $current_port"
        nohup /usr/bin/3proxy "$config_file" > "/var/log/3proxy_${plan_id}_${plan_subdomain}.log" 2>&1 &

        PLAN_SERVERS[$plan_type]+=\n'"    server 127.0.0.1:$current_port;"

        jq --arg plan_id "$plan_id" --arg subdomain "$plan_subdomain" --arg port "$current_port" \
            '(.[] | select(.plan_id == $plan_id and .subdomain == $subdomain) | .local_port) = ($port | tonumber)' \
            "$PROXY_LOG" > /tmp/updated_proxies.json && mv /tmp/updated_proxies.json "$PROXY_LOG"

        ((plan_count++))
        ((current_port++))
        sleep 0.1
    done

    echo "   📝 Created $plan_count individual proxy instances for $plan_type"
    echo "   📊 Port usage: ${PORT_COUNTS[$plan_type]}/$MAX_PORTS_PER_TYPE"
done

echo -e "\n🔄 Updating nginx configuration for HTTP proxy load balancing..."

NGINX_CONF="/etc/nginx/nginx.conf"
STREAM_CONFIG="/etc/nginx/stream.d"
mkdir -p "$STREAM_CONFIG"

for plan_type in "${!PLAN_SERVERS[@]}"; do
    public_port=${PUBLIC_PORTS[$plan_type]}
    subdomain=${SUBDOMAINS[$plan_type]}
    servers="${PLAN_SERVERS[$plan_type]}"

    [[ -z "$servers" ]] && continue

    echo "   📝 Creating nginx stream config for $subdomain"
    cat << EOF > "${STREAM_CONFIG}/${subdomain}.conf"
# Load balancer for ${subdomain}.oceanproxy.io:${public_port}
upstream ${plan_type}_pool {
    least_conn;
$servers
}
server {
    listen $public_port;
    proxy_pass ${plan_type}_pool;
    proxy_timeout 15s;
    proxy_connect_timeout 10s;
    proxy_responses 1;
    error_log /var/log/nginx/${subdomain}_proxy_error.log;
}
EOF
done

if ! grep -q "stream {" "$NGINX_CONF"; then
    echo "📝 Adding stream block to nginx.conf..."
    cp "$NGINX_CONF" "${NGINX_CONF}.backup.$(date +%s)"
    sed -i '/^}$/i\\nstream {\n    include /etc/nginx/stream.d/*.conf;\n}' "$NGINX_CONF"
else
    echo "✅ Stream block already exists in nginx.conf"
fi

echo "🧪 Testing nginx configuration..."
if nginx -t; then
    echo "✅ Nginx config valid - reloading..."
    systemctl reload nginx
    echo "🔍 Verifying nginx listeners..."
    for plan_type in "${!PLAN_GROUPS[@]}"; do
        port=${PUBLIC_PORTS[$plan_type]}
        sub=${SUBDOMAINS[$plan_type]}
        if netstat -tlnp | grep -q ":$port "; then
            echo "   ✅ ${sub}.oceanproxy.io:$port is listening"
        else
            echo "   ❌ ${sub}.oceanproxy.io:$port is NOT listening"
        fi
    done
else
    echo "❌ Nginx config test failed. Check logs."
    exit 1
fi

echo ""
echo "🎉 HTTP Proxy Whitelabel System Ready!"
echo ""
echo "📊 Summary:"
echo "   Total proxy plans: $(jq length "$PROXY_LOG")"
echo "   Active 3proxy instances: $(pgrep -fc 3proxy)"
echo "   Plan types configured: ${#PLAN_GROUPS[@]}"
echo ""
echo "📊 Port Usage by Type (Max 2000 per type):"
for plan_type in "${!PORT_COUNTS[@]}"; do
    sub=${SUBDOMAINS[$plan_type]}
    count=${PORT_COUNTS[$plan_type]}
    percent=$((count * 100 / MAX_PORTS_PER_TYPE))
    echo "   $sub: $count/$MAX_PORTS_PER_TYPE ($percent% used)"
done
echo ""
echo "🌐 Whitelabel Proxy Endpoints:"
for plan_type in "${!PLAN_GROUPS[@]}"; do
    sub=${SUBDOMAINS[$plan_type]}
    port=${PUBLIC_PORTS[$plan_type]}
    [[ -z "$sub" || -z "$port" ]] && continue
    count=${PORT_COUNTS[$plan_type]:-0}
    echo "   $sub.oceanproxy.io:$port → $count users"

    plan_sample=$(echo "${PLAN_GROUPS[$plan_type]}" | cut -d'|' -f1)
    if [[ -n "$plan_sample" ]]; then
        user=$(echo "$plan_sample" | jq -r '.username')
        pass=$(echo "$plan_sample" | jq -r '.password')
        echo "     Example: curl -x $sub.oceanproxy.io:$port -U $user:$pass http://httpbin.org/ip"
    fi
done
echo ""
echo "🆕 New Blank Proxy Endpoints Available:"
echo "   gamma.oceanproxy.io:5432"
echo "   delta.oceanproxy.io:4321"
echo "   epsilon.oceanproxy.io:3210"
echo "   zeta.oceanproxy.io:2109"
echo "   eta.oceanproxy.io:1098"
echo ""
echo "📋 Flow: Client → nginx → 3proxy → Upstream Provider (or direct for blank types)"