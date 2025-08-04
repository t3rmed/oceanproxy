#!/bin/bash
# create_proxy_plan.sh - Create individual HTTP proxy plan with instant nginx integration
# Updated with 2000 port limits per type and new proxy endpoints

# === Args ===
PLAN_ID="$1"
LOCAL_PORT="$2"
USERNAME="$3"
PASSWORD="$4"
UPSTREAM_HOST="$5"
UPSTREAM_PORT="$6"
SUBDOMAIN="$7"

# Validate required arguments
if [ $# -lt 7 ]; then
    echo "❌ Usage: $0 PLAN_ID LOCAL_PORT USERNAME PASSWORD UPSTREAM_HOST UPSTREAM_PORT SUBDOMAIN"
    echo ""
    echo "Example:"
    echo "  $0 plan123 10001 john mypass pr-us.proxies.fo 13337 usa"
    echo ""
    echo "This creates a whitelabel proxy where:"
    echo "  Client connects: usa.oceanproxy.io:1337:john:mypass"
    echo "  Routes through: 127.0.0.1:10001 → pr-us.proxies.fo:13337:john:mypass"
    echo ""
    echo "Available subdomains: usa, eu, alpha, beta, mobile, unlim, datacenter, gamma, delta, epsilon, zeta, eta"
    exit 1
fi

CONFIG_DIR="/opt/oceanproxy/app/backend/config/3proxy/plans"
CONFIG_FILE="${CONFIG_DIR}/${PLAN_ID}_${SUBDOMAIN}.cfg"
PROXY_LOG="/opt/oceanproxy/app/backend/logs/proxies.json"
STREAM_CONFIG="/opt/oceanproxy/app/backend/config/nginx/stream.d"

# Port ranges (2000 ports each)
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

# Public port mapping based on subdomain
declare -A PUBLIC_PORTS
PUBLIC_PORTS["usa"]="1337"
PUBLIC_PORTS["eu"]="1338"
PUBLIC_PORTS["alpha"]="9876"
PUBLIC_PORTS["beta"]="8765"
PUBLIC_PORTS["mobile"]="7654"
PUBLIC_PORTS["unlim"]="6543"
PUBLIC_PORTS["datacenter"]="1339"
PUBLIC_PORTS["gamma"]="5432"
PUBLIC_PORTS["delta"]="4321"
PUBLIC_PORTS["epsilon"]="3210"
PUBLIC_PORTS["zeta"]="2109"
PUBLIC_PORTS["eta"]="1098"

# Plan type mapping for upstream names
declare -A PLAN_TYPES
PLAN_TYPES["usa"]="pr-us.proxies.fo_usa"
PLAN_TYPES["eu"]="pr-eu.proxies.fo_eu"
PLAN_TYPES["alpha"]="proxy.nettify.xyz_alpha"
PLAN_TYPES["beta"]="proxy.nettify.xyz_beta"
PLAN_TYPES["mobile"]="proxy.nettify.xyz_mobile"
PLAN_TYPES["unlim"]="proxy.nettify.xyz_unlim"
PLAN_TYPES["datacenter"]="dcp.proxies.fo_datacenter"
PLAN_TYPES["gamma"]="blank_gamma"
PLAN_TYPES["delta"]="blank_delta"
PLAN_TYPES["epsilon"]="blank_epsilon"
PLAN_TYPES["zeta"]="blank_zeta"
PLAN_TYPES["eta"]="blank_eta"

PUBLIC_PORT=${PUBLIC_PORTS[$SUBDOMAIN]}
PLAN_TYPE=${PLAN_TYPES[$SUBDOMAIN]}
PORT_RANGE=${PORT_RANGES[$SUBDOMAIN]}

mkdir -p "$CONFIG_DIR"
mkdir -p "/opt/oceanproxy/app/backend/logs"
mkdir -p "$STREAM_CONFIG"

echo "🔧 Creating whitelabel HTTP proxy plan: $PLAN_ID [$SUBDOMAIN]"
echo "   👤 Username: $USERNAME"
echo "   🔌 Local Port: $LOCAL_PORT"
echo "   📊 Port Range: $PORT_RANGE (2000 ports max)"
echo "   🌐 Public Endpoint: ${SUBDOMAIN}.oceanproxy.io:${PUBLIC_PORT}"
echo "   📡 Upstream: $UPSTREAM_HOST:$UPSTREAM_PORT"

# === Validate port is within allowed range ===
IFS='-' read -r MIN_PORT MAX_PORT <<< "$PORT_RANGE"
if [[ $LOCAL_PORT -lt $MIN_PORT ]] || [[ $LOCAL_PORT -gt $MAX_PORT ]]; then
    echo "❌ Port $LOCAL_PORT is outside allowed range $PORT_RANGE for subdomain $SUBDOMAIN"
    exit 1
fi

# === Kill any existing process using the port ===
EXISTING_PID=$(lsof -tiTCP:$LOCAL_PORT 2>/dev/null)
if [ -n "$EXISTING_PID" ]; then
    echo "🛑 Killing existing process on port $LOCAL_PORT (PID: $EXISTING_PID)"
    kill -9 "$EXISTING_PID" 2>/dev/null
    sleep 1
fi

# === Remove any existing config files for this plan ===
rm -f "${CONFIG_DIR}/${PLAN_ID}.cfg" 2>/dev/null
rm -f "${CONFIG_DIR}/${PLAN_ID}_${SUBDOMAIN}.cfg" 2>/dev/null

# === Validate upstream host ===
case "$UPSTREAM_HOST" in
    dcp.proxies.fo|pr-us.proxies.fo|pr-eu.proxies.fo|proxy.nettify.xyz)
        echo "✅ Valid upstream host: $UPSTREAM_HOST"
        ;;
    blank|"")
        echo "⚠️ Blank proxy type - no upstream will be configured"
        UPSTREAM_HOST="blank"
        ;;
    *)
        echo "⚠️ Unknown upstream host: $UPSTREAM_HOST"
        echo "   Supported hosts: dcp.proxies.fo, pr-us.proxies.fo, pr-eu.proxies.fo, proxy.nettify.xyz, blank"
        exit 1
        ;;
