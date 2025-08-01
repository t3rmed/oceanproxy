#!/bin/bash

# Automatic Proxy Manager - HTTP Proxy Whitelabel Service

PROXY_LOG="/var/log/oceanproxy/proxies.json"
CONFIG_DIR="/etc/3proxy/plans"

# Port ranges for each plan type (internal ports)        
declare -A PORT_RANGES
PORT_RANGES["pr-us.proxies.fo_usa"]="10000"
PORT_RANGES["pr-eu.proxies.fo_eu"]="20000"
PORT_RANGES["proxy.nettify.xyz_alpha"]="30000"
PORT_RANGES["proxy.nettify.xyz_beta"]="40000"
PORT_RANGES["proxy.nettify.xyz_mobile"]="50000"
PORT_RANGES["proxy.nettify.xyz_unlim"]="60000"
PORT_RANGES["dcp.proxies.fo_datacenter"]="40000"

# Public ports (client-facing)
declare -A PUBLIC_PORTS
PUBLIC_PORTS["pr-us.proxies.fo_usa"]="1337"
PUBLIC_PORTS["pr-eu.proxies.fo_eu"]="1338"
PUBLIC_PORTS["proxy.nettify.xyz_alpha"]="9876"
PUBLIC_PORTS["proxy.nettify.xyz_beta"]="8765"
PUBLIC_PORTS["proxy.nettify.xyz_mobile"]="7654"
PUBLIC_PORTS["proxy.nettify.xyz_unlim"]="6543"
PUBLIC_PORTS["dcp.proxies.fo_datacenter"]="1339"

# Subdomain mapping
declare -A SUBDOMAINS
SUBDOMAINS["pr-us.proxies.fo_usa"]="usa"
SUBDOMAINS["pr-eu.proxies.fo_eu"]="eu"
SUBDOMAINS["proxy.nettify.xyz_alpha"]="alpha"
SUBDOMAINS["proxy.nettify.xyz_beta"]="beta"
SUBDOMAINS["proxy.nettify.xyz_mobile"]="mobile"
SUBDOMAINS["proxy.nettify.xyz_unlim"]="unlim"
SUBDOMAINS["dcp.proxies.fo_datacenter"]="datacenter"

echo "🚀 HTTP Proxy Whitelabel Manager - Rebuilding entire system..."

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

echo "📋 Analyzing plans..."
while IFS= read -r entry; do
    plan_id=$(echo "$entry" | jq -r '.plan_id')
    username=$(echo "$entry" | jq -r '.username')
    password=$(echo "$entry" | jq -r '.password')
    auth_host=$(echo "$entry" | jq -r '.auth_host')
    auth_port=$(echo "$entry" | jq -r '.auth_port')
    subdomain=$(echo "$entry" | jq -r '.subdomain')

    [[ "$plan_id" == "null" || "$username" == "null" ]] && continue

    PLAN_TYPE="${auth_host}_${subdomain}"
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
    echo "   🔢 Internal port range: $base_port+"

    PLAN_SERVERS[$plan_type]=""
    current_port=$base_port
    plan_count=0

    IFS='|' read -ra PLANS <<< "${PLAN_GROUPS[$plan_type]}"
    for plan_entry in "${PLANS[@]}"; do
        [[ -z "$plan_entry" ]] && continue

        plan_id=$(echo "$plan_entry" | jq -r '.plan_id')
        username=$(echo "$plan_entry" | jq -r '.username')
        password=$(echo "$plan_entry" | jq -r '.password')
        auth_host=$(echo "$plan_entry" | jq -r '.auth_host')
        auth_port=$(echo "$plan_entry" | jq -r '.auth_port')
        plan_subdomain=$(echo "$plan_entry" | jq -r '.subdomain')

        config_key="${plan_id}_${plan_subdomain}"
        [[ ${USED_CONFIGS[$config_key]} ]] && continue
        USED_CONFIGS[$config_key]=1

        while [[ ${USED_PORTS[$current_port]} ]]; do
            ((current_port++))
        done
        USED_PORTS[$current_port]=1

        echo "   🔄 Plan $plan_id ($username) → Internal port $current_port"
        echo "      Client connects: ${subdomain}.oceanproxy.io:${public_port}:${username}:${password}"     
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

        echo "      🚀 Starting 3proxy for user $username on port $current_port"
        nohup /usr/bin/3proxy "$config_file" > "/var/log/3proxy_${plan_id}_${plan_subdomain}.log" 2>&1 &    

        PLAN_SERVERS[$plan_type]+=$'\n'"    server 127.0.0.1:$current_port;"

        jq --arg plan_id "$plan_id" --arg subdomain "$plan_subdomain" --arg port "$current_port" \
            '(.[] | select(.plan_id == $plan_id and .subdomain == $subdomain) | .local_port) = ($port | tonumber)' \
            "$PROXY_LOG" > /tmp/updated_proxies.json && mv /tmp/updated_proxies.json "$PROXY_LOG"

        ((plan_count++))
        ((current_port++))
        sleep 0.1
    done

    echo "   📝 Created $plan_count individual proxy instances for $plan_type"
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
echo "🌐 Whitelabel Proxy Endpoints:"
for plan_type in "${!PLAN_GROUPS[@]}"; do
    sub=${SUBDOMAINS[$plan_type]}
    port=${PUBLIC_PORTS[$plan_type]}
    [[ -z "$sub" || -z "$port" ]] && continue
    count=$(echo "${PLAN_GROUPS[$plan_type]}" | tr '|' '\n' | wc -l)
    echo "   $sub.oceanproxy.io:$port → $count users"

    plan_sample=$(echo "${PLAN_GROUPS[$plan_type]}" | cut -d'|' -f1)
    user=$(echo "$plan_sample" | jq -r '.username')
    pass=$(echo "$plan_sample" | jq -r '.password')
    echo "     Example: curl -x $sub.oceanproxy.io:$port -U $user:$pass http://httpbin.org/ip"
done
echo ""
echo "📋 Flow: Client → nginx → 3proxy → Upstream Provider"