esac

# === Validate subdomain has corresponding public port ===
if [ -z "$PUBLIC_PORT" ] || [ -z "$PLAN_TYPE" ]; then
    echo "❌ Invalid subdomain: $SUBDOMAIN"
    echo "   Supported subdomains: usa, eu, alpha, beta, mobile, unlim, datacenter, gamma, delta, epsilon, zeta, eta"
    exit 1
fi

# === Generate the 3proxy config ===
echo "📝 Creating individual 3proxy config..."

if [[ "$UPSTREAM_HOST" == "blank" ]]; then
    # Blank proxy configuration (no upstream)
    cat << EOF > "$CONFIG_FILE"
# 3proxy config for whitelabel HTTP proxy (BLANK TYPE)
# Plan ID: $PLAN_ID
# User: $USERNAME
# Client endpoint: ${SUBDOMAIN}.oceanproxy.io:${PUBLIC_PORT}:${USERNAME}:${PASSWORD}
# Internal port: $LOCAL_PORT
# Upstream: NONE (blank proxy - direct connection)

nscache 65536
timeouts 1 5 30 60 180 1800 15 60

# Authentication for this specific user
users $USERNAME:CL:$PASSWORD
auth strong
allow $USERNAME

# HTTP proxy listening on port $LOCAL_PORT (no parent)
proxy -n -a -p$LOCAL_PORT -i0.0.0.0 -e0.0.0.0
EOF
else
    # Regular proxy configuration (with upstream)
    cat << EOF > "$CONFIG_FILE"
# 3proxy config for whitelabel HTTP proxy
# Plan ID: $PLAN_ID
# User: $USERNAME
# Client endpoint: ${SUBDOMAIN}.oceanproxy.io:${PUBLIC_PORT}:${USERNAME}:${PASSWORD}
# Internal port: $LOCAL_PORT
# Upstream: ${UPSTREAM_HOST}:${UPSTREAM_PORT}:${USERNAME}:${PASSWORD}

nscache 65536
timeouts 1 5 30 60 180 1800 15 60

# Authentication for this specific user
users $USERNAME:CL:$PASSWORD
auth strong
allow $USERNAME

# Parent proxy (upstream provider)
parent 1000 http $UPSTREAM_HOST $UPSTREAM_PORT $USERNAME $PASSWORD

# HTTP proxy listening on port $LOCAL_PORT
proxy -n -a -p$LOCAL_PORT -i0.0.0.0 -e0.0.0.0
EOF
fi

# === Launch 3proxy with the new config ===
echo "🚀 Starting 3proxy on port $LOCAL_PORT for user $USERNAME"
nohup /usr/bin/3proxy "$CONFIG_FILE" > "/opt/oceanproxy/app/backend/logs/3proxy_${PLAN_ID}_${SUBDOMAIN}.log" 2>&1 &
PROXY_PID=$!

# === Verify startup ===
sleep 2

# Check if process is still running
if ! kill -0 "$PROXY_PID" 2>/dev/null; then
    echo "❌ 3proxy process failed to start"
    echo "📋 Check log: /opt/oceanproxy/app/backend/logs/3proxy_${PLAN_ID}_${SUBDOMAIN}.log"
    echo "📋 Config file: $CONFIG_FILE"
    exit 1
fi

# Check if port is listening
if ! netstat -tlnp 2>/dev/null | grep -q ":$LOCAL_PORT "; then
    echo "❌ 3proxy is not listening on port $LOCAL_PORT"
    kill -9 "$PROXY_PID" 2>/dev/null
    echo "📋 Check log: /opt/oceanproxy/app/backend/logs/3proxy_${PLAN_ID}_${SUBDOMAIN}.log"
    echo "📋 Config file: $CONFIG_FILE"
    exit 1
fi

echo "✅ 3proxy started successfully (PID: $PROXY_PID)"

# === Add/Update entry in proxy log ===
echo "📝 Updating proxy log..."

# Create proxy log entry
PROXY_ENTRY=$(cat << EOF
{
  "plan_id": "$PLAN_ID",
  "username": "$USERNAME",
  "password": "$PASSWORD",
  "auth_host": "$UPSTREAM_HOST",
  "auth_port": $UPSTREAM_PORT,
  "subdomain": "$SUBDOMAIN",
  "local_port": $LOCAL_PORT,
  "public_port": $PUBLIC_PORT,
  "created_at": "$(date -Iseconds)",
  "status": "active"
}
EOF
)

# Initialize proxy log if it doesn't exist
if [ ! -f "$PROXY_LOG" ]; then
    echo "[]" > "$PROXY_LOG"
fi

# Remove existing entry for this plan_id and add new one
jq --argjson new_entry "$PROXY_ENTRY" \
   'map(select(.plan_id != $new_entry.plan_id)) + [$new_entry]' \
   "$PROXY_LOG" > /tmp/updated_proxies.json && mv /tmp/updated_proxies.json "$PROXY_LOG"

# === Update nginx configuration instantly ===
echo "🔄 Updating nginx configuration instantly..."

STREAM_FILE="${STREAM_CONFIG}/${SUBDOMAIN}.conf"

# Check if stream config exists for this subdomain
if [ ! -f "$STREAM_FILE" ]; then
    echo "📝 Creating new nginx stream config for ${SUBDOMAIN}"
    # Create new stream config with this server
    cat << EOF > "$STREAM_FILE"
# HTTP Proxy Load Balancer for ${SUBDOMAIN}.oceanproxy.io:${PUBLIC_PORT}
# Auto-updated by create_proxy_plan.sh

upstream ${PLAN_TYPE}_pool {
    least_conn;
    server 127.0.0.1:${LOCAL_PORT};
}

server {
    listen ${PUBLIC_PORT};
    proxy_pass ${PLAN_TYPE}_pool;
    proxy_timeout 15s;
    proxy_responses 1;
    proxy_connect_timeout 10s;
    error_log /opt/oceanproxy/app/backend/logs/nginx_${SUBDOMAIN}_proxy_error.log;
}
EOF
else
    echo "📝 Adding server to existing nginx stream config for ${SUBDOMAIN}"
    # Check if this server already exists in the config
    if grep -q "server 127.0.0.1:${LOCAL_PORT};" "$STREAM_FILE"; then
        echo "   ⚠️ Server 127.0.0.1:${LOCAL_PORT} already exists in nginx config"
    else
        # Add the new server to the upstream block
        # Find the line with the upstream block and add the server after least_conn
        sed -i "/upstream ${PLAN_TYPE}_pool {/,/}/ {
            /least_conn;/a\\    server 127.0.0.1:${LOCAL_PORT};
        }" "$STREAM_FILE"
        echo "   ✅ Added server 127.0.0.1:${LOCAL_PORT} to nginx upstream"
    fi
fi

# === Test and reload nginx ===
echo "🧪 Testing nginx configuration..."
if nginx -t > /dev/null 2>&1; then
    echo "✅ Nginx config valid - reloading..."
    systemctl reload nginx

    # Verify nginx is listening on the public port
    sleep 1
    if netstat -tlnp | grep -q ":${PUBLIC_PORT} "; then
        echo "✅ Nginx is listening on ${SUBDOMAIN}.oceanproxy.io:${PUBLIC_PORT}"
    else
        echo "❌ Nginx is NOT listening on port ${PUBLIC_PORT}"
    fi
else
    echo "❌ Nginx config invalid - check configuration"
    echo "📋 Stream config: $STREAM_FILE"
    nginx -t
fi

# === Count current port usage ===
PORT_COUNT=$(jq --arg subdomain "$SUBDOMAIN" '[.[] | select(.subdomain == $subdomain)] | length' "$PROXY_LOG")
echo ""
echo "📊 Port Usage for $SUBDOMAIN: $PORT_COUNT/2000"

# === Show connection info ===
echo ""
echo "🎉 Whitelabel HTTP Proxy Plan Created & Active!"
echo ""
echo "📋 Client Connection Details:"
echo "   🌐 Endpoint: ${SUBDOMAIN}.oceanproxy.io:${PUBLIC_PORT}"
echo "   👤 Username: $USERNAME"
echo "   🔑 Password: $PASSWORD"
echo ""
echo "🔄 Traffic Flow:"
echo "   Client → nginx (${SUBDOMAIN}.oceanproxy.io:${PUBLIC_PORT})"
echo "          → 3proxy (127.0.0.1:${LOCAL_PORT})"
if [[ "$UPSTREAM_HOST" != "blank" ]]; then
    echo "          → Upstream (${UPSTREAM_HOST}:${UPSTREAM_PORT})"
else
    echo "          → Direct connection (no upstream)"
fi
echo ""
echo "🧪 Test Commands:"
echo "   # HTTP Proxy Test (Client-facing):"
echo "   curl -x ${SUBDOMAIN}.oceanproxy.io:${PUBLIC_PORT} -U ${USERNAME}:${PASSWORD} http://httpbin.org/ip"
echo ""
echo "   # Direct Local Test (Debugging):"
echo "   curl -x 127.0.0.1:${LOCAL_PORT} -U ${USERNAME}:${PASSWORD} http://httpbin.org/ip"
echo ""
echo "⚡ The proxy is INSTANTLY READY - no need to run automatic_proxy_manager.sh!"
echo ""

# === Show current system status ===
echo "📊 Current System Status:"
active_processes=$(ps aux | grep 3proxy | grep -v grep | wc -l)
total_plans=$(jq length "$PROXY_LOG" 2>/dev/null || echo "0")
nginx_listening=$(netstat -tlnp | grep nginx | grep ":${PUBLIC_PORT} " | wc -l)

echo "   Active 3proxy processes: $active_processes"
echo "   Total plans in system: $total_plans"
echo "   Nginx listening on port ${PUBLIC_PORT}: $([[ $nginx_listening -gt 0 ]] && echo "✅ YES" || echo "❌ NO")"
echo ""
echo "✅ Proxy plan $PLAN_ID is live and ready for clients!"